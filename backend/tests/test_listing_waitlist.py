"""Acceptance of the shared listing queue and its timed place offers."""

import asyncio
from datetime import timedelta
from typing import Any
from uuid import UUID

import httpx2
import pytest
import time_machine
from sqlalchemy import func, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncEngine

from campus.core import clock
from campus.core.db import create_session_factory
from campus.core.deadlines import process_due_deadlines
from campus.core.outbox import OutboxMessage
from campus.modules.identity import User
from campus.modules.listings import (
    TYPE_POLICIES,
    Interaction,
    Listing,
    ListingStatus,
    TypePolicy,
    WaitlistEntry,
    WaitlistStatus,
)
from tests.test_identity import Auth
from tests.test_listings import (
    auth,
    borrower,
    move,
    owner,
    places,
    publish,
    request,
    reserve,
    staff,
)
from tests.test_profile import Account, Places, moscow_profile

__all__ = ["auth", "borrower", "owner", "places", "staff"]


@pytest.fixture(autouse=True)
def long_lived_test_access(auth: Auth) -> None:
    """Keep HTTP credentials valid while waiting out offer timers."""
    auth.settings = auth.settings.model_copy(
        update={"access_token_ttl": timedelta(days=365)}
    )
    auth.app.state.settings = auth.settings


async def queuer(auth: Auth, places: Places, number: int) -> Account:
    account = Account(
        auth, await auth.login(email=f"queuer{number}@university.example")
    )
    assert (await account.put(moscow_profile(places))).status_code == 200
    return account


async def join(account: Account, listing: dict[str, Any]) -> httpx2.Response:
    return await request(account, "POST", f"/{listing['id']}/waitlist")


async def leave(account: Account, listing: dict[str, Any]) -> httpx2.Response:
    return await request(account, "DELETE", f"/{listing['id']}/waitlist")


async def offer(
    account: Account, listing: dict[str, Any], action: str
) -> httpx2.Response:
    return await request(account, "POST", f"/{listing['id']}/waitlist/offer/{action}")


async def my_entry(account: Account, listing: dict[str, Any]) -> httpx2.Response:
    return await request(account, "GET", f"/{listing['id']}/waitlist/me")


async def busy(
    owner_account: Account, borrower_account: Account
) -> tuple[dict[str, Any], dict[str, Any]]:
    listing = await publish(owner_account)
    interaction = (await reserve(borrower_account, listing)).json()
    return listing, interaction


async def deadlines(account: Account) -> int:
    assert isinstance(account.auth.db.bind, AsyncEngine)
    return await process_due_deadlines(
        create_session_factory(account.auth.db.bind), account.auth.settings
    )


def settings(account: Account, **changes: Any) -> None:
    account.auth.settings = account.auth.settings.model_copy(update=changes)
    account.auth.app.state.settings = account.auth.settings


async def notifications(account: Account) -> list[OutboxMessage]:
    return list(
        await account.auth.db.scalars(
            select(OutboxMessage)
            .where(OutboxMessage.topic == "notifications.send")
            .order_by(OutboxMessage.id)
        )
    )


async def count_entries(account: Account) -> int:
    count = await account.auth.db.scalar(
        select(func.count()).select_from(WaitlistEntry)
    )
    return count or 0


async def test_join_requires_an_occupied_listing(
    owner: Account, borrower: Account, staff: Account
) -> None:
    listing = await publish(owner, audience="community")
    response = await join(borrower, listing)
    assert response.status_code == 409
    assert response.json()["code"] == "listing_waitlist_free"
    assert response.headers["content-type"] == "application/problem+json"
    assert (await reserve(borrower, listing)).status_code == 201
    first = await join(staff, listing)
    assert first.status_code == 201, first.text
    assert first.json()["position"] == 1
    assert first.json()["status"] == "waiting"
    me = await my_entry(staff, listing)
    assert me.json()["position"] == 1
    assert (await leave(staff, listing)).status_code == 204
    assert (await my_entry(staff, listing)).status_code == 404


