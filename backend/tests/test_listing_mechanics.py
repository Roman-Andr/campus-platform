"""Acceptance of shared listing lifecycle, deadlines, permissions and quotas."""

import asyncio
from datetime import timedelta
from typing import Any
from uuid import UUID, uuid4

import asyncpg
import pytest
import time_machine
from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncEngine

from campus.core import clock
from campus.core.db import create_session_factory
from campus.core.deadlines import process_due_deadlines
from campus.core.outbox import OutboxMessage
from campus.core.web import ProblemError
from campus.modules.identity import User
from campus.modules.listings import (
    TYPE_POLICIES,
    Category,
    Interaction,
    InteractionStatus,
    Listing,
    ListingEvent,
    ListingStatus,
    TypePolicy,
    change_listing,
    change_stage,
    hide,
    locked,
    transition,
)
from tests.database import run_alembic
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
    schedule_meeting,
    staff,
)
from tests.test_profile import Account

__all__ = ["auth", "borrower", "owner", "places", "staff"]


@pytest.fixture(autouse=True)
def long_lived_test_access(auth: Auth) -> None:
    """Keep HTTP credentials valid while testing month-long listing deadlines."""
    auth.settings = auth.settings.model_copy(
        update={"access_token_ttl": timedelta(days=365)}
    )
    auth.app.state.settings = auth.settings


async def deadlines(account: Account) -> int:
    assert isinstance(account.auth.db.bind, AsyncEngine)
    return await process_due_deadlines(
        create_session_factory(account.auth.db.bind), account.auth.settings
    )


def settings(account: Account, **changes: Any) -> None:
    account.auth.settings = account.auth.settings.model_copy(update=changes)
    account.auth.app.state.settings = account.auth.settings


@pytest.mark.parametrize("source", list(ListingStatus))
@pytest.mark.parametrize("target", list(ListingStatus))
async def test_listing_transition_matrix(
    owner: Account, source: ListingStatus, target: ListingStatus
) -> None:
    listing = await publish(owner)
    db = owner.auth.db
    await db.execute(update(Listing).values(status=source))
    await db.commit()
    row = await locked(db, UUID(listing["id"]))
    edges = {
        "draft": {"active", "cancelled"},
        "active": {"busy", "cancelled", "expired", "hidden"},
        "busy": {"active", "completed", "cancelled", "expired", "hidden"},
        "expired": {"active", "busy", "hidden"},
        "completed": {"hidden"},
        "cancelled": {"hidden"},
        "hidden": set(),
    }
    allowed = target in edges[source]
    if allowed:
        change_listing(db, row, target, row.author_id, "test_transition")
        await db.commit()
        assert row.status == target
        assert await db.scalar(select(func.count()).select_from(ListingEvent)) == 2
        assert (
            await db.scalar(
                select(func.count())
                .select_from(OutboxMessage)
                .where(OutboxMessage.topic == "notifications.send")
            )
            == 2
        )
    else:
        with pytest.raises(ProblemError) as error:
            change_listing(db, row, target, row.author_id, "test_transition")
        assert error.value.problem_type.code == "listing_conflict"
        await db.rollback()


@pytest.mark.parametrize("source", list(InteractionStatus))
@pytest.mark.parametrize("target", list(InteractionStatus))
async def test_interaction_service_matrix(
    owner: Account,
    borrower: Account,
    source: InteractionStatus,
    target: InteractionStatus,
) -> None:
    listing = await publish(owner)
    item = (await reserve(borrower, listing)).json()
    db = owner.auth.db
    await db.execute(update(Interaction).values(status=source))
    await db.commit()
    row = await locked(db, UUID(listing["id"]))
    interaction = await db.get(Interaction, UUID(item["id"]))
    assert interaction is not None
    edges = {
        ("pending", "accepted"): "author",
        ("pending", "rejected"): "author",
        ("pending", "cancelled"): "participant",
        ("accepted", "cancelled"): "participant",
        ("accepted", "completed"): "system",
        ("accepted", "no_show"): "system",
        ("no_show", "completed"): "system",
    }
    role = edges.get((source, target))
    actor = {
        "author": row.author_id,
        "participant": interaction.participant_id,
        "system": None,
    }.get(role or "system")
    if role is not None:
        await transition(db, row, interaction, target, actor)
        await db.commit()
        assert interaction.status == target
        message = await db.scalar(
            select(OutboxMessage)
            .where(OutboxMessage.topic == "notifications.send")
            .order_by(OutboxMessage.id.desc())
        )
        assert message is not None
        assert message.payload["params"]["status"] == target
        assert set(message.payload["recipients"]) == {
            str(row.author_id),
            str(interaction.participant_id),
        }
    else:
        with pytest.raises(ProblemError) as error:
            await transition(db, row, interaction, target, actor)
        assert error.value.problem_type.code == "listing_conflict"
        await db.rollback()


