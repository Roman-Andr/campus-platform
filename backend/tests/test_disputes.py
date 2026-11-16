"""Disputes and moderator decisions on PostgreSQL with controlled time.

The tests cover the opening window counted from the disputed event, the
one-case-per-event rule, the subject/action table, the role matrix, the
version races, the payment window, the audit own-case mark, the
transactional chronology/outbox/recalculation and the idempotency contract.
"""

import asyncio
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID, uuid4, uuid5

import httpx2
import pytest
import time_machine
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncEngine

from campus.core import clock
from campus.core.audit import AuditRecord
from campus.core.db import create_session_factory
from campus.core.outbox import OutboxMessage, process_outbox
from campus.modules.identity import Role, RoleAssignment
from campus.modules.listings import (
    Interaction,
    InteractionStatus,
    Listing,
    ListingEvent,
    ListingStatus,
    PaymentClaim,
    PaymentClaimStatus,
)
from campus.modules.moderation import (
    Dispute,
    DisputeAction,
    DisputeKind,
    DisputeStatus,
)
from campus.modules.notifications import Notification
from campus.modules.reputation import (
    NoShowMark,
    NoShowStatus,
    ProfileAggregate,
    refresh_aggregates,
)
from tests.test_event_attendance import event_at, signup
from tests.test_identity import Auth
from tests.test_listing_purchase import (
    join,
    publish_purchase,
)
from tests.test_listings import (
    auth,
    borrower,
    owner,
    places,
    request,
    staff,
)
from tests.test_loan import hand_over, loan, not_returned
from tests.test_no_show import dispute_event, mark, scheduled, vote
from tests.test_photos import at
from tests.test_profile import Account, Places, moscow_profile
from tests.test_qr import user_id

__all__ = ["auth", "borrower", "owner", "places", "staff"]

API = "/api/v1"
DISPUTES = f"{API}/disputes"
ADMIN = f"{API}/admin/disputes"


@pytest.fixture(autouse=True)
def long_lived_access(auth: Auth) -> None:
    """Keep access tokens valid while tests move time by days."""
    auth.settings = auth.settings.model_copy(
        update={"access_token_ttl": timedelta(days=365)}
    )
    auth.app.state.settings = auth.settings


def instant(value: datetime) -> str:
    return value.astimezone(UTC).isoformat().replace("+00:00", "Z")


