"""No-shows and "did not take place" (specification, 5.1.1, module 5).

A personal interaction is judged from its agreed meeting time:

- until ``no_show_mark_after`` (24 hours) after the meeting nobody may claim
  that it did not take place;
- from then until ``no_show_auto_after`` (7 days) either participant may
  charge the other one with a reason, which moves the interaction to
  "did not take place" and records the no-show;
- if both participants charge each other, one dispute is opened atomically
  and neither mark counts until the moderator decides (#94);
- without any mark or confirmation the interaction becomes "did not take
  place" after 7 days without charging either participant.

An event is judged from its end time: 24 hours later every registered
participant the organiser did not mark gets a no-show, unless the organiser
marked nobody at all. During the following 7 days the registered participants
may vote that the event did not take place; at a third of the registrations,
rounded up, the organiser is charged instead.

All mutations lock the listing aggregate first, so marks, attendance, the
late QR undo and the timers serialize. Each timer is a durable deadline row,
so a scheduler outage does not lose the transition: the deadline is simply
due on the next run after the start.
"""

from dataclasses import dataclass
from datetime import datetime
from typing import Any, Literal
from uuid import UUID, uuid5

from sqlalchemy import func, select, text, update
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from campus.core import clock
from campus.core.config import Settings, get_settings
from campus.core.deadlines import cancel_deadline, deadline_handlers, schedule_deadline
from campus.core.i18n import N_
from campus.core.jobs import JobInfo
from campus.core.outbox import add_message, outbox_handlers
from campus.core.web import ProblemError, ProblemType
from campus.core.web.problems import NOT_FOUND
from campus.modules.listings import (
    Interaction,
    InteractionStatus,
    Listing,
    ListingStatus,
    LoanStage,
    Meeting,
    cancel_return_reminder,
    locked,
    no_showed_at,
    record,
    transition,
)
from campus.modules.moderation import (
    Dispute,
    DisputeKind,
    DisputeStatus,
)
from campus.modules.reputation.attendance import current_attendance_participant_ids
from campus.modules.reputation.models import (
    EventNoShowVote,
    NoShowKind,
    NoShowMark,
    NoShowStatus,
)
from campus.modules.reputation.service import QR_COMPLETION_KINDS

# A signup that still stands after the event: it was accepted and was not
# cancelled. Once the automatic rule runs, the unmarked signups become
# "did not take place", so they keep participating in the vote threshold.
REGISTERED_EVENT_STATUSES = (
    InteractionStatus.ACCEPTED,
    InteractionStatus.COMPLETED,
    InteractionStatus.NO_SHOW,
)

NO_SHOW_TOPIC = "reputation.no_show"
PERSONAL_NO_SHOW_TOPIC = "reputation.no_show_auto"
EVENT_NO_SHOW_TOPIC = "reputation.event_no_show"

NO_SHOW_FORBIDDEN = ProblemType(
    "no_show_forbidden",
    403,
    N_("Forbidden"),
    N_("Only the two participants of the interaction can mark a no-show."),
)
NO_SHOW_UNAVAILABLE = ProblemType(
    "no_show_unavailable",
    409,
    N_("A no-show cannot be marked here"),
    N_(
        "A no-show is marked for a personal meeting of a giveaway, exchange,"
        " skill, loan or help interaction, or for an event."
    ),
)
NO_SHOW_TOO_EARLY = ProblemType(
    "no_show_too_early",
    409,
    N_("The meeting time is still recent"),
    N_("A no-show can be marked only 24 hours after the agreed meeting time."),
)
NO_SHOW_CLOSED = ProblemType(
    "no_show_closed",
    409,
    N_("No-show marking is closed"),
    N_(
        "The no-show window has passed: after 7 days the interaction becomes"
        " 'did not take place' without a no-show."
    ),
)
NO_SHOW_REASON_INVALID = ProblemType(
    "no_show_reason_invalid",
    422,
    N_("Invalid no-show reason"),
    N_("Describe the reason for the no-show in 1 to {max} characters."),
)
NO_SHOW_STATE = ProblemType(
    "no_show_state_conflict",
    409,
    N_("The interaction cannot be marked"),
    N_("Only an accepted or a marked 'did not take place' interaction replies."),
)
NOT_RETURNED_FORBIDDEN = ProblemType(
    "loan_not_returned_forbidden",
    403,
    N_("Forbidden"),
    N_("Only the owner of the lent item can mark it 'not returned'."),
)
NOT_RETURNED_UNAVAILABLE = ProblemType(
    "loan_not_returned_unavailable",
    409,
    N_("The loan cannot be marked"),
    N_(
        "Only a loan whose item was handed over and is not returned yet can be"
        " marked 'not returned'."
    ),
)
NOT_RETURNED_TOO_EARLY = ProblemType(
    "loan_not_returned_too_early",
    409,
    N_("The return deadline is still recent"),
    N_(
        "The owner can mark the item 'not returned' only after the configured"
        " wait after the return deadline."
    ),
)
LOAN_NO_SHOW_UNAVAILABLE = ProblemType(
    "loan_no_show_unavailable",
    409,
    N_("The loan is in progress"),
    N_(
        "The item was handed over; the loan ends with its return or the"
        " owner's 'not returned' mark."
    ),
)
EVENT_NO_SHOW_UNAVAILABLE = ProblemType(
    "event_no_show_unavailable",
    409,
    N_("The event cannot be judged"),
    N_("Only a published event with an end time accepts votes."),
)
EVENT_VOTE_CLOSED = ProblemType(
    "event_no_show_vote_closed",
    409,
    N_("Voting is closed"),
    N_("Vote that the event did not take place within 7 days after it ended."),
)
EVENT_VOTE_NOT_REGISTERED = ProblemType(
    "event_no_show_not_registered",
    403,
    N_("Not registered"),
    N_("Only a participant registered for the event can vote."),
)
EVENT_NO_SHOW_FORBIDDEN = ProblemType(
    "event_no_show_forbidden",
    403,
    N_("Forbidden"),
    N_("Only the organiser and the registered participants see the event result."),
)
EVENT_DISPUTE_FORBIDDEN = ProblemType(
    "event_no_show_dispute_forbidden",
    403,
    N_("Forbidden"),
    N_("Only the organiser can dispute the no-show of their event."),
)
EVENT_DISPUTE_UNAVAILABLE = ProblemType(
    "event_no_show_dispute_unavailable",
    409,
    N_("Nothing to dispute"),
    N_("The organiser has no charged no-show at this event yet."),
)
EVENT_DISPUTE_CLOSED = ProblemType(
    "event_no_show_dispute_closed",
    409,
    N_("The dispute is closed"),
    N_("The no-show can be disputed only within 7 days after it was charged."),
)

