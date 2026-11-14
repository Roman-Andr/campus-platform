"""Full-text discovery uses the feed's authorization and keyset pagination."""

from datetime import timedelta
from typing import Any
from urllib.parse import urlencode
from uuid import UUID

import pytest
import time_machine
from sqlalchemy import text, update

from campus.core import clock
from campus.modules.identity import Role, User
from campus.modules.listings import Listing
from tests.test_feed import grant, notice
from tests.test_listings import borrower, owner, publish, request, staff
from tests.test_profile import Account, Places, auth, places

__all__ = ["auth", "borrower", "owner", "places", "staff"]


async def search(account: Account, q: str, **filters: object) -> dict[str, Any]:
    response = await request(account, "GET", "?" + urlencode({"q": q, **filters}))
    assert response.status_code == 200, response.text
    result: dict[str, Any] = response.json()
    return result


async def test_morphology_ranking_and_updates(owner: Account) -> None:
    ru = await publish(owner, title="Отдам велосипед")
    en = await publish(owner, title="Giving away a bike")
    description = await publish(owner, title="Transport", description="A bike")
    mixed = await publish(owner, title="Велосипед bike")
    assert ru["id"] in [i["id"] for i in (await search(owner, "велосипеды"))["items"]]
    items = (await search(owner, "bikes"))["items"]
    assert {i["id"] for i in items} == {en["id"], description["id"], mixed["id"]}
    assert items[-1]["id"] == description["id"]
    assert (await search(owner, "велосипеды bikes"))["items"][0]["id"] == mixed["id"]
    edited = await request(
        owner,
        "PATCH",
        f"/{ru['id']}",
        {"title": "Учебники", "description": "Книги", "version": ru["version"]},
    )
    assert edited.status_code == 200, edited.text
    assert [i["id"] for i in (await search(owner, "велосипеды"))["items"]] == [
        mixed["id"]
    ]
    assert (await search(owner, "учебник"))["items"][0]["id"] == ru["id"]


@pytest.mark.parametrize("q", ["", "   ", "the and", "несуществующий", "!!!"])
async def test_empty_queries(owner: Account, q: str) -> None:
    await publish(owner)
    assert await search(owner, q) == {"items": [], "next_page": None}


async def test_status_scope_audience_and_filters(
    owner: Account, borrower: Account, staff: Account, places: Places
) -> None:
    wanted = await publish(owner, title="Bike", audience="community")
    students = await publish(owner, title="Bike")
    await publish(owner, title="Bike", draft=True)
    for status in ("hidden", "expired", "completed", "cancelled"):
        item = await publish(owner, title="Bike")
        await owner.auth.db.execute(
            update(Listing).where(Listing.id == UUID(item["id"])).values(status=status)
        )
    expired = await publish(owner, title="Bike")
    await owner.auth.db.execute(
        update(Listing)
        .where(Listing.id == UUID(expired["id"]))
        .values(expires_at=clock.now() - timedelta(seconds=1))
    )
    foreign = await publish(owner, title="Bike", visibility="dormitory")
    await owner.auth.db.execute(
        update(Listing)
        .where(Listing.id == UUID(foreign["id"]))
        .values(dormitory_id=places.perm_dormitory)
    )
    await owner.auth.db.commit()
    assert {i["id"] for i in (await search(borrower, "bikes"))["items"]} == {
        wanted["id"],
        students["id"],
    }
    assert [i["id"] for i in (await search(staff, "bikes"))["items"]] == [wanted["id"]]
    filtered = await search(
        borrower,
        "bikes",
        kind="giveaway",
        category_id=wanted["category_id"],
        dormitory_id=places.dubki,
    )
    assert len(filtered["items"]) == 2
    for filters in (
        {"kind": "publication"},
        {"dormitory_id": places.perm_dormitory},
        {"area": "faculty"},
    ):
        assert (await search(borrower, "bikes", **filters))["items"] == []
    await owner.auth.db.execute(
        update(User)
        .where(User.id == UUID(borrower.tokens["user"]["id"]))
        .values(
            city_id=places.perm,
            dormitory_id=places.perm_dormitory,
            faculty_id=places.perm_faculty,
        )
    )
    await owner.auth.db.commit()
    assert (await search(borrower, "bikes"))["items"] == []


async def test_ranked_pages_bind_query_filters_and_snapshot(owner: Account) -> None:
    await grant(owner, Role.ADMINISTRATOR)
    with time_machine.travel(clock.now(), tick=False) as traveller:
        await notice(owner, title="Notice", description="A bike")
        expected: list[str] = []
        for _ in range(4):
            traveller.shift(timedelta(seconds=1))
            item = await publish(owner, title="Bike")
            expected.insert(0, item["id"])
        first = await search(owner, "bikes", size=2)
        assert [i["id"] for i in first["items"]] == expected[:2]
        cursor = first["next_page"]
        for changed in ({"q": "desks"}, {"q": "bikes", "kind": "giveaway"}):
            response = await request(
                owner,
                "GET",
                "?"
                + urlencode(
                    {
                        **changed,
                        "cursor": cursor,
                        "size": 2,
                    }
                ),
            )
            assert response.status_code == 400
        traveller.shift(timedelta(seconds=1))
        await publish(owner, title="Bike")
        second = await search(owner, "bikes", cursor=cursor, size=2)
        assert [i["id"] for i in second["items"]] == expected[2:]
        third = await search(owner, "bikes", cursor=second["next_page"], size=2)
        assert third["items"][0]["kind"] == "publication"
        assert third["next_page"] is None


async def test_gin_index_plan(owner: Account) -> None:
    await publish(owner, title="Bike")
    # A tiny fixture normally favors a sequential scan. Disable it locally
    # to verify that the actual search predicate can use the GIN access path.
    await owner.auth.db.execute(text("SET LOCAL enable_seqscan = off"))
    plan = await owner.auth.db.scalars(
        text(
            "EXPLAIN SELECT id FROM listing WHERE search_vector @@ "
            "(plainto_tsquery('russian', 'bikes') || "
            "plainto_tsquery('english', 'bikes'))"
        )
    )
    assert "Bitmap Index Scan on ix_listing_search" in "\n".join(plan)
