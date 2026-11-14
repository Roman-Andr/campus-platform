"""Scheduled meetings of accepted interactions: proposals, transfers, reminders."""

import asyncio
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID, uuid4

import httpx2
import pytest
import time_machine
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncEngine

from campus.core import clock
from campus.core.db import create_session_factory
from campus.core.deadlines import Deadline, process_due_deadlines
from campus.core.outbox import OutboxMessage
from campus.modules.listings import Meeting
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
from tests.test_profile import Account

__all__ = ["auth", "borrower", "owner", "places", "staff"]

MEETING_TYPES = {
    "listing.meeting.proposed",
    "listing.meeting.scheduled",
    "listing.meeting.rescheduled",
    "listing.meeting.reminder",
}


@pytest.fixture(autouse=True)
def long_lived_test_access(auth: Auth) -> None:
    """Keep HTTP credentials valid while moving time by days."""
    auth.settings = auth.settings.model_copy(
        update={"access_token_ttl": timedelta(days=365)}
    )
    auth.app.state.settings = auth.settings


def instant(at: datetime) -> str:
    return at.astimezone(UTC).isoformat().replace("+00:00", "Z")


def parse_instant(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


async def accepted(
    owner: Account, borrower: Account, **overrides: Any
) -> tuple[dict[str, Any], dict[str, Any]]:
    listing = await publish(owner, **overrides)
    interaction = (await reserve(borrower, listing)).json()
    response = await move(owner, listing, interaction, "accepted")
    assert response.status_code == 200, response.text
    return listing, response.json()


def meeting_path(
    listing: dict[str, Any], interaction: dict[str, Any], action: str
) -> str:
    return f"/{listing['id']}/interactions/{interaction['id']}/meeting/{action}"


async def propose(  # noqa: PLR0913, PLR0917 - request context
    account: Account,
    listing: dict[str, Any],
    interaction: dict[str, Any],
    at: datetime,
    location: str = "Main library",
    key: str | None = None,
) -> httpx2.Response:
    return await request(
        account,
        "POST",
        meeting_path(listing, interaction, "proposals"),
        {"time": instant(at), "location": location},
        key=key,
    )


async def accept(
    account: Account,
    listing: dict[str, Any],
    interaction: dict[str, Any],
    version: int,
    key: str | None = None,
) -> httpx2.Response:
    return await request(
        account,
        "POST",
        meeting_path(listing, interaction, "accept"),
        {"version": version},
        key=key,
    )


async def event_list(
    account: Account, listing: dict[str, Any], interaction: dict[str, Any]
) -> list[dict[str, Any]]:
    response = await request(
        account,
        "GET",
        f"/{listing['id']}/interactions/{interaction['id']}/events",
    )
    assert response.status_code == 200, response.text
    items: list[dict[str, Any]] = response.json()["items"]
    return items


async def notifications(account: Account) -> list[OutboxMessage]:
    await account.auth.db.rollback()
    rows = await account.auth.db.scalars(
        select(OutboxMessage).order_by(OutboxMessage.id)
    )
    return [message for message in rows if message.payload.get("type") in MEETING_TYPES]


async def reminders(account: Account) -> list[Deadline]:
    await account.auth.db.rollback()
    rows = await account.auth.db.scalars(
        select(Deadline)
        .where(
            Deadline.topic == "listing.meeting_reminder",
            Deadline.is_pending(),
        )
        .order_by(Deadline.available_at)
    )
    return list(rows)


async def meetings(account: Account, interaction: dict[str, Any]) -> list[Meeting]:
    await account.auth.db.rollback()
    rows = await account.auth.db.scalars(
        select(Meeting).where(Meeting.interaction_id == UUID(interaction["id"]))
    )
    return list(rows)


async def run_deadlines(account: Account) -> int:
    assert isinstance(account.auth.db.bind, AsyncEngine)
    return await process_due_deadlines(
        create_session_factory(account.auth.db.bind), account.auth.settings
    )


def user_id(account: Account) -> str:
    return str(account.tokens["user"]["id"])


async def test_author_proposes_and_participant_accepts(
    owner: Account, borrower: Account, staff: Account
) -> None:
    now = clock.now()
    meeting_at = now + timedelta(days=2)
    with time_machine.travel(now, tick=False):
        listing, interaction = await accepted(owner, borrower)
        response = await propose(owner, listing, interaction, meeting_at)
        assert response.status_code == 200, response.text
        proposal = response.json()
        assert proposal["status"] == "proposed"
        assert proposal["version"] == 1
        assert proposal["scheduled_at"] is None
        assert parse_instant(proposal["proposed_at"]) == meeting_at
        assert proposal["proposed_location"] == "Main library"
        assert proposal["proposed_by_id"] == user_id(owner)

        # Only the participants may act, even before the proposal is accepted.
        assert (
            await propose(staff, listing, interaction, meeting_at)
        ).status_code == 403
        assert (await accept(staff, listing, interaction, 1)).status_code == 403

        response = await accept(borrower, listing, interaction, proposal["version"])
        assert response.status_code == 200, response.text
        meeting = response.json()
        assert meeting["status"] == "scheduled"
        assert meeting["version"] == 2
        assert parse_instant(meeting["scheduled_at"]) == meeting_at
        assert meeting["location"] == "Main library"
        assert meeting["scheduled_by_id"] == user_id(owner)
        assert meeting["proposed_at"] is None

        # The meeting is visible in the interaction API of both participants.
        own = (await request(borrower, "GET", "/reservations/mine")).json()["items"]
        item = next(value for value in own if value["id"] == interaction["id"])
        assert item["meeting"]["scheduled_at"] == meeting["scheduled_at"]
        incoming = (
            await request(owner, "GET", f"/{listing['id']}/interactions")
        ).json()["items"]
        assert incoming[0]["meeting"]["location"] == "Main library"

    messages = await notifications(owner)
    assert [message.payload["type"] for message in messages] == [
        "listing.meeting.proposed",
        "listing.meeting.scheduled",
    ]
    proposed, scheduled = messages
    assert proposed.payload["recipients"] == [user_id(borrower)]
    assert scheduled.payload["recipients"] == [user_id(owner)]
    for message in messages:
        assert set(message.payload["text"]) == {"ru", "en"}
        assert all(message.payload["text"].values())


async def test_participant_proposes_and_author_accepts(
    owner: Account, borrower: Account
) -> None:
    now = clock.now()
    meeting_at = now + timedelta(days=1)
    with time_machine.travel(now, tick=False):
        listing, interaction = await accepted(owner, borrower)
        proposal = (
            await propose(borrower, listing, interaction, meeting_at, "Dorm kitchen")
        ).json()
        assert proposal["proposed_by_id"] == user_id(borrower)
        response = await accept(owner, listing, interaction, proposal["version"])
        assert response.status_code == 200, response.text
        meeting = response.json()
        assert meeting["scheduled_by_id"] == user_id(borrower)
        assert meeting["location"] == "Dorm kitchen"


async def test_meeting_requires_an_accepted_interaction(
    owner: Account, borrower: Account
) -> None:
    listing = await publish(owner)
    interaction = (await reserve(borrower, listing)).json()
    at = clock.now() + timedelta(days=1)
    for account in (owner, borrower):
        response = await propose(account, listing, interaction, at)
        assert response.status_code == 409
        assert response.json()["code"] == "meeting_state_conflict"
        assert response.headers["content-type"] == "application/problem+json"


async def test_invalid_time_and_place_are_validation_errors(
    owner: Account, borrower: Account
) -> None:
    listing, interaction = await accepted(owner, borrower)
    now = clock.now()
    past = await propose(owner, listing, interaction, now - timedelta(seconds=1))
    assert past.status_code == 422
    assert past.json()["code"] == "meeting_time_invalid"
    blank = await propose(owner, listing, interaction, now + timedelta(hours=1), "  ")
    assert blank.status_code == 422
    assert blank.json()["code"] == "meeting_place_invalid"
    long = await propose(
        owner, listing, interaction, now + timedelta(hours=1), "x" * 201
    )
    assert long.status_code == 422
    assert long.json()["code"] == "meeting_place_invalid"
    assert await meetings(owner, interaction) == []


async def test_counter_proposal_replaces_pending_and_stale_accept_conflicts(
    owner: Account, borrower: Account
) -> None:
    now = clock.now()
    first_at = now + timedelta(days=2)
    second_at = now + timedelta(days=3)
    with time_machine.travel(now, tick=False):
        listing, interaction = await accepted(owner, borrower)
        first = (await propose(owner, listing, interaction, first_at)).json()
        second = (
            await propose(borrower, listing, interaction, second_at, "Cafe")
        ).json()
        assert second["version"] == first["version"] + 1
        assert second["proposed_by_id"] == user_id(borrower)
        assert parse_instant(second["proposed_at"]) == second_at
        assert second["proposed_location"] == "Cafe"

        stale = await accept(owner, listing, interaction, first["version"])
        assert stale.status_code == 409
        assert stale.json()["code"] == "meeting_stale"
        assert stale.json()["current_version"] == second["version"]
        assert stale.headers["content-type"] == "application/problem+json"

        response = await accept(owner, listing, interaction, second["version"])
        assert response.status_code == 200, response.text
        meeting = response.json()
        assert parse_instant(meeting["scheduled_at"]) == second_at
        assert meeting["location"] == "Cafe"
        assert meeting["scheduled_by_id"] == user_id(borrower)

    events = await event_list(owner, listing, interaction)
    assert [event["action"] for event in events][-3:] == [
        "meeting_proposed",
        "meeting_proposed",
        "meeting_scheduled",
    ]
    assert sum(event["action"] == "meeting_scheduled" for event in events) == 1
    assert (await meetings(owner, interaction))[0].scheduled_at is not None


async def test_reschedule_keeps_previous_time_until_accepted(
    owner: Account, borrower: Account
) -> None:
    now = clock.now()
    first_at = now + timedelta(days=2)
    second_at = now + timedelta(days=4)
    with time_machine.travel(now, tick=False):
        listing, interaction = await accepted(owner, borrower)
        proposal = (await propose(owner, listing, interaction, first_at)).json()
        scheduled = (
            await accept(borrower, listing, interaction, proposal["version"])
        ).json()

        counter = (
            await propose(borrower, listing, interaction, second_at, "Cafe")
        ).json()
        # Before acceptance the previous meeting is still in force.
        assert counter["status"] == "proposed"
        assert parse_instant(counter["scheduled_at"]) == first_at
        assert counter["location"] == "Main library"
        assert parse_instant(counter["proposed_at"]) == second_at
        assert counter["proposed_location"] == "Cafe"

        moved = (await accept(owner, listing, interaction, counter["version"])).json()
        assert parse_instant(moved["scheduled_at"]) == second_at
        assert moved["location"] == "Cafe"
        assert moved["scheduled_by_id"] == user_id(borrower)
        assert moved["status"] == "scheduled"

    events = await event_list(owner, listing, interaction)
    rescheduled = events[-1]
    assert rescheduled["action"] == "meeting_rescheduled"
    assert rescheduled["details"] == {
        "previous_time": parse_instant(scheduled["scheduled_at"]).isoformat(),
        "previous_location": "Main library",
        "time": second_at.isoformat(),
        "location": "Cafe",
    }

    messages = await notifications(owner)
    assert messages[-1].payload["type"] == "listing.meeting.rescheduled"
    assert messages[-1].payload["recipients"] == [user_id(borrower)]
    assert messages[-1].payload["text"]["ru"] == "Встреча перенесена."


async def test_reminders_fire_24h_and_1h_before_the_meeting(
    owner: Account, borrower: Account
) -> None:
    now = clock.now()
    meeting_at = now + timedelta(hours=30)
    with time_machine.travel(now, tick=False):
        listing, interaction = await accepted(owner, borrower)
        proposal = (await propose(owner, listing, interaction, meeting_at)).json()
        await accept(borrower, listing, interaction, proposal["version"])
        pending = await reminders(owner)
        assert [(row.payload["kind"], row.available_at) for row in pending] == [
            ("long", meeting_at - timedelta(hours=24)),
            ("short", meeting_at - timedelta(hours=1)),
        ]

    for moment in (
        now + timedelta(hours=5),
        now + timedelta(hours=6),
        now + timedelta(hours=29),
        now + timedelta(hours=31),
    ):
        with time_machine.travel(moment, tick=False):
            await run_deadlines(owner)
        received = [
            message.payload
            for message in await notifications(owner)
            if message.payload["type"] == "listing.meeting.reminder"
        ]
        expected = {
            now + timedelta(hours=5): 0,
            now + timedelta(hours=6): 1,
            now + timedelta(hours=29): 2,
            now + timedelta(hours=31): 2,
        }[moment]
        assert len(received) == expected

    received = [
        message.payload
        for message in await notifications(owner)
        if message.payload["type"] == "listing.meeting.reminder"
    ]
    assert [value["params"]["kind"] for value in received] == ["long", "short"]
    assert all(
        set(value["recipients"]) == {user_id(owner), user_id(borrower)}
        for value in received
    )


async def test_reminder_is_skipped_when_meeting_is_soon(
    owner: Account, borrower: Account
) -> None:
    now = clock.now()
    with time_machine.travel(now, tick=False):
        listing, interaction = await accepted(owner, borrower)
        proposal = (
            await propose(owner, listing, interaction, now + timedelta(hours=2))
        ).json()
        await accept(borrower, listing, interaction, proposal["version"])
        pending = await reminders(owner)
        assert [row.payload["kind"] for row in pending] == ["short"]


async def test_reschedule_replaces_the_reminders(
    owner: Account, borrower: Account
) -> None:
    now = clock.now()
    first_at = now + timedelta(hours=30)
    second_at = now + timedelta(hours=50)
    with time_machine.travel(now, tick=False):
        listing, interaction = await accepted(owner, borrower)
        proposal = (await propose(owner, listing, interaction, first_at)).json()
        await accept(borrower, listing, interaction, proposal["version"])
    with time_machine.travel(now + timedelta(hours=1), tick=False):
        counter = (await propose(owner, listing, interaction, second_at)).json()
        await accept(borrower, listing, interaction, counter["version"])
        pending = await reminders(owner)
        assert [row.available_at for row in pending] == [
            second_at - timedelta(hours=24),
            second_at - timedelta(hours=1),
        ]

    for moment, expected in (
        (now + timedelta(hours=6), 0),  # the old 24-hour reminder is gone
        (now + timedelta(hours=26), 1),  # the new 24-hour reminder
        (now + timedelta(hours=31), 1),  # the old 1-hour reminder is gone
        (now + timedelta(hours=49), 2),  # the new 1-hour reminder
    ):
        with time_machine.travel(moment, tick=False):
            await run_deadlines(owner)
        received = [
            message.payload
            for message in await notifications(owner)
            if message.payload["type"] == "listing.meeting.reminder"
        ]
        assert len(received) == expected


async def test_parallel_accepts_leave_one_scheduled_meeting(
    owner: Account, borrower: Account
) -> None:
    now = clock.now()
    meeting_at = now + timedelta(days=2)
    with time_machine.travel(now, tick=False):
        listing, interaction = await accepted(owner, borrower)
        proposal = (await propose(owner, listing, interaction, meeting_at)).json()
        responses = await asyncio.gather(
            accept(borrower, listing, interaction, proposal["version"]),
            accept(owner, listing, interaction, proposal["version"]),
        )
        assert sorted(response.status_code for response in responses) == [200, 409]
        rejected = next(
            response for response in responses if response.status_code == 409
        )
        assert rejected.json()["code"] == "meeting_stale"
        assert rejected.json()["current_version"] == proposal["version"] + 1

    rows = await meetings(owner, interaction)
    assert len(rows) == 1
    assert rows[0].scheduled_at is not None
    events = await event_list(owner, listing, interaction)
    assert sum(event["action"] == "meeting_scheduled" for event in events) == 1
    scheduled = [
        message
        for message in await notifications(owner)
        if message.payload["type"] == "listing.meeting.scheduled"
    ]
    assert len(scheduled) == 1


async def test_parallel_accepts_of_different_proposals(
    owner: Account, borrower: Account
) -> None:
    now = clock.now()
    first_at = now + timedelta(days=2)
    second_at = now + timedelta(days=3)
    with time_machine.travel(now, tick=False):
        listing, interaction = await accepted(owner, borrower)
        first = (await propose(owner, listing, interaction, first_at)).json()
        second = (await propose(borrower, listing, interaction, second_at)).json()
        responses = await asyncio.gather(
            accept(borrower, listing, interaction, first["version"]),
            accept(owner, listing, interaction, second["version"]),
        )
        assert sorted(response.status_code for response in responses) == [200, 409]

        rows = await meetings(owner, interaction)
        assert len(rows) == 1
        assert rows[0].scheduled_at is not None
        assert parse_instant(rows[0].scheduled_at.isoformat()) == second_at
        events = await event_list(owner, listing, interaction)
        assert sum(event["action"] == "meeting_scheduled" for event in events) == 1


async def test_same_idempotency_key_returns_the_stored_proposal(
    owner: Account, borrower: Account
) -> None:
    now = clock.now()
    with time_machine.travel(now, tick=False):
        listing, interaction = await accepted(owner, borrower)
        key = str(uuid4())
        first = await propose(
            owner, listing, interaction, now + timedelta(days=2), key=key
        )
        second = await propose(
            owner, listing, interaction, now + timedelta(days=2), key=key
        )
        assert first.status_code == second.status_code == 200
        assert first.json() == second.json()
        stored = first.json()

    rows = await meetings(owner, interaction)
    assert len(rows) == 1
    assert rows[0].version == stored["version"]
    events = await event_list(owner, listing, interaction)
    assert [event["action"] for event in events].count("meeting_proposed") == 1
    messages = [
        message
        for message in await notifications(owner)
        if message.payload["type"] == "listing.meeting.proposed"
    ]
    assert len(messages) == 1


async def test_cancelled_interaction_loses_its_reminders(
    owner: Account, borrower: Account
) -> None:
    now = clock.now()
    with time_machine.travel(now, tick=False):
        listing, interaction = await accepted(owner, borrower)
        proposal = (
            await propose(owner, listing, interaction, now + timedelta(hours=30))
        ).json()
        await accept(borrower, listing, interaction, proposal["version"])
        assert len(await reminders(owner)) == 2
        assert (
            await move(borrower, listing, interaction, "cancelled")
        ).status_code == 200
        assert await reminders(owner) == []
        await run_deadlines(owner)

    reminders_sent = [
        message
        for message in await notifications(owner)
        if message.payload["type"] == "listing.meeting.reminder"
    ]
    assert reminders_sent == []
