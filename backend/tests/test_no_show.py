"""No-shows and "did not take place" on PostgreSQL with controlled time.

The tests cover the personal mark window and its reason, the 7-day automatic
rule and its catch-up after downtime, the mutual allegation dispute, the
late QR undo, event attendance rules, event votes and their threshold, the
role matrix and the idempotency contract.
"""

import asyncio
from datetime import UTC, datetime, timedelta
from typing import Any, NamedTuple
from uuid import UUID, uuid4

import httpx2
import pytest
import time_machine
from sqlalchemy import delete, func, select, update
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker

from campus.core import clock
from campus.core.db import create_session_factory
from campus.core.deadlines import Deadline, process_due_deadlines
from campus.core.outbox import OutboxMessage, process_outbox
from campus.modules.identity import Role, RoleAssignment
from campus.modules.listings import (
    Interaction,
    InteractionStatus,
    Listing,
    ListingEvent,
)
from campus.modules.moderation import Dispute, DisputeStatus
from campus.modules.reputation import (
    PERSONAL_NO_SHOW_TOPIC,
    NoShowMark,
    NoShowStatus,
)
from tests.test_event_attendance import check_in, event_at, issue_qr, signup
from tests.test_identity import Auth
from tests.test_listings import (
    auth,
    borrower,
    owner,
    places,
    request,
    staff,
)
from tests.test_listings_meeting import accept as accept_meeting
from tests.test_listings_meeting import propose
from tests.test_offline_qr import offline_body, offline_scan
from tests.test_profile import Account, Places, moscow_profile
from tests.test_qr import Signer, accepted, register_key, scan, user_id

__all__ = ["auth", "borrower", "owner", "places", "staff"]

ROOT = "/api/v1/listings"
NO_SHOW_TOPIC = "reputation.no_show"
EVENT_TOPIC = "reputation.event_no_show"


@pytest.fixture(autouse=True)
def long_lived_access(auth: Auth) -> None:
    """Keep access tokens valid while tests move time by days."""
    auth.settings = auth.settings.model_copy(
        update={"access_token_ttl": timedelta(days=365)}
    )
    auth.app.state.settings = auth.settings


@pytest.fixture
async def sessions(engine: AsyncEngine) -> async_sessionmaker[AsyncSession]:
    return create_session_factory(engine)


def instant(at: datetime) -> str:
    return at.astimezone(UTC).isoformat().replace("+00:00", "Z")


def path(listing: dict[str, Any], interaction: dict[str, Any]) -> str:
    return f"/{listing['id']}/interactions/{interaction['id']}/no-show"


async def scheduled(
    author: Account, participant: Account, at: datetime
) -> tuple[dict[str, Any], dict[str, Any]]:
    """An accepted giveaway with an agreed meeting at ``at``."""
    listing, interaction = await accepted(author, participant)
    proposal = (await propose(author, listing, interaction, at)).json()
    response = await accept_meeting(
        participant, listing, interaction, proposal["version"]
    )
    assert response.status_code == 200, response.text
    return listing, interaction


async def mark(
    account: Account,
    listing: dict[str, Any],
    interaction: dict[str, Any],
    reason: str,
    key: str | None = None,
) -> httpx2.Response:
    return await request(
        account, "POST", path(listing, interaction), {"reason": reason}, key=key
    )


async def state(
    account: Account, listing: dict[str, Any], interaction: dict[str, Any]
) -> httpx2.Response:
    return await request(account, "GET", path(listing, interaction))


async def vote(
    account: Account, listing: dict[str, Any], key: str | None = None
) -> httpx2.Response:
    return await request(
        account, "POST", f"/{listing['id']}/event/no-show/votes", None, key=key
    )


async def event_state(account: Account, listing: dict[str, Any]) -> httpx2.Response:
    return await request(account, "GET", f"/{listing['id']}/event/no-show")


async def dispute_event(
    account: Account, listing: dict[str, Any], key: str | None = None
) -> httpx2.Response:
    return await request(
        account, "POST", f"/{listing['id']}/event/no-show/dispute", None, key=key
    )


async def run_deadlines(account: Account) -> int:
    assert isinstance(account.auth.db.bind, AsyncEngine)
    return await process_due_deadlines(
        create_session_factory(account.auth.db.bind), account.auth.settings
    )


async def reload_interaction(account: Account, interaction_id: UUID) -> Interaction:
    await account.auth.db.rollback()
    row = await account.auth.db.get(Interaction, interaction_id)
    assert row is not None
    await account.auth.db.refresh(row)
    return row


class MarkRow(NamedTuple):
    id: UUID
    kind: str
    status: str
    subject_id: UUID
    reporter_id: UUID | None
    interaction_id: UUID | None
    removed_at: datetime | None


class DisputeRow(NamedTuple):
    status: str


class JournalRow(NamedTuple):
    action: str
    actor_id: UUID | None
    reason: str | None
    previous_status: str | None
    status: str


def mark_row(mark: NoShowMark) -> MarkRow:
    return MarkRow(
        id=mark.id,
        kind=mark.kind,
        status=mark.status,
        subject_id=mark.subject_id,
        reporter_id=mark.reporter_id,
        interaction_id=mark.interaction_id,
        removed_at=mark.removed_at,
    )


async def interaction_marks(account: Account, interaction_id: UUID) -> list[MarkRow]:
    await account.auth.db.rollback()
    rows = await account.auth.db.scalars(
        select(NoShowMark)
        .where(NoShowMark.interaction_id == interaction_id)
        .order_by(NoShowMark.created_at, NoShowMark.id)
    )
    return [mark_row(mark) for mark in rows]


async def listing_marks(account: Account, listing_id: UUID) -> list[MarkRow]:
    await account.auth.db.rollback()
    rows = await account.auth.db.scalars(
        select(NoShowMark)
        .where(NoShowMark.listing_id == listing_id)
        .order_by(NoShowMark.created_at, NoShowMark.id)
    )
    return [mark_row(mark) for mark in rows]


