"""Help requests: applications, executor selection, reserve and deadlines."""

import asyncio
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID, uuid4

import httpx2
import pytest
import time_machine
from sqlalchemy import func, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncEngine

from campus.core import clock
from campus.core.db import create_session_factory
from campus.core.deadlines import process_due_deadlines
from campus.modules.listings import (
    Interaction,
    InteractionStatus,
    Listing,
    ListingEvent,
    ListingStatus,
    locked,
    transition,
)
from tests.test_identity import Auth
from tests.test_listings import (
    auth,
    borrower,
    move,
    owner,
    places,
    request,
    staff,
)
from tests.test_profile import Account, Places, moscow_profile

__all__ = ["auth", "borrower", "owner", "places", "staff"]

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


async def category(account: Account) -> str:
    response = await request(account, "GET", "/categories")
    assert response.status_code == 200, response.text
    result: str = response.json()["items"][0]["id"]
    return result


async def publish_help(
    account: Account, *, actual_until: datetime | None = None, **overrides: Any
) -> httpx2.Response:
    data: dict[str, Any] = {
        "category_id": await category(account),
        "title": "Help to move a couch",
        "description": "Two floors, no elevator, around 30 minutes.",
        "actual_until": instant(actual_until or clock.now() + timedelta(days=7)),
        **overrides,
    }
    return await request(account, "POST", "/help-requests", data)


async def help_request(account: Account, **overrides: Any) -> dict[str, Any]:
    response = await publish_help(account, **overrides)
    assert response.status_code == 201, response.text
    result: dict[str, Any] = response.json()
    return result


async def respond(
    account: Account, listing: dict[str, Any], key: str | None = None
) -> httpx2.Response:
    return await request(account, "POST", f"/{listing['id']}/responses", key=key)


async def respond_ok(account: Account, listing: dict[str, Any]) -> dict[str, Any]:
    response = await respond(account, listing)
    assert response.status_code == 201, response.text
    result: dict[str, Any] = response.json()
    return result


async def participant(auth: Auth, places: Places, number: int) -> Account:
    account = Account(
        auth, await auth.login(email=f"responder{number}@university.example")
    )
    assert (await account.put(moscow_profile(places))).status_code == 200
    return account


async def run_deadlines(account: Account) -> int:
    assert isinstance(account.auth.db.bind, AsyncEngine)
    return await process_due_deadlines(
        create_session_factory(account.auth.db.bind), account.auth.settings
    )


async def reload(account: Account) -> None:
    await account.auth.db.rollback()
    account.auth.db.expire_all()


async def interactions(
    account: Account, listing: dict[str, Any], status: InteractionStatus
) -> list[Interaction]:
    await reload(account)
    return list(
        await account.auth.db.scalars(
            select(Interaction).where(
                Interaction.listing_id == UUID(listing["id"]),
                Interaction.status == status,
            )
        )
    )


async def test_help_request_has_author_relevance_deadline(
    owner: Account, borrower: Account
) -> None:
    now = clock.now()
    until = now + timedelta(days=5)
    with time_machine.travel(now, tick=False):
        listing = await help_request(owner, actual_until=until)
        assert listing["kind"] == "help"
        assert parse_instant(listing["expires_at"]) == until
        assert listing["status"] == "active"
        feed = (await request(borrower, "GET", "?kind=help")).json()["items"]
        assert listing["id"] in [item["id"] for item in feed]


async def test_help_deadline_must_fit_the_listing_lifetime(owner: Account) -> None:
    now = clock.now()
    lifetime = owner.auth.settings.listing_lifetime
    with time_machine.travel(now, tick=False):
        late = await publish_help(
            owner, actual_until=now + lifetime + timedelta(seconds=1)
        )
        assert late.status_code == 422
        assert late.json()["code"] == "help_deadline_invalid"
        assert late.headers["content-type"] == "application/problem+json"

        past = await publish_help(owner, actual_until=now - timedelta(seconds=1))
        assert past.status_code == 422
        assert past.json()["code"] == "help_deadline_invalid"

        # The listing lifetime itself is allowed.
        edge = await publish_help(owner, actual_until=now + lifetime)
        assert edge.status_code == 201, edge.text