Basis = Literal["unmarked", "marked", "automatic", "mutual_dispute", "completed"]


@dataclass(frozen=True, slots=True)
class NoShowState:
    """The current result of a personal interaction and how it was reached."""

    listing_id: UUID
    interaction_id: UUID
    status: InteractionStatus
    basis: Basis
    marks: list[NoShowMark]
    dispute: Dispute | None
    no_show_at: datetime | None
    mark_from: datetime | None
    auto_after: datetime | None
    can_mark: bool


@dataclass(frozen=True, slots=True)
class EventNoShowState:
    """Votes and marks of one event."""

    listing_id: UUID
    organizer_id: UUID
    registered: int
    votes: int
    threshold: int
    voter_ids: set[UUID]
    registered_ids: set[UUID]
    not_held: bool
    organizer_mark: NoShowMark | None
    dispute: Dispute | None
    dispute_deadline: datetime | None
    participant_marks: list[NoShowMark]
    vote_opens_at: datetime | None
    vote_closes_at: datetime | None
    can_vote: bool


def no_show_key(interaction_id: UUID) -> str:
    return f"no-show:{interaction_id}"


def event_no_show_key(listing_id: UUID) -> str:
    return f"event-no-show:{listing_id}"


def agreed_moment(interaction: Interaction) -> datetime | None:
    """The agreed meeting time of a personal interaction, if any."""
    meeting = interaction.meeting
    if meeting is None:
        return None
    return meeting.scheduled_at


def mark_opens_at(interaction: Interaction, settings: Settings) -> datetime | None:
    """The first moment a no-show may be marked, inclusive."""
    agreed = agreed_moment(interaction)
    return None if agreed is None else agreed + settings.no_show_mark_after


def auto_no_show_at(interaction: Interaction, settings: Settings) -> datetime | None:
    """The moment an unmarked interaction becomes "did not take place"."""
    agreed = agreed_moment(interaction)
    return None if agreed is None else agreed + settings.no_show_auto_after


def check_no_show_kind(listing: Listing) -> None:
    """Refuse a personal mark on an event or a scenario without a meeting."""
    if listing.kind == "event":
        raise ProblemError(EVENT_NO_SHOW_UNAVAILABLE)
    if listing.kind not in QR_COMPLETION_KINDS:
        raise ProblemError(NO_SHOW_UNAVAILABLE)


def participant_ids(listing: Listing, interaction: Interaction) -> tuple[UUID, UUID]:
    """The two people of a personal interaction; raise for a self-interaction."""
    if listing.author_id == interaction.participant_id:
        raise ProblemError(NO_SHOW_FORBIDDEN)
    return listing.author_id, interaction.participant_id


def other_side(listing: Listing, interaction: Interaction, actor_id: UUID) -> UUID:
    """The person the actor charges with the no-show."""
    author_id, participant_id = participant_ids(listing, interaction)
    if actor_id == author_id:
        return participant_id
    if actor_id == participant_id:
        return author_id
    raise ProblemError(NO_SHOW_FORBIDDEN)


def validate_reason(reason: str | None, settings: Settings) -> str:
    """Normalize a required no-show reason."""
    normalized = (reason or "").strip()
    if not normalized or len(normalized) > settings.no_show_reason_max_length:
        raise ProblemError(
            NO_SHOW_REASON_INVALID, max=settings.no_show_reason_max_length
        )
    return normalized


async def interaction_no_show_marks(
    session: AsyncSession, interaction_id: UUID
) -> list[NoShowMark]:
    """Every personal mark of one interaction, oldest first."""
    return list(
        await session.scalars(
            select(NoShowMark)
            .where(NoShowMark.interaction_id == interaction_id)
            .order_by(NoShowMark.created_at, NoShowMark.id)
        )
    )


async def dispute_of(session: AsyncSession, interaction_id: UUID) -> Dispute | None:
    return await session.scalar(
        select(Dispute).where(Dispute.interaction_id == interaction_id)
    )


def basis_of(
    status: InteractionStatus,
    marks: list[NoShowMark],
    dispute: Dispute | None,
) -> Basis:
    if status == InteractionStatus.COMPLETED:
        return "completed"
    if status != InteractionStatus.NO_SHOW:
        return "unmarked"
    if dispute is not None:
        return "mutual_dispute"
    if any(mark.kind == NoShowKind.PERSONAL for mark in marks):
        return "marked"
    return "automatic"


