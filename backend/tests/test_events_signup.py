"""Event signup invariants through concurrent HTTP requests on PostgreSQL."""

import asyncio
from datetime import timedelta
from typing import Any
from uuid import UUID

import pytest
import time_machine
from sqlalchemy import update

from campus.core import clock
from campus.modules.identity import User
from tests.test_listing_waitlist import (
    auth,
    borrower,
    deadlines,
    long_lived_test_access,
    my_entry,
    notifications,
    offer,
    owner,
    places,
    queuer,
    staff,
)
from tests.test_listings import move, request
from tests.test_profile import Account, Places

__all__ = ["auth", "borrower", "long_lived_test_access", "owner", "places", "staff"]


async def event(account: Account, **changes: Any) -> dict[str, Any]:
    category = (await request(account, "GET", "/categories")).json()["items"][0]["id"]
    response = await request(
        account,
        "POST",
        "/events",
        {
            "title": "Campus concert",
            "description": "Meet in the hall",
            "category_id": category,
            "starts_at": (clock.now() + timedelta(days=3)).isoformat(),
            "ends_at": (clock.now() + timedelta(days=3, hours=2)).isoformat(),
            "location": "Hall A",
            "capacity": 1,
            **changes,
        },
    )
    assert response.status_code == 201, response.text
    return response.json()  # type: ignore[no-any-return]


async def signup(
    account: Account,
    listing: dict[str, Any],
    queue: bool = False,
    key: str | None = None,
) -> Any:
    return await request(
        account, "POST", f"/{listing['id']}/signup", {"join_queue": queue}, key=key
    )


async def edit(account: Account, listing: dict[str, Any], **changes: Any) -> Any:
    response = await request(account, "GET", f"/{listing['id']}")
    current = response.json() if response.status_code == 200 else listing
    return await request(
        account,
        "PATCH",
        f"/{listing['id']}/event",
        {
            "version": current["version"],
            "starts_at": current["event_starts_at"],
            "ends_at": current["event_ends_at"],
            "location": current["event_location"],
            "capacity": current["event_capacity"],
            **changes,
        },
    )


async def test_parallel_last_places_and_retries(owner: Account, places: Places) -> None:
    listing = await event(owner, capacity=3)
    accounts = [await queuer(owner.auth, places, i) for i in range(12)]
    replies = await asyncio.gather(
        *(signup(account, listing, i % 2 == 0) for i, account in enumerate(accounts))
    )
    assert {reply.status_code for reply in replies} == {200}
    assert sum(reply.json()["result"] == "registered" for reply in replies) == 3
    assert {reply.json()["result"] for reply in replies} <= {
        "registered",
        "queued",
        "full",
    }
    registered = next(
        account
        for account, reply in zip(accounts, replies, strict=True)
        if reply.json()["result"] == "registered"
    )
    key = "d019c075-6f9f-42ce-b51b-000000000052"
    first = await signup(registered, listing, key=key)
    again = await signup(registered, listing, key=key)
    assert again.json() == first.json()
    assert again.headers["Idempotent-Replayed"] == "true"
    assert (await request(owner, "GET", f"/{listing['id']}")).json()[
        "remaining_places"
    ] == 0
    history = (await request(owner, "GET", f"/{listing['id']}/events")).json()["items"]
    assert len([item for item in history if item["action"] == "requested"]) == 3
    assert (
        len(
            [
                item
                for item in history
                if item["action"] == "transition" and item["status"] == "accepted"
            ]
        )
        == 3
    )