async def test_parallel_applications_all_stay_pending(
    owner: Account, places: Places
) -> None:
    listing = await help_request(owner)
    applicants = [await participant(owner.auth, places, i) for i in range(6)]
    responses = await asyncio.gather(
        *(respond(account, listing) for account in applicants)
    )
    assert [response.status_code for response in responses] == [201] * 6
    assert len({response.json()["id"] for response in responses}) == 6

    pending = await interactions(owner, listing, InteractionStatus.PENDING)
    assert len(pending) == 6
    assert all(interaction.slot is None for interaction in pending)
    assert not any(interaction.executor for interaction in pending)
    await reload(owner)
    row = await owner.auth.db.get(Listing, UUID(listing["id"]))
    assert row is not None
    assert row.status == ListingStatus.ACTIVE


async def test_author_sees_applications_as_reserve(
    owner: Account, borrower: Account, places: Places
) -> None:
    listing = await help_request(owner)
    second = await participant(owner.auth, places, 1)
    first_application = await respond_ok(borrower, listing)
    second_application = await respond_ok(second, listing)
    selected = await move(owner, listing, first_application, "accepted")
    assert selected.status_code == 200, selected.text
    assert selected.json()["status"] == "accepted"
    assert selected.json()["executor"] is True

    incoming = (await request(owner, "GET", f"/{listing['id']}/interactions")).json()[
        "items"
    ]
    statuses = {item["id"]: item for item in incoming}
    assert statuses[first_application["id"]]["status"] == "accepted"
    assert statuses[first_application["id"]]["executor"] is True
    assert statuses[second_application["id"]]["status"] == "pending"
    assert statuses[second_application["id"]]["executor"] is False

    # The selected executor holds the only slot even without concurrency.
    retry = await move(owner, listing, second_application, "accepted")
    assert retry.status_code == 409
    assert retry.json()["code"] == "listing_conflict"

    reserve = (await request(second, "GET", "/reservations/mine")).json()["items"]
    own = next(item for item in reserve if item["id"] == second_application["id"])
    assert own["status"] == "pending"
    assert own["executor"] is False
    assert own["listing"]["status"] == "busy"


@pytest.mark.parametrize("attempt", range(3))
async def test_parallel_selection_picks_exactly_one_executor(
    owner: Account, places: Places, attempt: int
) -> None:
    listing = await help_request(owner, title=f"Help {attempt}")
    applicants = [await participant(owner.auth, places, i) for i in range(2)]
    applications = [await respond_ok(account, listing) for account in applicants]
    responses = await asyncio.gather(
        *(move(owner, listing, application, "accepted") for application in applications)
    )
    assert sorted(response.status_code for response in responses) == [200, 409]
    for response in responses:
        if response.status_code == 409:
            assert response.headers["content-type"] == "application/problem+json"
            assert response.json()["code"] == "listing_conflict"

    accepted = await interactions(owner, listing, InteractionStatus.ACCEPTED)
    assert len(accepted) == 1
    assert accepted[0].executor is True
    pending = await interactions(owner, listing, InteractionStatus.PENDING)
    assert len(pending) == 1
    assert pending[0].executor is False


async def test_only_author_selects_the_executor(
    owner: Account, borrower: Account, staff: Account, places: Places
) -> None:
    listing = await help_request(owner)
    second = await participant(owner.auth, places, 1)
    own = await respond_ok(borrower, listing)
    other = await respond_ok(second, listing)
    for account, application in (
        (borrower, own),
        (second, other),
        (staff, other),
    ):
        response = await move(account, listing, application, "accepted")
        assert response.status_code == 403
        assert response.json()["code"] == "listing_forbidden"
    assert (await interactions(owner, listing, InteractionStatus.PENDING)) != []

    selected = await move(owner, listing, own, "accepted")
    assert selected.status_code == 200, selected.text
    assert selected.json()["executor"] is True


async def test_executor_refusal_returns_to_the_reserve(
    owner: Account, borrower: Account, places: Places
) -> None:
    listing = await help_request(owner)
    second = await participant(owner.auth, places, 1)
    first = await respond_ok(borrower, listing)
    reserve = await respond_ok(second, listing)

    assert (await move(owner, listing, first, "accepted")).status_code == 200
    refusal = await move(borrower, listing, first, "cancelled")
    assert refusal.status_code == 200, refusal.text
    assert refusal.json()["status"] == "cancelled"

    await reload(owner)
    row = await owner.auth.db.get(Listing, UUID(listing["id"]))
    assert row is not None
    assert row.status == ListingStatus.ACTIVE
    waiting = await interactions(owner, listing, InteractionStatus.PENDING)
    assert [interaction.id for interaction in waiting] == [UUID(reserve["id"])]

    chosen = await move(owner, listing, reserve, "accepted")
    assert chosen.status_code == 200, chosen.text
    assert chosen.json()["status"] == "accepted"
    assert chosen.json()["executor"] is True
    accepted = await interactions(owner, listing, InteractionStatus.ACCEPTED)
    assert [interaction.id for interaction in accepted] == [UUID(reserve["id"])]