def can_mark_now(  # noqa: PLR0913, PLR0917 - the parts of a window
    interactive: InteractionStatus,
    marks: list[NoShowMark],
    actor_id: UUID,
    opens_at: datetime | None,
    closes_at: datetime | None,
    no_show_at: datetime | None,
    settings: Settings,
) -> bool:
    """Whether ``actor_id`` may mark or answer a no-show right now."""
    now = clock.now()
    if interactive == InteractionStatus.ACCEPTED:
        return (
            opens_at is not None
            and closes_at is not None
            and opens_at <= now < closes_at
        )
    if interactive != InteractionStatus.NO_SHOW or no_show_at is None:
        return False
    if any(mark.reporter_id == actor_id for mark in marks):
        return False
    if not any(mark.kind == NoShowKind.PERSONAL for mark in marks):
        # The automatic rule charged nobody; there is nothing to answer.
        return False
    return now <= no_show_at + settings.no_show_dispute_window


async def no_show_state(
    session: AsyncSession,
    listing: Listing,
    interaction: Interaction,
    actor_id: UUID,
    settings: Settings,
) -> NoShowState:
    """Read the result and its basis for one participant."""
    if actor_id not in (listing.author_id, interaction.participant_id):
        raise ProblemError(NO_SHOW_FORBIDDEN)
    participant_ids(listing, interaction)
    marks = await interaction_no_show_marks(session, interaction.id)
    dispute = await dispute_of(session, interaction.id)
    no_show_at = (
        await no_showed_at(session, interaction.id)
        if interaction.status == InteractionStatus.NO_SHOW
        else None
    )
    status = InteractionStatus(interaction.status)
    # A handed-over loan cannot be closed by a mutual no-show, so the state
    # never offers one even while the meeting window is formally open.
    staged_loan = listing.kind == "loan" and interaction.stage is not None
    return NoShowState(
        listing_id=listing.id,
        interaction_id=interaction.id,
        status=status,
        basis=basis_of(status, marks, dispute),
        marks=marks,
        dispute=dispute,
        no_show_at=no_show_at,
        mark_from=mark_opens_at(interaction, settings),
        auto_after=auto_no_show_at(interaction, settings),
        can_mark=not staged_loan
        and can_mark_now(
            status,
            marks,
            actor_id,
            mark_opens_at(interaction, settings),
            auto_no_show_at(interaction, settings),
            no_show_at,
            settings,
        ),
    )


async def _load_interaction(
    session: AsyncSession, listing: Listing, interaction_id: UUID
) -> Interaction:
    interaction = await session.get(Interaction, interaction_id)
    if interaction is None or interaction.listing_id != listing.id:
        raise ProblemError(NOT_FOUND)
    return interaction


async def _transition_no_show(  # noqa: PLR0913 - transition parts
    session: AsyncSession,
    listing: Listing,
    interaction: Interaction,
    actor_id: UUID | None,
    settings: Settings,
    *,
    action: str,
    reason: str | None,
    details: dict[str, Any],
) -> None:
    await transition(
        session,
        listing,
        interaction,
        InteractionStatus.NO_SHOW,
        actor_id,
        settings=settings,
        action=action,
        reason=reason,
        details=details,
        allow_no_show_by_participant=actor_id is not None,
    )


async def _suspend_marks(
    session: AsyncSession, interaction_id: UUID, now: datetime
) -> None:
    """Stop every counted mark of the interaction from counting."""
    await session.execute(
        update(NoShowMark)
        .where(
            NoShowMark.interaction_id == interaction_id,
            NoShowMark.status == NoShowStatus.COUNTED,
        )
        .values(status=NoShowStatus.DISPUTED, disputed_at=now, updated_at=now)
    )


async def _open_dispute(
    session: AsyncSession, listing: Listing, interaction: Interaction, now: datetime
) -> Dispute:
    """Create the one dispute of the interaction, or return the existing one."""
    dispute_id = await session.scalar(
        insert(Dispute)
        .values(
            kind=DisputeKind.NO_SHOW.value,
            status=DisputeStatus.OPEN.value,
            listing_id=listing.id,
            interaction_id=interaction.id,
            opened_at=now,
            version=1,
            created_at=now,
            updated_at=now,
        )
        .on_conflict_do_nothing(index_elements=["interaction_id"])
        .returning(Dispute.id)
    )
    if dispute_id is not None:
        dispute = await session.get(Dispute, dispute_id)
        if dispute is None:  # pragma: no cover - the insert just returned this id
            raise RuntimeError("dispute disappeared")
        return dispute
    existing = await dispute_of(session, interaction.id)
    if existing is None:  # pragma: no cover - only the unique key can race
        raise RuntimeError("dispute conflict without a stored dispute")
    return existing


async def _mark_against(  # noqa: PLR0913, PLR0917 - the parts of a mark
    session: AsyncSession,
    listing: Listing,
    interaction: Interaction,
    actor_id: UUID,
    reason: str,
    settings: Settings,
    now: datetime,
) -> NoShowMark:
    mark = NoShowMark(
        listing_id=listing.id,
        interaction_id=interaction.id,
        reporter_id=actor_id,
        subject_id=other_side(listing, interaction, actor_id),
        kind=NoShowKind.PERSONAL.value,
        status=NoShowStatus.COUNTED.value,
        reason=reason,
        disputed_at=None,
        removed_at=None,
        removed_by_id=None,
        created_at=now,
        updated_at=now,
    )
    session.add(mark)
    await session.flush()
    await _transition_no_show(
        session,
        listing,
        interaction,
        actor_id,
        settings,
        action="no_show_marked",
        reason=reason,
        details={
            "rule": "personal",
            "mark_id": str(mark.id),
            "subject_id": str(mark.subject_id),
            "time": (agreed_moment(interaction) or now).isoformat(),
        },
    )
    await cancel_deadline(session, no_show_key(interaction.id))
    queue_no_show(
        session,
        listing,
        {
            "interaction_id": str(interaction.id),
            "mark_id": str(mark.id),
            "subject_id": str(mark.subject_id),
            "kind": NoShowKind.PERSONAL.value,
            "status": "marked",
        },
        {listing.author_id, interaction.participant_id},
    )
    return mark


