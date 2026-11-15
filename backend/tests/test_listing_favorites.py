"""Favorites and the private "mine" views on real PostgreSQL over HTTP."""

import asyncio
from datetime import timedelta
from typing import Any
from uuid import uuid4

import time_machine
from sqlalchemy import func, select, update

from campus.core import clock
from campus.modules.listings import Favorite, Listing, ListingStatus
from campus.modules.university import Faculty
from tests.test_listings import (
    borrower,
    owner,
    publish,
    request,
    reserve,
    staff,
)
from tests.test_profile import Account, Places, auth, moscow_profile, places

__all__ = ["auth", "borrower", "owner", "places", "staff"]


async def favorites(account: Account) -> list[dict[str, Any]]:
    response = await request(account, "GET", "/favorites")
    assert response.status_code == 200, response.text
    items: list[dict[str, Any]] = response.json()["items"]
    return items


async def test_repeated_and_parallel_adds_keep_one(
    owner: Account, borrower: Account
) -> None:
    listing = await publish(owner)
    path = f"/{listing['id']}/favorite"
    responses = await asyncio.gather(
        *(request(borrower, "PUT", path) for _ in range(8))
    )
    assert {response.status_code for response in responses} == {204}
    assert (await request(borrower, "PUT", path)).status_code == 204
    count = await owner.auth.db.scalar(select(func.count()).select_from(Favorite))
    assert count == 1
    [item] = await favorites(borrower)
    assert item["available"] is True
    assert item["listing"]["id"] == listing["id"]
    assert item["listing"]["favorite"] is True
    card = (await request(borrower, "GET", f"/{listing['id']}")).json()
    assert card["favorite"] is True
    feed = (await request(borrower, "GET")).json()["items"]
    assert [entry["favorite"] for entry in feed] == [True]
    assert (await request(owner, "GET")).json()["items"][0]["favorite"] is False
    assert (await request(borrower, "DELETE", path)).status_code == 204
    assert (await request(borrower, "DELETE", path)).status_code == 204
    assert await favorites(borrower) == []
    card = (await request(borrower, "GET", f"/{listing['id']}")).json()
    assert card["favorite"] is False


async def test_unavailable_favorites_hide_content(
    owner: Account, borrower: Account, places: Places
) -> None:
    hidden = await publish(owner, title="Hidden")
    expired = await publish(owner, title="Expired")
    closed = await publish(owner, title="Closed")
    faculty = await publish(owner, title="Faculty", visibility="faculty")
    alive = await publish(owner, title="Alive")
    for listing in (hidden, expired, closed, faculty, alive):
        response = await request(borrower, "PUT", f"/{listing['id']}/favorite")
        assert response.status_code == 204
    db = owner.auth.db
    await db.execute(
        update(Listing)
        .where(Listing.id == hidden["id"])
        .values(status=ListingStatus.HIDDEN)
    )
    await db.execute(
        update(Listing)
        .where(Listing.id == expired["id"])
        .values(expires_at=clock.now() - timedelta(seconds=1))
    )
    assert (await request(owner, "POST", f"/{closed['id']}/cancel")).status_code == 200
    other = Faculty(
        city_id=places.moscow, code="other", name_ru="Другой", name_en="Other"
    )
    db.add(other)
    await db.commit()
    profile = moscow_profile(places, faculty_id=str(other.id))
    assert (await borrower.put(profile)).status_code == 200
    items = {item["listing_id"]: item for item in await favorites(borrower)}
    assert items[alive["id"]]["available"] is True
    assert items[alive["id"]]["listing"]["title"] == "Alive"
    for listing in (hidden, expired, closed, faculty):
        item = items[listing["id"]]
        assert item == {
            "listing_id": listing["id"],
            "created_at": item["created_at"],
            "available": False,
        }
    # Unavailable bookmarks can still be removed.
    response = await request(borrower, "DELETE", f"/{hidden['id']}/favorite")
    assert response.status_code == 204
    assert hidden["id"] not in {
        item["listing_id"] for item in await favorites(borrower)
    }