async def test_rejecting_a_reserve_keeps_the_executor_selected(
    owner: Account, borrower: Account, places: Places
) -> None:
    listing = await help_request(owner)
    second = await participant(owner.auth, places, 1)
    first = await respond_ok(borrower, listing)
    reserve = await respond_ok(second, listing)
    assert (await move(owner, listing, first, "accepted")).status_code == 200

    rejected = await move(owner, listing, reserve, "rejected")
    assert rejected.status_code == 200, rejected.text

    await reload(owner)
    row = await owner.auth.db.get(Listing, UUID(listing["id"]))
    assert row is not None
    assert row.status == ListingStatus.BUSY
    selected = await interactions(owner, listing, InteractionStatus.ACCEPTED)
    assert [interaction.id for interaction in selected] == [UUID(first["id"])]


async def test_deadline_closes_request_and_rejects_reserve(
    owner: Account, borrower: Account, places: Places
) -> None:
    now = clock.now()
    with time_machine.travel(now, tick=False):
        listing = await help_request(owner, actual_until=now + timedelta(hours=1))
        second = await participant(owner.auth, places, 1)
        first = await respond_ok(borrower, listing)
        reserve = await respond_ok(second, listing)

    with time_machine.travel(now + timedelta(hours=2), tick=False):
        assert await run_deadlines(owner) >= 1
        await reload(owner)
        row = await owner.auth.db.get(Listing, UUID(listing["id"]))
        assert row is not None
        assert row.status == ListingStatus.EXPIRED
        assert row.archived_at is not None
        for application in (first["id"], reserve["id"]):
            interaction = await owner.auth.db.get(Interaction, UUID(application))
            assert interaction is not None
            assert interaction.status == InteractionStatus.REJECTED

        events = list(
            await owner.auth.db.scalars(
                select(ListingEvent).where(
                    ListingEvent.listing_id == UUID(listing["id"])
                )
            )
        )
        assert [event.action for event in events].count("auto_rejected") == 2
        feed = (await request(owner, "GET", "?kind=help")).json()["items"]
        assert listing["id"] not in [item["id"] for item in feed]


async def test_deadline_keeps_request_with_an_executor(
    owner: Account, borrower: Account, places: Places
) -> None:
    now = clock.now()
    with time_machine.travel(now, tick=False):
        listing = await help_request(owner, actual_until=now + timedelta(hours=1))
        second = await participant(owner.auth, places, 1)
        first = await respond_ok(borrower, listing)
        reserve = await respond_ok(second, listing)
        assert (await move(owner, listing, first, "accepted")).status_code == 200

    with time_machine.travel(now + timedelta(hours=2), tick=False):
        assert await run_deadlines(owner) >= 1
        await reload(owner)
        row = await owner.auth.db.get(Listing, UUID(listing["id"]))
        assert row is not None
        assert row.status == ListingStatus.BUSY
        assert row.archived_at is None
        accepted = await interactions(owner, listing, InteractionStatus.ACCEPTED)
        assert [interaction.id for interaction in accepted] == [UUID(first["id"])]
        assert accepted[0].executor is True
        pending = await interactions(owner, listing, InteractionStatus.PENDING)
        assert [interaction.id for interaction in pending] == [UUID(reserve["id"])]


async def test_completion_rejects_the_reserve(
    owner: Account, borrower: Account, places: Places
) -> None:
    listing = await help_request(owner)
    second = await participant(owner.auth, places, 1)
    first = await respond_ok(borrower, listing)
    reserve = await respond_ok(second, listing)
    assert (await move(owner, listing, first, "accepted")).status_code == 200

    await reload(owner)
    db = owner.auth.db
    listing_row = await locked(db, UUID(listing["id"]))
    interaction_row = await db.get(Interaction, UUID(first["id"]))
    assert interaction_row is not None
    await transition(
        db, listing_row, interaction_row, InteractionStatus.COMPLETED, None
    )
    await db.commit()

    await reload(owner)
    completed_row = await db.get(Listing, UUID(listing["id"]))
    assert completed_row is not None
    assert completed_row.status == ListingStatus.COMPLETED
    finished = await db.get(Interaction, UUID(reserve["id"]))
    assert finished is not None
    assert finished.status == InteractionStatus.REJECTED
    event = await db.scalar(
        select(ListingEvent).where(
            ListingEvent.listing_id == UUID(listing["id"]),
            ListingEvent.action == "auto_rejected",
            ListingEvent.interaction_id == UUID(reserve["id"]),
        )
    )
    assert event is not None
    assert event.reason == "help_completed"