async def _answer_marks(  # noqa: PLR0913, PLR0917 - the parts of a mark
    session: AsyncSession,
    listing: Listing,
    interaction: Interaction,
    actor_id: UUID,
    reason: str,
    now: datetime,
) -> None:
    """Record a mutual allegation and open the single dispute atomically."""
    mark = NoShowMark(
        listing_id=listing.id,
        interaction_id=interaction.id,
        reporter_id=actor_id,
        subject_id=other_side(listing, interaction, actor_id),
        kind=NoShowKind.PERSONAL.value,
        status=NoShowStatus.COUNTED.value,
        reason=reason,
        disputed_at=None,
        removed_at=None,
        removed_by_id=None,
        created_at=now,
        updated_at=now,
    )
    session.add(mark)
    await session.flush()
    await _suspend_marks(session, interaction.id, now)
    dispute = await _open_dispute(session, listing, interaction, now)
    listing.version += 1
    details: dict[str, Any] = {
        "rule": "mutual",
        "mark_id": str(mark.id),
        "subject_id": str(mark.subject_id),
        "dispute_id": str(dispute.id),
    }
    record(
        session,
        listing,
        actor_id,
        "no_show_disputed",
        InteractionStatus.NO_SHOW.value,
        interaction,
        reason=reason,
        details=details,
    )
    await cancel_deadline(session, no_show_key(interaction.id))
    queue_no_show(
        session,
        listing,
        {
            "interaction_id": str(interaction.id),
            "mark_id": str(mark.id),
            "subject_id": str(mark.subject_id),
            "dispute_id": str(dispute.id),
            "kind": NoShowKind.PERSONAL.value,
            "status": "disputed",
        },
        {listing.author_id, interaction.participant_id},
    )
    await session.flush()


async def mark_no_show(  # noqa: PLR0913, PLR0917 - request context
    session: AsyncSession,
    listing_id: UUID,
    interaction_id: UUID,
    actor_id: UUID,
    reason: str | None,
    settings: Settings,
) -> NoShowState:
    """Charge the other participant with a no-show, or answer their mark.

    The listing lock serializes this call with the attendance, the timers and
    each other, so a pair of parallel mutual allegations leaves one
    interaction, one dispute and suspended marks. A handed-over loan is
    refused: the item is an obligation, and its end is the return or the
    owner's "not returned" mark, not a mutual no-show.
    """
    listing = await locked(session, listing_id)
    check_no_show_kind(listing)
    interaction = await _load_interaction(session, listing, interaction_id)
    participant_ids(listing, interaction)
    if actor_id not in (listing.author_id, interaction.participant_id):
        raise ProblemError(NO_SHOW_FORBIDDEN)
    if listing.kind == "loan" and interaction.stage is not None:
        # The item was handed over, so the loan is an obligation: it ends by
        # its return or by the owner's "not returned" mark, never by a mutual
        # no-show of a meeting that already served its purpose.
        raise ProblemError(LOAN_NO_SHOW_UNAVAILABLE)
    now = clock.now()
    status = InteractionStatus(interaction.status)
    if status == InteractionStatus.ACCEPTED:
        opens_at = mark_opens_at(interaction, settings)
        closes_at = auto_no_show_at(interaction, settings)
        if opens_at is None or closes_at is None:
            raise ProblemError(NO_SHOW_UNAVAILABLE)
        if now < opens_at:
            raise ProblemError(NO_SHOW_TOO_EARLY)
        if now >= closes_at:
            raise ProblemError(NO_SHOW_CLOSED)
        await _mark_against(
            session,
            listing,
            interaction,
            actor_id,
            validate_reason(reason, settings),
            settings,
            now,
        )
    elif status == InteractionStatus.NO_SHOW:
        marks = await interaction_no_show_marks(session, interaction.id)
        if any(mark.reporter_id == actor_id for mark in marks):
            # A retry with a fresh Idempotency-Key changes nothing.
            return await no_show_state(
                session, listing, interaction, actor_id, settings
            )
        no_show_at = await no_showed_at(session, interaction.id)
        if no_show_at is None:
            raise ProblemError(NO_SHOW_STATE)
        if not any(
            mark.kind == NoShowKind.PERSONAL and mark.status != NoShowStatus.REMOVED
            for mark in marks
        ):
            raise ProblemError(NO_SHOW_CLOSED)
        if now > no_show_at + settings.no_show_dispute_window:
            raise ProblemError(NO_SHOW_CLOSED)
        await _answer_marks(
            session,
            listing,
            interaction,
            actor_id,
            validate_reason(reason, settings),
            now,
        )
    else:
        raise ProblemError(NO_SHOW_STATE)
    await session.flush()
    return await no_show_state(session, listing, interaction, actor_id, settings)


LOAN_NOT_RETURNED_REASON = "loan_not_returned"


