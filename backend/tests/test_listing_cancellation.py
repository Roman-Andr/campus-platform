"""Listing and interaction cancellation rules (#55)."""

import asyncio
from datetime import timedelta
from uuid import UUID

import pytest
import time_machine
from sqlalchemy import select

from campus.core import clock
from campus.modules.listings import Interaction, InteractionStatus
from tests.test_events_signup import edit, event, signup
from tests.test_listing_waitlist import notifications, queuer
from tests.test_listings import (
    auth,
    borrower,
    move,
    owner,
    places,
    publish,
    request,
    reserve,
    schedule_meeting,
)
from tests.test_profile import Account, Places

__all__ = ["auth", "borrower", "owner", "places"]


async def interaction_row(account: Account, identifier: str) -> Interaction:
    await account.auth.db.rollback()
    row = await account.auth.db.get(Interaction, UUID(identifier))
    assert row is not None
    return row


def configure(account: Account, **changes: object) -> None:
    account.auth.settings = account.auth.settings.model_copy(update=changes)
    account.auth.app.state.settings = account.auth.settings


async def test_author_cancel_requires_reason_after_acceptance(
    owner: Account, borrower: Account
) -> None:
    listing = await publish(owner)
    interaction = (await reserve(borrower, listing)).json()
    assert (await move(owner, listing, interaction, "accepted")).status_code == 200

    preview = await request(owner, "GET", f"/{listing['id']}/cancellation")
    assert preview.status_code == 200, preview.text
    assert preview.json() == {
        "accepted_interactions": 1,
        "reason_required": True,
        "can_cancel": True,
        "reason_max_length": owner.auth.settings.listing_cancellation_reason_max_length,
    }

    refused = await request(owner, "POST", f"/{listing['id']}/cancel")
    assert refused.status_code == 422
    assert refused.json()["code"] == "listing_cancel_reason_required"

    too_long = await request(
        owner,
        "POST",
        f"/{listing['id']}/cancel",
        {"reason": "x" * 501},
    )
    assert too_long.status_code == 422
    assert too_long.json()["code"] == "listing_cancel_reason_invalid"

    cancelled = await request(
        owner,
        "POST",
        f"/{listing['id']}/cancel",
        {"reason": "  No longer available  "},
    )
    assert cancelled.status_code == 200, cancelled.text

    stored = await interaction_row(owner, interaction["id"])
    assert stored.status == InteractionStatus.CANCELLED
    assert stored.cancelled_by == "author"
    assert stored.cancellation_reason == "No longer available"
    assert stored.late_cancelled is False

    mine = (await request(borrower, "GET", "/reservations/mine")).json()["items"]
    row = next(item for item in mine if item["id"] == interaction["id"])
    assert row["status"] == "cancelled"
    assert row["cancelled_by"] == "author"
    assert row["cancellation_reason"] == "No longer available"
    assert row["late_cancelled"] is False

    events = (await request(owner, "GET", f"/{listing['id']}/events")).json()["items"]
    journal = next(item for item in events if item["action"] == "cancelled_by_author")
    assert journal["reason"] == "No longer available"
    assert journal["details"]["after_acceptance"] is True
    assert journal["details"]["late"] is False

    messages = await notifications(borrower)
    notice = next(
        message
        for message in messages
        if message.payload.get("type") == "listing.cancelled"
    )
    assert notice.payload["params"]["reason"] == "No longer available"
    assert "No longer available" in notice.payload["text"]["en"]
    assert "No longer available" in notice.payload["text"]["ru"]


async def test_author_cancel_without_accepted_needs_no_reason(
    owner: Account, borrower: Account
) -> None:
    listing = await publish(owner)
    interaction = (await reserve(borrower, listing)).json()

    preview = await request(owner, "GET", f"/{listing['id']}/cancellation")
    assert preview.status_code == 200
    assert preview.json()["accepted_interactions"] == 0
    assert preview.json()["reason_required"] is False

    cancelled = await request(owner, "POST", f"/{listing['id']}/cancel")
    assert cancelled.status_code == 200, cancelled.text

    stored = await interaction_row(owner, interaction["id"])
    assert stored.status == InteractionStatus.REJECTED
    assert stored.cancelled_by is None
    assert stored.cancellation_reason is None

    events = (await request(owner, "GET", f"/{listing['id']}/events")).json()["items"]
    assert not [item for item in events if item["action"] == "cancelled_by_author"]
    rejected = next(item for item in events if item["action"] == "auto_rejected")
    assert rejected["reason"] == "listing_cancelled"
    assert rejected["details"] is None


