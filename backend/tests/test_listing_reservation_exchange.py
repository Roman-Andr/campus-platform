"""Item reservations and exchange offers on real PostgreSQL."""

import asyncio
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID

import httpx2
import pytest
import time_machine
from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncEngine

from campus.core import clock
from campus.core.config import Settings
from campus.core.db import create_session_factory
from campus.core.deadlines import process_due_deadlines
from campus.core.outbox import OutboxMessage
from campus.modules.listings import Interaction, InteractionStatus
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
)
from tests.test_profile import Account, Places, moscow_profile

__all__ = ["auth", "borrower", "owner", "places"]

ROOT = "/api/v1/listings"


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


async def deadlines(account: Account) -> int:
    assert isinstance(account.auth.db.bind, AsyncEngine)
    return await process_due_deadlines(
        create_session_factory(account.auth.db.bind), account.auth.settings
    )


def settings(account: Account, **changes: Any) -> None:
    account.auth.settings = account.auth.settings.model_copy(update=changes)
    account.auth.app.state.settings = account.auth.settings


async def participant(auth: Auth, places: Places, number: int) -> Account:
    account = Account(
        auth, await auth.login(email=f"exchanger{number}@university.example")
    )
    assert (await account.put(moscow_profile(places))).status_code == 200
    return account


async def publish_exchange(account: Account, **overrides: Any) -> dict[str, Any]:
    category = (await request(account, "GET", "/categories")).json()["items"][0]["id"]
    response = await request(
        account,
        "POST",
        "/exchanges",
        {
            "category_id": category,
            "title": "A desk lamp",
            "description": "I want to swap it for a chair",
            **overrides,
        },
    )
    assert response.status_code == 201, response.text
    result: dict[str, Any] = response.json()
    assert result["kind"] == "exchange"
    return result


async def offer(
    account: Account,
    listing: dict[str, Any],
    description: str = "A wooden chair",
) -> httpx2.Response:
    return await request(
        account,
        "POST",
        f"/{listing['id']}/exchange-offers",
        {"description": description},
    )


async def offers(account: Account, listing: dict[str, Any]) -> list[dict[str, Any]]:
    response = await request(account, "GET", f"/{listing['id']}/exchange-offers")
    assert response.status_code == 200, response.text
    items: list[dict[str, Any]] = response.json()["items"]
    return items


async def accepted(
    owner_account: Account, borrower_account: Account, **overrides: Any
) -> tuple[dict[str, Any], dict[str, Any]]:
    listing = await publish(owner_account, **overrides)
    interaction = (await reserve(borrower_account, listing)).json()
    response = await move(owner_account, listing, interaction, "accepted")
    assert response.status_code == 200, response.text
    return listing, response.json()


async def propose(
    account: Account,
    listing: dict[str, Any],
    interaction: dict[str, Any],
    at: datetime,
) -> httpx2.Response:
    return await request(
        account,
        "POST",
        f"/{listing['id']}/interactions/{interaction['id']}/meeting/proposals",
        {"time": instant(at), "location": "Main library"},
    )


async def accept_meeting(
    account: Account,
    listing: dict[str, Any],
    interaction: dict[str, Any],
    version: int,
) -> httpx2.Response:
    return await request(
        account,
        "POST",
        f"/{listing['id']}/interactions/{interaction['id']}/meeting/accept",
        {"version": version},
    )


async def own_interaction(
    account: Account, interaction: dict[str, Any]
) -> dict[str, Any]:
    response = await request(account, "GET", "/reservations/mine")
    assert response.status_code == 200, response.text
    rows: list[dict[str, Any]] = response.json()["items"]
    return next(row for row in rows if row["id"] == interaction["id"])