async def mark_loan_not_returned(
    session: AsyncSession,
    listing_id: UUID,
    interaction_id: UUID,
    actor_id: UUID,
    settings: Settings,
) -> NoShowState:
    """The owner's claim that a lent item was not returned in time.

    Only the owner may use it, and only after the configured wait following
    the return deadline (appendix 4: not earlier than 3 days). It moves the
    interaction to "did not take place" and charges the borrower with the
    no-show of #66; the borrower may answer it within the dispute window,
    which suspends both marks until the moderator decides (#94). The item is
    not back, so the listing keeps its occupied place and the overdue flag
    stays visible. A repeat with a fresh idempotency key changes nothing.
    """
    listing = await locked(session, listing_id)
    interaction = await _load_interaction(session, listing, interaction_id)
    participant_ids(listing, interaction)
    if actor_id != listing.author_id:
        raise ProblemError(NOT_RETURNED_FORBIDDEN)
    if listing.kind != "loan":
        raise ProblemError(NOT_RETURNED_UNAVAILABLE)
    now = clock.now()
    status = InteractionStatus(interaction.status)
    if status == InteractionStatus.NO_SHOW:
        marks = await interaction_no_show_marks(session, interaction.id)
        if any(
            mark.kind == NoShowKind.PERSONAL
            and mark.reporter_id == actor_id
            and mark.status != NoShowStatus.REMOVED
            for mark in marks
        ):
            return await no_show_state(
                session, listing, interaction, actor_id, settings
            )
        raise ProblemError(NOT_RETURNED_UNAVAILABLE)
    if (
        status != InteractionStatus.ACCEPTED
        or interaction.stage != LoanStage.ISSUED.value
        or interaction.return_due_at is None
    ):
        raise ProblemError(NOT_RETURNED_UNAVAILABLE)
    available_at = interaction.return_due_at + settings.loan_not_returned_after
    if now < available_at:
        raise ProblemError(NOT_RETURNED_TOO_EARLY, available_at=available_at)
    return_due_at = interaction.return_due_at
    mark = NoShowMark(
        listing_id=listing.id,
        interaction_id=interaction.id,
        reporter_id=actor_id,
        subject_id=interaction.participant_id,
        kind=NoShowKind.PERSONAL.value,
        status=NoShowStatus.COUNTED.value,
        reason=LOAN_NOT_RETURNED_REASON,
        disputed_at=None,
        removed_at=None,
        removed_by_id=None,
        created_at=now,
        updated_at=now,
    )
    session.add(mark)
    await session.flush()
    await _transition_no_show(
        session,
        listing,
        interaction,
        actor_id,
        settings,
        action="loan_not_returned",
        reason=LOAN_NOT_RETURNED_REASON,
        details={
            "rule": "loan_return",
            "mark_id": str(mark.id),
            "subject_id": str(mark.subject_id),
            "return_due_at": return_due_at.isoformat(),
        },
    )
    await cancel_deadline(session, no_show_key(interaction.id))
    await cancel_return_reminder(session, interaction)
    queue_no_show(
        session,
        listing,
        {
            "interaction_id": str(interaction.id),
            "mark_id": str(mark.id),
            "subject_id": str(mark.subject_id),
            "kind": NoShowKind.PERSONAL.value,
            "status": "not_returned",
            "rule": "loan_return",
        },
        {listing.author_id, interaction.participant_id},
    )
    await session.flush()
    return await no_show_state(session, listing, interaction, actor_id, settings)


async def _accepted_interactions(
    session: AsyncSession, listing_id: UUID
) -> list[Interaction]:
    return list(
        await session.scalars(
            select(Interaction).where(
                Interaction.listing_id == listing_id,
                Interaction.status == InteractionStatus.ACCEPTED,
            )
        )
    )


async def _remove_event_auto_marks(
    session: AsyncSession, listing_id: UUID, now: datetime
) -> list[UUID]:
    """Lift the automatic event no-shows once the event is declared not held."""
    result = await session.execute(
        update(NoShowMark)
        .where(
            NoShowMark.listing_id == listing_id,
            NoShowMark.kind == NoShowKind.EVENT_AUTO.value,
            NoShowMark.status == NoShowStatus.COUNTED.value,
        )
        .values(status=NoShowStatus.REMOVED.value, removed_at=now, updated_at=now)
        .returning(NoShowMark.id)
    )
    return list(result.scalars())


