"""Mutual no-meeting confirmation of online lessons and help on PostgreSQL."""

import asyncio
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID, uuid4

import httpx2
import pytest
import time_machine
from sqlalchemy import func, select, update

from campus.core import clock
from campus.core.outbox import OutboxMessage
from campus.modules.identity import Role, RoleAssignment, User
from campus.modules.listings import (
    CompletionMethod,
    Interaction,
    InteractionStatus,
    ListingEvent,
    NoMeetingConfirmation,
)
from tests.test_events_signup import event, signup
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
from tests.test_listings_help import help_request, respond_ok
from tests.test_listings_meeting import propose as propose_meeting
from tests.test_listings_skills import (
    accept_option,
    publish_skill,
    slot,
)
from tests.test_listings_skills import (
    propose as propose_lesson,
)
from tests.test_profile import Account

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


def no_meeting_path(listing: dict[str, Any], interaction: dict[str, Any]) -> str:
    return f"/{listing['id']}/interactions/{interaction['id']}/no-meeting"


async def state(
    account: Account, listing: dict[str, Any], interaction: dict[str, Any]
) -> httpx2.Response:
    return await request(account, "GET", no_meeting_path(listing, interaction))


async def confirm(
    account: Account,
    listing: dict[str, Any],
    interaction: dict[str, Any],
    *,
    key: str | None = None,
    body: dict[str, Any] | None = None,
) -> httpx2.Response:
    return await request(
        account,
        "POST",
        no_meeting_path(listing, interaction) + "/confirmations",
        body,
        key=key,
    )


async def accepted_online_lesson(
    owner_account: Account, borrower_account: Account, **overrides: Any
) -> tuple[dict[str, Any], dict[str, Any], datetime]:
    listing = await publish_skill(owner_account, **overrides)
    at = clock.now() + timedelta(days=1)
    interaction = (
        await propose_lesson(
            borrower_account,
            listing,
            [
                slot(at, online=True),
                slot(at + timedelta(days=1), online=True),
            ],
        )
    ).json()
    response = await accept_option(
        owner_account, listing, interaction, interaction["options"][0]["id"]
    )
    assert response.status_code == 200, response.text
    return listing, response.json(), at


async def accepted_help(
    owner_account: Account,
    borrower_account: Account,
    *,
    audience: str = "students",
) -> tuple[dict[str, Any], dict[str, Any]]:
    listing = await help_request(owner_account, audience=audience)
    interaction = await respond_ok(borrower_account, listing)
    response = await move(owner_account, listing, interaction, "accepted")
    assert response.status_code == 200, response.text
    return listing, response.json()


async def refresh(account: Account) -> None:
    await account.auth.db.rollback()
    account.auth.db.expire_all()


async def confirmation_count(account: Account, interaction: dict[str, Any]) -> int:
    await refresh(account)
    return int(
        await account.auth.db.scalar(
            select(func.count())
            .select_from(NoMeetingConfirmation)
            .where(
                NoMeetingConfirmation.interaction_id == UUID(interaction["id"]),
            )
        )
        or 0
    )


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


async def interaction_row(
    account: Account, listing: dict[str, Any], interaction: dict[str, Any]
) -> dict[str, Any]:
    response = await request(account, "GET", f"/{listing['id']}/interactions")
    assert response.status_code == 200, response.text
    return next(
        item for item in response.json()["items"] if item["id"] == interaction["id"]
    )


async def outbox_actions(account: Account) -> list[str]:
    await refresh(account)
    messages = await account.auth.db.scalars(
        select(OutboxMessage).where(OutboxMessage.topic == "notifications.send")
    )
    actions: list[str] = []
    for message in messages:
        action = (message.payload.get("params") or {}).get("action")
        if isinstance(action, str):
            actions.append(action)
    return actions


def configure(account: Account, **changes: Any) -> None:
    account.auth.settings = account.auth.settings.model_copy(update=changes)
    account.auth.app.state.settings = account.auth.settings