async def test_cancellation_rejects_the_reserve(
    owner: Account, borrower: Account, places: Places
) -> None:
    listing = await help_request(owner)
    second = await participant(owner.auth, places, 1)
    first = await respond_ok(borrower, listing)
    reserve = await respond_ok(second, listing)
    assert (await move(owner, listing, first, "accepted")).status_code == 200

    response = await request(
        owner,
        "POST",
        f"/{listing['id']}/cancel",
        {"reason": "I found another helper"},
    )
    assert response.status_code == 200, response.text
    assert response.json()["status"] == "cancelled"
    await reload(owner)
    rejected = await owner.auth.db.get(Interaction, UUID(reserve["id"]))
    assert rejected is not None
    assert rejected.status == InteractionStatus.REJECTED
    accepted = await owner.auth.db.get(Interaction, UUID(first["id"]))
    assert accepted is not None
    assert accepted.status == InteractionStatus.CANCELLED
    assert accepted.cancelled_by == "author"
    assert accepted.cancellation_reason == "I found another helper"


async def test_applications_are_limited_to_open_help_requests(
    owner: Account, borrower: Account, staff: Account
) -> None:
    giveaway = await request(
        owner,
        "POST",
        "/giveaways",
        {
            "category_id": await category(owner),
            "title": "A desk",
            "description": "Collect on campus",
        },
    )
    assert giveaway.status_code == 201, giveaway.text
    assert (await respond(borrower, giveaway.json())).status_code == 409
    assert (await respond(owner, await help_request(owner))).status_code == 403
    # Employees may apply only to requests open to the whole community.
    assert (await respond(staff, await help_request(owner))).status_code == 403
    community = await help_request(owner, audience="community")
    assert (await respond(staff, community)).status_code == 201

    listing = await help_request(owner)
    assert (await respond(borrower, listing)).status_code == 201
    duplicate = await respond(borrower, listing)
    assert duplicate.status_code == 409
    assert duplicate.json()["code"] == "listing_conflict"


async def test_help_mutations_accept_idempotency_keys(
    owner: Account, borrower: Account
) -> None:
    listing = await help_request(owner)
    key = str(uuid4())
    first = await respond(borrower, listing, key)
    assert first.status_code == 201, first.text
    replay = await respond(borrower, listing, key)
    assert replay.headers["Idempotent-Replayed"] == "true"
    assert replay.json() == first.json()

    path = f"/{listing['id']}/interactions/{first.json()['id']}/transition"
    key = str(uuid4())
    selected = await request(owner, "POST", path, {"status": "accepted"}, key)
    assert selected.status_code == 200, selected.text
    repeated = await request(owner, "POST", path, {"status": "accepted"}, key)
    assert repeated.headers["Idempotent-Replayed"] == "true"
    assert repeated.json() == selected.json()


async def test_database_allows_only_one_executor(
    owner: Account, borrower: Account
) -> None:
    listing = await help_request(owner)
    first = await respond_ok(borrower, listing)
    await owner.auth.db.execute(
        update(Interaction)
        .where(Interaction.id == UUID(first["id"]))
        .values(status="accepted", executor=True)
    )
    await owner.auth.db.commit()

    db = owner.auth.db
    db.add(
        Interaction(
            listing_id=UUID(listing["id"]),
            participant_id=UUID(owner.tokens["user"]["id"]),
            slot=None,
            status=InteractionStatus.ACCEPTED,
            executor=True,
        )
    )
    with pytest.raises(IntegrityError, match="uq_listing_one_executor"):
        await db.commit()
    await db.rollback()
    count = await db.scalar(
        select(func.count())
        .select_from(Interaction)
        .where(
            Interaction.listing_id == UUID(listing["id"]),
            Interaction.status == InteractionStatus.ACCEPTED,
        )
    )
    assert count == 1