async def event_no_show_state(
    session: AsyncSession, listing: Listing, settings: Settings
) -> EventNoShowState:
    """Votes, the current threshold and the marks charged to the organiser."""
    registered = await session.scalar(
        select(func.count())
        .select_from(Interaction)
        .where(
            Interaction.listing_id == listing.id,
            Interaction.status.in_(REGISTERED_EVENT_STATUSES),
        )
    )
    votes = await session.scalar(
        select(func.count())
        .select_from(EventNoShowVote)
        .where(EventNoShowVote.listing_id == listing.id)
    )
    voter_ids = set(
        await session.scalars(
            select(EventNoShowVote.voter_id).where(
                EventNoShowVote.listing_id == listing.id
            )
        )
    )
    registered_ids = set(
        await session.scalars(
            select(Interaction.participant_id).where(
                Interaction.listing_id == listing.id,
                Interaction.status.in_(REGISTERED_EVENT_STATUSES),
            )
        )
    )
    registered_count = int(registered or 0)
    divisor = settings.event_no_show_votes_divisor
    threshold = (
        0 if registered_count == 0 else (registered_count + divisor - 1) // divisor
    )
    organizer_mark = await session.scalar(
        select(NoShowMark).where(
            NoShowMark.listing_id == listing.id,
            NoShowMark.interaction_id.is_(None),
        )
    )
    participant_marks = list(
        await session.scalars(
            select(NoShowMark)
            .where(
                NoShowMark.listing_id == listing.id,
                NoShowMark.interaction_id.is_not(None),
            )
            .order_by(NoShowMark.created_at, NoShowMark.id)
        )
    )
    dispute = await event_dispute_of(session, listing.id)
    dispute_deadline = (
        None
        if organizer_mark is None
        else organizer_mark.created_at + settings.no_show_dispute_window
    )
    now = clock.now()
    opens_at = listing.event_ends_at
    closes_at = (
        None if opens_at is None else opens_at + settings.event_no_show_votes_window
    )
    return EventNoShowState(
        listing_id=listing.id,
        organizer_id=listing.author_id,
        registered=registered_count,
        votes=int(votes or 0),
        threshold=threshold,
        voter_ids=voter_ids,
        registered_ids=registered_ids,
        not_held=organizer_mark is not None,
        organizer_mark=organizer_mark,
        dispute=dispute,
        dispute_deadline=dispute_deadline,
        participant_marks=participant_marks,
        vote_opens_at=opens_at,
        vote_closes_at=closes_at,
        can_vote=(
            opens_at is not None
            and closes_at is not None
            and opens_at <= now <= closes_at
            and listing.status != ListingStatus.CANCELLED
        ),
    )


async def require_event(listing: Listing) -> None:
    if listing.kind != "event" or listing.event_ends_at is None:
        raise ProblemError(EVENT_NO_SHOW_UNAVAILABLE)


async def _charge_organizer(
    session: AsyncSession,
    listing: Listing,
    actor_id: UUID,
    state: EventNoShowState,
    now: datetime,
) -> NoShowMark | None:
    """Charge the organiser once the threshold is reached; lift participant marks."""
    mark_id = await session.scalar(
        insert(NoShowMark)
        .values(
            listing_id=listing.id,
            interaction_id=None,
            reporter_id=None,
            subject_id=listing.author_id,
            kind=NoShowKind.EVENT_VOTE.value,
            status=NoShowStatus.COUNTED.value,
            reason=None,
            disputed_at=None,
            removed_at=None,
            removed_by_id=None,
            created_at=now,
            updated_at=now,
        )
        .on_conflict_do_nothing(
            index_elements=["listing_id", "subject_id"],
            index_where=text("interaction_id IS NULL"),
        )
        .returning(NoShowMark.id)
    )
    if mark_id is None:
        return None
    removed = await _remove_event_auto_marks(session, listing.id, now)
    mark = await session.get(NoShowMark, mark_id)
    if mark is None:  # pragma: no cover - the insert just returned this id
        raise RuntimeError("organiser mark disappeared")
    listing.version += 1
    record(
        session,
        listing,
        actor_id,
        "event_not_held",
        listing.status,
        details={
            "vote_count": state.votes,
            "threshold": state.threshold,
            "organizer_mark_id": str(mark.id),
            "lifted_mark_ids": [str(value) for value in removed],
        },
    )
    queue_no_show(
        session,
        listing,
        {
            "mark_id": str(mark.id),
            "subject_id": str(listing.author_id),
            "kind": NoShowKind.EVENT_VOTE.value,
            "status": "marked",
        },
        {listing.author_id},
    )
    return mark


async def vote_event_not_held(
    session: AsyncSession, listing_id: UUID, voter_id: UUID, settings: Settings
) -> EventNoShowState:
    """Vote that an event did not take place; a third of registrations decides.

    A repeated vote is a no-op: the unique row keeps one participant from
    raising the count. Reaching the threshold charges the organiser and lifts
    the automatic participant marks in the same transaction.
    """
    listing = await locked(session, listing_id)
    await require_event(listing)
    now = clock.now()
    state = await event_no_show_state(session, listing, settings)
    if not state.can_vote:
        raise ProblemError(EVENT_VOTE_CLOSED)
    interaction = await session.scalar(
        select(Interaction).where(
            Interaction.listing_id == listing.id,
            Interaction.participant_id == voter_id,
            Interaction.status.in_(REGISTERED_EVENT_STATUSES),
        )
    )
    if interaction is None:
        raise ProblemError(EVENT_VOTE_NOT_REGISTERED)
    vote_id = await session.scalar(
        insert(EventNoShowVote)
        .values(
            listing_id=listing.id,
            interaction_id=interaction.id,
            voter_id=voter_id,
            created_at=now,
            updated_at=now,
        )
        .on_conflict_do_nothing(index_elements=["listing_id", "voter_id"])
        .returning(EventNoShowVote.id)
    )
    await session.flush()
    state = await event_no_show_state(session, listing, settings)
    if (
        vote_id is not None
        and state.threshold > 0
        and state.votes >= state.threshold
        and state.organizer_mark is None
    ):
        await _charge_organizer(session, listing, voter_id, state, now)
        await session.flush()
        state = await event_no_show_state(session, listing, settings)
    return state


async def event_dispute_of(session: AsyncSession, listing_id: UUID) -> Dispute | None:
    """The single case of the organiser's event no-show, if it exists."""
    return await session.scalar(
        select(Dispute).where(
            Dispute.listing_id == listing_id,
            Dispute.interaction_id.is_(None),
        )
    )


