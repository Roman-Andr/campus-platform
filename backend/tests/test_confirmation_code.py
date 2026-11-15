"""Server-issued six-digit confirmation codes on real PostgreSQL."""

import asyncio
import json
import logging
import re
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from datetime import datetime, timedelta
from typing import Any
from uuid import UUID, uuid4

import httpx2
import pytest
import time_machine
from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from campus.core import clock
from campus.core.db import create_engine, create_session_factory
from campus.core.outbox import OutboxMessage
from campus.modules.identity import Role, RoleAssignment, User
from campus.modules.listings import (
    Interaction,
    Listing,
    ListingEvent,
)
from campus.modules.listings import (
    transition as real_transition,
)
from campus.modules.reputation import ConfirmationCode
from tests.test_listings import (
    auth,
    borrower,
    move,
    owner,
    places,
    publish,
    reserve,
    staff,
)
from tests.test_profile import Account

__all__ = ["auth", "borrower", "owner", "places", "staff"]

ROOT = "/api/v1/listings"
SIX_DIGITS = re.compile(r"^[0-9]{6}$")


def set_settings(account: Account, **changes: Any) -> None:
    account.auth.settings = account.auth.settings.model_copy(update=changes)
    account.auth.app.state.settings = account.auth.settings


def user_id(account: Account) -> UUID:
    return UUID(account.tokens["user"]["id"])


def code_path(listing: dict[str, Any], interaction: dict[str, Any]) -> str:
    return f"{ROOT}/{listing['id']}/interactions/{interaction['id']}/code"


async def issue(
    account: Account,
    listing: dict[str, Any],
    interaction: dict[str, Any],
    key: str | None = None,
) -> httpx2.Response:
    return await account.auth.client.post(
        code_path(listing, interaction),
        headers={"Idempotency-Key": key or str(uuid4()), **account.headers},
    )


async def confirm(
    account: Account,
    listing: dict[str, Any],
    interaction: dict[str, Any],
    code: str,
    key: str | None = None,
) -> httpx2.Response:
    return await account.auth.client.post(
        code_path(listing, interaction) + "/confirm",
        json={"code": code},
        headers={"Idempotency-Key": key or str(uuid4()), **account.headers},
    )


def other_code(code: str) -> str:
    """A different six-digit string, even when ``code`` is all zeroes."""
    return ("1" if code[0] == "0" else "0") + code[1:]


async def accepted(
    author: Account, participant: Account
) -> tuple[dict[str, Any], dict[str, Any]]:
    listing = await publish(author)
    interaction = (await reserve(participant, listing)).json()
    response = await move(author, listing, interaction, "accepted")
    assert response.status_code == 200, response.text
    return listing, response.json()


async def code_row(account: Account, interaction_id: UUID) -> ConfirmationCode | None:
    db = account.auth.db
    await db.rollback()
    return await db.scalar(
        select(ConfirmationCode).where(
            ConfirmationCode.interaction_id == interaction_id
        )
    )


async def counts(account: Account, interaction_id: UUID) -> tuple[int, int, int]:
    """Journal, outbox and code-completed events for one interaction."""
    db = account.auth.db
    await db.rollback()
    events = await db.scalar(
        select(func.count())
        .select_from(ListingEvent)
        .where(ListingEvent.interaction_id == interaction_id)
    )
    outbox = await db.scalar(select(func.count()).select_from(OutboxMessage))
    completed = await db.scalar(
        select(func.count())
        .select_from(ListingEvent)
        .where(
            ListingEvent.interaction_id == interaction_id,
            ListingEvent.action == "code_completed",
        )
    )
    return int(events or 0), int(outbox or 0), int(completed or 0)