async def dispute_rows(account: Account, interaction_id: UUID) -> list[DisputeRow]:
    await account.auth.db.rollback()
    rows = await account.auth.db.scalars(
        select(Dispute).where(Dispute.interaction_id == interaction_id)
    )
    return [DisputeRow(status=row.status) for row in rows]


async def journal(account: Account, interaction_id: UUID) -> list[JournalRow]:
    await account.auth.db.rollback()
    rows = await account.auth.db.scalars(
        select(ListingEvent)
        .where(ListingEvent.interaction_id == interaction_id)
        .order_by(ListingEvent.created_at, ListingEvent.id)
    )
    return [
        JournalRow(
            action=row.action,
            actor_id=row.actor_id,
            reason=row.reason,
            previous_status=row.previous_status,
            status=row.status,
        )
        for row in rows
    ]


async def new_student(auth: Auth, places: Places, number: int) -> Account:
    account = Account(
        auth, await auth.login(email=f"no-show-{number}@university.example")
    )
    assert (await account.put(moscow_profile(places))).status_code == 200
    return account


async def test_mark_window_reason_and_result(owner: Account, borrower: Account) -> None:
    now = clock.now()
    meeting_at = now + timedelta(hours=2)
    with time_machine.travel(now, tick=False):
        listing, interaction = await scheduled(owner, borrower, meeting_at)
    interaction_id = UUID(interaction["id"])

    with time_machine.travel(
        meeting_at + timedelta(hours=24) - timedelta(seconds=1), tick=False
    ):
        early = await mark(owner, listing, interaction, "Did not come")
        assert early.status_code == 409, early.text
        assert early.json()["code"] == "no_show_too_early"
        before = (await state(owner, listing, interaction)).json()
        assert before["can_mark"] is False
        assert before["basis"] == "unmarked"
        assert before["mark_from"] == instant(meeting_at + timedelta(hours=24))

    with time_machine.travel(meeting_at + timedelta(hours=24), tick=False):
        empty = await mark(owner, listing, interaction, "   ")
        assert empty.status_code == 422, empty.text
        assert empty.json()["code"] == "no_show_reason_invalid"
        long_reason = await mark(owner, listing, interaction, "x" * 501)
        assert long_reason.status_code == 422, long_reason.text

        marked = await mark(owner, listing, interaction, "Did not come")
        assert marked.status_code == 200, marked.text
        body = marked.json()
        assert body["status"] == "no_show"
        assert body["basis"] == "marked"
        assert body["can_mark"] is False
        assert [item["status"] for item in body["marks"]] == ["counted"]
        assert body["marks"][0]["reason"] == "Did not come"
        assert body["marks"][0]["reporter_id"] == str(user_id(owner))
        assert body["marks"][0]["subject_id"] == str(user_id(borrower))

        repeat = await mark(owner, listing, interaction, "Did not come")
        assert repeat.status_code == 200, repeat.text
        assert len(repeat.json()["marks"]) == 1

    row = await reload_interaction(owner, interaction_id)
    assert row.status == InteractionStatus.NO_SHOW
    assert row.completion_method is None
    marks = await interaction_marks(owner, interaction_id)
    assert len(marks) == 1
    events = await journal(owner, interaction_id)
    assert [event.action for event in events][-1] == "no_show_marked"
    assert events[-1].actor_id == user_id(owner)
    assert events[-1].previous_status == "accepted"
    assert events[-1].status == "no_show"
    assert events[-1].reason == "Did not come"


async def test_only_a_participant_marks_even_with_admin_rights(
    owner: Account, borrower: Account, staff: Account
) -> None:
    now = clock.now()
    meeting_at = now + timedelta(hours=2)
    with time_machine.travel(now, tick=False):
        listing, interaction = await scheduled(owner, borrower, meeting_at)
        await staff.auth.db.rollback()
        staff.auth.db.add(
            RoleAssignment(user_id=user_id(staff), role=Role.ADMINISTRATOR)
        )
        await staff.auth.db.commit()

    with time_machine.travel(meeting_at + timedelta(hours=25), tick=False):
        denied = await mark(staff, listing, interaction, "Not my meeting")
        assert denied.status_code == 403, denied.text
        assert denied.json()["code"] == "no_show_forbidden"
        assert (await state(staff, listing, interaction)).status_code == 403
        accepted_mark = await mark(owner, listing, interaction, "Did not come")
        assert accepted_mark.status_code == 200


async def test_seven_day_rule_closes_without_no_show_and_catches_up(
    owner: Account, borrower: Account
) -> None:
    now = clock.now()
    meeting_at = now + timedelta(hours=2)
    with time_machine.travel(now, tick=False):
        listing, interaction = await scheduled(owner, borrower, meeting_at)
    interaction_id = UUID(interaction["id"])

    # The window closes exactly at the seventh day: a mark is no longer
    # accepted, but the automatic rule has not run yet.
    with time_machine.travel(meeting_at + timedelta(days=7), tick=False):
        closed = await mark(owner, listing, interaction, "Did not come")
        assert closed.status_code == 409, closed.text
        assert closed.json()["code"] == "no_show_closed"
    # The scheduler is down for more than a week: the deadline is simply due
    # on the first run after the start.
    with time_machine.travel(meeting_at + timedelta(days=10), tick=False):
        assert await run_deadlines(owner) >= 1
        # A redelivered timer finds nothing due and changes nothing.
        assert await run_deadlines(owner) == 0
        read = (await state(borrower, listing, interaction)).json()
        assert read["status"] == "no_show"
        assert read["basis"] == "automatic"
        assert read["marks"] == []
        assert read["can_mark"] is False

    row = await reload_interaction(owner, interaction_id)
    assert row.status == InteractionStatus.NO_SHOW
    assert await interaction_marks(owner, interaction_id) == []
    events = await journal(owner, interaction_id)
    assert events[-1].action == "no_show_automatic"
    assert events[-1].actor_id is None