async def _open_event_dispute(
    session: AsyncSession, listing: Listing, now: datetime
) -> Dispute:
    """Create the one event dispute, or return the existing one."""
    dispute_id = await session.scalar(
        insert(Dispute)
        .values(
            kind=DisputeKind.NO_SHOW.value,
            status=DisputeStatus.OPEN.value,
            listing_id=listing.id,
            interaction_id=None,
            opened_at=now,
            version=1,
            created_at=now,
            updated_at=now,
        )
        .on_conflict_do_nothing(
            index_elements=["listing_id"],
            index_where=text("interaction_id IS NULL"),
        )
        .returning(Dispute.id)
    )
    if dispute_id is not None:
        dispute = await session.get(Dispute, dispute_id)
        if dispute is None:  # pragma: no cover - the insert just returned this id
            raise RuntimeError("event dispute disappeared")
        return dispute
    existing = await event_dispute_of(session, listing.id)
    if existing is None:  # pragma: no cover - only the unique key can race
        raise RuntimeError("event dispute conflict without a stored case")
    return existing


async def dispute_event_no_show(
    session: AsyncSession,
    listing_id: UUID,
    actor_id: UUID,
    settings: Settings,
) -> EventNoShowState:
    """Let the organiser dispute the no-show charged by the event vote.

    The listing lock serializes the command with the vote that charges the
    mark and with another dispute request. The mark becomes ``disputed`` and
    stops counting until the moderator decides (#94); the event-level case is
    one per listing, so a repeat or a parallel request is idempotent.
    """
    listing = await locked(session, listing_id)
    await require_event(listing)
    if listing.author_id != actor_id:
        raise ProblemError(EVENT_DISPUTE_FORBIDDEN)
    now = clock.now()
    state = await event_no_show_state(session, listing, settings)
    mark = state.organizer_mark
    if mark is None or mark.kind != NoShowKind.EVENT_VOTE.value:
        raise ProblemError(EVENT_DISPUTE_UNAVAILABLE)
    if state.dispute is not None:
        if (
            mark.status == NoShowStatus.DISPUTED.value
            and state.dispute.status == DisputeStatus.OPEN.value
        ):
            return state
        raise ProblemError(EVENT_DISPUTE_CLOSED)
    if mark.status != NoShowStatus.COUNTED.value:
        raise ProblemError(EVENT_DISPUTE_UNAVAILABLE)
    if now > mark.created_at + settings.no_show_dispute_window:
        raise ProblemError(EVENT_DISPUTE_CLOSED)
    suspended = await session.scalar(
        update(NoShowMark)
        .where(
            NoShowMark.id == mark.id,
            NoShowMark.status == NoShowStatus.COUNTED.value,
        )
        .values(
            status=NoShowStatus.DISPUTED.value,
            disputed_at=now,
            updated_at=now,
        )
        .returning(NoShowMark.id)
    )
    if suspended is None:  # pragma: no cover - the listing lock serializes
        raise ProblemError(EVENT_DISPUTE_UNAVAILABLE)
    dispute = await _open_event_dispute(session, listing, now)
    listing.version += 1
    record(
        session,
        listing,
        actor_id,
        "event_no_show_disputed",
        listing.status,
        details={
            "mark_id": str(mark.id),
            "dispute_id": str(dispute.id),
            "rule": "event_vote",
        },
    )
    queue_no_show(
        session,
        listing,
        {
            "mark_id": str(mark.id),
            "dispute_id": str(dispute.id),
            "kind": NoShowKind.EVENT_VOTE.value,
            "status": "disputed",
        },
        {listing.author_id} | state.registered_ids,
    )
    await session.flush()
    return await event_no_show_state(session, listing, settings)


async def event_result(
    session: AsyncSession, listing_id: UUID, viewer_id: UUID, settings: Settings
) -> EventNoShowState:
    """Read the event result; only the organiser and registered participants."""
    listing = await session.get(Listing, listing_id)
    if listing is None:
        raise ProblemError(NOT_FOUND)
    await require_event(listing)
    registered = await session.scalar(
        select(Interaction.id).where(
            Interaction.listing_id == listing.id,
            Interaction.participant_id == viewer_id,
            Interaction.status.in_(REGISTERED_EVENT_STATUSES),
        )
    )
    if listing.author_id != viewer_id and registered is None:
        raise ProblemError(EVENT_NO_SHOW_FORBIDDEN)
    return await event_no_show_state(session, listing, settings)


async def arm_no_show_timer(
    session: AsyncSession,
    settings: Settings,
    listing: Listing,
    interaction: Interaction,
    meeting: Meeting | None,
) -> None:
    """Arm the durable no-show timer of a meeting or an event.

    Used by the listing module from its meeting and event flows; a repeated
    call replaces the pending timer of the same key, so a rescheduled meeting
    moves its own deadline.
    """
    if listing.kind == "event":
        if listing.event_ends_at is None:
            return
        await schedule_deadline(
            session,
            EVENT_NO_SHOW_TOPIC,
            listing.event_ends_at + settings.event_no_show_after,
            {"listing_id": str(listing.id)},
            key=event_no_show_key(listing.id),
        )
        return
    if listing.kind not in QR_COMPLETION_KINDS:
        return
    scheduled_at = None if meeting is None else meeting.scheduled_at
    if scheduled_at is None:
        return
    await schedule_deadline(
        session,
        PERSONAL_NO_SHOW_TOPIC,
        scheduled_at + settings.no_show_auto_after,
        {
            "listing_id": str(listing.id),
            "interaction_id": str(interaction.id),
            "time": scheduled_at.isoformat(),
        },
        key=no_show_key(interaction.id),
    )


async def disarm_no_show_timer(
    session: AsyncSession, listing: Listing, interaction: Interaction
) -> None:
    """Drop the personal timer of an interaction that can no longer fire."""
    if listing.kind in QR_COMPLETION_KINDS:
        await cancel_deadline(session, no_show_key(interaction.id))