async def test_one_position_even_in_parallel(
    owner: Account, borrower: Account, places: Places
) -> None:
    listing, _ = await busy(owner, borrower)
    account = await queuer(owner.auth, places, 1)
    responses = await asyncio.gather(*(join(account, listing) for _ in range(8)))
    assert sorted(response.status_code for response in responses) == [201] + [409] * 7
    assert {
        response.json()["code"] for response in responses if response.status_code == 409
    } == {"listing_waitlist_duplicate"}
    assert await count_entries(owner) == 1
    again = await join(account, listing)
    assert again.status_code == 409
    assert again.json()["code"] == "listing_waitlist_duplicate"


async def test_rejection_offers_the_place_with_a_timer(
    owner: Account, borrower: Account, places: Places
) -> None:
    listing, interaction = await busy(owner, borrower)
    first = await queuer(owner.auth, places, 1)
    second = await queuer(owner.auth, places, 2)
    assert (await join(first, listing)).status_code == 201
    assert (await join(second, listing)).status_code == 201
    now = clock.now()
    with time_machine.travel(now, tick=False):
        rejected = await move(owner, listing, interaction, "rejected")
    assert rejected.status_code == 200
    assert rejected.json()["status"] == "rejected"
    offered = (await my_entry(first, listing)).json()
    assert offered["status"] == "offered"
    assert offered["position"] == 1
    assert offered["offer_expires_at"] == (
        now + owner.auth.settings.listing_offer_timeout
    ).isoformat().replace("+00:00", "Z")
    assert (await my_entry(second, listing)).json()["position"] == 2
    assert (await my_entry(second, listing)).json()["status"] == "waiting"

    offer_message = (await notifications(owner))[-1]
    assert offer_message.payload["type"] == "listing.offer"
    assert offer_message.payload["important"] is True
    assert offer_message.payload["recipients"] == [first.tokens["user"]["id"]]
    assert offer_message.payload["params"]["entry_id"] == offered["id"]
    history = (await request(owner, "GET", f"/{listing['id']}/events")).json()["items"]
    assert any(
        event["action"] == "offered"
        and event["waitlist_entry_id"] == offered["id"]
        and event["status"] == "offered"
        for event in history
    )


async def test_unconfirmed_offer_expires_and_moves_on(
    owner: Account, borrower: Account, places: Places
) -> None:
    settings(owner, listing_offer_timeout=timedelta(minutes=30))
    now = clock.now()
    with time_machine.travel(now, tick=False):
        listing, interaction = await busy(owner, borrower)
        first = await queuer(owner.auth, places, 1)
        second = await queuer(owner.auth, places, 2)
        assert (await join(first, listing)).status_code == 201
        assert (await join(second, listing)).status_code == 201
        assert (await move(owner, listing, interaction, "rejected")).status_code == 200
        assert (await my_entry(first, listing)).json()["offer_expires_at"] == (
            now + timedelta(minutes=30)
        ).isoformat().replace("+00:00", "Z")
    with time_machine.travel(
        now + timedelta(minutes=30) - timedelta(seconds=1), tick=False
    ):
        assert await deadlines(owner) == 0
    with time_machine.travel(now + timedelta(minutes=30, seconds=1), tick=False):
        assert await deadlines(owner) == 1
        assert await deadlines(owner) == 0
        expired = (await request(first, "GET", "/waitlist/mine")).json()["items"]
        assert expired[0]["status"] == "expired"
        assert (await my_entry(first, listing)).status_code == 404
        moved = (await my_entry(second, listing)).json()
        assert moved["status"] == "offered"
        assert moved["position"] == 1
        assert moved["offer_expires_at"] == (
            now + timedelta(minutes=30, seconds=1) + timedelta(minutes=30)
        ).isoformat().replace("+00:00", "Z")
    message = (await notifications(owner))[-1]
    assert message.payload["type"] == "listing.offer"
    assert message.payload["recipients"] == [second.tokens["user"]["id"]]
    history = (await request(owner, "GET", f"/{listing['id']}/events")).json()["items"]
    assert [
        event["action"]
        for event in history
        if event["action"]
        in {
            "offered",
            "offer_expired",
        }
    ] == ["offered", "offer_expired", "offered"]
    assert any(
        event["action"] == "offer_expired" and event["actor_id"] is None
        for event in history
    )