async def test_an_issued_loan_is_not_closed_by_the_seven_day_rule(
    owner: Account, borrower: Account
) -> None:
    """#214: after the handover the loan's own rules decide, not the 7 days.

    Before the handover a loan is a meeting like any other and the flat rule
    still applies; the stage marks the item as handed over.
    """
    now = clock.now()
    meeting_at = now + timedelta(hours=2)
    with time_machine.travel(now, tick=False):
        listing, interaction = await scheduled(owner, borrower, meeting_at)
        await owner.auth.db.rollback()
        await owner.auth.db.execute(
            update(Listing).where(Listing.id == UUID(listing["id"])).values(kind="loan")
        )
        await owner.auth.db.execute(
            update(Interaction)
            .where(Interaction.id == UUID(interaction["id"]))
            .values(stage="issued", return_due_at=meeting_at + timedelta(days=7))
        )
        await owner.auth.db.commit()

    with time_machine.travel(meeting_at + timedelta(days=10), tick=False):
        await run_deadlines(owner)

    row = await reload_interaction(owner, UUID(interaction["id"]))
    assert row.status == InteractionStatus.ACCEPTED
    assert await interaction_marks(owner, row.id) == []


async def test_mutual_allegations_open_one_dispute_and_suspend_marks(
    owner: Account, borrower: Account
) -> None:
    now = clock.now()
    meeting_at = now + timedelta(hours=2)
    with time_machine.travel(now, tick=False):
        listing, interaction = await scheduled(owner, borrower, meeting_at)
    interaction_id = UUID(interaction["id"])

    with time_machine.travel(meeting_at + timedelta(hours=24), tick=False):
        first = await mark(owner, listing, interaction, "Did not come")
        assert first.status_code == 200, first.text
    with time_machine.travel(meeting_at + timedelta(hours=30), tick=False):
        second = await mark(borrower, listing, interaction, "The author did not come")
        assert second.status_code == 200, second.text
        body = second.json()
        assert body["basis"] == "mutual_dispute"
        assert body["dispute"]["status"] == "open"
        assert {item["status"] for item in body["marks"]} == {"disputed"}
        assert body["can_mark"] is False
        assert body["marks"][0]["subject_id"] in {
            str(user_id(owner)),
            str(user_id(borrower)),
        }
        repeat = await mark(owner, listing, interaction, "Did not come")
        assert repeat.status_code == 200, repeat.text
        assert len(repeat.json()["marks"]) == 2

    marks = await interaction_marks(owner, interaction_id)
    assert len(marks) == 2
    assert {mark.status for mark in marks} == {NoShowStatus.DISPUTED.value}
    disputes = await dispute_rows(owner, interaction_id)
    assert len(disputes) == 1
    assert disputes[0].status == DisputeStatus.OPEN.value
    row = await reload_interaction(owner, interaction_id)
    assert row.status == InteractionStatus.NO_SHOW
    events = await journal(owner, interaction_id)
    assert events[-1].action == "no_show_disputed"
    assert events[-1].actor_id == user_id(borrower)


async def test_parallel_mutual_allegations_leave_one_dispute(
    owner: Account, borrower: Account
) -> None:
    now = clock.now()
    meeting_at = now + timedelta(hours=2)
    with time_machine.travel(now, tick=False):
        listing, interaction = await scheduled(owner, borrower, meeting_at)
    interaction_id = UUID(interaction["id"])

    with time_machine.travel(meeting_at + timedelta(hours=24), tick=False):
        first, second = await asyncio.gather(
            mark(owner, listing, interaction, "Did not come"),
            mark(borrower, listing, interaction, "The author did not come"),
        )
    assert {first.status_code, second.status_code} == {200}
    marks = await interaction_marks(owner, interaction_id)
    assert len(marks) == 2
    assert {mark.status for mark in marks} == {NoShowStatus.DISPUTED.value}
    assert len(await dispute_rows(owner, interaction_id)) == 1
    counted = [mark for mark in marks if mark.status == NoShowStatus.COUNTED.value]
    assert counted == []
    actions = [event.action for event in await journal(owner, interaction_id)]
    assert actions.count("no_show_marked") == 1
    assert actions.count("no_show_disputed") == 1


async def test_late_qr_formed_before_the_mark_completes_and_lifts_it(
    owner: Account, borrower: Account
) -> None:
    now = clock.now()
    meeting_at = now + timedelta(hours=2)
    signer = Signer.generate()
    with time_machine.travel(now, tick=False):
        listing, interaction = await scheduled(owner, borrower, meeting_at)
        assert (await register_key(owner, signer)).status_code == 200
    interaction_id = UUID(interaction["id"])
    body = offline_body(
        signer,
        listing["id"],
        interaction["id"],
        user_id(owner),
        issued_at=meeting_at + timedelta(hours=23),
    )

    with time_machine.travel(meeting_at + timedelta(hours=24, minutes=10), tick=False):
        marked = await mark(owner, listing, interaction, "Did not come")
        assert marked.status_code == 200, marked.text
        assert marked.json()["basis"] == "marked"
        scanned = await offline_scan(borrower, listing, interaction, body)
        assert scanned.status_code == 200, scanned.text
        result = scanned.json()
        assert result["status"] == "completed"
        assert result["completed"] is True
        assert result["mode"] == "offline"
        assert result["replayed"] is False

    row = await reload_interaction(owner, interaction_id)
    assert row.status == InteractionStatus.COMPLETED
    assert row.completion_method == "qr"
    marks = await interaction_marks(owner, interaction_id)
    assert len(marks) == 1
    assert marks[0].status == NoShowStatus.REMOVED.value
    assert marks[0].removed_at is not None
    events = await journal(owner, interaction_id)
    assert events[-1].action == "qr_completed_after_no_show"
    state_after = await state(owner, listing, interaction)
    assert state_after.json()["basis"] == "completed"
    refused = await mark(borrower, listing, interaction, "The author did not come")
    assert refused.status_code == 409, refused.text
    assert refused.json()["code"] == "no_show_state_conflict"