def parse_instant(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


async def api_request(
    account: Account,
    method: str,
    path: str,
    data: dict[str, Any] | None = None,
    key: str | None = None,
) -> httpx2.Response:
    return await account.auth.client.request(
        method,
        path,
        json=data,
        headers={"Idempotency-Key": key or str(uuid4()), **account.headers},
    )


async def open_case(  # noqa: PLR0913, PLR0917 - a request builder
    account: Account,
    kind: DisputeKind,
    listing: dict[str, Any],
    interaction: dict[str, Any],
    reason: str = "Please check this",
    key: str | None = None,
) -> httpx2.Response:
    return await api_request(
        account,
        "POST",
        DISPUTES,
        {
            "kind": kind.value,
            "listing_id": listing["id"],
            "interaction_id": interaction["id"],
            "reason": reason,
        },
        key=key,
    )


async def decide(  # noqa: PLR0913, PLR0917 - a request builder
    account: Account,
    dispute_id: str,
    action: DisputeAction,
    reason: str = "The evidence is sufficient",
    version: int = 1,
    key: str | None = None,
) -> httpx2.Response:
    return await api_request(
        account,
        "POST",
        f"{ADMIN}/{dispute_id}/decision",
        {"version": version, "action": action.value, "reason": reason},
        key=key,
    )


async def grant(account: Account, role: Role, places: Places | None = None) -> None:
    db = account.auth.db
    await db.rollback()
    scope: dict[str, Any] = {}
    if role == Role.HEADMAN:
        assert places is not None
        scope["dormitory_id"] = places.dubki
    db.add(RoleAssignment(user_id=user_id(account), role=role, **scope))
    await db.commit()


@pytest.fixture
async def moderator(auth: Auth, places: Places) -> Account:
    account = Account(auth, await auth.login(email="moderator@staff.example"))
    assert (await account.put(moscow_profile(places, course=None))).status_code == 200
    await grant(account, Role.MODERATOR)
    return account


@pytest.fixture
async def administrator(auth: Auth, places: Places) -> Account:
    account = Account(auth, await auth.login(email="admin@staff.example"))
    assert (await account.put(moscow_profile(places, course=None))).status_code == 200
    await grant(account, Role.ADMINISTRATOR)
    return account


async def new_student(auth: Auth, places: Places, number: int) -> Account:
    account = Account(
        auth, await auth.login(email=f"dispute-{number}@university.example")
    )
    assert (await account.put(moscow_profile(places))).status_code == 200
    return account


async def db_row(account: Account, model: type[Any], object_id: UUID) -> Any:
    await account.auth.db.rollback()
    row = await account.auth.db.get(model, object_id)
    assert row is not None
    return row


async def db_disputes(account: Account, **filters: Any) -> list[Dispute]:
    await account.auth.db.rollback()
    query = select(Dispute).order_by(Dispute.opened_at, Dispute.id)
    for name, value in filters.items():
        query = query.where(getattr(Dispute, name) == value)
    return list(await account.auth.db.scalars(query))


async def outbox_topics(account: Account) -> list[str]:
    await account.auth.db.rollback()
    return list(
        await account.auth.db.scalars(
            select(OutboxMessage.topic).order_by(OutboxMessage.id)
        )
    )


async def run_outbox(account: Account) -> int:
    assert isinstance(account.auth.db.bind, AsyncEngine)
    return await process_outbox(
        create_session_factory(account.auth.db.bind), account.auth.settings
    )


async def drain_outbox(account: Account) -> None:
    for _ in range(20):
        if await run_outbox(account) == 0:
            return


async def counts(account: Account) -> tuple[int, int, int]:
    await account.auth.db.rollback()
    disputes = await account.auth.db.scalar(select(func.count()).select_from(Dispute))
    audit = await account.auth.db.scalar(select(func.count()).select_from(AuditRecord))
    outbox = await account.auth.db.scalar(
        select(func.count()).select_from(OutboxMessage)
    )
    return int(disputes or 0), int(audit or 0), int(outbox or 0)


async def test_opening_window_counts_from_the_event_not_the_interaction(
    owner: Account, borrower: Account, moderator: Account
) -> None:
    now = clock.now()
    meeting_at = now + timedelta(hours=2)
    with time_machine.travel(now, tick=False):
        listing, interaction = await scheduled(owner, borrower, meeting_at)
    # The interaction is ten days old when the mark is created, so the
    # seven-day window must count from the mark and not from the start.
    with time_machine.travel(meeting_at + timedelta(days=2), tick=False):
        assert (
            await mark(owner, listing, interaction, "did not come")
        ).status_code == 200
        mark_now = clock.now()
        opened = await open_case(
            borrower, DisputeKind.NO_SHOW, listing, interaction, "I was there"
        )
    assert opened.status_code == 201, opened.text
    body = opened.json()
    assert body["kind"] == "no_show"
    assert body["status"] == "open"
    assert body["opened_by_id"] == str(user_id(borrower))
    assert body["event_at"] == instant(mark_now)
    assert body["statement"] == "I was there"
    assert body["participant_id"] == str(user_id(borrower))
    assert body["author_id"] == str(user_id(owner))
    assert [mark["status"] for mark in body["marks"]] == ["disputed"]

    repeat = await open_case(
        borrower, DisputeKind.NO_SHOW, listing, interaction, "again"
    )
    assert repeat.status_code == 200, repeat.text
    assert repeat.json()["id"] == body["id"]
    assert len(await db_disputes(owner, interaction_id=UUID(interaction["id"]))) == 1

    # The decision is one-shot: a terminal repeat is a conflict.
    resolved = await decide(moderator, body["id"], DisputeAction.KEEP)
    assert resolved.status_code == 200, resolved.text
    assert resolved.json()["status"] == "resolved"
    repeated = await decide(
        moderator, body["id"], DisputeAction.LIFT_NO_SHOW, version=2
    )
    assert repeated.status_code == 409
    assert repeated.json()["code"] == "dispute_resolved"


async def test_window_closes_and_requires_a_basis(
    owner: Account, borrower: Account, places: Places, auth: Auth
) -> None:
    now = clock.now()
    meeting_at = now + timedelta(hours=2)
    with time_machine.travel(now, tick=False):
        listing, interaction = await scheduled(owner, borrower, meeting_at)
    with time_machine.travel(meeting_at + timedelta(days=2), tick=False):
        assert (
            await mark(owner, listing, interaction, "did not come")
        ).status_code == 200
        # The author has no mark against them, so there is nothing to dispute.
        no_basis = await open_case(
            owner, DisputeKind.NO_SHOW, listing, interaction, "unfair"
        )
        assert no_basis.status_code == 409
        assert no_basis.json()["code"] == "dispute_unavailable"
        # A third person is not a participant at all.
        outsider = await new_student(auth, places, 51)
        forbidden = await open_case(
            outsider, DisputeKind.NO_SHOW, listing, interaction, "unfair"
        )
        assert forbidden.status_code == 403
        assert forbidden.json()["code"] == "dispute_forbidden"
        # The kind must match the mark: a personal no-show is not a loan.
        wrong_kind = await open_case(
            borrower, DisputeKind.NOT_RETURNED, listing, interaction, "unfair"
        )
        assert wrong_kind.status_code == 422
        assert wrong_kind.json()["code"] == "dispute_kind_invalid"
        payment_kind = await open_case(
            borrower, DisputeKind.PAYMENT, listing, interaction, "unfair"
        )
        assert payment_kind.status_code == 422
        assert payment_kind.json()["code"] == "dispute_kind_invalid"
        blank = await open_case(
            borrower, DisputeKind.NO_SHOW, listing, interaction, "   "
        )
        assert blank.status_code == 422
        assert blank.json()["code"] == "dispute_reason_invalid"
        long_reason = await open_case(
            borrower, DisputeKind.NO_SHOW, listing, interaction, "x" * 1001
        )
        assert long_reason.status_code == 422
        assert long_reason.json()["code"] == "dispute_reason_invalid"

    with time_machine.travel(meeting_at + timedelta(days=10), tick=False):
        late = await open_case(
            borrower, DisputeKind.NO_SHOW, listing, interaction, "too late"
        )
    assert late.status_code == 409
    assert late.json()["code"] == "dispute_closed"


@pytest.mark.parametrize(
    ("action", "interaction_status", "mark_status"),
    [
        (DisputeAction.KEEP, InteractionStatus.NO_SHOW, NoShowStatus.COUNTED),
        (
            DisputeAction.LIFT_NO_SHOW,
            InteractionStatus.NO_SHOW,
            NoShowStatus.REMOVED,
        ),
        (
            DisputeAction.COMPLETE,
            InteractionStatus.COMPLETED,
            NoShowStatus.REMOVED,
        ),
    ],
)
async def test_decision_table_of_no_show_outcomes(  # noqa: PLR0913, PLR0917 - case parts
    owner: Account,
    borrower: Account,
    moderator: Account,
    action: DisputeAction,
    interaction_status: InteractionStatus,
    mark_status: NoShowStatus,
) -> None:
    now = clock.now()
    meeting_at = now + timedelta(hours=2)
    with time_machine.travel(now, tick=False):
        listing, interaction = await scheduled(owner, borrower, meeting_at)
    with time_machine.travel(meeting_at + timedelta(days=2), tick=False):
        assert (
            await mark(owner, listing, interaction, "did not come")
        ).status_code == 200
        opened = await open_case(
            borrower, DisputeKind.NO_SHOW, listing, interaction, "I was there"
        )
    dispute = opened.json()
    decided = await decide(moderator, dispute["id"], action)
    assert decided.status_code == 200, decided.text
    assert decided.json()["action"] == action.value
    assert decided.json()["resolution"] == "The evidence is sufficient"

    row = await db_row(owner, Interaction, UUID(interaction["id"]))
    assert row.status == interaction_status.value
    await owner.auth.db.rollback()
    mark_row = await owner.auth.db.scalar(
        select(NoShowMark).where(NoShowMark.interaction_id == UUID(interaction["id"]))
    )
    assert mark_row is not None
    assert mark_row.status == mark_status.value
    await owner.auth.db.rollback()
    actions = list(
        await owner.auth.db.scalars(
            select(ListingEvent.action)
            .where(ListingEvent.interaction_id == UUID(interaction["id"]))
            .order_by(ListingEvent.created_at, ListingEvent.id)
        )
    )
    assert "dispute_opened" in actions
    assert "dispute_resolved" in actions


async def test_own_case_is_marked_in_the_audit(
    owner: Account, borrower: Account
) -> None:
    await grant(owner, Role.MODERATOR)
    now = clock.now()
    meeting_at = now + timedelta(hours=2)
    with time_machine.travel(now, tick=False):
        listing, interaction = await scheduled(owner, borrower, meeting_at)
    with time_machine.travel(meeting_at + timedelta(days=2), tick=False):
        assert (
            await mark(owner, listing, interaction, "did not come")
        ).status_code == 200
        opened = await open_case(
            borrower, DisputeKind.NO_SHOW, listing, interaction, "I was there"
        )
    decided = await decide(owner, opened.json()["id"], DisputeAction.LIFT_NO_SHOW)
    assert decided.status_code == 200, decided.text

    await owner.auth.db.rollback()
    record = await owner.auth.db.scalar(
        select(AuditRecord).where(
            AuditRecord.action == "moderation.dispute.resolve",
            AuditRecord.object_id == UUID(opened.json()["id"]),
        )
    )
    assert record is not None
    assert record.own_case is True
    assert record.actor_id == user_id(owner)
    assert set(record.participant_ids) == {user_id(owner), user_id(borrower)}


async def test_role_matrix_of_the_decision(  # noqa: PLR0913, PLR0917 - role cases
    owner: Account,
    borrower: Account,
    moderator: Account,
    staff: Account,
    administrator: Account,
    places: Places,
) -> None:
    now = clock.now()
    meeting_at = now + timedelta(hours=2)
    with time_machine.travel(now, tick=False):
        listing, interaction = await scheduled(owner, borrower, meeting_at)
        second_listing, second = await scheduled(
            owner, borrower, meeting_at + timedelta(hours=1)
        )
    with time_machine.travel(meeting_at + timedelta(days=2), tick=False):
        assert (
            await mark(owner, listing, interaction, "did not come")
        ).status_code == 200
        assert (
            await mark(owner, second_listing, second, "did not come")
        ).status_code == 200
        opened = await open_case(
            borrower, DisputeKind.NO_SHOW, listing, interaction, "I was there"
        )
        second_case = await open_case(
            borrower, DisputeKind.NO_SHOW, second_listing, second, "I was there"
        )
    dispute_id = opened.json()["id"]

    for account in (borrower, owner):
        answer = await decide(account, dispute_id, DisputeAction.KEEP)
        assert answer.status_code == 403
        assert answer.json()["code"] == "forbidden"
    await grant(staff, Role.HEADMAN, places)
    headman = await decide(staff, dispute_id, DisputeAction.KEEP)
    assert headman.status_code == 403
    assert (await decide(moderator, dispute_id, DisputeAction.KEEP)).status_code == 200
    # The administrator may decide another case.
    assert (
        await decide(administrator, second_case.json()["id"], DisputeAction.KEEP)
    ).status_code == 200


async def test_parallel_decisions_with_one_version_do_not_overwrite(
    owner: Account, borrower: Account, moderator: Account
) -> None:
    now = clock.now()
    meeting_at = now + timedelta(hours=2)
    with time_machine.travel(now, tick=False):
        listing, interaction = await scheduled(owner, borrower, meeting_at)
    with time_machine.travel(meeting_at + timedelta(days=2), tick=False):
        assert (
            await mark(owner, listing, interaction, "did not come")
        ).status_code == 200
        opened = await open_case(
            borrower, DisputeKind.NO_SHOW, listing, interaction, "I was there"
        )
    dispute_id = opened.json()["id"]
    responses = await asyncio.gather(
        decide(moderator, dispute_id, DisputeAction.KEEP),
        decide(moderator, dispute_id, DisputeAction.LIFT_NO_SHOW),
    )
    assert sorted(response.status_code for response in responses) == [200, 409]
    refused = next(response for response in responses if response.status_code == 409)
    assert refused.json()["code"] == "dispute_version_conflict"
    await owner.auth.db.rollback()
    rows = await db_disputes(owner, id=UUID(dispute_id))
    assert rows[0].status == DisputeStatus.RESOLVED.value
    assert rows[0].version == 2


async def test_stale_version_and_invalid_action_leave_no_partial_state(
    owner: Account, borrower: Account, moderator: Account
) -> None:
    now = clock.now()
    meeting_at = now + timedelta(hours=2)
    with time_machine.travel(now, tick=False):
        listing, interaction = await scheduled(owner, borrower, meeting_at)
    with time_machine.travel(meeting_at + timedelta(days=2), tick=False):
        assert (
            await mark(owner, listing, interaction, "did not come")
        ).status_code == 200
        opened = await open_case(
            borrower, DisputeKind.NO_SHOW, listing, interaction, "I was there"
        )
    dispute_id = opened.json()["id"]
    before = await counts(owner)
    stale = await decide(moderator, dispute_id, DisputeAction.KEEP, version=5)
    assert stale.status_code == 409
    assert stale.json()["code"] == "dispute_version_conflict"
    assert stale.headers["content-type"].startswith("application/problem+json")
    invalid = await decide(moderator, dispute_id, DisputeAction.CONFIRM_PAYMENT)
    assert invalid.status_code == 422
    assert invalid.json()["code"] == "dispute_action_invalid"
    assert await counts(owner) == before
    row = await db_row(owner, Dispute, UUID(dispute_id))
    assert row.status == DisputeStatus.OPEN.value
    assert row.version == 1


async def test_idempotent_decision_replay_stores_one_result(
    owner: Account, borrower: Account, moderator: Account
) -> None:
    now = clock.now()
    meeting_at = now + timedelta(hours=2)
    with time_machine.travel(now, tick=False):
        listing, interaction = await scheduled(owner, borrower, meeting_at)
    with time_machine.travel(meeting_at + timedelta(days=2), tick=False):
        assert (
            await mark(owner, listing, interaction, "did not come")
        ).status_code == 200
        opened = await open_case(
            borrower, DisputeKind.NO_SHOW, listing, interaction, "I was there"
        )
    dispute_id = opened.json()["id"]
    key = str(uuid4())
    first = await decide(moderator, dispute_id, DisputeAction.KEEP, key=key)
    assert first.status_code == 200
    replay = await decide(moderator, dispute_id, DisputeAction.KEEP, key=key)
    assert replay.status_code == 200
    assert replay.json() == first.json()
    await owner.auth.db.rollback()
    audit = await owner.auth.db.scalar(select(func.count()).select_from(AuditRecord))
    assert audit == 1
    different = await api_request(
        moderator,
        "POST",
        f"{ADMIN}/{dispute_id}/decision",
        {"version": 1, "action": "lift_no_show", "reason": "Different body"},
        key=key,
    )
    assert different.status_code == 422
    assert different.json()["code"] == "idempotency_key_reused"


async def test_queue_and_participant_views(
    owner: Account, borrower: Account, moderator: Account, places: Places, auth: Auth
) -> None:
    now = clock.now()
    meeting_at = now + timedelta(hours=2)
    with time_machine.travel(now, tick=False):
        listing, interaction = await scheduled(owner, borrower, meeting_at)
    with time_machine.travel(meeting_at + timedelta(days=2), tick=False):
        assert (
            await mark(owner, listing, interaction, "did not come")
        ).status_code == 200
        opened = await open_case(
            borrower, DisputeKind.NO_SHOW, listing, interaction, "I was there"
        )
    dispute_id = opened.json()["id"]

    queue = await api_request(moderator, "GET", ADMIN)
    assert queue.status_code == 200, queue.text
    items = queue.json()["items"]
    assert [item["id"] for item in items] == [dispute_id]
    assert items[0]["overdue"] is False
    assert items[0]["author_id"] == str(user_id(owner))
    assert items[0]["participant_id"] == str(user_id(borrower))
    with time_machine.travel(meeting_at + timedelta(days=2, hours=25), tick=False):
        overdue = await api_request(moderator, "GET", ADMIN)
    assert overdue.json()["items"][0]["overdue"] is True
    filtered = await api_request(moderator, "GET", f"{ADMIN}?status=resolved")
    assert filtered.json()["items"] == []
    detail = await api_request(moderator, "GET", f"{ADMIN}/{dispute_id}")
    assert detail.status_code == 200, detail.text
    assert [event["action"] for event in detail.json()["history"]][-1] == (
        "dispute_opened"
    )

    outsider = await new_student(auth, places, 52)
    assert (await api_request(outsider, "GET", DISPUTES)).json()["items"] == []
    outsider_detail = await api_request(outsider, "GET", f"{DISPUTES}/{dispute_id}")
    assert outsider_detail.status_code == 403
    mine = await api_request(borrower, "GET", DISPUTES)
    assert [item["id"] for item in mine.json()["items"]] == [dispute_id]
    own_detail = await api_request(borrower, "GET", f"{DISPUTES}/{dispute_id}")
    assert "dispute_opened" in [
        event["action"] for event in own_detail.json()["history"]
    ]


async def test_decision_reason_is_required_and_bounded(
    owner: Account, borrower: Account, moderator: Account
) -> None:
    now = clock.now()
    meeting_at = now + timedelta(hours=2)
    with time_machine.travel(now, tick=False):
        listing, interaction = await scheduled(owner, borrower, meeting_at)
    with time_machine.travel(meeting_at + timedelta(days=2), tick=False):
        assert (
            await mark(owner, listing, interaction, "did not come")
        ).status_code == 200
        opened = await open_case(
            borrower, DisputeKind.NO_SHOW, listing, interaction, "I was there"
        )
    dispute_id = opened.json()["id"]
    before = await counts(owner)
    for reason in ("   ", "x" * 1001):
        refused = await decide(moderator, dispute_id, DisputeAction.KEEP, reason=reason)
        assert refused.status_code == 422
        assert refused.json()["code"] == "dispute_reason_invalid"
        assert refused.headers["content-type"].startswith("application/problem+json")
    assert await counts(owner) == before
    accepted = await decide(
        moderator, dispute_id, DisputeAction.KEEP, reason="  Enough evidence  "
    )
    assert accepted.status_code == 200, accepted.text
    assert accepted.json()["resolution"] == "Enough evidence"


async def test_mutual_no_show_marks_open_one_case(
    owner: Account, borrower: Account
) -> None:
    now = clock.now()
    meeting_at = now + timedelta(hours=2)
    with time_machine.travel(now, tick=False):
        listing, interaction = await scheduled(owner, borrower, meeting_at)
    with time_machine.travel(meeting_at + timedelta(hours=24), tick=False):
        first = await mark(owner, listing, interaction, "Did not come")
        assert first.status_code == 200, first.text
    with time_machine.travel(meeting_at + timedelta(hours=30), tick=False):
        second = await mark(borrower, listing, interaction, "The author did not come")
        assert second.status_code == 200, second.text
        dispute_id = second.json()["dispute"]["id"]
        repeat = await open_case(
            owner, DisputeKind.NO_SHOW, listing, interaction, "I was there"
        )
        assert repeat.status_code == 200, repeat.text
        assert repeat.json()["id"] == dispute_id
        assert {mark["status"] for mark in repeat.json()["marks"]} == {"disputed"}
    assert len(await db_disputes(owner, interaction_id=UUID(interaction["id"]))) == 1


async def test_payment_dispute_closes_after_seven_days(
    owner: Account, borrower: Account
) -> None:
    deadline = clock.now() + timedelta(hours=2)
    listing = await publish_purchase(
        owner, min_units=1, collection_deadline=instant(deadline)
    )
    assert (await join(borrower, listing, 1)).status_code == 201
    with at(deadline + timedelta(seconds=1)):
        assert await _deadlines(owner) == 1
        claim = await api_request(
            borrower,
            "POST",
            f"{API}/listings/{listing['id']}/shares/me/payment/claims",
        )
        assert claim.status_code == 201
    with at(deadline + timedelta(days=8)):
        late = await open_case(
            borrower,
            DisputeKind.PAYMENT,
            listing,
            {"id": claim.json()["interaction_id"]},
            "Too late",
        )
    assert late.status_code == 409
    assert late.json()["code"] == "dispute_closed"


async def test_event_no_show_decision(
    owner: Account,
    borrower: Account,
    moderator: Account,
    auth: Auth,
    places: Places,
) -> None:
    extra = await new_student(auth, places, 53)
    now = clock.now()
    starts_at = now + timedelta(hours=2)
    ends_at = now + timedelta(hours=4)
    with time_machine.travel(now, tick=False):
        listing = await event_at(owner, starts_at, ends_at)
        await signup(borrower, listing)
        await signup(extra, listing)
    with time_machine.travel(ends_at + timedelta(hours=1), tick=False):
        assert (await vote(borrower, listing)).status_code == 200
        opened = await dispute_event(owner, listing)
        assert opened.status_code == 200, opened.text
        dispute_id = opened.json()["dispute"]["id"]
        decided = await decide(moderator, dispute_id, DisputeAction.LIFT_NO_SHOW)
        assert decided.status_code == 200, decided.text
        assert [mark["status"] for mark in decided.json()["marks"]] == ["removed"]


async def test_payment_read_endpoints_and_answers(  # noqa: PLR0915 - one flow
    owner: Account, borrower: Account
) -> None:
    deadline = clock.now() + timedelta(hours=2)
    listing = await publish_purchase(
        owner, min_units=1, collection_deadline=instant(deadline)
    )
    assert (await join(borrower, listing, 1)).status_code == 201
    with at(deadline + timedelta(seconds=1)):
        assert await _deadlines(owner) == 1
        share = await api_request(
            borrower, "GET", f"{API}/listings/{listing['id']}/shares/me"
        )
        interaction_id = share.json()["id"]
        own = await api_request(
            borrower, "GET", f"{API}/listings/{listing['id']}/shares/me/payment"
        )
        assert own.status_code == 200, own.text
        assert own.json()["status"] is None
        assert own.json()["claim"] is None
        assert own.json()["can_claim"] is True
        author_view = await api_request(
            owner,
            "GET",
            f"{API}/listings/{listing['id']}/shares/{interaction_id}/payment",
        )
        assert author_view.status_code == 200, author_view.text
        assert author_view.json()["claim"] is None
        participant_view = await api_request(
            borrower,
            "GET",
            f"{API}/listings/{listing['id']}/shares/{interaction_id}/payment",
        )
        assert participant_view.status_code == 403
        missing = await api_request(
            owner,
            "GET",
            f"{API}/listings/{listing['id']}/shares/{uuid4()}/payment",
        )
        assert missing.status_code == 404

        claim = await api_request(
            borrower,
            "POST",
            f"{API}/listings/{listing['id']}/shares/me/payment/claims",
        )
        assert claim.status_code == 201, claim.text
        claim_id = claim.json()["claim"]["id"]
        repeated = await api_request(
            borrower,
            "POST",
            f"{API}/listings/{listing['id']}/shares/me/payment/claims",
        )
        assert repeated.status_code == 201
        assert repeated.json()["claim"]["id"] == claim_id
        answered = await api_request(
            owner,
            "POST",
            f"{API}/listings/{listing['id']}/shares/{interaction_id}/payment/decision",
            {"approve": True, "version": 9},
        )
        assert answered.status_code == 409
        assert answered.json()["code"] == "purchase_payment_version_conflict"
        assert answered.json()["current_version"] == 1

        await owner.auth.db.rollback()
        row = await owner.auth.db.get(Listing, UUID(listing["id"]))
        assert row is not None
        original_status = row.status
        row.status = ListingStatus.CANCELLED.value
        await owner.auth.db.commit()
        cancelled = await api_request(
            owner,
            "POST",
            f"{API}/listings/{listing['id']}/shares/{interaction_id}/payment/decision",
            {"approve": True, "version": 1},
        )
        assert cancelled.status_code == 409
        assert cancelled.json()["code"] == "purchase_payment_cancelled"
        await owner.auth.db.rollback()
        row = await owner.auth.db.get(Listing, UUID(listing["id"]))
        assert row is not None
        row.status = original_status
        await owner.auth.db.commit()

        rejected = await api_request(
            owner,
            "POST",
            f"{API}/listings/{listing['id']}/shares/{interaction_id}/payment/decision",
            {"approve": False, "version": 1},
        )
        assert rejected.status_code == 200, rejected.text
        assert rejected.json()["status"] == "rejected"
        refused = await api_request(
            owner,
            "POST",
            f"{API}/listings/{listing['id']}/shares/{interaction_id}/payment/decision",
            {"approve": True, "version": 2},
        )
        assert refused.status_code == 409
        assert refused.json()["code"] == "purchase_payment_unavailable"

        second = await api_request(
            borrower,
            "POST",
            f"{API}/listings/{listing['id']}/shares/me/payment/claims",
        )
        assert second.status_code == 201, second.text
        confirmed = await api_request(
            owner,
            "POST",
            f"{API}/listings/{listing['id']}/shares/{interaction_id}/payment/decision",
            {"approve": True, "version": 1},
        )
        assert confirmed.status_code == 200, confirmed.text
        assert confirmed.json()["status"] == "confirmed"
        already = await api_request(
            borrower,
            "POST",
            f"{API}/listings/{listing['id']}/shares/me/payment/claims",
        )
        assert already.status_code == 409
        assert already.json()["code"] == "purchase_payment_confirmed"
        terminal = await api_request(
            owner,
            "POST",
            f"{API}/listings/{listing['id']}/shares/{interaction_id}/payment/decision",
            {"approve": True, "version": 2},
        )
        assert terminal.status_code == 409
        assert terminal.json()["code"] == "purchase_payment_confirmed"

    # A non-purchase listing has no payment marks at all.
    now = clock.now()
    with time_machine.travel(now, tick=False):
        giveaway, interaction = await scheduled(
            owner, borrower, now + timedelta(hours=2)
        )
    for method, path, body in (
        ("GET", f"{API}/listings/{giveaway['id']}/shares/me/payment", None),
        ("POST", f"{API}/listings/{giveaway['id']}/shares/me/payment/claims", None),
        (
            "POST",
            f"{API}/listings/{giveaway['id']}/shares/{interaction['id']}/payment/decision",
            {"approve": True, "version": 1},
        ),
    ):
        answer = await api_request(owner, method, path, body)
        assert answer.status_code == 404


async def test_payment_dispute_window_and_decision(
    owner: Account, borrower: Account, moderator: Account
) -> None:
    deadline = clock.now() + timedelta(hours=2)
    listing = await publish_purchase(
        owner,
        min_units=1,
        max_units=10,
        collection_deadline=instant(deadline),
    )
    assert (await join(borrower, listing, 2)).status_code == 201
    with at(deadline + timedelta(seconds=1)):
        assert await _deadlines(owner) == 1
        # There is no payment mark yet, so there is nothing to dispute.
        no_claim = await open_case(
            borrower,
            DisputeKind.PAYMENT,
            listing,
            {
                "id": (
                    await api_request(
                        borrower,
                        "GET",
                        f"{API}/listings/{listing['id']}/shares/me",
                    )
                ).json()["id"]
            },
            "I have not paid yet",
        )
        assert no_claim.status_code == 409
        assert no_claim.json()["code"] == "dispute_unavailable"
        claim = await api_request(
            borrower, "POST", f"{API}/listings/{listing['id']}/shares/me/payment/claims"
        )
        assert claim.status_code == 201, claim.text
        assert claim.json()["status"] == "claimed"
        assert claim.json()["can_dispute"] is False
        early = await open_case(
            borrower,
            DisputeKind.PAYMENT,
            listing,
            {"id": claim.json()["interaction_id"]},
            "The organiser does not answer",
        )
        assert early.status_code == 409
        assert early.json()["code"] == "dispute_too_early"
        assert parse_instant(early.json()["available_at"]) == clock.now() + (
            timedelta(hours=24)
        )

    with at(deadline + timedelta(hours=24, minutes=1)):
        opened = await open_case(
            borrower,
            DisputeKind.PAYMENT,
            listing,
            {"id": claim.json()["interaction_id"]},
            "The organiser does not answer",
        )
        assert opened.status_code == 201, opened.text
        body = opened.json()
        assert body["kind"] == "payment"
        assert body["payment"]["id"] == claim.json()["claim"]["id"]
        assert body["payment"]["status"] == "disputed"
        wrong = await decide(moderator, body["id"], DisputeAction.KEEP)
        assert wrong.status_code == 422
        assert wrong.json()["code"] == "dispute_action_invalid"
        decided = await decide(moderator, body["id"], DisputeAction.CONFIRM_PAYMENT)
        assert decided.status_code == 200, decided.text
        assert decided.json()["payment"]["status"] == "confirmed"

    await owner.auth.db.rollback()
    stored = await owner.auth.db.get(PaymentClaim, UUID(claim.json()["claim"]["id"]))
    assert stored is not None
    assert stored.status == PaymentClaimStatus.CONFIRMED.value


async def _deadlines(account: Account) -> int:
    from tests.test_listing_purchase import deadlines  # noqa: PLC0415

    return await deadlines(account)


async def test_payment_mark_belongs_to_the_two_sides(
    owner: Account, borrower: Account
) -> None:
    deadline = clock.now() + timedelta(hours=2)
    listing = await publish_purchase(
        owner, min_units=1, collection_deadline=instant(deadline)
    )
    assert (await join(borrower, listing, 1)).status_code == 201
    with at(deadline + timedelta(seconds=1)):
        assert await _deadlines(owner) == 1
        refused = await api_request(
            owner, "POST", f"{API}/listings/{listing['id']}/shares/me/payment/claims"
        )
        assert refused.status_code == 404
        share = await api_request(
            borrower, "GET", f"{API}/listings/{listing['id']}/shares/me"
        )
        interaction = share.json()
        claim = await api_request(
            borrower, "POST", f"{API}/listings/{listing['id']}/shares/me/payment/claims"
        )
        assert claim.status_code == 201, claim.text
        version = claim.json()["claim"]["version"]
        # Only the organiser answers the mark.
        participant_answer = await api_request(
            borrower,
            "POST",
            f"{API}/listings/{listing['id']}/shares/{interaction['id']}/payment/decision",
            {"approve": True, "version": version},
        )
        assert participant_answer.status_code == 403
        confirmed = await api_request(
            owner,
            "POST",
            f"{API}/listings/{listing['id']}/shares/{interaction['id']}/payment/decision",
            {"approve": True, "version": version},
        )
        assert confirmed.status_code == 200, confirmed.text
        assert confirmed.json()["status"] == "confirmed"
        repeated = await api_request(
            owner,
            "POST",
            f"{API}/listings/{listing['id']}/shares/{interaction['id']}/payment/decision",
            {"approve": True, "version": version},
        )
        assert repeated.status_code == 409


async def test_payment_obligation_survives_a_refused_response(
    owner: Account, borrower: Account, moderator: Account
) -> None:
    deadline = clock.now() + timedelta(hours=2)
    listing = await publish_purchase(
        owner, min_units=1, collection_deadline=instant(deadline)
    )
    assert (await join(borrower, listing, 1)).status_code == 201
    with at(deadline + timedelta(seconds=1)):
        assert await _deadlines(owner) == 1
        claim = await api_request(
            borrower,
            "POST",
            f"{API}/listings/{listing['id']}/shares/me/payment/claims",
        )
        assert claim.status_code == 201
    with at(deadline + timedelta(hours=24, minutes=1)):
        opened = await open_case(
            borrower,
            DisputeKind.PAYMENT,
            listing,
            {"id": claim.json()["interaction_id"]},
            "The organiser does not answer",
        )
        assert opened.status_code == 201, opened.text
        # The organiser cannot settle a disputed mark behind the moderator.
        refused = await api_request(
            owner,
            "POST",
            f"{API}/listings/{listing['id']}/shares/"
            f"{claim.json()['interaction_id']}/payment/decision",
            {"approve": False, "version": 1},
        )
        assert refused.status_code == 409
        assert refused.json()["code"] == "purchase_payment_disputed"
        # Moderation hides the listing while the case is open; the payment
        # mark is still an obligation and the decision resolves it.
        await owner.auth.db.rollback()
        row = await owner.auth.db.get(Listing, UUID(listing["id"]))
        assert row is not None
        row.status = ListingStatus.HIDDEN.value
        await owner.auth.db.commit()
        decided = await decide(
            moderator, opened.json()["id"], DisputeAction.CONFIRM_PAYMENT
        )
        assert decided.status_code == 200, decided.text
        assert decided.json()["payment"]["status"] == "confirmed"
    await owner.auth.db.rollback()
    claim_row = await owner.auth.db.get(PaymentClaim, UUID(claim.json()["claim"]["id"]))
    assert claim_row is not None
    assert claim_row.status == PaymentClaimStatus.CONFIRMED.value
    listing_row = await owner.auth.db.get(Listing, UUID(listing["id"]))
    assert listing_row is not None
    assert listing_row.status == ListingStatus.HIDDEN.value


async def test_transactional_chronology_outbox_and_recalculation(
    owner: Account, borrower: Account, moderator: Account
) -> None:
    now = clock.now()
    meeting_at = now + timedelta(hours=2)
    with time_machine.travel(now, tick=False):
        listing, interaction = await scheduled(owner, borrower, meeting_at)
    with time_machine.travel(meeting_at + timedelta(days=2), tick=False):
        assert (
            await mark(owner, listing, interaction, "did not come")
        ).status_code == 200
        opened = await open_case(
            borrower, DisputeKind.NO_SHOW, listing, interaction, "I was there"
        )
        dispute_id = opened.json()["id"]
        await drain_outbox(owner)
        await owner.auth.db.rollback()
        aggregate = await owner.auth.db.scalar(
            select(ProfileAggregate).where(
                ProfileAggregate.user_id == user_id(borrower)
            )
        )
        assert aggregate is not None
        assert aggregate.no_shows == 0  # the mark is suspended by the case

        decided = await decide(moderator, dispute_id, DisputeAction.KEEP)
        assert decided.status_code == 200, decided.text
        topics = await outbox_topics(owner)
        assert topics.count("moderation.dispute") == 2
        assert "reputation.profile_aggregate" in topics
        assert "notifications.send" in topics
        await drain_outbox(owner)
        await owner.auth.db.rollback()
        aggregate = await owner.auth.db.scalar(
            select(ProfileAggregate).where(
                ProfileAggregate.user_id == user_id(borrower)
            )
        )
        assert aggregate is not None
        assert aggregate.no_shows == 1
        event_id = uuid5(UUID(dispute_id), "decision-2")
        await owner.auth.db.rollback()
        notifications = list(
            await owner.auth.db.scalars(
                select(Notification).where(Notification.event_id == event_id)
            )
        )
        assert {item.recipient_id for item in notifications} == {
            user_id(owner),
            user_id(borrower),
        }
        # A repeated aggregate refresh is absolute, not additive.
        await refresh_aggregates(
            owner.auth.db, {user_id(borrower)}, owner.auth.settings
        )
        await owner.auth.db.commit()
        await owner.auth.db.rollback()
        aggregate = await owner.auth.db.scalar(
            select(ProfileAggregate).where(
                ProfileAggregate.user_id == user_id(borrower)
            )
        )
        assert aggregate is not None
        assert aggregate.no_shows == 1
        # Replaying the notification outbox message adds no second inbox row.
        original = await owner.auth.db.scalar(
            select(OutboxMessage).where(OutboxMessage.topic == "notifications.send")
        )
        assert original is not None
        owner.auth.db.add(
            OutboxMessage(
                topic="notifications.send",
                payload=original.payload,
                available_at=clock.now(),
            )
        )
        await owner.auth.db.commit()
        await drain_outbox(owner)
        await owner.auth.db.rollback()
        replay = list(
            await owner.auth.db.scalars(
                select(Notification).where(Notification.event_id == event_id)
            )
        )
        assert len(replay) == len(notifications)


async def test_loan_not_returned_dispute_completes_the_loan(
    owner: Account, borrower: Account, moderator: Account
) -> None:
    now = clock.now()
    with time_machine.travel(now, tick=False):
        listing, interaction = await loan(owner, borrower, loan_days=3)
        assert (
            await hand_over(owner, borrower, listing, interaction)
        ).status_code == 200
    with time_machine.travel(now + timedelta(days=6), tick=False):
        assert (await not_returned(owner, listing, interaction)).status_code == 200
        opened = await open_case(
            borrower,
            DisputeKind.NOT_RETURNED,
            listing,
            interaction,
            "I returned it",
        )
        assert opened.status_code == 201, opened.text
        assert opened.json()["kind"] == "not_returned"
        assert opened.json()["marks"][0]["status"] == "disputed"
        # The author cancels the listing while the case is open; the issued
        # item is still an obligation, so the case and the deadline survive.
        cancelled = await request(
            owner,
            "POST",
            f"/{listing['id']}/cancel",
            {"reason": "The item is written off"},
        )
        assert cancelled.status_code == 200, cancelled.text
        decided = await decide(moderator, opened.json()["id"], DisputeAction.COMPLETE)
        assert decided.status_code == 200, decided.text
    await owner.auth.db.rollback()
    row = await owner.auth.db.get(Interaction, UUID(interaction["id"]))
    assert row is not None
    assert row.status == InteractionStatus.COMPLETED.value
    assert row.completion_method == "moderator"
    assert row.return_due_at is None
    stored = await owner.auth.db.get(Listing, UUID(listing["id"]))
    assert stored is not None
    assert stored.status == ListingStatus.CANCELLED.value