async def test_decline_passes_the_offer_at_once(
    owner: Account, borrower: Account, places: Places
) -> None:
    listing, interaction = await busy(owner, borrower)
    first = await queuer(owner.auth, places, 1)
    second = await queuer(owner.auth, places, 2)
    assert (await join(first, listing)).status_code == 201
    assert (await join(second, listing)).status_code == 201
    assert (await move(owner, listing, interaction, "rejected")).status_code == 200
    declined = await offer(first, listing, "decline")
    assert declined.status_code == 200, declined.text
    assert declined.json()["status"] == "declined"
    moved = (await my_entry(second, listing)).json()
    assert moved["status"] == "offered"
    assert moved["position"] == 1
    assert (await offer(first, listing, "decline")).status_code == 409
    history = (await request(owner, "GET", f"/{listing['id']}/events")).json()["items"]
    assert any(
        event["action"] == "offer_declined"
        and event["actor_id"] == first.tokens["user"]["id"]
        for event in history
    )


async def test_confirmed_offer_becomes_an_application(
    owner: Account, borrower: Account, places: Places
) -> None:
    listing, interaction = await busy(owner, borrower)
    first = await queuer(owner.auth, places, 1)
    second = await queuer(owner.auth, places, 2)
    assert (await join(first, listing)).status_code == 201
    assert (await join(second, listing)).status_code == 201
    assert (await move(owner, listing, interaction, "rejected")).status_code == 200
    accepted = await offer(first, listing, "accept")
    assert accepted.status_code == 201, accepted.text
    application = accepted.json()
    assert application["status"] == "pending"
    assert application["participant_id"] == first.tokens["user"]["id"]
    assert (await request(owner, "GET", f"/{listing['id']}")).json()["status"] == "busy"
    assert (await my_entry(first, listing)).status_code == 404
    mine = (await request(first, "GET", "/waitlist/mine")).json()["items"]
    assert mine[0]["status"] == "claimed"
    assert mine[0]["interaction_id"] == application["id"]
    assert mine[0]["position"] is None
    assert (await my_entry(second, listing)).json()["position"] == 1
    assert (await move(owner, listing, application, "accepted")).status_code == 200
    assert (await move(first, listing, application, "cancelled")).status_code == 200
    assert (await request(owner, "GET", f"/{listing['id']}")).json()[
        "status"
    ] == "active"
    assert (await my_entry(second, listing)).json()["status"] == "offered"
    assert await count_entries(owner) == 2


async def test_accepting_race_with_a_direct_reservation(
    owner: Account, borrower: Account, places: Places
) -> None:
    listing, interaction = await busy(owner, borrower)
    first = await queuer(owner.auth, places, 1)
    outsider = await queuer(owner.auth, places, 2)
    assert (await join(first, listing)).status_code == 201
    assert (await move(owner, listing, interaction, "rejected")).status_code == 200
    responses = await asyncio.gather(
        offer(first, listing, "accept"), reserve(outsider, listing)
    )
    assert sorted(response.status_code for response in responses) == [201, 409]
    assert (await count_entries(owner)) == 1
    active = await owner.auth.db.scalar(
        select(func.count())
        .select_from(Interaction)
        .where(Interaction.status.in_(("pending", "accepted")))
    )
    assert active == 1
    application = (await request(first, "GET", "/reservations/mine")).json()["items"]
    assert len(application) == 1
    assert application[0]["status"] == "pending"