async def test_event_cancel_notifies_registered_and_queue(
    owner: Account, borrower: Account, places: Places
) -> None:
    listing = await event(owner, capacity=1)
    first = (await signup(borrower, listing)).json()["interaction"]
    waiting = await queuer(owner.auth, places, 1)
    assert (await signup(waiting, listing, True)).json()["result"] == "queued"

    cancelled = await request(
        owner,
        "POST",
        f"/{listing['id']}/cancel",
        {"reason": "The hall is closed"},
    )
    assert cancelled.status_code == 200, cancelled.text

    stored = await interaction_row(owner, first["id"])
    assert stored.status == InteractionStatus.CANCELLED
    assert stored.cancelled_by == "author"
    assert stored.cancellation_reason == "The hall is closed"

    messages = await notifications(borrower)
    registered = next(
        message
        for message in messages
        if message.payload.get("type") == "listing.cancelled"
    )
    assert "The hall is closed" in registered.payload["text"]["en"]
    cleared = [
        message
        for message in await notifications(waiting)
        if message.payload.get("type") == "listing.waitlist_cleared"
    ]
    assert cleared
    assert cleared[-1].payload["params"]["listing_id"] == listing["id"]


@pytest.mark.parametrize(("hours", "late"), [(23, True), (25, False)])
async def test_late_cancellation_threshold(
    owner: Account, borrower: Account, hours: int, late: bool
) -> None:
    now = clock.now()
    with time_machine.travel(now, tick=False):
        listing = await publish(owner)
        interaction = (await reserve(borrower, listing)).json()
        assert (await move(owner, listing, interaction, "accepted")).status_code == 200
        await schedule_meeting(
            owner,
            borrower,
            listing,
            interaction,
            now + timedelta(hours=hours),
        )

        preview = await request(
            borrower,
            "GET",
            f"/{listing['id']}/interactions/{interaction['id']}/cancellation",
        )
        assert preview.status_code == 200, preview.text
        assert preview.json()["late"] is late
        assert preview.json()["allowed"] is True
        assert preview.json()["requires_approval"] is False

        cancelled = await move(borrower, listing, interaction, "cancelled")
        assert cancelled.status_code == 200, cancelled.text
        assert cancelled.json()["late_cancelled"] is late

        stored = await interaction_row(owner, interaction["id"])
        assert stored.late_cancelled is late
        events = (
            await request(
                owner,
                "GET",
                f"/{listing['id']}/interactions/{interaction['id']}/events",
            )
        ).json()["items"]
        assert events[-1]["details"]["late"] is late


async def test_event_cancellation_is_late(owner: Account, borrower: Account) -> None:
    now = clock.now()
    starts = now + timedelta(hours=23)
    with time_machine.travel(now, tick=False):
        listing = await event(
            owner,
            capacity=2,
            starts_at=starts.isoformat(),
            ends_at=(starts + timedelta(hours=2)).isoformat(),
        )
        interaction = (await signup(borrower, listing)).json()["interaction"]
        preview = await request(
            borrower,
            "GET",
            f"/{listing['id']}/interactions/{interaction['id']}/cancellation",
        )
        assert preview.json()["late"] is True
        cancelled = await move(borrower, listing, interaction, "cancelled")
        assert cancelled.status_code == 200, cancelled.text
        assert cancelled.json()["late_cancelled"] is True


async def test_late_threshold_comes_from_settings(
    owner: Account, borrower: Account
) -> None:
    configure(owner, listing_late_cancellation_threshold=timedelta(hours=1))
    now = clock.now()
    with time_machine.travel(now, tick=False):
        listing = await publish(owner)
        interaction = (await reserve(borrower, listing)).json()
        assert (await move(owner, listing, interaction, "accepted")).status_code == 200
        await schedule_meeting(
            owner,
            borrower,
            listing,
            interaction,
            now + timedelta(hours=23),
        )
        preview = await request(
            borrower,
            "GET",
            f"/{listing['id']}/interactions/{interaction['id']}/cancellation",
        )
        assert preview.json()["late"] is False
        cancelled = await move(borrower, listing, interaction, "cancelled")
        assert cancelled.json()["late_cancelled"] is False