async def test_cannot_bookmark_invisible_listings(
    owner: Account, borrower: Account, staff: Account
) -> None:
    draft = await publish(owner, draft=True)
    students = await publish(owner)
    for account, listing in ((borrower, draft), (owner, draft), (staff, students)):
        response = await request(account, "PUT", f"/{listing['id']}/favorite")
        assert response.status_code == 404
    assert (await request(borrower, "PUT", f"/{uuid4()}/favorite")).status_code == 404
    community = await publish(owner, audience="community")
    response = await request(staff, "PUT", f"/{community['id']}/favorite")
    assert response.status_code == 204


async def test_favorites_are_private(owner: Account, borrower: Account) -> None:
    listing = await publish(owner)
    assert (
        await request(borrower, "PUT", f"/{listing['id']}/favorite")
    ).status_code == 204
    assert await favorites(owner) == []
    # Removing another user's bookmark id only touches the caller's own rows.
    assert (
        await request(owner, "DELETE", f"/{listing['id']}/favorite")
    ).status_code == 204
    assert len(await favorites(borrower)) == 1


async def test_favorites_paginate_newest_first(
    owner: Account, borrower: Account
) -> None:
    listings = [await publish(owner, title=f"Item {i}") for i in range(3)]
    for offset, listing in enumerate(listings):
        with time_machine.travel(clock.now() + timedelta(seconds=offset), tick=False):
            response = await request(borrower, "PUT", f"/{listing['id']}/favorite")
            assert response.status_code == 204
    first = (await request(borrower, "GET", "/favorites?size=2")).json()
    assert [item["listing_id"] for item in first["items"]] == [
        listings[2]["id"],
        listings[1]["id"],
    ]
    second = (
        await request(borrower, "GET", f"/favorites?size=2&cursor={first['next_page']}")
    ).json()
    assert [item["listing_id"] for item in second["items"]] == [listings[0]["id"]]
    assert second["next_page"] is None


async def test_mine_filters_by_status(owner: Account, borrower: Account) -> None:
    draft = await publish(owner, draft=True)
    active = await publish(owner)
    busy = await publish(owner)
    assert (await reserve(borrower, busy)).status_code == 201
    expired = await publish(owner)
    await owner.auth.db.execute(
        update(Listing)
        .where(Listing.id == expired["id"])
        .values(status=ListingStatus.EXPIRED)
    )
    await owner.auth.db.commit()
    everything = (await request(owner, "GET", "/mine")).json()["items"]
    assert {item["status"] for item in everything} == {
        "draft",
        "active",
        "busy",
        "expired",
    }
    for status, listing in (
        ("draft", draft),
        ("active", active),
        ("busy", busy),
        ("expired", expired),
    ):
        page = (await request(owner, "GET", f"/mine?status={status}")).json()
        assert [item["id"] for item in page["items"]] == [listing["id"]]
    archive = await request(
        owner, "GET", "/mine?status=expired&status=completed&status=cancelled"
    )
    assert [item["id"] for item in archive.json()["items"]] == [expired["id"]]
    assert (await request(borrower, "GET", "/mine?status=busy")).json()["items"] == []
    invalid = await request(owner, "GET", "/mine?status=unknown")
    assert invalid.status_code == 422


async def test_participation_carries_listing_summary(
    owner: Account, borrower: Account
) -> None:
    listing = await publish(owner, title="Lamp")
    interaction = (await reserve(borrower, listing)).json()
    [item] = (await request(borrower, "GET", "/reservations/mine")).json()["items"]
    assert item["id"] == interaction["id"]
    assert item["status"] == "pending"
    assert item["stage"] is None
    assert item["created_at"].endswith("Z")
    assert item["listing"] == {
        "id": listing["id"],
        "kind": "giveaway",
        "title": "Lamp",
        "status": "busy",
        "city_timezone": "Europe/Moscow",
        "purchase_unit_price": None,
    }
    assert (await request(owner, "GET", "/reservations/mine")).json()["items"] == []