async def test_qr_formed_after_the_mark_has_no_effect(
    owner: Account, borrower: Account
) -> None:
    now = clock.now()
    meeting_at = now + timedelta(hours=2)
    signer = Signer.generate()
    with time_machine.travel(now, tick=False):
        listing, interaction = await scheduled(owner, borrower, meeting_at)
        assert (await register_key(owner, signer)).status_code == 200
    interaction_id = UUID(interaction["id"])
    with time_machine.travel(meeting_at + timedelta(hours=24, minutes=5), tick=False):
        assert (
            await mark(owner, listing, interaction, "Did not come")
        ).status_code == 200
    body = offline_body(
        signer,
        listing["id"],
        interaction["id"],
        user_id(owner),
        issued_at=meeting_at + timedelta(hours=24, minutes=11),
    )
    with time_machine.travel(meeting_at + timedelta(hours=24, minutes=12), tick=False):
        refused = await offline_scan(borrower, listing, interaction, body)
        assert refused.status_code == 409, refused.text
        assert refused.json()["code"] == "qr_after_no_show"

    row = await reload_interaction(owner, interaction_id)
    assert row.status == InteractionStatus.NO_SHOW
    marks = await interaction_marks(owner, interaction_id)
    assert [mark.status for mark in marks] == [NoShowStatus.COUNTED.value]


async def test_parallel_timer_and_late_qr_leave_one_outcome(
    owner: Account, borrower: Account
) -> None:
    now = clock.now()
    meeting_at = now + timedelta(hours=2)
    signer = Signer.generate()
    with time_machine.travel(now, tick=False):
        listing, interaction = await scheduled(owner, borrower, meeting_at)
        assert (await register_key(owner, signer)).status_code == 200
    interaction_id = UUID(interaction["id"])
    body = offline_body(
        signer,
        listing["id"],
        interaction["id"],
        user_id(owner),
        issued_at=meeting_at + timedelta(days=6, hours=23),
    )

    with time_machine.travel(meeting_at + timedelta(days=7, minutes=5), tick=False):
        attempted, scanned = await asyncio.gather(
            run_deadlines(owner),
            offline_scan(borrower, listing, interaction, body),
        )
    assert attempted >= 1
    assert scanned.status_code == 200, scanned.text
    row = await reload_interaction(owner, interaction_id)
    assert row.status == InteractionStatus.COMPLETED
    events = await journal(owner, interaction_id)
    completed = [
        event
        for event in events
        if event.action in {"qr_completed", "qr_completed_after_no_show"}
    ]
    assert len(completed) == 1
    assert await interaction_marks(owner, interaction_id) == []


async def test_idempotency_key_returns_the_stored_result(
    owner: Account, borrower: Account
) -> None:
    now = clock.now()
    meeting_at = now + timedelta(hours=2)
    with time_machine.travel(now, tick=False):
        listing, interaction = await scheduled(owner, borrower, meeting_at)
    with time_machine.travel(meeting_at + timedelta(hours=24), tick=False):
        key = str(uuid4())
        first = await mark(owner, listing, interaction, "Did not come", key=key)
        second = await mark(owner, listing, interaction, "Did not come", key=key)
        assert first.status_code == 200, first.text
        assert second.status_code == 200, second.text
        assert first.json() == second.json()
        conflict = await mark(owner, listing, interaction, "Another reason", key=key)
        assert conflict.status_code == 422, conflict.text
        assert conflict.json()["code"] == "idempotency_key_reused"
        assert conflict.headers["content-type"].startswith("application/problem+json")
        missing = await owner.auth.client.post(
            f"{ROOT}{path(listing, interaction)}",
            json={"reason": "No header"},
            headers=owner.headers,
        )
        assert missing.status_code == 400, missing.text
        assert missing.json()["code"] == "idempotency_key_missing"
    assert len(await interaction_marks(owner, UUID(interaction["id"]))) == 1


async def test_marks_endpoint_requires_an_accepted_or_answered_interaction(
    owner: Account, borrower: Account
) -> None:
    listing, interaction = await accepted(owner, borrower)
    pending_state = (await state(owner, listing, interaction)).json()
    assert pending_state["basis"] == "unmarked"
    assert pending_state["can_mark"] is False
    assert (await mark(owner, listing, interaction, "Not yet")).status_code == 409
    cancelled = await request(
        borrower,
        "POST",
        f"/{listing['id']}/interactions/{interaction['id']}/transition",
        {"status": "cancelled"},
    )
    assert cancelled.status_code == 200, cancelled.text
    assert (await mark(owner, listing, interaction, "Did not come")).status_code == 409