async def test_cancel_offers_and_capacity_increase(
    owner: Account, borrower: Account, places: Places
) -> None:
    listing = await event(owner)
    interaction = (await signup(borrower, listing)).json()["interaction"]
    first, second, third = [await queuer(owner.auth, places, i) for i in range(3)]
    for account in (first, second, third):
        assert (await signup(account, listing, True)).json()["result"] == "queued"
    assert (await edit(owner, listing, capacity=2)).status_code == 200
    assert (await my_entry(first, listing)).json()["status"] == "offered"
    assert (await move(borrower, listing, interaction, "cancelled")).status_code == 200
    assert (await my_entry(second, listing)).json()["status"] == "offered"
    assert (await my_entry(third, listing)).json()["status"] == "waiting"
    accepted = await offer(first, listing, "accept")
    assert accepted.status_code == 201, accepted.text
    assert accepted.json()["status"] == "accepted"
    assert accepted.json()["meeting"]["location"] == "Hall A"
    assert (await signup(second, listing)).json()["result"] == "registered"
    assert (await edit(owner, listing, capacity=1)).status_code == 409
    assert (await signup(third, listing)).json()["result"] == "queued"


async def test_open_to_everyone_before_start(
    owner: Account, borrower: Account, places: Places
) -> None:
    now = clock.now()
    # Avoid expiring credentials during controlled travel.
    owner.auth.settings = owner.auth.settings.model_copy(
        update={"access_token_ttl": timedelta(days=365)}
    )
    owner.auth.app.state.settings = owner.auth.settings
    with time_machine.travel(now, tick=False):
        listing = await event(
            owner,
            starts_at=(now + timedelta(hours=2)).isoformat(),
            ends_at=(now + timedelta(hours=4)).isoformat(),
        )
        interaction = (await signup(borrower, listing)).json()["interaction"]
        first = await queuer(owner.auth, places, 1)
        outsider = await queuer(owner.auth, places, 2)
        assert (await signup(first, listing, True)).json()["result"] == "queued"
    with time_machine.travel(now + timedelta(minutes=61), tick=False):
        assert (
            await move(borrower, listing, interaction, "cancelled")
        ).status_code == 200
        assert (await my_entry(first, listing)).json()["status"] == "waiting"
        opened = [
            n
            for n in await notifications(owner)
            if n.payload["type"] == "listing.waitlist_open"
        ]
        assert len(opened) == 1
        assert opened[0].payload["recipients"] == [first.tokens["user"]["id"]]
        assert (await signup(outsider, listing)).json()["result"] == "registered"
    with time_machine.travel(now + timedelta(hours=2), tick=False):
        assert (await signup(first, listing)).status_code == 409


async def test_reminders_and_conditions_change(owner: Account, places: Places) -> None:
    now = clock.now()
    owner.auth.settings = owner.auth.settings.model_copy(
        update={"access_token_ttl": timedelta(days=365)}
    )
    owner.auth.app.state.settings = owner.auth.settings
    with time_machine.travel(now, tick=False):
        participant = await queuer(owner.auth, places, 1)
        waiter = await queuer(owner.auth, places, 2)
        listing = await event(owner)
        interaction = (await signup(participant, listing)).json()["interaction"]
        assert (await signup(waiter, listing, True)).json()["result"] == "queued"
        moved = await edit(
            owner,
            listing,
            starts_at=(now + timedelta(days=4)).isoformat(),
            ends_at=(now + timedelta(days=4, hours=2)).isoformat(),
            location="Hall B",
        )
        assert moved.status_code == 200, moved.text
        changed = [
            n
            for n in await notifications(owner)
            if n.payload["type"] == "listing.event.conditions_changed"
        ]
        assert set(changed[0].payload["recipients"]) == {
            participant.tokens["user"]["id"],
            waiter.tokens["user"]["id"],
        }
        history = (await request(owner, "GET", f"/{listing['id']}/events")).json()[
            "items"
        ]
        assert any(item["action"] == "conditions_changed" for item in history)
    with time_machine.travel(now + timedelta(days=2), tick=False):
        await deadlines(owner)
        assert not [
            n
            for n in await notifications(owner)
            if n.payload["type"] == "listing.meeting.reminder"
        ]
    with time_machine.travel(now + timedelta(days=3), tick=False):
        await deadlines(owner)
        reminders = [
            n
            for n in await notifications(owner)
            if n.payload["type"] == "listing.meeting.reminder"
        ]
        assert len(reminders) == 1
        assert reminders[0].payload["recipients"] == [participant.tokens["user"]["id"]]
        assert reminders[0].payload["params"]["kind"] == "long"
        assert reminders[0].payload["params"]["location"] == "Hall B"
    with time_machine.travel(now + timedelta(days=4) - timedelta(hours=1), tick=False):
        await deadlines(owner)
        reminders = [
            n
            for n in await notifications(owner)
            if n.payload["type"] == "listing.meeting.reminder"
        ]
        assert len(reminders) == 2
        assert reminders[-1].payload["params"]["kind"] == "short"
        assert (
            await move(participant, listing, interaction, "cancelled")
        ).status_code == 200