async def interaction_events(
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
    return list(
        await account.auth.db.scalars(select(OutboxMessage).order_by(OutboxMessage.id))
    )


def test_reservation_defaults_to_48_hours() -> None:
    assert Settings().listing_reservation_timeout == timedelta(hours=48)


async def test_accepted_reservation_reports_its_deadline(
    owner: Account, borrower: Account
) -> None:
    now = clock.now()
    with time_machine.travel(now, tick=False):
        _listing, interaction = await accepted(owner, borrower)
        assert parse_instant(interaction["reservation_due_at"]) == now + timedelta(
            hours=48
        )
        own = await own_interaction(borrower, interaction)
        assert parse_instant(own["reservation_due_at"]) == now + timedelta(hours=48)


async def test_reservation_expiry_releases_the_listing_and_offers_the_queue(
    owner: Account, borrower: Account, auth: Auth, places: Places
) -> None:
    queuer = await participant(auth, places, 1)
    now = clock.now()
    with time_machine.travel(now, tick=False):
        listing, interaction = await accepted(owner, borrower)
        queued = await request(queuer, "POST", f"/{listing['id']}/waitlist")
        assert queued.status_code == 201, queued.text
    with time_machine.travel(now + timedelta(hours=48, seconds=1), tick=False):
        assert await deadlines(owner) == 1

    own = await own_interaction(borrower, interaction)
    assert own["status"] == "cancelled"
    assert own["cancelled_by"] == "system"
    assert own["late_cancelled"] is False
    assert own["reservation_due_at"] is None
    events = await interaction_events(borrower, listing, interaction)
    assert events[-1]["action"] == "reservation_expired"
    assert events[-1]["previous_status"] == "accepted"
    assert events[-1]["status"] == "cancelled"
    assert events[-1]["reason"] == "reservation_expired"
    assert events[-1]["actor_id"] is None

    response = await request(owner, "GET", f"/{listing['id']}")
    assert response.json()["status"] == "active"

    entry = await request(queuer, "GET", f"/{listing['id']}/waitlist/me")
    assert entry.status_code == 200, entry.text
    assert entry.json()["status"] == "offered"
    assert entry.json()["position"] == 1
    assert entry.json()["offer_expires_at"] is not None

    db = owner.auth.db
    assert (
        await db.scalar(
            select(func.count())
            .select_from(Interaction)
            .where(Interaction.status == InteractionStatus.NO_SHOW)
        )
        == 0
    )
    messages = await notifications(owner)
    assert messages[-1].payload["type"] == "listing.offer"
    assert messages[-1].payload["recipients"] == [entry.json()["participant_id"]]


async def test_scheduled_meeting_extends_the_reservation(
    owner: Account, borrower: Account
) -> None:
    now = clock.now()
    meeting_at = now + timedelta(days=5)
    with time_machine.travel(now, tick=False):
        listing, interaction = await accepted(owner, borrower)
        proposal = (await propose(owner, listing, interaction, meeting_at)).json()
        response = await accept_meeting(
            borrower, listing, interaction, proposal["version"]
        )
        assert response.status_code == 200, response.text
        own = await own_interaction(borrower, interaction)
        assert parse_instant(own["reservation_due_at"]) == meeting_at
    with time_machine.travel(now + timedelta(hours=49), tick=False):
        assert await deadlines(owner) == 0
        own = await own_interaction(borrower, interaction)
        assert own["status"] == "accepted"


async def test_rescheduled_meeting_moves_the_reservation(
    owner: Account, borrower: Account
) -> None:
    now = clock.now()
    first_at = now + timedelta(days=2)
    second_at = now + timedelta(days=4)
    with time_machine.travel(now, tick=False):
        listing, interaction = await accepted(owner, borrower)
        first = (await propose(owner, listing, interaction, first_at)).json()
        assert (
            await accept_meeting(borrower, listing, interaction, first["version"])
        ).status_code == 200
        second = (await propose(borrower, listing, interaction, second_at)).json()
        assert (
            await accept_meeting(owner, listing, interaction, second["version"])
        ).status_code == 200
        own = await own_interaction(borrower, interaction)
        assert parse_instant(own["reservation_due_at"]) == second_at
    with time_machine.travel(now + timedelta(days=2, hours=1), tick=False):
        assert await deadlines(owner) == 0
        assert (await own_interaction(borrower, interaction))["status"] == "accepted"


async def test_reservation_timeout_comes_from_configuration(
    owner: Account, borrower: Account
) -> None:
    settings(owner, listing_reservation_timeout=timedelta(hours=1))
    now = clock.now()
    with time_machine.travel(now, tick=False):
        _listing, interaction = await accepted(owner, borrower)
        own = await own_interaction(borrower, interaction)
        assert parse_instant(own["reservation_due_at"]) == now + timedelta(hours=1)
    with time_machine.travel(now + timedelta(minutes=59), tick=False):
        assert await deadlines(owner) == 0
        assert (await own_interaction(borrower, interaction))["status"] == "accepted"
    with time_machine.travel(now + timedelta(hours=1, seconds=1), tick=False):
        assert await deadlines(owner) == 1
        assert (await own_interaction(borrower, interaction))["status"] == "cancelled"


async def test_reservation_expiry_races_user_cancellation(
    owner: Account, borrower: Account
) -> None:
    now = clock.now()
    with time_machine.travel(now, tick=False):
        listing, interaction = await accepted(owner, borrower)
    with time_machine.travel(now + timedelta(hours=48, seconds=1), tick=False):
        expired, cancelled = await asyncio.gather(
            deadlines(owner),
            move(borrower, listing, interaction, "cancelled"),
        )
    assert expired == 1
    assert cancelled.status_code in (200, 409)
    own = await own_interaction(borrower, interaction)
    assert own["status"] == "cancelled"
    events = await interaction_events(borrower, listing, interaction)
    endings = [event for event in events if event["status"] == "cancelled"]
    assert len(endings) == 1
    assert endings[0]["action"] in ("reservation_expired", "transition")


async def test_exchange_offers_and_the_author_choice(
    owner: Account,
    borrower: Account,
    auth: Auth,
    places: Places,
) -> None:
    second_user = await participant(auth, places, 2)
    listing = await publish_exchange(owner)
    first = await offer(borrower, listing, "A wooden chair")
    second = await offer(second_user, listing, "A floor lamp")
    assert first.status_code == 201, first.text
    assert second.status_code == 201, second.text
    duplicate = await offer(second_user, listing, "Another lamp")
    assert duplicate.status_code == 409
    assert duplicate.json()["code"] == "exchange_offer_duplicate"

    mine = await offers(borrower, listing)
    assert [item["id"] for item in mine] == [first.json()["id"]]
    assert mine[0]["offer_description"] == "A wooden chair"
    assert mine[0]["status"] == "pending"

    all_offers = await offers(owner, listing)
    assert {item["id"] for item in all_offers} == {
        first.json()["id"],
        second.json()["id"],
    }
    assert {item["participant_id"] for item in all_offers} == {
        borrower.tokens["user"]["id"],
        second_user.tokens["user"]["id"],
    }

    # A participant cannot choose an offer; only the author can.
    forbidden = await move(borrower, listing, first.json(), "accepted")
    assert forbidden.status_code == 403
    assert forbidden.json()["code"] == "listing_forbidden"
    outsider = await participant(auth, places, 9)
    assert (await move(outsider, listing, second.json(), "accepted")).status_code == 403

    chosen = await move(owner, listing, first.json(), "accepted")
    assert chosen.status_code == 200, chosen.text
    assert chosen.json()["status"] == "accepted"
    assert chosen.json()["reservation_due_at"] is not None

    rows = {item["id"]: item for item in await offers(owner, listing)}
    assert rows[first.json()["id"]]["status"] == "accepted"
    assert rows[second.json()["id"]]["status"] == "rejected"

    response = await request(owner, "GET", f"/{listing['id']}")
    assert response.json()["status"] == "busy"

    rejected = await interaction_events(second_user, listing, second.json())
    assert rejected[-1]["action"] == "auto_rejected"
    assert rejected[-1]["status"] == "rejected"
    assert rejected[-1]["reason"] == "another_offer_accepted"

    messages = await notifications(owner)
    rejected_message = next(
        message
        for message in messages
        if message.payload.get("type") == "listing.activity"
        and message.payload["params"].get("reason") == "another_offer_accepted"
    )
    assert second_user.tokens["user"]["id"] in rejected_message.payload["recipients"]


async def test_parallel_choice_accepts_exactly_one_offer(
    owner: Account, borrower: Account, auth: Auth, places: Places
) -> None:
    second_user = await participant(auth, places, 2)
    listing = await publish_exchange(owner)
    first = (await offer(borrower, listing)).json()
    second = (await offer(second_user, listing)).json()
    responses = await asyncio.gather(
        move(owner, listing, first, "accepted"),
        move(owner, listing, second, "accepted"),
    )
    assert sorted(response.status_code for response in responses) == [200, 409]
    db = owner.auth.db
    assert (
        await db.scalar(
            select(func.count())
            .select_from(Interaction)
            .where(
                Interaction.listing_id == UUID(listing["id"]),
                Interaction.status == InteractionStatus.ACCEPTED,
            )
        )
        == 1
    )
    assert (
        await db.scalar(
            select(func.count())
            .select_from(Interaction)
            .where(
                Interaction.listing_id == UUID(listing["id"]),
                Interaction.status == InteractionStatus.REJECTED,
            )
        )
        == 1
    )


async def test_exchange_rejects_invalid_offers(
    owner: Account, borrower: Account
) -> None:
    listing = await publish_exchange(owner)
    assert (await offer(owner, listing)).status_code == 403
    blank = await offer(borrower, listing, "   ")
    assert blank.status_code == 422
    assert blank.json()["code"] == "exchange_offer_invalid"
    long = await offer(borrower, listing, "x" * 5001)
    assert long.status_code == 422
    assert long.json()["code"] == "exchange_offer_invalid"

    giveaway = await publish(owner)
    assert (await offer(borrower, giveaway)).status_code == 409

    queue = await request(borrower, "POST", f"/{listing['id']}/waitlist")
    assert queue.status_code == 409
    assert queue.json()["code"] == "listing_waitlist_unavailable"


@pytest.mark.parametrize("source", list(InteractionStatus))
@pytest.mark.parametrize("target", list(InteractionStatus))
async def test_exchange_transition_edges(
    owner: Account,
    borrower: Account,
    source: InteractionStatus,
    target: InteractionStatus,
) -> None:
    listing = await publish_exchange(owner)
    interaction = (await offer(borrower, listing)).json()
    await owner.auth.db.execute(update(Interaction).values(status=source))
    await owner.auth.db.commit()
    allowed = {
        ("pending", "accepted"),
        ("pending", "rejected"),
        ("pending", "cancelled"),
        ("accepted", "cancelled"),
    }
    actor = borrower if target == "cancelled" else owner
    response = await move(actor, listing, interaction, target)
    service_only = (source == "accepted" and target in ("completed", "no_show")) or (
        source == "no_show" and target == "completed"
    )
    assert response.status_code == (
        200 if (source, target) in allowed else 403 if service_only else 409
    )
    events = await request(
        owner, "GET", f"/{listing['id']}/interactions/{interaction['id']}/events"
    )
    items = events.json()["items"]
    if response.status_code == 200:
        assert items[-1]["previous_status"] == source
        assert items[-1]["status"] == target
    else:
        assert response.headers["content-type"] == "application/problem+json"
        assert response.json()["code"] == (
            "listing_forbidden" if service_only else "listing_conflict"
        )