async def test_realtime_wakeup_carries_metadata_only(
    owner: Account,
    borrower: Account,
    sessions: async_sessionmaker[AsyncSession],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    now = clock.now()
    meeting_at = now + timedelta(hours=2)
    with time_machine.travel(now, tick=False):
        listing, interaction = await scheduled(owner, borrower, meeting_at)
    published: list[tuple[UUID, dict[str, Any]]] = []

    async def fake(recipient: UUID, data: dict[str, Any], _delivery_id: UUID) -> None:
        published.append((recipient, data))

    with time_machine.travel(meeting_at + timedelta(hours=25), tick=False):
        assert (
            await mark(owner, listing, interaction, "Private reason")
        ).status_code == 200
        await owner.auth.db.rollback()
        await owner.auth.db.execute(
            delete(OutboxMessage).where(OutboxMessage.topic != NO_SHOW_TOPIC)
        )
        await owner.auth.db.commit()
        stored = list(
            await owner.auth.db.scalars(
                select(OutboxMessage).where(OutboxMessage.topic == NO_SHOW_TOPIC)
            )
        )
        assert len(stored) == 1
        payload = stored[0].payload
        assert "reason" not in payload
        assert payload["status"] == "marked"
        assert payload["listing_id"] == listing["id"]

        monkeypatch.setattr("campus.modules.realtime.publish_personal", fake)
        assert await process_outbox(sessions, owner.auth.settings) == 1
    assert {recipient for recipient, _ in published} == {
        user_id(owner),
        user_id(borrower),
    }
    assert all("reason" not in data for _, data in published)


async def test_unmarked_event_participant_gets_a_no_show(
    owner: Account, borrower: Account, auth: Auth, places: Places
) -> None:
    extra = await new_student(auth, places, 1)
    now = clock.now()
    starts_at = now + timedelta(hours=2)
    ends_at = now + timedelta(hours=4)
    with time_machine.travel(now, tick=False):
        listing = await event_at(owner, starts_at, ends_at)
        await signup(borrower, listing)
        await signup(extra, listing)
    listing_id = UUID(listing["id"])
    with time_machine.travel(starts_at, tick=False):
        code = (await issue_qr(owner, listing)).json()["code"]
        assert (await check_in(borrower, listing, code)).status_code == 200

    with time_machine.travel(ends_at + timedelta(hours=24, minutes=1), tick=False):
        assert await run_deadlines(owner) >= 1
        read = (await event_state(borrower, listing)).json()
        assert read["registered"] == 2
        assert read["threshold"] == 1
        assert read["not_held"] is False
        assert read["participant_marks"][0]["subject_id"] == str(user_id(extra))
        assert read["can_vote"] is True

    marks = await listing_marks(owner, listing_id)
    assert len(marks) == 1
    assert marks[0].kind == "event_auto"
    assert marks[0].status == NoShowStatus.COUNTED.value
    assert marks[0].subject_id == user_id(extra)
    assert marks[0].reporter_id is None
    assert marks[0].interaction_id is not None


async def test_event_without_any_organiser_mark_charges_nobody(
    owner: Account, borrower: Account, auth: Auth, places: Places
) -> None:
    extra = await new_student(auth, places, 2)
    now = clock.now()
    starts_at = now + timedelta(hours=2)
    ends_at = now + timedelta(hours=4)
    with time_machine.travel(now, tick=False):
        listing = await event_at(owner, starts_at, ends_at)
        await signup(borrower, listing)
        await signup(extra, listing)
    listing_id = UUID(listing["id"])

    with time_machine.travel(ends_at + timedelta(hours=24, minutes=1), tick=False):
        assert await run_deadlines(owner) >= 1

    await owner.auth.db.rollback()
    statuses = set(
        await owner.auth.db.scalars(
            select(Interaction.status).where(Interaction.listing_id == listing_id)
        )
    )
    assert statuses == {InteractionStatus.NO_SHOW.value}
    assert await listing_marks(owner, listing_id) == []
    read = (await event_state(borrower, listing)).json()
    assert read["participant_marks"] == []
    assert read["not_held"] is False


async def test_threshold_is_a_third_of_registrations_rounded_up(
    owner: Account, borrower: Account, auth: Auth, places: Places
) -> None:
    extras = [await new_student(auth, places, number) for number in (3, 4, 5)]
    now = clock.now()
    starts_at = now + timedelta(hours=2)
    ends_at = now + timedelta(hours=4)
    with time_machine.travel(now, tick=False):
        listing = await event_at(owner, starts_at, ends_at)
        await signup(borrower, listing)
        for extra in extras:
            await signup(extra, listing)
    listing_id = UUID(listing["id"])

    with time_machine.travel(ends_at + timedelta(hours=1), tick=False):
        first = await vote(borrower, listing)
        assert first.status_code == 200, first.text
        body = first.json()
        assert body["registered"] == 4
        assert body["threshold"] == 2
        assert body["votes"] == 1
        assert body["not_held"] is False
        assert body["organizer_mark"] is None

        duplicate = await vote(borrower, listing)
        assert duplicate.status_code == 200, duplicate.text
        assert duplicate.json()["votes"] == 1

        second = await vote(extras[0], listing)
        assert second.status_code == 200, second.text
        charged = second.json()
        assert charged["votes"] == 2
        assert charged["not_held"] is True
        assert charged["organizer_mark"] is not None
        assert charged["organizer_mark"]["kind"] == "event_vote"
        assert charged["organizer_mark"]["status"] == "counted"
        assert charged["organizer_mark"]["subject_id"] == str(user_id(owner))

    marks = await listing_marks(owner, listing_id)
    assert len(marks) == 1
    events = await owner.auth.db.scalars(
        select(ListingEvent).where(ListingEvent.listing_id == listing_id)
    )
    assert any(event.action == "event_not_held" for event in events)


async def test_vote_lifts_automatic_participant_marks(
    owner: Account, borrower: Account, auth: Auth, places: Places
) -> None:
    extras = [await new_student(auth, places, number) for number in (6, 7)]
    now = clock.now()
    starts_at = now + timedelta(hours=2)
    ends_at = now + timedelta(hours=4)
    with time_machine.travel(now, tick=False):
        listing = await event_at(owner, starts_at, ends_at)
        await signup(borrower, listing)
        for extra in extras:
            await signup(extra, listing)
    listing_id = UUID(listing["id"])
    with time_machine.travel(starts_at, tick=False):
        code = (await issue_qr(owner, listing)).json()["code"]
        assert (await check_in(borrower, listing, code)).status_code == 200

    with time_machine.travel(ends_at + timedelta(hours=24, minutes=1), tick=False):
        assert await run_deadlines(owner) >= 1
        before = await listing_marks(owner, listing_id)
        assert len(before) == 2
        assert {mark.status for mark in before} == {NoShowStatus.COUNTED.value}
        charged = await vote(extras[0], listing)
        assert charged.status_code == 200, charged.text
        body = charged.json()
        assert body["not_held"] is True
        assert {mark["status"] for mark in body["participant_marks"]} == {"removed"}
        assert body["organizer_mark"] is not None

    marks = await listing_marks(owner, listing_id)
    by_kind = {mark.kind: mark for mark in marks}
    assert by_kind["event_vote"].status == NoShowStatus.COUNTED.value
    assert {mark.status for mark in marks if mark.kind == "event_auto"} == {
        NoShowStatus.REMOVED.value
    }
    # The lifted participants keep the "did not take place" status but are
    # no longer charged with a no-show.
    await owner.auth.db.rollback()
    statuses = set(
        await owner.auth.db.scalars(
            select(Interaction.status).where(Interaction.listing_id == listing_id)
        )
    )
    assert statuses == {
        InteractionStatus.ACCEPTED.value,
        InteractionStatus.NO_SHOW.value,
    }


async def test_vote_window_and_registration_rights(
    owner: Account, borrower: Account, staff: Account
) -> None:
    now = clock.now()
    starts_at = now + timedelta(hours=2)
    ends_at = now + timedelta(hours=4)
    with time_machine.travel(now, tick=False):
        listing = await event_at(owner, starts_at, ends_at)
        await signup(borrower, listing)
    with time_machine.travel(starts_at, tick=False):
        closed = await vote(borrower, listing)
        assert closed.status_code == 409, closed.text
        assert closed.json()["code"] == "event_no_show_vote_closed"
    with time_machine.travel(ends_at + timedelta(hours=1), tick=False):
        outsider = await vote(staff, listing)
        assert outsider.status_code == 403, outsider.text
        assert outsider.json()["code"] == "event_no_show_not_registered"
        denied = await event_state(staff, listing)
        assert denied.status_code == 403
        assert denied.json()["code"] == "event_no_show_forbidden"
        readable = await event_state(borrower, listing)
        assert readable.status_code == 200, readable.text
        assert readable.json()["registered"] == 1
        assert readable.json()["threshold"] == 1
    with time_machine.travel(
        ends_at + timedelta(days=7) + timedelta(seconds=1), tick=False
    ):
        late = await vote(borrower, listing)
        assert late.status_code == 409, late.text
        assert late.json()["code"] == "event_no_show_vote_closed"


async def test_removed_marks_mean_the_organizer_marked_nobody(
    owner: Account, borrower: Account, auth: Auth, places: Places
) -> None:
    """The attendance helper counts only active marks (#61 contract)."""
    extra = await new_student(auth, places, 8)
    now = clock.now()
    starts_at = now + timedelta(hours=2)
    ends_at = now + timedelta(hours=4)
    with time_machine.travel(now, tick=False):
        listing = await event_at(owner, starts_at, ends_at)
        await signup(borrower, listing)
        await signup(extra, listing)
    listing_id = UUID(listing["id"])
    with time_machine.travel(starts_at, tick=False):
        code = (await issue_qr(owner, listing)).json()["code"]
        assert (await check_in(borrower, listing, code)).status_code == 200
        assert (
            await request(
                owner,
                "DELETE",
                f"/{listing['id']}/event/attendance/{user_id(borrower)}",
            )
        ).status_code == 200

    with time_machine.travel(ends_at + timedelta(hours=24, minutes=1), tick=False):
        assert await run_deadlines(owner) >= 1

    # The only attendance mark was removed, so the helper reports an empty
    # set: the organiser marked nobody and nobody is charged (#61 contract).
    assert await listing_marks(owner, listing_id) == []
    await owner.auth.db.rollback()
    statuses = set(
        await owner.auth.db.scalars(
            select(Interaction.status).where(Interaction.listing_id == listing_id)
        )
    )
    assert statuses == {InteractionStatus.NO_SHOW.value}


async def test_event_timer_keeps_a_single_head(
    owner: Account, borrower: Account
) -> None:
    now = clock.now()
    starts_at = now + timedelta(hours=2)
    ends_at = now + timedelta(hours=4)
    with time_machine.travel(now, tick=False):
        listing = await event_at(owner, starts_at, ends_at)
        await signup(borrower, listing)

    await owner.auth.db.rollback()
    pending = list(
        await owner.auth.db.scalars(
            select(Deadline).where(Deadline.topic == EVENT_TOPIC)
        )
    )
    assert len(pending) == 1
    assert pending[0].available_at == ends_at + timedelta(hours=24)


async def test_vote_on_a_cancelled_event_is_refused(
    owner: Account, borrower: Account
) -> None:
    now = clock.now()
    starts_at = now + timedelta(hours=2)
    ends_at = now + timedelta(hours=4)
    with time_machine.travel(now, tick=False):
        listing = await event_at(owner, starts_at, ends_at)
        await signup(borrower, listing)
        cancelled = await request(
            owner, "POST", f"/{listing['id']}/cancel", {"reason": "No room"}
        )
        assert cancelled.status_code == 200, cancelled.text
    with time_machine.travel(ends_at + timedelta(hours=1), tick=False):
        refused = await vote(borrower, listing)
        assert refused.status_code == 409, refused.text
        assert refused.json()["code"] == "event_no_show_vote_closed"
    with time_machine.travel(ends_at + timedelta(hours=25), tick=False):
        await run_deadlines(owner)
    await owner.auth.db.rollback()
    count = await owner.auth.db.scalar(
        select(func.count())
        .select_from(NoShowMark)
        .where(NoShowMark.listing_id == UUID(listing["id"]))
    )
    assert count == 0


async def test_counter_mark_after_the_dispute_window_is_refused(
    owner: Account, borrower: Account
) -> None:
    now = clock.now()
    meeting_at = now + timedelta(hours=2)
    with time_machine.travel(now, tick=False):
        listing, interaction = await scheduled(owner, borrower, meeting_at)
    with time_machine.travel(meeting_at + timedelta(hours=24), tick=False):
        assert (
            await mark(owner, listing, interaction, "Did not come")
        ).status_code == 200
    with time_machine.travel(
        meeting_at + timedelta(hours=24) + timedelta(days=7, seconds=1), tick=False
    ):
        late = await mark(borrower, listing, interaction, "The author did not come")
        assert late.status_code == 409, late.text
        assert late.json()["code"] == "no_show_closed"
        read = (await state(borrower, listing, interaction)).json()
        assert [item["status"] for item in read["marks"]] == ["counted"]


async def test_event_declared_not_held_closes_without_participant_marks(
    owner: Account, borrower: Account, auth: Auth, places: Places
) -> None:
    extras = [await new_student(auth, places, number) for number in (9, 10)]
    now = clock.now()
    starts_at = now + timedelta(hours=2)
    ends_at = now + timedelta(hours=4)
    with time_machine.travel(now, tick=False):
        listing = await event_at(owner, starts_at, ends_at)
        await signup(borrower, listing)
        for extra in extras:
            await signup(extra, listing)
    listing_id = UUID(listing["id"])

    with time_machine.travel(ends_at + timedelta(hours=1), tick=False):
        declared = await vote(borrower, listing)
        assert declared.status_code == 200, declared.text
        assert declared.json()["not_held"] is True
    with time_machine.travel(ends_at + timedelta(hours=24, minutes=1), tick=False):
        assert await run_deadlines(owner) >= 1

    await owner.auth.db.rollback()
    statuses = set(
        await owner.auth.db.scalars(
            select(Interaction.status).where(Interaction.listing_id == listing_id)
        )
    )
    assert statuses == {InteractionStatus.NO_SHOW.value}
    marks = await listing_marks(owner, listing_id)
    assert [(mark.kind, mark.subject_id) for mark in marks] == [
        ("event_vote", user_id(owner))
    ]


async def test_event_endpoints_reject_a_non_event_and_an_unknown_listing(
    owner: Account, borrower: Account
) -> None:
    listing, interaction = await accepted(owner, borrower)
    assert interaction["status"] == "accepted"
    not_event = await event_state(owner, listing)
    assert not_event.status_code == 409, not_event.text
    assert not_event.json()["code"] == "event_no_show_unavailable"
    refused_vote = await vote(borrower, listing)
    assert refused_vote.status_code == 409, refused_vote.text
    assert refused_vote.json()["code"] == "event_no_show_unavailable"
    unknown = await request(owner, "GET", f"/{uuid4()}/event/no-show")
    assert unknown.status_code == 404, unknown.text
    assert unknown.json()["code"] == "not_found"


async def test_timer_follows_the_rescheduled_meeting(
    owner: Account, borrower: Account
) -> None:
    now = clock.now()
    first_at = now + timedelta(days=2)
    second_at = now + timedelta(days=4)
    with time_machine.travel(now, tick=False):
        listing, interaction = await scheduled(owner, borrower, first_at)
        await owner.auth.db.rollback()
        pending = list(
            await owner.auth.db.scalars(
                select(Deadline).where(Deadline.topic == PERSONAL_NO_SHOW_TOPIC)
            )
        )
        assert len(pending) == 1
        assert pending[0].available_at == first_at + timedelta(days=7)

        counter = (
            await propose(borrower, listing, interaction, second_at, "Cafe")
        ).json()
        moved = await accept_meeting(owner, listing, interaction, counter["version"])
        assert moved.status_code == 200, moved.text
        await owner.auth.db.rollback()
        pending = list(
            await owner.auth.db.scalars(
                select(Deadline).where(Deadline.topic == PERSONAL_NO_SHOW_TOPIC)
            )
        )
        assert len(pending) == 1
        assert pending[0].available_at == second_at + timedelta(days=7)


async def test_cancelling_the_interaction_drops_the_timer(
    owner: Account, borrower: Account
) -> None:
    now = clock.now()
    meeting_at = now + timedelta(hours=2)
    with time_machine.travel(now, tick=False):
        listing, interaction = await scheduled(owner, borrower, meeting_at)
        cancelled = await request(
            borrower,
            "POST",
            f"/{listing['id']}/interactions/{interaction['id']}/transition",
            {"status": "cancelled"},
        )
        assert cancelled.status_code == 200, cancelled.text
        await owner.auth.db.rollback()
        pending = list(
            await owner.auth.db.scalars(
                select(Deadline).where(Deadline.topic == PERSONAL_NO_SHOW_TOPIC)
            )
        )
        assert pending == []
    with time_machine.travel(meeting_at + timedelta(days=10), tick=False):
        await run_deadlines(owner)
    row = await reload_interaction(owner, UUID(interaction["id"]))
    assert row.status == InteractionStatus.CANCELLED


async def test_a_staged_interaction_is_not_closed_by_the_seven_day_rule(
    owner: Account, borrower: Account
) -> None:
    now = clock.now()
    meeting_at = now + timedelta(hours=2)
    with time_machine.travel(now, tick=False):
        _listing, interaction = await scheduled(owner, borrower, meeting_at)
        await owner.auth.db.rollback()
        await owner.auth.db.execute(
            update(Interaction)
            .where(Interaction.id == UUID(interaction["id"]))
            .values(stage="handover")
        )
        await owner.auth.db.commit()
    with time_machine.travel(meeting_at + timedelta(days=10), tick=False):
        await run_deadlines(owner)
    row = await reload_interaction(owner, UUID(interaction["id"]))
    assert row.status == InteractionStatus.ACCEPTED
    assert row.stage == "handover"


async def test_an_online_code_formed_before_the_mark_still_completes(
    owner: Account, borrower: Account
) -> None:
    now = clock.now()
    meeting_at = now + timedelta(hours=2)
    signer = Signer.generate()
    with time_machine.travel(now, tick=False):
        listing, interaction = await scheduled(owner, borrower, meeting_at)
        assert (await register_key(owner, signer)).status_code == 200
    body = signer.body(
        listing["id"],
        interaction["id"],
        user_id(owner),
        issued_at=meeting_at + timedelta(hours=24),
    )
    with time_machine.travel(meeting_at + timedelta(hours=24, seconds=1), tick=False):
        assert (
            await mark(owner, listing, interaction, "Did not come")
        ).status_code == 200
    with time_machine.travel(meeting_at + timedelta(hours=24, seconds=2), tick=False):
        confirmed = await scan(borrower, listing, interaction, body)
        assert confirmed.status_code == 200, confirmed.text
        assert confirmed.json()["status"] == "completed"
    row = await reload_interaction(owner, UUID(interaction["id"]))
    assert row.status == InteractionStatus.COMPLETED
    marks = await interaction_marks(owner, UUID(interaction["id"]))
    assert [mark.status for mark in marks] == [NoShowStatus.REMOVED.value]


async def test_an_online_code_formed_after_the_mark_has_no_effect(
    owner: Account, borrower: Account
) -> None:
    now = clock.now()
    meeting_at = now + timedelta(hours=2)
    signer = Signer.generate()
    with time_machine.travel(now, tick=False):
        listing, interaction = await scheduled(owner, borrower, meeting_at)
        assert (await register_key(owner, signer)).status_code == 200
    with time_machine.travel(meeting_at + timedelta(hours=24, seconds=1), tick=False):
        assert (
            await mark(owner, listing, interaction, "Did not come")
        ).status_code == 200
    body = signer.body(
        listing["id"],
        interaction["id"],
        user_id(owner),
        issued_at=meeting_at + timedelta(hours=24, seconds=2),
    )
    with time_machine.travel(meeting_at + timedelta(hours=24, seconds=3), tick=False):
        refused = await scan(borrower, listing, interaction, body)
        assert refused.status_code == 409, refused.text
        assert refused.json()["code"] == "qr_after_no_show"
    row = await reload_interaction(owner, UUID(interaction["id"]))
    assert row.status == InteractionStatus.NO_SHOW


async def test_organizer_disputes_the_event_no_show(
    owner: Account, borrower: Account, staff: Account, auth: Auth, places: Places
) -> None:
    extras = [await new_student(auth, places, number) for number in (11, 12)]
    now = clock.now()
    starts_at = now + timedelta(hours=2)
    ends_at = now + timedelta(hours=4)
    with time_machine.travel(now, tick=False):
        listing = await event_at(owner, starts_at, ends_at)
        await signup(borrower, listing)
        for extra in extras:
            await signup(extra, listing)
    listing_id = UUID(listing["id"])

    with time_machine.travel(ends_at + timedelta(hours=1), tick=False):
        assert (await vote(borrower, listing)).status_code == 200
        denied = await dispute_event(borrower, listing)
        assert denied.status_code == 403, denied.text
        assert denied.json()["code"] == "event_no_show_dispute_forbidden"
        outsider = await dispute_event(staff, listing)
        assert outsider.status_code == 403, outsider.text
        await staff.auth.db.rollback()
        staff.auth.db.add(
            RoleAssignment(user_id=user_id(staff), role=Role.ADMINISTRATOR)
        )
        await staff.auth.db.commit()
        admin = await dispute_event(staff, listing)
        assert admin.status_code == 403, admin.text
        assert admin.json()["code"] == "event_no_show_dispute_forbidden"

        opened = await dispute_event(owner, listing)
        assert opened.status_code == 200, opened.text
        body = opened.json()
        assert body["not_held"] is True
        assert body["organizer_mark"]["status"] == "disputed"
        assert body["dispute"]["status"] == "open"
        assert body["can_dispute"] is False

        repeat = await dispute_event(owner, listing)
        assert repeat.status_code == 200, repeat.text
        assert repeat.json()["dispute"]["id"] == body["dispute"]["id"]
        assert repeat.json()["organizer_mark"]["status"] == "disputed"
        participant_view = (await event_state(borrower, listing)).json()
        assert participant_view["dispute"]["status"] == "open"
        assert participant_view["organizer_mark"]["status"] == "disputed"
        assert participant_view["can_dispute"] is False

    await owner.auth.db.rollback()
    disputes = list(
        await owner.auth.db.scalars(
            select(Dispute).where(Dispute.listing_id == listing_id)
        )
    )
    assert len(disputes) == 1
    assert disputes[0].interaction_id is None
    assert disputes[0].status == DisputeStatus.OPEN.value
    marks = await listing_marks(owner, listing_id)
    assert [(mark.kind, mark.status) for mark in marks] == [
        ("event_vote", NoShowStatus.DISPUTED.value)
    ]
    events = list(
        await owner.auth.db.scalars(
            select(ListingEvent).where(ListingEvent.listing_id == listing_id)
        )
    )
    actions = [event.action for event in events]
    assert actions.count("event_no_show_disputed") == 1
    assert actions.count("event_not_held") == 1


async def test_parallel_event_disputes_leave_one_case(
    owner: Account, borrower: Account, auth: Auth, places: Places
) -> None:
    extras = [await new_student(auth, places, number) for number in (13, 14, 15)]
    now = clock.now()
    starts_at = now + timedelta(hours=2)
    ends_at = now + timedelta(hours=4)
    with time_machine.travel(now, tick=False):
        listing = await event_at(owner, starts_at, ends_at)
        await signup(borrower, listing)
        for extra in extras:
            await signup(extra, listing)
    listing_id = UUID(listing["id"])
    with time_machine.travel(ends_at + timedelta(hours=1), tick=False):
        assert (await vote(borrower, listing)).json()["votes"] == 1
        assert (await vote(extras[0], listing)).json()["not_held"] is True
        first, second = await asyncio.gather(
            dispute_event(owner, listing), dispute_event(owner, listing)
        )
    assert first.status_code == 200, first.text
    assert second.status_code == 200, second.text
    assert first.json()["dispute"]["id"] == second.json()["dispute"]["id"]
    await owner.auth.db.rollback()
    disputes = list(
        await owner.auth.db.scalars(
            select(Dispute).where(Dispute.listing_id == listing_id)
        )
    )
    assert len(disputes) == 1
    marks = await listing_marks(owner, listing_id)
    assert [mark.status for mark in marks] == [NoShowStatus.DISPUTED.value]
    await owner.auth.db.rollback()
    count = await owner.auth.db.scalar(
        select(func.count())
        .select_from(ListingEvent)
        .where(
            ListingEvent.listing_id == listing_id,
            ListingEvent.action == "event_no_show_disputed",
        )
    )
    assert count == 1


async def test_event_dispute_needs_a_charge_and_has_a_window(
    owner: Account, borrower: Account, auth: Auth, places: Places
) -> None:
    extras = [await new_student(auth, places, number) for number in (16, 17, 18)]
    now = clock.now()
    starts_at = now + timedelta(hours=2)
    ends_at = now + timedelta(hours=4)
    with time_machine.travel(now, tick=False):
        listing = await event_at(owner, starts_at, ends_at)
        await signup(borrower, listing)
        for extra in extras:
            await signup(extra, listing)
    with time_machine.travel(ends_at + timedelta(hours=1), tick=False):
        assert (await vote(borrower, listing)).json()["votes"] == 1
        unavailable = await dispute_event(owner, listing)
        assert unavailable.status_code == 409, unavailable.text
        assert unavailable.json()["code"] == "event_no_show_dispute_unavailable"
        charged = (await vote(extras[0], listing)).json()
        assert charged["not_held"] is True
    with time_machine.travel(
        ends_at + timedelta(hours=1, days=7, seconds=1), tick=False
    ):
        closed = await dispute_event(owner, listing)
        assert closed.status_code == 409, closed.text
        assert closed.json()["code"] == "event_no_show_dispute_closed"