@pytest.mark.parametrize("presenter", ["author", "participant"])
async def test_code_completes_accepted_interaction(  # noqa: PLR0915 - full response
    owner: Account, borrower: Account, presenter: str
) -> None:
    listing, interaction = await accepted(owner, borrower)
    showing = owner if presenter == "author" else borrower
    scanning = borrower if presenter == "author" else owner
    interaction_id = UUID(interaction["id"])
    before = await counts(owner, interaction_id)

    response = await issue(showing, listing, interaction)
    assert response.status_code == 200, response.text
    body = response.json()
    assert SIX_DIGITS.fullmatch(body["code"]) is not None
    assert body["attempts_left"] == 5
    assert body["presenter_id"] == str(user_id(showing))
    assert body["server_time"].endswith("Z")
    assert response.headers["cache-control"] == "no-store"
    issued = datetime_from(body["issued_at"])
    expires = datetime_from(body["expires_at"])
    assert expires - issued == owner.auth.settings.confirmation_code_ttl
    code = body["code"]

    row = await code_row(owner, interaction_id)
    assert row is not None
    assert row.presenter_id == user_id(showing)
    assert row.code_hash != code
    assert len(row.code_hash) == 64
    assert row.attempts == 0
    assert row.consumed_at is None
    assert code not in json.dumps(row.code_hash)

    confirmed = await confirm(scanning, listing, interaction, code)
    assert confirmed.status_code == 200, confirmed.text
    result = confirmed.json()
    assert result["status"] == "completed"
    assert result["completed"] is True
    assert result["completion_method"] == "qr"
    assert result["rating_weight"] == 1.0
    assert result["presenter_id"] == str(user_id(showing))
    assert result["scanner_id"] == str(user_id(scanning))
    assert result["completed_at"] is not None
    assert "code" not in result

    db = owner.auth.db
    await db.rollback()
    interaction_row = await db.get(Interaction, interaction_id)
    assert interaction_row is not None
    assert interaction_row.status == "completed"
    assert interaction_row.completion_method == "qr"
    assert interaction_row.completion_weight == 1.0
    listing_row = await db.get(Listing, UUID(listing["id"]))
    assert listing_row is not None
    assert listing_row.status == "completed"

    row = await code_row(owner, interaction_id)
    assert row is not None
    assert row.consumed_at is not None
    events = list(
        await db.scalars(
            select(ListingEvent)
            .where(ListingEvent.interaction_id == interaction_id)
            .order_by(ListingEvent.created_at, ListingEvent.id)
        )
    )
    assert events[-1].action == "code_completed"
    assert events[-1].details is not None
    assert events[-1].details["method"] == "code"
    assert events[-1].details["presenter_id"] == str(user_id(showing))
    assert code not in json.dumps(events[-1].details)
    after = await counts(owner, interaction_id)
    assert after[0] == before[0] + 1
    # Listing closed, completion recorded, profile aggregates refreshed.
    assert after[1] == before[1] + 3
    assert after[2] == 1