async def test_author_reschedule_exempts_late_cancellation(
    owner: Account, borrower: Account
) -> None:
    now = clock.now()
    with time_machine.travel(now, tick=False):
        listing = await publish(owner)
        interaction = (await reserve(borrower, listing)).json()
        assert (await move(owner, listing, interaction, "accepted")).status_code == 200
        await schedule_meeting(
            owner,
            borrower,
            listing,
            interaction,
            now + timedelta(hours=23),
        )
        proposed = await request(
            owner,
            "POST",
            f"/{listing['id']}/interactions/{interaction['id']}/meeting/proposals",
            {
                "time": (now + timedelta(hours=23, minutes=30)).isoformat(),
                "location": "Another room",
            },
        )
        assert proposed.status_code == 200, proposed.text
        assert (
            await request(
                borrower,
                "POST",
                f"/{listing['id']}/interactions/{interaction['id']}/meeting/accept",
                {"version": proposed.json()["version"]},
            )
        ).status_code == 200

        preview = await request(
            borrower,
            "GET",
            f"/{listing['id']}/interactions/{interaction['id']}/cancellation",
        )
        assert preview.json()["late"] is False
        cancelled = await move(borrower, listing, interaction, "cancelled")
        assert cancelled.status_code == 200, cancelled.text
        assert cancelled.json()["late_cancelled"] is False

        stored = await interaction_row(owner, interaction["id"])
        assert stored.late_cancelled is False


async def test_event_edit_exempts_late_cancellation(
    owner: Account, borrower: Account
) -> None:
    now = clock.now()
    starts = now + timedelta(hours=23)
    with time_machine.travel(now, tick=False):
        listing = await event(
            owner,
            capacity=2,
            starts_at=starts.isoformat(),
            ends_at=(starts + timedelta(hours=2)).isoformat(),
        )
        interaction = (await signup(borrower, listing)).json()["interaction"]
        changed = await edit(
            owner,
            listing,
            starts_at=(starts + timedelta(minutes=30)).isoformat(),
            ends_at=(starts + timedelta(hours=2, minutes=30)).isoformat(),
            location="Hall B",
        )
        assert changed.status_code == 200, changed.text

        preview = await request(
            borrower,
            "GET",
            f"/{listing['id']}/interactions/{interaction['id']}/cancellation",
        )
        assert preview.json()["late"] is False
        cancelled = await move(borrower, listing, interaction, "cancelled")
        assert cancelled.status_code == 200, cancelled.text
        assert cancelled.json()["late_cancelled"] is False


async def test_parallel_cancel_and_event_signup_are_serialized(
    owner: Account, borrower: Account
) -> None:
    listing = await event(owner, capacity=5)
    replies = await asyncio.gather(
        request(owner, "POST", f"/{listing['id']}/cancel"),
        signup(borrower, listing),
    )
    assert sorted(reply.status_code for reply in replies) in ([200, 409], [200, 422])

    current = (await request(owner, "GET", f"/{listing['id']}")).json()
    if current["status"] == "cancelled":
        await owner.auth.db.rollback()
        active = await owner.auth.db.scalar(
            select(Interaction.id).where(
                Interaction.listing_id == UUID(listing["id"]),
                Interaction.status.in_(
                    (InteractionStatus.PENDING, InteractionStatus.ACCEPTED)
                ),
            )
        )
        assert active is None
    else:
        assert current["status"] == "active"
        assert replies[1].json()["result"] == "registered"


async def test_cancel_preview_is_private(owner: Account, borrower: Account) -> None:
    listing = await publish(owner)
    interaction = (await reserve(borrower, listing)).json()
    preview = await request(owner, "GET", f"/{listing['id']}/cancellation")
    assert preview.status_code == 200
    assert (
        await request(borrower, "GET", f"/{listing['id']}/cancellation")
    ).status_code == 403
    path = f"/{listing['id']}/interactions/{interaction['id']}/cancellation"
    assert (await request(borrower, "GET", path)).status_code == 200
    assert (await request(owner, "GET", path)).status_code == 403
