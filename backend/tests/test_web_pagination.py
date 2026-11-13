"""Cursor pagination: stable under inserts, bounded size, opaque cursors."""

import base64
import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

import httpx2
import pytest
import time_machine
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from tests.factories import NoteFactory
from tests.models import Note
from tests.web_app import NOTES_URL

START = datetime(2027, 3, 1, 12, 0, tzinfo=UTC)


async def add_notes(session: AsyncSession, titles: list[str], start: datetime) -> None:
    """Commit notes created one minute apart, starting at ``start``."""
    with time_machine.travel(start, tick=False) as traveller:
        for title in titles:
            await NoteFactory.create_async(title=title)
            traveller.shift(timedelta(minutes=1))
    await session.commit()


async def get_page(
    api: httpx2.AsyncClient, **params: Any
) -> tuple[list[str], str | None]:
    response = await api.get(NOTES_URL, params=params)
    assert response.status_code == 200, response.text
    page = response.json()
    return [item["title"] for item in page["items"]], page["next_page"]


async def scroll(
    api: httpx2.AsyncClient, *, between_pages: Any = None, **params: Any
) -> list[str]:
    """Titles of all pages; ``between_pages`` runs before each next page."""
    titles, cursor = await get_page(api, **params)
    while cursor is not None:
        if between_pages is not None:
            await between_pages()
        page, cursor = await get_page(api, cursor=cursor, **params)
        titles += page
    return titles


@pytest.mark.parametrize(
    ("order_by", "expected"),
    [
        ("created_at", ["n0", "n1", "n2", "n3", "n4"]),
        ("-created_at", ["n4", "n3", "n2", "n1", "n0"]),
        ("title", ["n0", "n1", "n2", "n3", "n4"]),
        ("-title", ["n4", "n3", "n2", "n1", "n0"]),
    ],
)
async def test_pages_cover_the_list_in_order(
    api: httpx2.AsyncClient,
    session: AsyncSession,
    order_by: str,
    expected: list[str],
) -> None:
    await add_notes(session, [f"n{i}" for i in range(5)], START)

    first, cursor = await get_page(api, size=2, order_by=order_by)

    assert first == expected[:2]
    assert cursor is not None
    assert await scroll(api, size=2, order_by=order_by) == expected


async def test_equal_sort_keys_are_neither_lost_nor_repeated(
    api: httpx2.AsyncClient, session: AsyncSession
) -> None:
    await add_notes(session, ["same"] * 7, START)

    titles = await scroll(api, size=3, order_by="title")

    assert titles == ["same"] * 7


@pytest.mark.parametrize(
    ("order_by", "inserted"),
    [
        # A feed: newer notes appear above the part already seen.
        ("-created_at", ["new0", "new1"]),
        # Alphabetical: new notes land both before and after the cursor.
        ("title", ["a-new", "m-new", "z-new"]),
    ],
)
async def test_inserts_while_scrolling_do_not_shift_pages(
    api: httpx2.AsyncClient,
    session: AsyncSession,
    order_by: str,
    inserted: list[str],
) -> None:
    original = [f"n{i:02}" for i in range(10)]
    await add_notes(session, original, START)
    pending = iter(inserted)
    later = START + timedelta(days=1)

    async def insert_one() -> None:
        title = next(pending, None)
        if title is not None:
            await add_notes(session, [title], later)

    titles = await scroll(api, between_pages=insert_one, size=3, order_by=order_by)

    assert len(titles) == len(set(titles))  # nothing repeated
    assert set(original) <= set(titles)  # nothing lost


async def test_deletes_while_scrolling_do_not_shift_pages(
    api: httpx2.AsyncClient, session: AsyncSession
) -> None:
    await add_notes(session, [f"n{i}" for i in range(6)], START)
    first, cursor = await get_page(api, size=2, order_by="title")
    # Delete the last note seen and the first one not seen yet.
    for title in ("n1", "n2"):
        note_id = await session.scalar(select(Note.id).where(Note.title == title))
        response = await api.delete(
            f"{NOTES_URL}/{note_id}", headers={"Idempotency-Key": str(uuid.uuid4())}
        )
        assert response.status_code == 204

    rest, _ = await get_page(api, size=10, order_by="title", cursor=cursor)

    assert first == ["n0", "n1"]
    assert rest == ["n3", "n4", "n5"]


async def test_empty_list_has_no_next_page(api: httpx2.AsyncClient) -> None:
    assert await get_page(api) == ([], None)


async def test_default_and_maximum_page_size(
    api: httpx2.AsyncClient, session: AsyncSession
) -> None:
    await add_notes(session, [f"n{i:03}" for i in range(101)], START)

    default_page, _ = await get_page(api)
    largest_page, _ = await get_page(api, size=100)
    too_large = await api.get(
        NOTES_URL, params={"size": 101}, headers={"Accept-Language": "en"}
    )
    too_small = await api.get(NOTES_URL, params={"size": 0})

    assert len(default_page) == 20
    assert len(largest_page) == 100
    assert too_large.status_code == 422
    assert too_large.json()["errors"] == [
        {
            "parameter": "size",
            "code": "less_than_equal",
            "detail": "Must be at most 100.",
        }
    ]
    assert too_small.status_code == 422


def encode(text: str) -> str:
    return base64.urlsafe_b64encode(text.encode()).decode().rstrip("=")


async def test_invalid_cursors_are_rejected(
    api: httpx2.AsyncClient, session: AsyncSession
) -> None:
    await add_notes(session, ["a", "b", "c"], START)
    _, title_cursor = await get_page(api, size=1, order_by="title")
    assert title_cursor is not None
    signature = base64.urlsafe_b64decode(title_cursor + "==").decode()[:16]

    cursors = [
        "%%%",  # not base64
        "_w",  # not UTF-8 once decoded
        encode("short"),  # no ordering signature
        encode(signature + "garbage"),  # not a bookmark
        encode(signature + ">i:1~i:2~i:3"),  # wrong number of sort keys
        encode(signature + ">i:1~i:2"),  # wrong types of sort keys
    ]
    for cursor in cursors:
        response = await api.get(
            NOTES_URL, params={"cursor": cursor, "order_by": "title"}
        )
        assert response.status_code == 400, cursor
        assert response.json()["code"] == "invalid_cursor"


async def test_cursor_of_another_ordering_is_rejected(
    api: httpx2.AsyncClient, session: AsyncSession
) -> None:
    await add_notes(session, ["a", "b", "c"], START)
    _, cursor = await get_page(api, size=1, order_by="title")

    response = await api.get(
        NOTES_URL, params={"cursor": cursor, "order_by": "-created_at"}
    )

    assert response.status_code == 400
    assert response.json()["code"] == "invalid_cursor"