async def test_draft_publish_category_and_archive(
    owner: Account, borrower: Account
) -> None:
    listing = await publish(owner, draft=True, category_id=None)
    assert listing["status"] == "draft"
    assert listing["expires_at"] is None
    assert (await request(borrower, "GET", f"/{listing['id']}")).status_code == 404
    assert (await request(borrower, "GET")).json()["items"] == []
    assert (
        await request(owner, "POST", f"/{listing['id']}/publish")
    ).status_code == 422
    assert (
        await request(
            owner,
            "PATCH",
            f"/{listing['id']}",
            {
                "title": "Draft edited",
                "description": "Ready",
                "version": 1,
                "category_id": str(uuid4()),
            },
        )
    ).status_code == 422
    category = await owner.auth.db.scalar(select(Category.id))
    edited = await request(
        owner,
        "PATCH",
        f"/{listing['id']}",
        {
            "title": "Draft edited",
            "description": "Ready",
            "version": 1,
            "category_id": str(category),
        },
    )
    assert edited.status_code == 200
    assert (
        await request(borrower, "POST", f"/{listing['id']}/publish")
    ).status_code == 403
    response = await request(owner, "POST", f"/{listing['id']}/publish")
    assert response.json()["status"] == "active"
    assert len((await request(borrower, "GET")).json()["items"]) == 1
    assert len((await request(owner, "GET", "/mine")).json()["items"]) == 1
    assert (await request(borrower, "GET", "/mine")).json()["items"] == []


async def test_category_languages(owner: Account) -> None:
    async def names(locale: str) -> dict[str, str]:
        response = await owner.auth.client.get(
            "/api/v1/listings/categories",
            headers={
                **owner.headers,
                "Accept-Language": locale,
            },
        )
        assert response.headers["Content-Language"] == locale
        return {item["code"]: item["name"] for item in response.json()["items"]}

    assert (await names("ru"))["books"] == "Книги и учебные материалы"
    assert (await names("en"))["books"] == "Books and study materials"
    assert (
        await request(
            owner,
            "POST",
            "/giveaways",
            {
                "title": "x",
                "description": "y",
            },
        )
    ).json()["code"] == "listing_category_invalid"


async def test_employee_audience(owner: Account, staff: Account) -> None:
    category = str(await owner.auth.db.scalar(select(Category.id)))
    response = await request(
        staff,
        "POST",
        "/giveaways",
        {
            "title": "Staff",
            "description": "Desk",
            "category_id": category,
        },
    )
    assert response.status_code == 403
    listing = await publish(owner)
    assert (await reserve(staff, listing)).status_code == 403
    community = await publish(owner, audience="community")
    assert (await request(staff, "GET", f"/{community['id']}")).status_code == 200
    assert (await reserve(staff, community)).status_code == 201
    assert (await publish(staff, audience="community"))["status"] == "active"