@pytest.mark.parametrize(
    ("account_type", "audience", "expected"),
    [
        ("student", "students", 200),
        ("employee", "students", 403),
        ("employee", "community", 200),
        ("former_employee", "community", 403),
    ],
)
async def test_signup_permissions(
    owner: Account, borrower: Account, account_type: str, audience: str, expected: int
) -> None:
    listing = await event(owner, audience=audience)
    await owner.auth.db.execute(
        update(User)
        .where(User.id == UUID(borrower.tokens["user"]["id"]))
        .values(account_type=account_type)
    )
    await owner.auth.db.commit()
    assert (await signup(borrower, listing)).status_code == expected
    assert (await signup(owner, listing)).status_code == 403
    assert (await edit(borrower, listing, location="Other")).status_code == 403


@pytest.mark.parametrize(("offset", "end_offset"), [(-1, 1), (1, 0)])
async def test_invalid_times(owner: Account, offset: int, end_offset: int) -> None:
    response = await request(
        owner,
        "POST",
        "/events",
        {
            "title": "Concert",
            "description": "Hall",
            "location": "Hall A",
            "capacity": 1,
            "starts_at": (clock.now() + timedelta(hours=offset)).isoformat(),
            "ends_at": (clock.now() + timedelta(hours=end_offset)).isoformat(),
        },
    )
    assert response.status_code == 422
    assert response.json()["code"] == "event_time_invalid"


async def test_same_participant_parallel_and_cancel_rights(
    owner: Account, borrower: Account, staff: Account
) -> None:
    listing = await event(owner, audience="community", capacity=2)
    responses = await asyncio.gather(*(signup(borrower, listing) for _ in range(6)))
    assert {response.status_code for response in responses} == {200}
    ids = {response.json()["interaction"]["id"] for response in responses}
    assert len(ids) == 1
    interaction = responses[0].json()["interaction"]
    for outsider in (owner, staff):
        assert (
            await move(outsider, listing, interaction, "cancelled")
        ).status_code == 403
    proposal = await request(
        borrower,
        "POST",
        f"/{listing['id']}/interactions/{interaction['id']}/meeting/proposals",
        {
            "time": (clock.now() + timedelta(days=4)).isoformat(),
            "location": "Elsewhere",
        },
    )
    assert proposal.status_code == 409
    assert (await move(borrower, listing, interaction, "cancelled")).status_code == 200
    assert (await move(borrower, listing, interaction, "cancelled")).status_code == 409
    current = (await request(owner, "GET", f"/{listing['id']}")).json()
    assert current["remaining_places"] == 2


async def test_priority_offer_race_and_expiry(
    owner: Account, borrower: Account, places: Places
) -> None:
    now = clock.now()
    with time_machine.travel(now, tick=False):
        listing = await event(owner)
        interaction = (await signup(borrower, listing)).json()["interaction"]
        first, second, outsider = [
            await queuer(owner.auth, places, i) for i in range(3)
        ]
        for account in (first, second):
            assert (await signup(account, listing, True)).json()["result"] == "queued"
        assert (
            await move(borrower, listing, interaction, "cancelled")
        ).status_code == 200
        assert (await signup(outsider, listing)).json()["result"] == "full"
    with time_machine.travel(
        now + owner.auth.settings.listing_offer_timeout + timedelta(seconds=1),
        tick=False,
    ):
        await deadlines(owner)
        assert (await my_entry(first, listing)).status_code == 404
        assert (await my_entry(second, listing)).json()["status"] == "offered"
        replies = await asyncio.gather(
            signup(second, listing), signup(outsider, listing)
        )
        assert [reply.json()["result"] for reply in replies] == ["registered", "full"]