async def test_first_consent_does_not_complete(
    owner: Account, borrower: Account
) -> None:
    listing, interaction, at = await accepted_online_lesson(owner, borrower)

    initial = await state(owner, listing, interaction)
    assert initial.status_code == 200, initial.text
    body = initial.json()
    assert body["status"] == "accepted"
    assert parse_instant(body["agreed_at"]) == at
    assert body["confirmed_by_me"] is False
    assert body["confirmed_by_other"] is False
    assert body["completed"] is False
    assert body["rating_weight"] is None

    first = await confirm(borrower, listing, interaction)
    assert first.status_code == 200, first.text
    body = first.json()
    assert body["status"] == "accepted"
    assert body["completed"] is False
    assert body["confirmed_by_me"] is True
    assert body["confirmed_by_other"] is False
    assert len(body["confirmations"]) == 1
    assert parse_instant(body["agreed_at"]) == at
    assert await confirmation_count(owner, interaction) == 1

    await refresh(owner)
    row = await owner.auth.db.get(Interaction, UUID(interaction["id"]))
    assert row is not None
    assert row.status == InteractionStatus.ACCEPTED
    assert row.completion_method is None

    events = await interaction_events(owner, listing, interaction)
    assert events[-1]["action"] == "no_meeting_confirmed"
    assert events[-1]["status"] == "accepted"
    assert events[-1]["details"]["method"] == "no_meeting"
    assert parse_instant(events[-1]["details"]["agreed_at"]) == at
    assert "no_meeting_confirmed" in await outbox_actions(owner)


async def test_second_consent_completes_once(owner: Account, borrower: Account) -> None:
    listing, interaction, at = await accepted_online_lesson(owner, borrower)
    assert (await confirm(borrower, listing, interaction)).status_code == 200

    second = await confirm(owner, listing, interaction)
    assert second.status_code == 200, second.text
    body = second.json()
    assert body["status"] == "completed"
    assert body["completed"] is True
    assert body["confirmed_by_me"] is True
    assert body["confirmed_by_other"] is True
    assert body["completion_method"] == "no_meeting"
    assert body["rating_weight"] == pytest.approx(0.5)
    assert body["completed_at"] is not None
    assert await confirmation_count(owner, interaction) == 2

    row = await interaction_row(owner, listing, interaction)
    assert row["status"] == "completed"
    assert row["without_meeting"] is True
    assert row["completion_method"] == "no_meeting"
    assert row["completion_weight"] == pytest.approx(0.5)

    events = await interaction_events(owner, listing, interaction)
    assert [item["action"] for item in events[-2:]] == [
        "no_meeting_confirmed",
        "no_meeting_completed",
    ]
    assert events[-1]["status"] == "completed"
    assert parse_instant(events[-1]["details"]["agreed_at"]) == at
    assert set(events[-1]["details"]["confirmed_by"]) == {
        owner.tokens["user"]["id"],
        borrower.tokens["user"]["id"],
    }
    assert "no_meeting_completed" in await outbox_actions(owner)

    # Any further consent is a no-op: one completion, no extra events.
    before = len(events)
    again = await confirm(borrower, listing, interaction)
    assert again.status_code == 200
    assert again.json()["status"] == "completed"
    assert len(await interaction_events(owner, listing, interaction)) == before


async def test_help_without_meeting_uses_the_first_consent_moment(
    owner: Account, borrower: Account
) -> None:
    listing, interaction = await accepted_help(owner, borrower)
    first_at = clock.now()

    with time_machine.travel(first_at, tick=False):
        first = await confirm(borrower, listing, interaction)

    assert first.status_code == 200, first.text
    assert parse_instant(first.json()["agreed_at"]) == first_at

    later = first_at + timedelta(hours=3)
    with time_machine.travel(later, tick=False):
        second = await confirm(owner, listing, interaction)

    assert second.status_code == 200, second.text
    body = second.json()
    assert body["status"] == "completed"
    assert parse_instant(body["agreed_at"]) == first_at
    assert parse_instant(body["completed_at"]) == later
    assert body["rating_weight"] == pytest.approx(0.5)


async def test_same_participant_cannot_confirm_twice(
    owner: Account, borrower: Account
) -> None:
    listing, interaction, _ = await accepted_online_lesson(owner, borrower)

    first = await confirm(borrower, listing, interaction)
    assert first.status_code == 200
    again = await confirm(borrower, listing, interaction)
    assert again.status_code == 200
    assert again.json()["status"] == "accepted"
    assert again.json()["confirmed_by_other"] is False
    assert await confirmation_count(owner, interaction) == 1

    events = await interaction_events(owner, listing, interaction)
    assert [item["action"] for item in events].count("no_meeting_confirmed") == 1
    assert "no_meeting_completed" not in [item["action"] for item in events]


async def test_only_participants_may_confirm(
    owner: Account, borrower: Account, staff: Account, auth: Auth
) -> None:
    listing, interaction, _ = await accepted_online_lesson(owner, borrower)

    for account in (staff,):
        response = await confirm(account, listing, interaction)
        assert response.status_code == 403
        assert response.headers["content-type"] == "application/problem+json"
        assert response.json()["code"] == "listing_forbidden"
        assert (await state(account, listing, interaction)).status_code == 403

    # An administrative role does not replace participation.
    auth.db.add(
        RoleAssignment(
            user_id=UUID(staff.tokens["user"]["id"]),
            role=Role.ADMINISTRATOR,
        )
    )
    await auth.db.commit()
    response = await confirm(staff, listing, interaction)
    assert response.status_code == 403

    assert (await confirm(owner, listing, interaction)).status_code == 200
    assert (await confirm(borrower, listing, interaction)).status_code == 200