@pytest.mark.parametrize("accepted", [False, True])
async def test_close_rejects_only_pending(
    owner: Account, borrower: Account, accepted: bool
) -> None:
    listing = await publish(owner)
    interaction = (await reserve(borrower, listing)).json()
    if accepted:
        assert (await move(owner, listing, interaction, "accepted")).status_code == 200
    # Add multiple pending applications to verify bulk rejection for future types.
    owner.auth.db.add_all(
        [
            Interaction(
                listing_id=UUID(listing["id"]),
                participant_id=UUID(interaction["participant_id"]),
                slot=slot,
            )
            for slot in (2, 3)
        ]
    )
    await owner.auth.db.commit()
    body = {"reason": "No longer available"} if accepted else None
    assert (
        await request(owner, "POST", f"/{listing['id']}/cancel", body)
    ).status_code == 200
    owner.auth.db.expire_all()
    rows = list(
        await owner.auth.db.scalars(select(Interaction).order_by(Interaction.id))
    )
    assert [row.status for row in rows] == [
        "cancelled" if accepted else "rejected",
        "rejected",
        "rejected",
    ]
    if accepted:
        cancelled = rows[0]
        assert cancelled.cancelled_by == "author"
        assert cancelled.cancellation_reason == "No longer available"
        assert cancelled.late_cancelled is False
        assert (
            await move(borrower, listing, interaction, "cancelled")
        ).status_code == 409
        assert (await request(owner, "GET", f"/{listing['id']}")).json()[
            "status"
        ] == "cancelled"
    events = (await request(owner, "GET", f"/{listing['id']}/events")).json()["items"]
    assert {e["reason"] for e in events if e["action"] == "auto_rejected"} == {
        "listing_cancelled"
    }
    if accepted:
        by_author = next(e for e in events if e["action"] == "cancelled_by_author")
        assert by_author["reason"] == "No longer available"
        assert by_author["details"]["after_acceptance"] is True


async def test_timeout_and_no_reputation_effect(
    owner: Account, borrower: Account
) -> None:
    now = clock.now()
    with time_machine.travel(now, tick=False):
        listing = await publish(owner)
        interaction = (await reserve(borrower, listing)).json()
    with time_machine.travel(
        now + timedelta(hours=24) - timedelta(seconds=1), tick=False
    ):
        assert await deadlines(owner) == 0
    with time_machine.travel(now + timedelta(hours=24, seconds=1), tick=False):
        assert await deadlines(owner) == 1
        assert await deadlines(owner) == 0
        response = await request(owner, "GET", f"/{listing['id']}")
        assert response.json()["status"] == "active"
        events = (
            await request(
                borrower,
                "GET",
                f"/{listing['id']}/interactions/{interaction['id']}/events",
            )
        ).json()["items"]
        assert events[-1]["status"] == "rejected"
        assert events[-1]["reason"] == "author_timeout"
        assert events[-1]["actor_id"] is None
        assert not events[-1]["via_assistant"]
        assert not events[-1]["offline_qr"]
        messages = list(
            await owner.auth.db.scalars(
                select(OutboxMessage).where(OutboxMessage.topic == "notifications.send")
            )
        )
        assert messages[-1].payload["type"] == "listing.activity"
        assert messages[-1].payload["params"]["reason"] == "author_timeout"


async def test_extend_expire_republish(owner: Account, borrower: Account) -> None:
    now = clock.now()
    with time_machine.travel(now, tick=False):
        listing = await publish(owner)
    with time_machine.travel(now + timedelta(days=20), tick=False):
        assert (
            await request(borrower, "POST", f"/{listing['id']}/extend")
        ).status_code == 403
        extended = (await request(owner, "POST", f"/{listing['id']}/extend")).json()
    with time_machine.travel(now + timedelta(days=31), tick=False):
        assert await deadlines(owner) == 0
        assert len((await request(borrower, "GET")).json()["items"]) == 1
    with time_machine.travel(now + timedelta(days=51), tick=False):
        assert await deadlines(owner) == 1
        assert (await request(borrower, "GET")).json()["items"] == []
        archived = (await request(owner, "GET", "/mine")).json()["items"][0]
        assert archived["status"] == "expired"
        assert archived["expires_at"] == extended["expires_at"]
        response = await request(owner, "POST", f"/{listing['id']}/publish")
        assert response.status_code == 200
        assert response.json()["status"] == "active"
        assert len((await request(borrower, "GET")).json()["items"]) == 1


async def test_hidden_is_private(owner: Account, borrower: Account) -> None:
    listing = await publish(owner)
    db = owner.auth.db
    row = await locked(db, UUID(listing["id"]))
    await hide(db, row, row.author_id, "Moderation reason")
    await db.commit()
    assert (await request(borrower, "GET", f"/{listing['id']}")).status_code == 404
    assert (await request(borrower, "GET")).json()["items"] == []
    response = (await request(owner, "GET", f"/{listing['id']}")).json()
    assert response["status"] == "hidden"
    assert response["hidden_reason"] == "Moderation reason"