async def test_cancel_clears_the_queue_and_notifies(
    owner: Account, borrower: Account, places: Places
) -> None:
    listing, interaction = await busy(owner, borrower)
    first = await queuer(owner.auth, places, 1)
    second = await queuer(owner.auth, places, 2)
    assert (await join(first, listing)).status_code == 201
    assert (await join(second, listing)).status_code == 201
    assert (await move(owner, listing, interaction, "rejected")).status_code == 200
    assert (await request(owner, "POST", f"/{listing['id']}/cancel")).status_code == 200
    assert (await count_entries(owner)) == 2
    assert {
        entry.status for entry in await owner.auth.db.scalars(select(WaitlistEntry))
    } == {"removed"}
    cleared = [
        message
        for message in await notifications(owner)
        if message.payload["type"] == "listing.waitlist_cleared"
    ]
    assert {message.payload["recipients"][0] for message in cleared} == {
        first.tokens["user"]["id"],
        second.tokens["user"]["id"],
    }
    history = (await request(owner, "GET", f"/{listing['id']}/events")).json()["items"]
    assert {
        event["reason"] for event in history if event["action"] == "waitlist_cleared"
    } == {"listing_cancelled"}


async def test_expiry_clears_the_queue(
    owner: Account, borrower: Account, places: Places
) -> None:
    settings(owner, listing_lifetime=timedelta(minutes=1))
    now = clock.now()
    with time_machine.travel(now, tick=False):
        listing, interaction = await busy(owner, borrower)
        first = await queuer(owner.auth, places, 1)
        assert (await join(first, listing)).status_code == 201
        assert (await move(owner, listing, interaction, "rejected")).status_code == 200
    with time_machine.travel(now + timedelta(minutes=2), tick=False):
        await deadlines(owner)
    assert (await request(owner, "GET", f"/{listing['id']}")).json()[
        "status"
    ] == "expired"
    entry = await owner.auth.db.scalar(select(WaitlistEntry))
    assert entry is not None
    assert entry.status == "removed"
    assert any(
        message.payload["type"] == "listing.waitlist_cleared"
        for message in await notifications(owner)
    )