def datetime_from(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


async def test_code_keeps_leading_zeroes(
    owner: Account, borrower: Account, monkeypatch: pytest.MonkeyPatch
) -> None:
    listing, interaction = await accepted(owner, borrower)
    monkeypatch.setattr(
        "campus.modules.reputation.service.secrets.randbelow",
        lambda _upper: 7,
    )

    response = await issue(owner, listing, interaction)
    assert response.status_code == 200, response.text
    assert response.json()["code"] == "000007"

    confirmed = await confirm(borrower, listing, interaction, "000007")
    assert confirmed.status_code == 200, confirmed.text


async def test_code_ttl_boundaries(owner: Account, borrower: Account) -> None:
    listing, interaction = await accepted(owner, borrower)
    fixed = clock.now()
    with time_machine.travel(fixed, tick=False):
        response = await issue(owner, listing, interaction)
        assert response.status_code == 200, response.text
        code = response.json()["code"]

    ttl = owner.auth.settings.confirmation_code_ttl
    with time_machine.travel(fixed + ttl - timedelta(microseconds=1), tick=False):
        accepted_response = await confirm(borrower, listing, interaction, code)
    assert accepted_response.status_code == 200, accepted_response.text

    second_listing, second_interaction = await accepted(owner, borrower)
    fixed = clock.now()
    with time_machine.travel(fixed, tick=False):
        response = await issue(owner, second_listing, second_interaction)
        assert response.status_code == 200, response.text
        code = response.json()["code"]

    with time_machine.travel(fixed + ttl, tick=False):
        expired = await confirm(borrower, second_listing, second_interaction, code)
        assert expired.status_code == 409
        assert expired.json()["code"] == "confirmation_code_expired"
        replaced = await issue(owner, second_listing, second_interaction)
        assert replaced.status_code == 200, replaced.text
        new_code = replaced.json()["code"]
        confirmed = await confirm(
            borrower, second_listing, second_interaction, new_code
        )
    assert confirmed.status_code == 200, confirmed.text


async def test_code_ttl_is_configurable(owner: Account, borrower: Account) -> None:
    listing, interaction = await accepted(owner, borrower)
    set_settings(owner, confirmation_code_ttl=timedelta(seconds=5))
    fixed = clock.now()
    with time_machine.travel(fixed, tick=False):
        response = await issue(owner, listing, interaction)
        assert response.status_code == 200, response.text
        body = response.json()
        assert datetime_from(body["expires_at"]) - datetime_from(
            body["issued_at"]
        ) == timedelta(seconds=5)
        code = body["code"]

    with time_machine.travel(fixed + timedelta(seconds=5), tick=False):
        expired = await confirm(borrower, listing, interaction, code)
    assert expired.status_code == 409
    assert expired.json()["code"] == "confirmation_code_expired"


async def test_attempt_limit_is_configurable(owner: Account, borrower: Account) -> None:
    listing, interaction = await accepted(owner, borrower)
    set_settings(owner, confirmation_code_max_attempts=2)
    issued = await issue(owner, listing, interaction)
    assert issued.status_code == 200, issued.text
    assert issued.json()["attempts_left"] == 2
    wrong = other_code(issued.json()["code"])

    first = await confirm(borrower, listing, interaction, wrong)
    assert first.status_code == 422
    second = await confirm(borrower, listing, interaction, wrong)
    assert second.status_code == 429
    correct = await confirm(borrower, listing, interaction, issued.json()["code"])
    assert correct.status_code == 429


async def test_wrong_code_limit_is_exhausted(owner: Account, borrower: Account) -> None:
    listing, interaction = await accepted(owner, borrower)
    interaction_id = UUID(interaction["id"])
    issued = (await issue(owner, listing, interaction)).json()
    wrong = other_code(issued["code"])

    for attempt in range(4):
        response = await confirm(borrower, listing, interaction, wrong)
        assert response.status_code == 422, response.text
        assert response.json()["code"] == "confirmation_code_invalid"
        row = await code_row(owner, interaction_id)
        assert row is not None
        assert row.attempts == attempt + 1

    fifth = await confirm(borrower, listing, interaction, wrong)
    assert fifth.status_code == 429
    assert fifth.json()["code"] == "confirmation_code_attempts_exceeded"
    row = await code_row(owner, interaction_id)
    assert row is not None
    assert row.attempts == 5

    correct_after_limit = await confirm(borrower, listing, interaction, issued["code"])
    assert correct_after_limit.status_code == 429
    assert correct_after_limit.json()["code"] == "confirmation_code_attempts_exceeded"
    reissue = await issue(owner, listing, interaction)
    assert reissue.status_code == 429
    assert reissue.json()["code"] == "confirmation_code_attempts_exceeded"

    db = owner.auth.db
    await db.rollback()
    current = await db.get(Interaction, interaction_id)
    assert current is not None
    assert current.status == "accepted"


async def test_reissue_keeps_the_attempt_counter(
    owner: Account, borrower: Account
) -> None:
    listing, interaction = await accepted(owner, borrower)
    first = (await issue(owner, listing, interaction)).json()
    wrong = other_code(first["code"])
    assert (await confirm(borrower, listing, interaction, wrong)).status_code == 422

    reissued = await issue(owner, listing, interaction)
    assert reissued.status_code == 200, reissued.text
    assert reissued.json()["attempts_left"] == 4

    second_wrong = other_code(reissued.json()["code"])
    for _ in range(4):
        response = await confirm(borrower, listing, interaction, second_wrong)
    assert response.status_code == 429
    assert response.json()["code"] == "confirmation_code_attempts_exceeded"

    blocked = await issue(owner, listing, interaction)
    assert blocked.status_code == 429


async def test_parallel_wrong_entries_cannot_exceed_limit(
    owner: Account, borrower: Account
) -> None:
    listing, interaction = await accepted(owner, borrower)
    interaction_id = UUID(interaction["id"])
    issued = (await issue(owner, listing, interaction)).json()
    wrong = other_code(issued["code"])

    responses = await asyncio.gather(
        *(confirm(borrower, listing, interaction, wrong) for _ in range(10))
    )

    assert sum(response.status_code == 422 for response in responses) == 4
    assert sum(response.status_code == 429 for response in responses) == 6
    row = await code_row(owner, interaction_id)
    assert row is not None
    assert row.attempts == 5
    correct = await confirm(borrower, listing, interaction, issued["code"])
    assert correct.status_code == 429


async def test_parallel_correct_entries_complete_once(
    owner: Account, borrower: Account
) -> None:
    listing, interaction = await accepted(owner, borrower)
    interaction_id = UUID(interaction["id"])
    before = await counts(owner, interaction_id)
    code = (await issue(owner, listing, interaction)).json()["code"]

    responses = await asyncio.gather(
        *(confirm(borrower, listing, interaction, code) for _ in range(6))
    )

    assert all(response.status_code == 200 for response in responses)
    after = await counts(owner, interaction_id)
    assert after[0] == before[0] + 1
    # Listing closed, completion recorded, profile aggregates refreshed.
    assert after[1] == before[1] + 3
    assert after[2] == 1
    row = await code_row(owner, interaction_id)
    assert row is not None
    assert row.consumed_at is not None
    assert row.attempts == 0


async def test_outsider_cannot_issue_or_confirm(
    owner: Account, borrower: Account, staff: Account
) -> None:
    listing, interaction = await accepted(owner, borrower)

    denied_issue = await issue(staff, listing, interaction)
    assert denied_issue.status_code == 403
    assert denied_issue.json()["code"] == "confirmation_code_not_participant"

    code = (await issue(owner, listing, interaction)).json()["code"]
    denied_confirm = await confirm(staff, listing, interaction, code)
    assert denied_confirm.status_code == 403
    assert denied_confirm.json()["code"] == "confirmation_code_not_participant"
    row = await code_row(owner, UUID(interaction["id"]))
    assert row is not None
    assert row.attempts == 0


async def test_administrator_has_no_override(
    owner: Account, borrower: Account, staff: Account
) -> None:
    listing, interaction = await accepted(owner, borrower)
    db = owner.auth.db
    db.add(RoleAssignment(user_id=user_id(staff), role=Role.ADMINISTRATOR))
    await db.commit()

    response = await issue(staff, listing, interaction)
    assert response.status_code == 403
    assert response.json()["code"] == "confirmation_code_not_participant"

    code = (await issue(owner, listing, interaction)).json()["code"]
    confirmed = await confirm(staff, listing, interaction, code)
    assert confirmed.status_code == 403
    assert confirmed.json()["code"] == "confirmation_code_not_participant"


async def test_same_participant_cannot_enter_own_code(
    owner: Account, borrower: Account
) -> None:
    listing, interaction = await accepted(owner, borrower)
    code = (await issue(owner, listing, interaction)).json()["code"]

    response = await confirm(owner, listing, interaction, code)
    assert response.status_code == 403
    assert response.json()["code"] == "confirmation_code_same_participant"
    row = await code_row(owner, UUID(interaction["id"]))
    assert row is not None
    assert row.attempts == 0

    success = await confirm(borrower, listing, interaction, code)
    assert success.status_code == 200, success.text


async def test_revoked_session_cannot_use_a_code(
    owner: Account, borrower: Account
) -> None:
    listing, interaction = await accepted(owner, borrower)
    code = (await issue(owner, listing, interaction)).json()["code"]
    signed_out = await borrower.auth.client.post(
        "/api/v1/auth/sign-out",
        headers={"Idempotency-Key": str(uuid4()), **borrower.headers},
    )
    assert signed_out.status_code == 204

    response = await confirm(borrower, listing, interaction, code)
    assert response.status_code == 401
    assert response.json()["code"] == "unauthorized"


async def test_anonymous_cannot_confirm(owner: Account, borrower: Account) -> None:
    listing, interaction = await accepted(owner, borrower)
    response = await owner.auth.client.post(
        code_path(listing, interaction) + "/confirm",
        json={"code": "123456"},
        headers={"Idempotency-Key": str(uuid4())},
    )
    assert response.status_code == 401


async def test_graduate_and_employee_follow_completion_matrix(
    owner: Account, borrower: Account, staff: Account
) -> None:
    listing, interaction = await accepted(owner, borrower)
    db = owner.auth.db
    await db.execute(
        update(User).where(User.id == user_id(borrower)).values(account_type="alumni")
    )
    await db.commit()
    code = (await issue(owner, listing, interaction)).json()["code"]
    graduate = await confirm(borrower, listing, interaction, code)
    assert graduate.status_code == 200, graduate.text

    staff_listing = await publish(staff, audience="community")
    staff_interaction = (await reserve(owner, staff_listing)).json()
    accepted_response = await move(staff, staff_listing, staff_interaction, "accepted")
    assert accepted_response.status_code == 200, accepted_response.text
    staff_interaction = accepted_response.json()
    code = (await issue(staff, staff_listing, staff_interaction)).json()["code"]
    employee = await confirm(owner, staff_listing, staff_interaction, code)
    assert employee.status_code == 200, employee.text


@pytest.mark.parametrize("state", ["pending", "rejected", "cancelled"])
async def test_inactive_interaction_cannot_use_code(
    owner: Account, borrower: Account, state: str
) -> None:
    listing = await publish(owner)
    interaction = (await reserve(borrower, listing)).json()
    if state != "pending":
        actor = owner if state == "rejected" else borrower
        response = await move(actor, listing, interaction, state)
        assert response.status_code == 200, response.text
        interaction = response.json()

    issued = await issue(owner, listing, interaction)
    assert issued.status_code == 409
    assert issued.json()["code"] == "confirmation_code_not_accepted"
    confirmed = await confirm(borrower, listing, interaction, "123456")
    assert confirmed.status_code == 409
    assert confirmed.json()["code"] == "confirmation_code_not_accepted"


async def test_completed_interaction_has_no_repeated_effects(
    owner: Account, borrower: Account
) -> None:
    listing, interaction = await accepted(owner, borrower)
    interaction_id = UUID(interaction["id"])
    code = (await issue(owner, listing, interaction)).json()["code"]
    assert (await confirm(borrower, listing, interaction, code)).status_code == 200
    before = await counts(owner, interaction_id)

    issued_again = await issue(owner, listing, interaction)
    assert issued_again.status_code == 409
    assert issued_again.json()["code"] == "confirmation_code_already_completed"

    repeated = await confirm(borrower, listing, interaction, "000000")
    assert repeated.status_code == 200
    assert repeated.json()["status"] == "completed"
    assert await counts(owner, interaction_id) == before


async def test_cancelled_interaction_rejects_an_issued_code(
    owner: Account, borrower: Account
) -> None:
    listing, interaction = await accepted(owner, borrower)
    interaction_id = UUID(interaction["id"])
    code = (await issue(owner, listing, interaction)).json()["code"]
    cancelled = await move(borrower, listing, interaction, "cancelled")
    assert cancelled.status_code == 200, cancelled.text

    response = await confirm(borrower, listing, interaction, code)
    assert response.status_code == 409
    assert response.json()["code"] == "confirmation_code_not_accepted"
    db = owner.auth.db
    await db.rollback()
    row = await db.get(Interaction, interaction_id)
    assert row is not None
    assert row.status == "cancelled"
    _events, _outbox, completed = await counts(owner, interaction_id)
    assert completed == 0


async def test_stage_and_kind_are_guarded(owner: Account, borrower: Account) -> None:
    listing, interaction = await accepted(owner, borrower)
    db = owner.auth.db
    await db.execute(
        update(Interaction)
        .where(Interaction.id == UUID(interaction["id"]))
        .values(stage="collecting")
    )
    await db.commit()

    staged = await issue(owner, listing, interaction)
    assert staged.status_code == 409
    assert staged.json()["code"] == "confirmation_code_stage_unavailable"
    staged_confirm = await confirm(borrower, listing, interaction, "123456")
    assert staged_confirm.status_code == 409
    assert staged_confirm.json()["code"] == "confirmation_code_stage_unavailable"

    await db.execute(
        update(Interaction)
        .where(Interaction.id == UUID(interaction["id"]))
        .values(stage=None)
    )
    await db.execute(
        update(Listing)
        .where(Listing.id == UUID(listing["id"]))
        .values(kind="publication")
    )
    await db.commit()

    unavailable = await issue(owner, listing, interaction)
    assert unavailable.status_code == 409
    assert unavailable.json()["code"] == "confirmation_code_unavailable"
    unavailable_confirm = await confirm(borrower, listing, interaction, "123456")
    assert unavailable_confirm.status_code == 409
    assert unavailable_confirm.json()["code"] == "confirmation_code_unavailable"


async def test_confirm_without_an_issued_code_is_invalid(
    owner: Account, borrower: Account
) -> None:
    listing, interaction = await accepted(owner, borrower)
    response = await confirm(borrower, listing, interaction, "123456")
    assert response.status_code == 422
    assert response.json()["code"] == "confirmation_code_invalid"
    assert await code_row(owner, UUID(interaction["id"])) is None


async def test_code_is_not_written_to_logs(
    owner: Account, borrower: Account, caplog: pytest.LogCaptureFixture
) -> None:
    caplog.set_level(logging.INFO)
    listing, interaction = await accepted(owner, borrower)
    code = (await issue(owner, listing, interaction)).json()["code"]
    confirmed = await confirm(borrower, listing, interaction, code)
    assert confirmed.status_code == 200, confirmed.text
    assert code not in caplog.text
    assert code not in confirmed.text


async def test_code_input_must_be_six_digits(owner: Account, borrower: Account) -> None:
    listing, interaction = await accepted(owner, borrower)
    for invalid in ("12345", "1234567", "abcdef", "12345a", " 123456"):
        response = await confirm(borrower, listing, interaction, invalid)
        assert response.status_code == 422
        assert response.json()["code"] == "validation_failed"


async def test_code_idempotency_replay_and_body_conflict(
    owner: Account, borrower: Account
) -> None:
    listing, interaction = await accepted(owner, borrower)
    issue_key = str(uuid4())
    first_issue = await issue(owner, listing, interaction, key=issue_key)
    assert first_issue.status_code == 200, first_issue.text
    replay_issue = await issue(owner, listing, interaction, key=issue_key)
    assert replay_issue.status_code == 200
    assert replay_issue.headers["Idempotent-Replayed"] == "true"
    assert replay_issue.json() == first_issue.json()

    code = first_issue.json()["code"]
    confirm_key = str(uuid4())
    first_confirm = await confirm(borrower, listing, interaction, code, key=confirm_key)
    assert first_confirm.status_code == 200, first_confirm.text
    before = await counts(owner, UUID(interaction["id"]))
    replay_confirm = await confirm(
        borrower, listing, interaction, code, key=confirm_key
    )
    assert replay_confirm.status_code == 200
    assert replay_confirm.headers["Idempotent-Replayed"] == "true"
    assert replay_confirm.json() == first_confirm.json()
    assert await counts(owner, UUID(interaction["id"])) == before

    conflict = await confirm(
        borrower, listing, interaction, other_code(code), key=confirm_key
    )
    assert conflict.status_code == 422
    assert conflict.json()["code"] == "idempotency_key_reused"


async def test_wrong_code_idempotency_replay_keeps_attempt_count(
    owner: Account, borrower: Account
) -> None:
    listing, interaction = await accepted(owner, borrower)
    interaction_id = UUID(interaction["id"])
    issued = (await issue(owner, listing, interaction)).json()
    wrong = other_code(issued["code"])
    key = str(uuid4())

    first = await confirm(borrower, listing, interaction, wrong, key=key)
    assert first.status_code == 422
    assert first.json()["code"] == "confirmation_code_invalid"
    assert "Idempotent-Replayed" not in first.headers
    row = await code_row(owner, interaction_id)
    assert row is not None
    assert row.attempts == 1

    replay = await confirm(borrower, listing, interaction, wrong, key=key)
    assert replay.status_code == 422
    assert replay.headers["Idempotent-Replayed"] == "true"
    assert replay.json() == first.json()
    row = await code_row(owner, interaction_id)
    assert row is not None
    assert row.attempts == 1

    conflict = await confirm(borrower, listing, interaction, other_code(wrong), key=key)
    assert conflict.status_code == 422
    assert conflict.json()["code"] == "idempotency_key_reused"
    row = await code_row(owner, interaction_id)
    assert row is not None
    assert row.attempts == 1

    completed = await confirm(borrower, listing, interaction, issued["code"])
    assert completed.status_code == 200, completed.text


async def test_exhausted_limit_replays_the_stored_429(
    owner: Account, borrower: Account
) -> None:
    listing, interaction = await accepted(owner, borrower)
    interaction_id = UUID(interaction["id"])
    issued = (await issue(owner, listing, interaction)).json()
    wrong = other_code(issued["code"])
    for _ in range(4):
        attempt = await confirm(borrower, listing, interaction, wrong)
        assert attempt.status_code == 422, attempt.text

    key = str(uuid4())
    fifth = await confirm(borrower, listing, interaction, wrong, key=key)
    assert fifth.status_code == 429
    assert fifth.json()["code"] == "confirmation_code_attempts_exceeded"
    assert "Idempotent-Replayed" not in fifth.headers
    row = await code_row(owner, interaction_id)
    assert row is not None
    assert row.attempts == 5

    replay = await confirm(borrower, listing, interaction, wrong, key=key)
    assert replay.status_code == 429
    assert replay.headers["Idempotent-Replayed"] == "true"
    assert replay.json() == fifth.json()
    row = await code_row(owner, interaction_id)
    assert row is not None
    assert row.attempts == 5

    conflict = await confirm(borrower, listing, interaction, other_code(wrong), key=key)
    assert conflict.status_code == 422
    assert conflict.json()["code"] == "idempotency_key_reused"

    correct = await confirm(borrower, listing, interaction, issued["code"])
    assert correct.status_code == 429
    reissue = await issue(owner, listing, interaction)
    assert reissue.status_code == 429


async def test_parallel_wrong_code_replays_count_once(
    owner: Account, borrower: Account
) -> None:
    listing, interaction = await accepted(owner, borrower)
    issued = (await issue(owner, listing, interaction)).json()
    wrong = other_code(issued["code"])
    key = str(uuid4())
    responses = await asyncio.gather(
        *(confirm(borrower, listing, interaction, wrong, key=key) for _ in range(6))
    )
    assert all(response.status_code == 422 for response in responses)
    assert all(response.json() == responses[0].json() for response in responses)
    assert sum("Idempotent-Replayed" in response.headers for response in responses) == 5
    row = await code_row(owner, UUID(interaction["id"]))
    assert row is not None
    assert row.attempts == 1


@pytest.mark.parametrize("correct", [True, False])
async def test_concurrent_confirmation_with_single_connection_pool(
    owner: Account, borrower: Account, correct: bool
) -> None:
    listing, interaction = await accepted(owner, borrower)
    issued = (await issue(owner, listing, interaction)).json()
    code = issued["code"] if correct else other_code(issued["code"])
    app = owner.auth.app
    original = app.state.session_factory
    settings = owner.auth.settings.model_copy(
        update={
            "database_pool_size": 1,
            "database_max_overflow": 0,
            "database_pool_timeout": 2,
        }
    )
    engine = create_engine(settings)
    app.state.session_factory = create_session_factory(engine)
    try:
        async with asyncio.timeout(10):
            responses = await asyncio.gather(
                *(confirm(borrower, listing, interaction, code) for _ in range(6))
            )
    finally:
        app.state.session_factory = original
        await engine.dispose()
    expected = [200] * 6 if correct else [422] * 4 + [429] * 2
    assert sorted(response.status_code for response in responses) == expected
    row = await code_row(owner, UUID(interaction["id"]))
    assert row is not None
    assert row.attempts == (0 if correct else 5)


async def test_confirm_uses_one_database_session(
    owner: Account, borrower: Account
) -> None:
    listing, interaction = await accepted(owner, borrower)
    code = (await issue(owner, listing, interaction)).json()["code"]
    app = owner.auth.app
    original = app.state.session_factory
    opened = 0
    peak = 0

    @asynccontextmanager
    async def counted() -> AsyncIterator[AsyncSession]:
        nonlocal opened, peak
        opened += 1
        peak = max(peak, opened)
        try:
            async with original() as session:
                yield session
        finally:
            opened -= 1

    app.state.session_factory = counted
    try:
        response = await confirm(borrower, listing, interaction, code)
    finally:
        app.state.session_factory = original
    assert response.status_code == 200, response.text
    assert peak == 1


async def test_failed_completion_rolls_back_consumption(
    owner: Account, borrower: Account, monkeypatch: pytest.MonkeyPatch
) -> None:
    listing, interaction = await accepted(owner, borrower)
    interaction_id = UUID(interaction["id"])
    code = (await issue(owner, listing, interaction)).json()["code"]
    before = await counts(owner, interaction_id)
    attempts = 0

    async def fail_once(*args: Any, **kwargs: Any) -> None:
        nonlocal attempts
        if attempts == 0:
            attempts += 1
            raise RuntimeError("transition failed")
        await real_transition(*args, **kwargs)

    monkeypatch.setattr("campus.modules.reputation.service.transition", fail_once)
    failed = await confirm(borrower, listing, interaction, code)
    assert failed.status_code == 500

    db = owner.auth.db
    await db.rollback()
    row = await db.get(Interaction, interaction_id)
    assert row is not None
    assert row.status == "accepted"
    code_state = await code_row(owner, interaction_id)
    assert code_state is not None
    assert code_state.consumed_at is None
    assert await counts(owner, interaction_id) == before

    success = await confirm(borrower, listing, interaction, code)
    assert success.status_code == 200, success.text


async def test_confirm_races_cancellation(owner: Account, borrower: Account) -> None:
    listing, interaction = await accepted(owner, borrower)
    interaction_id = UUID(interaction["id"])
    code = (await issue(owner, listing, interaction)).json()["code"]

    confirmed, cancelled = await asyncio.gather(
        confirm(borrower, listing, interaction, code),
        move(borrower, listing, interaction, "cancelled"),
    )
    assert sorted((confirmed.status_code, cancelled.status_code)) == [200, 409]
    current = await code_row(owner, interaction_id)
    assert current is not None
    completed = current.consumed_at is not None
    if completed:
        assert confirmed.status_code == 200
        assert cancelled.status_code == 409
    else:
        assert confirmed.status_code == 409
        assert cancelled.status_code == 200
    _events, _, completed_events = await counts(owner, interaction_id)
    assert completed_events == (1 if completed else 0)