async def test_alumni_can_finish_a_started_interaction(
    owner: Account, borrower: Account, auth: Auth
) -> None:
    listing, interaction, _ = await accepted_online_lesson(owner, borrower)
    await auth.db.execute(
        update(User)
        .where(User.id == UUID(borrower.tokens["user"]["id"]))
        .values(account_type="alumni")
    )
    await auth.db.commit()

    assert (await confirm(borrower, listing, interaction)).status_code == 200
    second = await confirm(owner, listing, interaction)
    assert second.status_code == 200
    assert second.json()["status"] == "completed"


async def test_employee_can_finish_own_interaction(
    owner: Account, staff: Account
) -> None:
    listing = await publish_skill(owner, audience="community")
    at = clock.now() + timedelta(days=1)
    interaction = (
        await propose_lesson(
            staff,
            listing,
            [slot(at, online=True), slot(at + timedelta(days=1), online=True)],
        )
    ).json()
    accepted = await accept_option(
        owner, listing, interaction, interaction["options"][0]["id"]
    )
    assert accepted.status_code == 200, accepted.text

    assert (await confirm(staff, listing, interaction)).status_code == 200
    second = await confirm(owner, listing, interaction)
    assert second.status_code == 200
    assert second.json()["status"] == "completed"


@pytest.mark.parametrize(
    "kind",
    ["giveaway", "event", "offline_skill", "help_with_meeting"],
)
async def test_only_online_lesson_and_meetingless_help_are_eligible(
    owner: Account, borrower: Account, kind: str
) -> None:
    if kind == "giveaway":
        listing = await publish(owner)
        interaction = (await reserve(borrower, listing)).json()
        response = await move(owner, listing, interaction, "accepted")
        assert response.status_code == 200
        interaction = response.json()
    elif kind == "event":
        listing = await event(owner)
        response = await signup(borrower, listing)
        assert response.status_code == 200, response.text
        interaction = response.json()["interaction"]
    elif kind == "offline_skill":
        listing = await publish_skill(owner)
        at = clock.now() + timedelta(days=1)
        proposed = (
            await propose_lesson(
                borrower,
                listing,
                [slot(at), slot(at + timedelta(days=1))],
            )
        ).json()
        response = await accept_option(
            owner, listing, proposed, proposed["options"][0]["id"]
        )
        assert response.status_code == 200
        interaction = response.json()
        assert interaction["meeting"]["online"] is False
    else:
        listing, interaction = await accepted_help(owner, borrower)
        meeting = await propose_meeting(
            owner,
            listing,
            interaction,
            clock.now() + timedelta(days=1),
        )
        assert meeting.status_code == 200, meeting.text

    response = await confirm(borrower, listing, interaction)
    assert response.status_code == 409, response.text
    assert response.headers["content-type"] == "application/problem+json"
    assert response.json()["code"] == "listing_no_meeting_unavailable"
    assert await confirmation_count(owner, interaction) == 0


@pytest.mark.parametrize(
    "status",
    [
        InteractionStatus.PENDING,
        InteractionStatus.REJECTED,
        InteractionStatus.CANCELLED,
        InteractionStatus.NO_SHOW,
    ],
)
async def test_non_accepted_interactions_are_not_eligible(
    owner: Account, borrower: Account, status: InteractionStatus
) -> None:
    listing, interaction, _ = await accepted_online_lesson(owner, borrower)
    await owner.auth.db.execute(
        update(Interaction)
        .where(Interaction.id == UUID(interaction["id"]))
        .values(status=status)
    )
    await owner.auth.db.commit()

    response = await confirm(borrower, listing, interaction)
    assert response.status_code == 409, response.text
    assert response.json()["code"] == "listing_no_meeting_unavailable"
    assert await confirmation_count(owner, interaction) == 0