async def test_interaction_history_permissions(
    owner: Account, borrower: Account, staff: Account
) -> None:
    listing = await publish(owner, audience="community")
    interaction = (await reserve(borrower, listing)).json()
    path = f"/{listing['id']}/interactions/{interaction['id']}/events"
    for account, status in ((owner, 200), (borrower, 200), (staff, 403)):
        assert (await request(account, "GET", path)).status_code == status


async def test_publication_limit_parallel_and_window(owner: Account) -> None:
    category = str(await owner.auth.db.scalar(select(Category.id)))
    body = {"title": "Desk", "description": "Good", "category_id": category}
    responses = await asyncio.gather(
        *(request(owner, "POST", "/giveaways", body) for _ in range(11))
    )
    assert sorted(r.status_code for r in responses) == [201] * 10 + [429]
    limited = next(r for r in responses if r.status_code == 429)
    assert 0 < int(limited.headers["Retry-After"]) <= 86400
    assert limited.json()["code"] == "listing_rate_limited"
    assert limited.headers["content-type"] == "application/problem+json"
    with time_machine.travel(clock.now() + timedelta(days=1, seconds=1), tick=False):
        assert (await request(owner, "POST", "/giveaways", body)).status_code == 201


async def test_response_limit(owner: Account, borrower: Account) -> None:
    listing = await publish(owner)
    for _ in range(30):
        interaction = (await reserve(borrower, listing)).json()
        assert (
            await move(borrower, listing, interaction, "cancelled")
        ).status_code == 200
    response = await reserve(borrower, listing)
    assert response.status_code == 429
    assert int(response.headers["Retry-After"]) > 0
    with time_machine.travel(clock.now() + timedelta(hours=1, seconds=1), tick=False):
        assert (await reserve(borrower, listing)).status_code == 201


async def test_configured_deadlines_and_limits(
    owner: Account, borrower: Account
) -> None:
    settings(
        owner,
        listing_lifetime=timedelta(minutes=5),
        listing_response_timeout=timedelta(minutes=1),
        listing_publication_limit=1,
        listing_publication_window=timedelta(minutes=2),
        listing_response_limit=1,
        listing_response_window=timedelta(seconds=30),
    )
    now = clock.now()
    with time_machine.travel(now, tick=False):
        listing = await publish(owner)
        interaction = (await reserve(borrower, listing)).json()
        await move(borrower, listing, interaction, "cancelled")
        assert (await reserve(borrower, listing)).status_code == 429
        category = str(await owner.auth.db.scalar(select(Category.id)))
        assert (
            await request(
                owner,
                "POST",
                "/giveaways",
                {
                    "title": "x",
                    "description": "y",
                    "category_id": category,
                },
            )
        ).status_code == 429
    with time_machine.travel(now + timedelta(seconds=31), tick=False):
        assert (await reserve(borrower, listing)).status_code == 201
    with time_machine.travel(now + timedelta(seconds=92), tick=False):
        assert await deadlines(owner) == 2  # cancelled request and current request
        assert (await request(owner, "GET", f"/{listing['id']}")).json()[
            "status"
        ] == "active"
    with time_machine.travel(now + timedelta(minutes=6), tick=False):
        assert await deadlines(owner) == 1
        assert (await request(owner, "GET", f"/{listing['id']}")).json()[
            "status"
        ] == "expired"


async def test_outbox_rolls_back_with_journal(owner: Account) -> None:
    listing = await publish(owner)
    db = owner.auth.db
    before = await db.scalar(
        select(func.count())
        .select_from(OutboxMessage)
        .where(OutboxMessage.topic == "notifications.send")
    )
    assert before is not None
    row = await locked(db, UUID(listing["id"]))
    change_listing(db, row, ListingStatus.CANCELLED, row.author_id, "cancelled")
    await db.flush()
    assert (
        await db.scalar(
            select(func.count())
            .select_from(OutboxMessage)
            .where(OutboxMessage.topic == "notifications.send")
        )
        == before + 1
    )
    await db.rollback()
    assert (
        await db.scalar(
            select(func.count())
            .select_from(OutboxMessage)
            .where(OutboxMessage.topic == "notifications.send")
        )
        == before
    )
    assert await db.scalar(select(func.count()).select_from(ListingEvent)) == 1