async def test_offer_is_capped_by_the_start_time(
    owner: Account,
    borrower: Account,
    places: Places,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    now = clock.now()
    starts_at = now + timedelta(hours=2, minutes=30)
    monkeypatch.setitem(
        TYPE_POLICIES,
        "giveaway",
        TypePolicy(True, capacity=1, start_time=lambda _listing: starts_at),
    )
    listing, interaction = await busy(owner, borrower)
    first = await queuer(owner.auth, places, 1)
    with time_machine.travel(now, tick=False):
        assert (await join(first, listing)).status_code == 201
        assert (await move(owner, listing, interaction, "rejected")).status_code == 200
        offered = (await my_entry(first, listing)).json()
        assert offered["offer_expires_at"] == (
            starts_at - owner.auth.settings.listing_open_to_all_before
        ).isoformat().replace("+00:00", "Z")


async def test_places_open_to_all_close_to_the_start(
    owner: Account,
    borrower: Account,
    places: Places,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    now = clock.now()
    starts_at = now + timedelta(minutes=90)
    monkeypatch.setitem(
        TYPE_POLICIES,
        "giveaway",
        TypePolicy(True, capacity=1, start_time=lambda _listing: starts_at),
    )
    settings(owner, listing_open_to_all_before=timedelta(hours=2))
    listing, interaction = await busy(owner, borrower)
    first = await queuer(owner.auth, places, 1)
    second = await queuer(owner.auth, places, 2)
    with time_machine.travel(now, tick=False):
        assert (await join(first, listing)).status_code == 201
        assert (await join(second, listing)).status_code == 201
        assert (await move(owner, listing, interaction, "rejected")).status_code == 200
        # No timed offer: the place is open to everyone at once.
        assert (await my_entry(first, listing)).json()["status"] == "waiting"
        assert (await my_entry(second, listing)).json()["status"] == "waiting"
        opened = [
            message
            for message in await notifications(owner)
            if message.payload["type"] == "listing.waitlist_open"
        ]
        assert len(opened) == 1
        assert set(opened[0].payload["recipients"]) == {
            first.tokens["user"]["id"],
            second.tokens["user"]["id"],
        }
        assert opened[0].payload["important"] is False
        # Any participant can take the place directly.
        assert (await reserve(second, listing)).status_code == 201


async def test_role_and_object_permissions(
    owner: Account,
    borrower: Account,
    staff: Account,
    places: Places,
) -> None:
    listing, _ = await busy(owner, borrower)
    # The author does not queue for their own listing.
    assert (await join(owner, listing)).status_code == 403
    # An employee cannot join a students-only audience.
    assert (await join(staff, listing)).status_code == 403
    community = await publish(owner, audience="community")
    assert (await reserve(staff, community)).status_code == 201
    student = await queuer(owner.auth, places, 1)
    # A participant of the listing cannot also stand in its queue.
    assert (await join(staff, community)).status_code == 409
    assert (await join(student, community)).status_code == 201
    # An employee may join the queue of a "whole community" listing.
    other = await publish(owner, audience="community")
    assert (await reserve(student, other)).status_code == 201
    assert (await join(staff, other)).status_code == 201
    # A former employee loses the ability to join the queue.
    former = await queuer(owner.auth, places, 2)
    assert (await join(former, listing)).status_code == 201
    assert (await leave(former, listing)).status_code == 204
    await owner.auth.db.execute(
        update(User)
        .where(User.id == UUID(former.tokens["user"]["id"]))
        .values(account_type="former_employee")
    )
    await owner.auth.db.commit()
    assert (await join(former, listing)).status_code == 403
    draft = await publish(owner, draft=True)
    assert (await join(student, draft)).status_code == 404
    await owner.auth.db.execute(
        update(Listing)
        .where(Listing.id == UUID(listing["id"]))
        .values(status=ListingStatus.CANCELLED)
    )
    await owner.auth.db.commit()
    assert (await join(student, listing)).status_code == 409


async def test_queue_history_is_private_to_its_member(
    owner: Account, borrower: Account, places: Places
) -> None:
    listing, interaction = await busy(owner, borrower)
    first = await queuer(owner.auth, places, 1)
    second = await queuer(owner.auth, places, 2)
    assert (await join(first, listing)).status_code == 201
    assert (await join(second, listing)).status_code == 201
    assert (await move(owner, listing, interaction, "rejected")).status_code == 200
    assert (await offer(first, listing, "accept")).status_code == 201
    own_entries = (await request(first, "GET", "/waitlist/mine")).json()["items"]
    first_id = own_entries[0]["id"]
    second_id = (await my_entry(second, listing)).json()["id"]
    own = (await request(first, "GET", f"/{listing['id']}/events")).json()["items"]
    assert {
        event["waitlist_entry_id"] for event in own if event["waitlist_entry_id"]
    } == {first_id}
    # A waiting member is not a participant and has no access to the journal.
    assert (await request(second, "GET", f"/{listing['id']}/events")).status_code == 403
    author_view = (await request(owner, "GET", f"/{listing['id']}/events")).json()[
        "items"
    ]
    assert {first_id, second_id} <= {
        event["waitlist_entry_id"] for event in author_view
    }


async def test_join_replays_with_the_same_key(
    owner: Account, borrower: Account, places: Places
) -> None:
    listing, _ = await busy(owner, borrower)
    account = await queuer(owner.auth, places, 1)
    key = "6f1c47e0-1b1a-4f52-9d33-5f0f3a0f0001"
    first = await request(account, "POST", f"/{listing['id']}/waitlist", key=key)
    replay = await request(account, "POST", f"/{listing['id']}/waitlist", key=key)
    assert first.status_code == 201
    assert replay.json() == first.json()
    assert replay.headers["Idempotent-Replayed"] == "true"
    assert await count_entries(owner) == 1


async def test_queue_rows_follow_the_database_invariants(
    owner: Account, borrower: Account, places: Places
) -> None:
    listing, _ = await busy(owner, borrower)
    first = await queuer(owner.auth, places, 1)
    assert (await join(first, listing)).status_code == 201
    db = owner.auth.db
    duplicate = WaitlistEntry(
        listing_id=UUID(listing["id"]),
        participant_id=UUID(first.tokens["user"]["id"]),
        status=WaitlistStatus.WAITING,
    )
    db.add(duplicate)
    with pytest.raises(IntegrityError, match="uq_listing_waitlist_participant"):
        await db.commit()
    await db.rollback()
    other = await queuer(owner.auth, places, 2)
    db.add(
        WaitlistEntry(
            listing_id=UUID(listing["id"]),
            participant_id=UUID(other.tokens["user"]["id"]),
            status=WaitlistStatus.OFFERED,
            offered_at=clock.now(),
            offer_expires_at=clock.now() + timedelta(minutes=5),
        )
    )
    await db.commit()
    db.add(
        WaitlistEntry(
            listing_id=UUID(listing["id"]),
            participant_id=UUID(owner.tokens["user"]["id"]),
            status=WaitlistStatus.OFFERED,
            offered_at=clock.now(),
            offer_expires_at=clock.now() + timedelta(minutes=5),
        )
    )
    with pytest.raises(IntegrityError, match="uq_listing_waitlist_offer"):
        await db.commit()
    await db.rollback()


async def test_queue_views_and_offer_edges(
    owner: Account, borrower: Account, places: Places
) -> None:
    listing, interaction = await busy(owner, borrower)
    first = await queuer(owner.auth, places, 1)
    second = await queuer(owner.auth, places, 2)
    outsider = await queuer(owner.auth, places, 3)
    assert (await join(first, listing)).status_code == 201
    assert (await join(second, listing)).status_code == 201
    queue = (await request(owner, "GET", f"/{listing['id']}/waitlist")).json()["items"]
    assert [item["position"] for item in queue] == [1, 2]
    assert [item["participant_id"] for item in queue] == [
        first.tokens["user"]["id"],
        second.tokens["user"]["id"],
    ]
    assert all(item["participant_name"] for item in queue)
    assert (
        await request(borrower, "GET", f"/{listing['id']}/waitlist")
    ).status_code == 403
    assert (await move(owner, listing, interaction, "rejected")).status_code == 200
    # The active offer reserves the place for its holder.
    blocked = await reserve(outsider, listing)
    assert blocked.status_code == 409
    assert blocked.json()["code"] == "listing_offer_pending"
    # Leaving while offered gives the place to the next member.
    assert (await leave(first, listing)).status_code == 204
    moved = (await my_entry(second, listing)).json()
    assert moved["status"] == "offered"
    history = (await request(owner, "GET", f"/{listing['id']}/events")).json()["items"]
    left = (await request(first, "GET", "/waitlist/mine")).json()["items"][0]
    assert any(
        event["action"] == "offer_declined"
        and event["waitlist_entry_id"] == left["id"]
        and event["actor_id"] == first.tokens["user"]["id"]
        for event in history
    )
    now = clock.now()
    with time_machine.travel(
        now + owner.auth.settings.listing_offer_timeout + timedelta(seconds=1),
        tick=False,
    ):
        expired = await offer(second, listing, "accept")
        assert expired.status_code == 409
        assert expired.json()["code"] == "listing_offer_expired"
        assert await deadlines(owner) == 1
        assert (await request(owner, "GET", f"/{listing['id']}")).json()[
            "status"
        ] == "active"
    assert (await my_entry(second, listing)).status_code == 404