@deadline_handlers.register(PERSONAL_NO_SHOW_TOPIC)
async def auto_no_show(session: AsyncSession, job: JobInfo) -> None:
    """Turn an unmarked personal interaction into "did not take place"."""
    listing = await locked(session, UUID(job.payload["listing_id"]))
    settings = get_settings()
    if listing.kind == "event" or listing.kind not in QR_COMPLETION_KINDS:
        return
    interaction = await session.get(Interaction, UUID(job.payload["interaction_id"]))
    if interaction is None or interaction.status != InteractionStatus.ACCEPTED:
        return
    if interaction.stage is not None:
        # A staged scenario (the loan handover of #214) has its own rules;
        # the flat 7-day rule must not close an issued loan.
        return
    agreed = agreed_moment(interaction)
    if agreed is None or clock.now() < agreed + settings.no_show_auto_after:
        return
    await _transition_no_show(
        session,
        listing,
        interaction,
        None,
        settings,
        action="no_show_automatic",
        reason=None,
        details={"rule": "no_show_window", "time": agreed.isoformat()},
    )
    queue_no_show(
        session,
        listing,
        {
            "interaction_id": str(interaction.id),
            "kind": "automatic",
            "status": "not_held",
        },
        {listing.author_id, interaction.participant_id},
    )


@deadline_handlers.register(EVENT_NO_SHOW_TOPIC)
async def auto_event_no_show(session: AsyncSession, job: JobInfo) -> None:
    """Judge the attendance of an ended event 24 hours later.

    A registered participant the organiser did not mark becomes
    "did not take place" with a no-show; if the organiser marked nobody, the
    participants still lose the interaction but get no no-show. An event the
    participants declared not held charges nobody but the organiser.
    """
    listing = await locked(session, UUID(job.payload["listing_id"]))
    settings = get_settings()
    if listing.kind != "event" or listing.event_ends_at is None:
        return
    if listing.status == ListingStatus.CANCELLED:
        return
    if clock.now() < listing.event_ends_at + settings.event_no_show_after:
        return
    interactions = await _accepted_interactions(session, listing.id)
    if not interactions:
        return
    state = await event_no_show_state(session, listing, settings)
    if state.not_held:
        for interaction in interactions:
            await _transition_no_show(
                session,
                listing,
                interaction,
                None,
                settings,
                action="no_show_automatic",
                reason=None,
                details={"rule": "event_not_held"},
            )
        queue_no_show(
            session,
            listing,
            {"kind": "automatic", "status": "not_held", "rule": "event_not_held"},
            {listing.author_id} | {item.participant_id for item in interactions},
        )
        return
    marked = await current_attendance_participant_ids(session, listing.id)
    now = clock.now()
    for interaction in interactions:
        if interaction.participant_id in marked:
            continue
        await _transition_no_show(
            session,
            listing,
            interaction,
            None,
            settings,
            action="no_show_automatic",
            reason=None,
            details={"rule": "event_end", "organizer_marked": bool(marked)},
        )
        if marked:
            session.add(
                NoShowMark(
                    listing_id=listing.id,
                    interaction_id=interaction.id,
                    reporter_id=None,
                    subject_id=interaction.participant_id,
                    kind=NoShowKind.EVENT_AUTO.value,
                    status=NoShowStatus.COUNTED.value,
                    reason=None,
                    disputed_at=None,
                    removed_at=None,
                    removed_by_id=None,
                    created_at=now,
                    updated_at=now,
                )
            )
    queue_no_show(
        session,
        listing,
        {
            "kind": NoShowKind.EVENT_AUTO.value if marked else "automatic",
            "status": "marked" if marked else "not_held",
            "rule": "event_end",
        },
        {listing.author_id} | {item.participant_id for item in interactions},
    )


def queue_no_show(
    session: AsyncSession,
    listing: Listing,
    payload: dict[str, Any],
    recipients: set[UUID],
) -> None:
    """Queue a metadata-only realtime wakeup in the transaction of the change.

    The payload never carries a reason or another user-written text: realtime
    is only a hint that a committed change exists, and the client reloads the
    authoritative state through the API.
    """
    add_message(
        session,
        NO_SHOW_TOPIC,
        {
            "listing_id": str(listing.id),
            "version": listing.version,
            "occurred_at": clock.now().isoformat(),
            "recipients": sorted(str(value) for value in recipients),
            **payload,
        },
    )


@outbox_handlers.register(NO_SHOW_TOPIC)
async def _publish_no_show(_session: AsyncSession, job: JobInfo) -> None:
    """Publish the committed wakeup to the personal channel of each recipient."""
    from campus.modules.realtime import publish_personal  # noqa: PLC0415

    payload = dict(job.payload)
    recipients = [UUID(str(value)) for value in payload.pop("recipients", [])]
    for recipient in recipients:
        await publish_personal(recipient, payload, uuid5(job.id, str(recipient)))


__all__ = [
    "EVENT_NO_SHOW_TOPIC",
    "NO_SHOW_TOPIC",
    "PERSONAL_NO_SHOW_TOPIC",
    "EventNoShowState",
    "NoShowState",
    "agreed_moment",
    "arm_no_show_timer",
    "auto_event_no_show",
    "auto_no_show",
    "disarm_no_show_timer",
    "dispute_event_no_show",
    "event_no_show_state",
    "event_result",
    "mark_no_show",
    "no_show_state",
    "vote_event_not_held",
]