async def test_type_specific_stages(
    owner: Account, borrower: Account, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setitem(
        TYPE_POLICIES,
        "giveaway",
        TypePolicy(True, "ready", frozenset({("ready", "handover")})),
    )
    listing = await publish(owner)
    interaction = (await reserve(borrower, listing)).json()
    assert (await move(owner, listing, interaction, "accepted")).json()[
        "stage"
    ] == "ready"
    db = owner.auth.db
    row = await locked(db, UUID(listing["id"]))
    item = await db.get(Interaction, UUID(interaction["id"]))
    assert item is not None
    with pytest.raises(ProblemError):
        change_stage(db, row, item, "unknown", row.author_id)
    with pytest.raises(ProblemError):
        change_stage(db, row, item, "handover", uuid4())
    change_stage(db, row, item, "handover", row.author_id)
    await db.commit()
    assert item.stage == "handover"
    assert item.status == "accepted"


@pytest.mark.parametrize(
    ("field", "value"),
    [("title", "x" * 101), ("description", "x" * 5001), ("title", " ")],
)
async def test_text_validation(owner: Account, field: str, value: str) -> None:
    category = str(await owner.auth.db.scalar(select(Category.id)))
    response = await request(
        owner,
        "POST",
        "/giveaways",
        {
            "title": "Desk",
            "description": "Good",
            "category_id": category,
            field: value,
        },
    )
    assert response.status_code == 422
    assert response.json()["code"] == "listing_content_invalid"
    assert response.headers["content-type"] == "application/problem+json"


async def test_configured_text_lengths(owner: Account) -> None:
    settings(owner, listing_title_max_length=4, listing_description_max_length=6)
    await publish(owner, title="Desk", description="Good")
    category = str(await owner.auth.db.scalar(select(Category.id)))
    response = await request(
        owner,
        "POST",
        "/giveaways",
        {
            "title": "12345",
            "description": "Good",
            "category_id": category,
        },
    )
    assert response.status_code == 422
    response = await request(
        owner,
        "POST",
        "/giveaways",
        {
            "title": "Desk",
            "description": "1234567",
            "category_id": category,
        },
    )
    assert response.status_code == 422


async def test_republish_accepted_stays_occupied(
    owner: Account, borrower: Account
) -> None:
    listing = await publish(owner)
    interaction = (await reserve(borrower, listing)).json()
    await move(owner, listing, interaction, "accepted")
    await schedule_meeting(
        owner, borrower, listing, interaction, clock.now() + timedelta(days=40)
    )
    with time_machine.travel(clock.now() + timedelta(days=31), tick=False):
        assert await deadlines(owner) == 1
        assert (await request(owner, "POST", f"/{listing['id']}/publish")).json()[
            "status"
        ] == "busy"
        assert (await reserve(borrower, listing)).status_code == 409
        assert (
            await move(borrower, listing, interaction, "cancelled")
        ).status_code == 200
        assert (await request(owner, "GET", f"/{listing['id']}")).json()[
            "status"
        ] == "active"


async def test_accepted_finishes_after_expiry(
    owner: Account, borrower: Account
) -> None:
    listing = await publish(owner)
    interaction = (await reserve(borrower, listing)).json()
    await move(owner, listing, interaction, "accepted")
    await schedule_meeting(
        owner, borrower, listing, interaction, clock.now() + timedelta(days=40)
    )
    with time_machine.travel(clock.now() + timedelta(days=31), tick=False):
        assert await deadlines(owner) == 1
        db = owner.auth.db
        row = await locked(db, UUID(listing["id"]))
        item = await db.get(Interaction, UUID(interaction["id"]))
        assert item is not None
        await transition(db, row, item, InteractionStatus.COMPLETED, None)
        await db.commit()
        assert row.status == "expired"
        assert item.status == "completed"


async def test_new_mutations_idempotent(owner: Account) -> None:
    listing = await publish(owner, draft=True)
    for action in ("publish", "extend"):
        key = str(uuid4())
        path = f"/{listing['id']}/{action}"
        first = await request(owner, "POST", path, key=key)
        replay = await request(owner, "POST", path, key=key)
        assert first.status_code == 200
        assert replay.json() == first.json()
        assert replay.headers["Idempotent-Replayed"] == "true"


async def test_response_quota_parallel(owner: Account, borrower: Account) -> None:
    settings(owner, listing_response_limit=2)
    listings = [await publish(owner) for _ in range(3)]
    responses = await asyncio.gather(
        *(reserve(borrower, listing) for listing in listings)
    )
    assert sorted(response.status_code for response in responses) == [201, 201, 429]
    assert (
        await owner.auth.db.scalar(select(func.count()).select_from(Interaction)) == 2
    )


@pytest.mark.parametrize(
    "path",
    ["", "/publish", "/extend", "/cancel", "/interactions/{interaction}/transition"],
)
async def test_mutations_require_complete_profile(
    owner: Account, borrower: Account, path: str
) -> None:
    listing = await publish(owner)
    interaction = (await reserve(borrower, listing)).json()
    await owner.auth.db.execute(
        update(User)
        .where(User.id == UUID(listing["author_id"]))
        .values(city_id=None, faculty_id=None, dormitory_id=None, course=None)
    )
    await owner.auth.db.commit()
    response = await request(
        owner,
        "POST" if path else "PATCH",
        f"/{listing['id']}" + path.format(interaction=interaction["id"]),
        {"status": "accepted"}
        if "transition" in path
        else {"version": 2, "title": "Desk", "description": "Good"}
        if not path
        else None,
    )
    assert response.status_code == 403
    assert response.json()["code"] == "profile_incomplete"


async def test_expiry_bulk_rejection(owner: Account, borrower: Account) -> None:
    settings(
        owner,
        listing_response_timeout=timedelta(days=60),
        listing_lifetime=timedelta(minutes=1),
    )
    listing = await publish(owner)
    interaction = (await reserve(borrower, listing)).json()
    owner.auth.db.add_all(
        [
            Interaction(
                listing_id=UUID(listing["id"]),
                participant_id=UUID(interaction["participant_id"]),
                slot=slot,
            )
            for slot in (2, 3)
        ]
    )
    await owner.auth.db.commit()
    with time_machine.travel(clock.now() + timedelta(minutes=2), tick=False):
        assert await deadlines(owner) == 1
    assert set(await owner.auth.db.scalars(select(Interaction.status))) == {"rejected"}
    assert set(
        await owner.auth.db.scalars(
            select(ListingEvent.reason).where(ListingEvent.action == "auto_rejected")
        )
    ) == {"listing_expired"}


async def test_upgrade_existing_pending_request(
    owner: Account, borrower: Account, database_url: str
) -> None:
    """Backfill a pre-46 reservation and its durable author-response deadline."""
    listing = await publish(owner)
    interaction = (await reserve(borrower, listing)).json()
    await owner.auth.db.close()
    await asyncio.to_thread(run_alembic, database_url, "downgrade", "b87769795a67")
    await asyncio.to_thread(run_alembic, database_url, "upgrade", "head")
    connection = await asyncpg.connect(database_url.replace("+asyncpg", ""))
    try:
        category = await connection.fetchval(
            "SELECT c.code FROM listing l "
            "JOIN listing_category c ON c.id=l.category_id WHERE l.id=$1",
            UUID(listing["id"]),
        )
        assert category == "other"
        item = await connection.fetchrow(
            "SELECT * FROM listing_interaction WHERE id=$1", UUID(interaction["id"])
        )
        assert item is not None
        assert item["status"] == "pending"
        assert item["response_due_at"] == item["created_at"] + timedelta(hours=24)
        deadline = await connection.fetchrow(
            "SELECT * FROM deadline WHERE topic='listing.author_response'"
        )
        assert deadline is not None
        assert deadline["available_at"] == item["response_due_at"]
        assert deadline["key"] == f"interaction:{interaction['id']}"
    finally:
        await connection.close()


async def test_aggregate_history_does_not_leak_other_interactions(
    owner: Account, borrower: Account, staff: Account
) -> None:
    listing = await publish(owner, audience="community")
    first = (await reserve(borrower, listing)).json()
    await move(borrower, listing, first, "cancelled")
    second = (await reserve(staff, listing)).json()
    response = await request(
        borrower, "GET", f"/{listing['id']}/interactions/{second['id']}/events"
    )
    assert response.status_code == 403
    history = (await request(borrower, "GET", f"/{listing['id']}/events")).json()[
        "items"
    ]
    assert {event["interaction_id"] for event in history} == {None, first["id"]}
    history = (await request(owner, "GET", f"/{listing['id']}/events")).json()["items"]
    assert {event["interaction_id"] for event in history} == {
        None,
        first["id"],
        second["id"],
    }