async def test_parallel_consents_complete_exactly_once(
    owner: Account, borrower: Account
) -> None:
    listing, interaction, _ = await accepted_online_lesson(owner, borrower)

    responses = await asyncio.gather(
        confirm(owner, listing, interaction),
        confirm(borrower, listing, interaction),
    )
    assert [response.status_code for response in responses] == [200, 200]
    assert await confirmation_count(owner, interaction) == 2

    row = await interaction_row(owner, listing, interaction)
    assert row["status"] == "completed"
    assert row["without_meeting"] is True

    events = await interaction_events(owner, listing, interaction)
    actions = [item["action"] for item in events]
    assert actions.count("no_meeting_completed") == 1
    assert actions.count("no_meeting_confirmed") == 1

    # The same participant confirming in parallel still gives one consent.
    other_listing, other_interaction, _ = await accepted_online_lesson(owner, borrower)
    replies = await asyncio.gather(
        *(confirm(borrower, other_listing, other_interaction) for _ in range(5))
    )
    assert {reply.status_code for reply in replies} == {200}
    assert await confirmation_count(owner, other_interaction) == 1
    row = await interaction_row(owner, other_listing, other_interaction)
    assert row["status"] == "accepted"


@pytest.mark.parametrize("attempt", range(5))
async def test_race_with_cancellation_never_completes_a_cancelled_interaction(
    owner: Account, borrower: Account, attempt: int
) -> None:
    del attempt
    listing, interaction, _ = await accepted_online_lesson(owner, borrower)
    assert (await confirm(borrower, listing, interaction)).status_code == 200

    confirm_reply, cancel_reply = await asyncio.gather(
        confirm(owner, listing, interaction),
        move(borrower, listing, interaction, "cancelled"),
    )
    assert {confirm_reply.status_code, cancel_reply.status_code} == {200, 409}

    row = await interaction_row(owner, listing, interaction)
    events = await interaction_events(owner, listing, interaction)
    actions = [item["action"] for item in events]
    if row["status"] == "cancelled":
        assert cancel_reply.status_code == 200
        assert confirm_reply.status_code == 409
        assert "no_meeting_completed" not in actions
        assert row["completion_method"] is None
        assert row["completed_at"] is None
        assert await confirmation_count(owner, interaction) == 1
    else:
        assert row["status"] == "completed"
        assert confirm_reply.status_code == 200
        assert cancel_reply.status_code == 409
        assert actions.count("no_meeting_completed") == 1
        assert row["completion_method"] == "no_meeting"


async def test_repeats_are_idempotent(owner: Account, borrower: Account) -> None:
    listing, interaction, _ = await accepted_online_lesson(owner, borrower)
    key = str(uuid4())

    first = await confirm(borrower, listing, interaction, key=key)
    assert first.status_code == 200, first.text
    replay = await confirm(borrower, listing, interaction, key=key)
    assert replay.status_code == 200
    assert replay.json() == first.json()
    assert replay.headers["Idempotent-Replayed"] == "true"

    conflict = await confirm(
        borrower,
        listing,
        interaction,
        key=key,
        body={"unexpected": True},
    )
    assert conflict.status_code == 422
    assert conflict.headers["content-type"] == "application/problem+json"
    assert conflict.json()["code"] == "idempotency_key_reused"
    assert await confirmation_count(owner, interaction) == 1


async def test_idempotency_key_is_required(owner: Account, borrower: Account) -> None:
    listing, interaction, _ = await accepted_online_lesson(owner, borrower)
    response = await borrower.auth.client.post(
        ROOT + no_meeting_path(listing, interaction) + "/confirmations",
        headers=borrower.headers,
    )
    assert response.status_code == 400
    assert response.headers["content-type"] == "application/problem+json"
    assert response.json()["code"] == "idempotency_key_missing"


async def test_missing_interaction_is_not_found(
    owner: Account, borrower: Account
) -> None:
    listing, _, _ = await accepted_online_lesson(owner, borrower)
    response = await request(
        owner,
        "GET",
        f"/{listing['id']}/interactions/{uuid4()}/no-meeting",
    )
    assert response.status_code == 404
    assert response.json()["code"] == "not_found"


async def test_weight_comes_from_configuration(
    owner: Account, borrower: Account
) -> None:
    configure(owner, rating_weight_no_meeting=0.25)
    listing, interaction, _ = await accepted_online_lesson(owner, borrower)

    assert (await confirm(owner, listing, interaction)).status_code == 200
    response = await confirm(borrower, listing, interaction)
    assert response.status_code == 200
    assert response.json()["rating_weight"] == pytest.approx(0.25)

    await refresh(owner)
    row = await owner.auth.db.get(Interaction, UUID(interaction["id"]))
    assert row is not None
    assert row.completion_weight == pytest.approx(0.25)

    history = list(
        await owner.auth.db.scalars(
            select(ListingEvent).where(
                ListingEvent.interaction_id == UUID(interaction["id"]),
                ListingEvent.action == "no_meeting_completed",
            )
        )
    )
    assert len(history) == 1
    assert history[0].details is not None
    assert history[0].details["method"] == CompletionMethod.NO_MEETING.value