async def test_offers_open_at_one_hour_deadline(
    owner: Account, borrower: Account, places: Places
) -> None:
    now = clock.now()
    with time_machine.travel(now, tick=False):
        listing = await event(
            owner,
            starts_at=(now + timedelta(hours=2)).isoformat(),
            ends_at=(now + timedelta(hours=4)).isoformat(),
        )
        interaction = (await signup(borrower, listing)).json()["interaction"]
        first, second = [await queuer(owner.auth, places, i) for i in range(2)]
        for account in (first, second):
            assert (await signup(account, listing, True)).json()["result"] == "queued"
        assert (
            await move(borrower, listing, interaction, "cancelled")
        ).status_code == 200
        assert (await my_entry(first, listing)).json()["status"] == "offered"
    with time_machine.travel(now + timedelta(hours=1), tick=False):
        await deadlines(owner)
        assert (await my_entry(first, listing)).json()["status"] == "waiting"
        assert (await my_entry(second, listing)).json()["status"] == "waiting"
        assert (await signup(second, listing)).json()["result"] == "registered"
        assert await deadlines(owner) == 0


async def test_queue_and_edit_edges(owner: Account, borrower: Account) -> None:
    listing = await event(owner, capacity=2)
    response = await request(borrower, "POST", f"/{listing['id']}/waitlist")
    assert response.status_code == 409
    assert response.json()["code"] == "listing_waitlist_free"
    stale = await request(
        owner,
        "PATCH",
        f"/{listing['id']}/event",
        {
            "version": listing["version"] + 1,
            "starts_at": listing["event_starts_at"],
            "ends_at": listing["event_ends_at"],
            "location": "Hall B",
            "capacity": 2,
        },
    )
    assert stale.status_code == 409
    assert stale.json()["code"] == "listing_version_conflict"
    assert (await edit(owner, listing, location="  ")).status_code == 422
    assert (await request(owner, "POST", f"/{listing['id']}/extend")).status_code == 409
    assert (
        await request(owner, "POST", f"/{listing['id']}/publish")
    ).status_code == 409


async def test_cancel_removes_pending_reminders(
    owner: Account, borrower: Account
) -> None:
    now = clock.now()
    with time_machine.travel(now, tick=False):
        listing = await event(owner)
        interaction = (await signup(borrower, listing)).json()["interaction"]
        assert (
            await move(borrower, listing, interaction, "cancelled")
        ).status_code == 200
    with time_machine.travel(
        now + timedelta(days=3) - timedelta(minutes=30), tick=False
    ):
        await deadlines(owner)
        assert not [
            n
            for n in await notifications(owner)
            if n.payload["type"] == "listing.meeting.reminder"
        ]


async def test_signup_catches_up_an_expired_offer(
    owner: Account, borrower: Account, places: Places
) -> None:
    now = clock.now()
    with time_machine.travel(now, tick=False):
        listing = await event(owner)
        interaction = (await signup(borrower, listing)).json()["interaction"]
        waiter = await queuer(owner.auth, places, 1)
        assert (await signup(waiter, listing, True)).json()["result"] == "queued"
        assert (
            await move(borrower, listing, interaction, "cancelled")
        ).status_code == 200
    with time_machine.travel(
        now + owner.auth.settings.listing_offer_timeout + timedelta(seconds=1),
        tick=False,
    ):
        # No scheduler call: a direct retry must settle the expired offer itself.
        response = await signup(waiter, listing)
        assert response.status_code == 200, response.text
        assert response.json()["result"] == "registered"
