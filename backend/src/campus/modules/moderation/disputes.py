"""Dispute cases and moderator decisions (specification, module 8, item 6).

A case is opened by a participant within seven days of the disputed event,
not within seven days of the start of the interaction:

- a personal no-show mark against the participant (the loan's "not
  returned" mark is its own subject);
- an event no-show vote that charged the organiser (opened by the
  organiser through the event endpoint);
- an unanswered payment mark of a fixed group purchase share, after the
  configured wait and within the configured window (#54, #94).

The opening suspends the marks, so nothing is counted until a moderator
decides. The decision is one-shot and versioned: two moderators cannot
overwrite each other, and a decided case answers 409. The decision applies
the primary change, the interaction journal, the audit record, the profile
recalculation and the notification outbox in one transaction; the outbox
handlers are idempotent, so a repeated delivery cannot multiply the effect.

The table of actions per subject is :data:`DISPUTE_ACTIONS_BY_KIND`; an
action that does not fit the subject is a 422, a terminal repeat is a 409.
"""

from dataclasses import dataclass
from datetime import datetime
from typing import Any
from uuid import UUID, uuid5

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from campus.core import clock
from campus.core.audit import record_action
from campus.core.config import Settings
from campus.core.i18n import N_
from campus.core.jobs import JobInfo
from campus.core.outbox import add_message, outbox_handlers
from campus.core.web import ProblemError, ProblemType
from campus.core.web.problems import NOT_FOUND
from campus.modules.listings import (
    CompletionMethod,
    Interaction,
    InteractionStatus,
    Listing,
    PaymentClaim,
    append_event,
    cancel_return_reminder,
    latest_claim,
    locked,
    resolve_payment_claim,
    suspend_payment_claim,
    transition,
)
from campus.modules.moderation.models import (
    DISPUTE_ACTIONS_BY_KIND,
    Dispute,
    DisputeAction,
    DisputeKind,
    DisputeStatus,
)
from campus.modules.notifications import (
    DISPUTE_OPENED,
    notify,
)
from campus.modules.notifications import (
    DISPUTE_RESOLVED as DISPUTE_RESOLVED_MESSAGE,
)

DISPUTE_TOPIC = "moderation.dispute"

# Registered signups of an event whose no-show case affects them; the same
# set the event no-show rules of #66 count as registered.
EVENT_PARTICIPANT_STATUSES = (
    InteractionStatus.ACCEPTED,
    InteractionStatus.COMPLETED,
    InteractionStatus.NO_SHOW,
)

DISPUTE_FORBIDDEN = ProblemType(
    "dispute_forbidden",
    403,
    N_("Forbidden"),
    N_("Only a participant of the interaction or the event can open its dispute."),
)
DISPUTE_UNAVAILABLE = ProblemType(
    "dispute_unavailable",
    409,
    N_("Nothing to dispute"),
    N_(
        "A dispute is opened about a no-show mark against you, a 'not"
        " returned' mark of your loan, or an unanswered payment mark."
    ),
)
DISPUTE_TOO_EARLY = ProblemType(
    "dispute_too_early",
    409,
    N_("The dispute cannot be opened yet"),
    N_(
        "The organiser still has the configured wait to answer the payment"
        " mark before the dispute opens."
    ),
)
DISPUTE_CLOSED = ProblemType(
    "dispute_closed",
    409,
    N_("The dispute window has closed"),
    N_("A dispute is opened within 7 days after the disputed event."),
)
DISPUTE_KIND_INVALID = ProblemType(
    "dispute_kind_invalid",
    422,
    N_("The dispute kind does not fit"),
    N_("The requested kind does not match the disputed event and its participants."),
)
DISPUTE_ACTION_INVALID = ProblemType(
    "dispute_action_invalid",
    422,
    N_("The action does not fit the subject"),
    N_("Choose an action that applies to this kind of dispute."),
)
DISPUTE_REASON_INVALID = ProblemType(
    "dispute_reason_invalid",
    422,
    N_("Invalid decision reason"),
    N_("Describe the decision in 1 to {max} characters."),
)
DISPUTE_STATE = ProblemType(
    "dispute_state_conflict",
    409,
    N_("The dispute cannot be decided"),
    N_("The disputed interaction is no longer in a state this action applies to."),
)
DISPUTE_ALREADY_RESOLVED = ProblemType(
    "dispute_resolved",
    409,
    N_("The dispute is already decided"),
    N_("A decided dispute cannot be decided again."),
)
DISPUTE_VERSION_CONFLICT = ProblemType(
    "dispute_version_conflict",
    409,
    N_("The dispute was decided by someone else"),
    N_("Reload the dispute. Its current version is {version}."),
)


class DisputeVersionConflictError(ProblemError):
    """A moderator decided a case from a stale version."""

    def __init__(self, current_version: int) -> None:
        super().__init__(DISPUTE_VERSION_CONFLICT, params={"version": current_version})
        self.current_version = current_version


@dataclass(frozen=True, slots=True)
class OpenedCase:
    """A case and whether this call created it or returned an existing one."""

    dispute: Dispute
    created: bool


def normalize_reason(reason: str | None, settings: Settings) -> str:
    """Normalize the required justification of an opening or a decision."""
    normalized = (reason or "").strip()
    if not normalized or len(normalized) > settings.dispute_reason_max_length:
        raise ProblemError(
            DISPUTE_REASON_INVALID, max=settings.dispute_reason_max_length
        )
    return normalized


def queue_profile_refresh(session: AsyncSession, users: set[UUID]) -> None:
    """Queue the profile recalculation without a module import cycle."""
    from campus.modules.reputation import (  # noqa: PLC0415
        queue_profile_refresh as enqueue,
    )

    enqueue(session, users)


async def _participant_ids(
    session: AsyncSession, dispute: Dispute, listing: Listing
) -> set[UUID]:
    """Every party of the case, loaded from the case itself for the audit."""
    if dispute.interaction_id is not None:
        interaction = await session.get(Interaction, dispute.interaction_id)
        if interaction is None:
            raise ProblemError(NOT_FOUND)
        return {listing.author_id, interaction.participant_id}
    registered = await session.scalars(
        select(Interaction.participant_id).where(
            Interaction.listing_id == listing.id,
            Interaction.status.in_(EVENT_PARTICIPANT_STATUSES),
        )
    )
    return {listing.author_id} | set(registered)


async def case_participants(
    session: AsyncSession, dispute: Dispute, listing: Listing
) -> set[UUID]:
    """Public alias of the party ids; also used for the notification outbox."""
    return await _participant_ids(session, dispute, listing)


def _opening_notification(
    session: AsyncSession,
    dispute: Dispute,
    participants: set[UUID],
) -> None:
    notify(
        session,
        participants,
        "moderation.decided",
        {
            "dispute_id": str(dispute.id),
            "listing_id": str(dispute.listing_id),
            "interaction_id": (
                None if dispute.interaction_id is None else str(dispute.interaction_id)
            ),
            "kind": dispute.kind,
            "status": DisputeStatus.OPEN.value,
        },
        message=DISPUTE_OPENED,
        event_id=uuid5(dispute.id, "opened"),
    )


def _decision_notification(
    session: AsyncSession,
    dispute: Dispute,
    participants: set[UUID],
) -> None:
    notify(
        session,
        participants,
        "moderation.decided",
        {
            "dispute_id": str(dispute.id),
            "listing_id": str(dispute.listing_id),
            "interaction_id": (
                None if dispute.interaction_id is None else str(dispute.interaction_id)
            ),
            "kind": dispute.kind,
            "status": DisputeStatus.RESOLVED.value,
            "action": dispute.action,
        },
        message=DISPUTE_RESOLVED_MESSAGE,
        event_id=uuid5(dispute.id, f"decision-{dispute.version}"),
    )


def queue_dispute(
    session: AsyncSession, dispute: Dispute, participants: set[UUID]
) -> None:
    """Queue a metadata-only realtime wakeup in the decision transaction."""
    add_message(
        session,
        DISPUTE_TOPIC,
        {
            "dispute_id": str(dispute.id),
            "listing_id": str(dispute.listing_id),
            "interaction_id": (
                None if dispute.interaction_id is None else str(dispute.interaction_id)
            ),
            "kind": dispute.kind,
            "status": dispute.status,
            "version": dispute.version,
            "occurred_at": clock.now().isoformat(),
            "recipients": sorted(str(value) for value in participants),
        },
    )


async def case_marks(session: AsyncSession, dispute: Dispute) -> list[Any]:
    """The marks the decision applies to; a payment case has none."""
    from campus.modules.reputation import NoShowMark  # noqa: PLC0415

    if dispute.kind == DisputeKind.PAYMENT.value:
        return []
    if dispute.interaction_id is not None:
        return list(
            await session.scalars(
                select(NoShowMark)
                .where(NoShowMark.interaction_id == dispute.interaction_id)
                .order_by(NoShowMark.created_at, NoShowMark.id)
            )
        )
    return list(
        await session.scalars(
            select(NoShowMark).where(
                NoShowMark.listing_id == dispute.listing_id,
                NoShowMark.interaction_id.is_(None),
            )
        )
    )


async def case_claim(session: AsyncSession, dispute: Dispute) -> PaymentClaim | None:
    if dispute.payment_claim_id is None:
        return None
    return await session.get(PaymentClaim, dispute.payment_claim_id)


async def _existing_interaction_case(
    session: AsyncSession, interaction_id: UUID
) -> Dispute | None:
    return await session.scalar(
        select(Dispute).where(
            Dispute.interaction_id == interaction_id,
            Dispute.kind.in_(
                (DisputeKind.NO_SHOW.value, DisputeKind.NOT_RETURNED.value)
            ),
        )
    )


async def _existing_claim_case(session: AsyncSession, claim_id: UUID) -> Dispute | None:
    return await session.scalar(
        select(Dispute).where(Dispute.payment_claim_id == claim_id)
    )


def _return_existing(dispute: Dispute) -> OpenedCase:
    if dispute.status == DisputeStatus.RESOLVED.value:
        raise ProblemError(DISPUTE_CLOSED)
    return OpenedCase(dispute=dispute, created=False)


async def _open_no_show_case(  # noqa: PLR0913, PLR0917 - an opening
    session: AsyncSession,
    listing: Listing,
    interaction: Interaction,
    actor_id: UUID,
    kind: DisputeKind,
    statement: str,
    settings: Settings,
) -> OpenedCase:
    from campus.modules.reputation import (  # noqa: PLC0415
        LOAN_NOT_RETURNED_REASON,
        NoShowKind,
        NoShowMark,
        NoShowStatus,
    )

    existing = await _existing_interaction_case(session, interaction.id)
    if existing is not None:
        return _return_existing(existing)
    marks = list(
        await session.scalars(
            select(NoShowMark)
            .where(NoShowMark.interaction_id == interaction.id)
            .order_by(NoShowMark.created_at, NoShowMark.id)
        )
    )
    against = [
        mark
        for mark in marks
        if mark.kind == NoShowKind.PERSONAL.value
        and mark.status == NoShowStatus.COUNTED.value
        and mark.subject_id == actor_id
    ]
    if not against:
        raise ProblemError(DISPUTE_UNAVAILABLE)
    expected = (
        DisputeKind.NOT_RETURNED
        if any(mark.reason == LOAN_NOT_RETURNED_REASON for mark in against)
        else DisputeKind.NO_SHOW
    )
    if kind != expected:
        raise ProblemError(DISPUTE_KIND_INVALID)
    event_at = min(mark.created_at for mark in against)
    now = clock.now()
    if now > event_at + settings.no_show_dispute_window:
        raise ProblemError(DISPUTE_CLOSED)
    await session.execute(
        update(NoShowMark)
        .where(
            NoShowMark.interaction_id == interaction.id,
            NoShowMark.status == NoShowStatus.COUNTED.value,
        )
        .values(
            status=NoShowStatus.DISPUTED.value,
            disputed_at=now,
            updated_at=now,
        )
    )
    dispute = Dispute(
        kind=kind.value,
        status=DisputeStatus.OPEN.value,
        listing_id=listing.id,
        interaction_id=interaction.id,
        opened_by_id=actor_id,
        event_at=event_at,
        opened_at=now,
        statement=statement,
        version=1,
    )
    session.add(dispute)
    await session.flush()
    listing.version += 1
    append_event(
        session,
        listing,
        actor_id,
        "dispute_opened",
        interaction.status,
        interaction,
        reason=statement,
        details={
            "dispute_id": str(dispute.id),
            "kind": kind.value,
            "mark_ids": [str(mark.id) for mark in against],
        },
    )
    participants = await _participant_ids(session, dispute, listing)
    queue_profile_refresh(session, participants)
    _opening_notification(session, dispute, participants)
    queue_dispute(session, dispute, participants)
    await session.flush()
    return OpenedCase(dispute=dispute, created=True)


async def _open_payment_case(  # noqa: PLR0913, PLR0917 - an opening
    session: AsyncSession,
    listing: Listing,
    interaction: Interaction,
    actor_id: UUID,
    statement: str,
    settings: Settings,
) -> OpenedCase:
    if listing.kind != "purchase":
        raise ProblemError(DISPUTE_KIND_INVALID)
    if actor_id != interaction.participant_id:
        raise ProblemError(DISPUTE_FORBIDDEN)
    claim = await latest_claim(session, interaction.id, for_update=True)
    if claim is None:
        raise ProblemError(DISPUTE_UNAVAILABLE)
    existing = await _existing_claim_case(session, claim.id)
    if existing is not None:
        return _return_existing(existing)
    if claim.status != "claimed":
        raise ProblemError(DISPUTE_UNAVAILABLE)
    now = clock.now()
    available_at = claim.claimed_at + settings.payment_dispute_after
    if now < available_at:
        raise ProblemError(DISPUTE_TOO_EARLY, available_at=available_at)
    if now > claim.claimed_at + settings.payment_dispute_window:
        raise ProblemError(DISPUTE_CLOSED)
    await suspend_payment_claim(session, claim, now)
    dispute = Dispute(
        kind=DisputeKind.PAYMENT.value,
        status=DisputeStatus.OPEN.value,
        listing_id=listing.id,
        interaction_id=interaction.id,
        payment_claim_id=claim.id,
        opened_by_id=actor_id,
        event_at=claim.claimed_at,
        opened_at=now,
        statement=statement,
        version=1,
    )
    session.add(dispute)
    await session.flush()
    listing.version += 1
    append_event(
        session,
        listing,
        actor_id,
        "payment_disputed",
        interaction.status,
        interaction,
        reason=statement,
        details={
            "dispute_id": str(dispute.id),
            "claim_id": str(claim.id),
            "kind": DisputeKind.PAYMENT.value,
        },
    )
    participants = await _participant_ids(session, dispute, listing)
    _opening_notification(session, dispute, participants)
    queue_dispute(session, dispute, participants)
    await session.flush()
    return OpenedCase(dispute=dispute, created=True)


async def open_dispute(  # noqa: PLR0913, PLR0917 - request context
    session: AsyncSession,
    listing_id: UUID,
    interaction_id: UUID | None,
    actor_id: UUID,
    kind: DisputeKind,
    reason: str | None,
    settings: Settings,
) -> OpenedCase:
    """Open one case about a disputed event; a duplicate returns the open one."""
    if kind == DisputeKind.PAYMENT:
        if interaction_id is None:
            raise ProblemError(DISPUTE_UNAVAILABLE)
    elif kind not in (DisputeKind.NO_SHOW, DisputeKind.NOT_RETURNED):
        raise ProblemError(DISPUTE_KIND_INVALID)
    listing = await locked(session, listing_id)
    if kind == DisputeKind.NO_SHOW and listing.kind == "event":
        raise ProblemError(DISPUTE_KIND_INVALID)
    if interaction_id is None:
        raise ProblemError(DISPUTE_UNAVAILABLE)
    interaction = await session.get(Interaction, interaction_id)
    if interaction is None or interaction.listing_id != listing.id:
        raise ProblemError(NOT_FOUND)
    if actor_id not in (listing.author_id, interaction.participant_id):
        raise ProblemError(DISPUTE_FORBIDDEN)
    statement = normalize_reason(reason, settings)
    if kind == DisputeKind.PAYMENT:
        return await _open_payment_case(
            session, listing, interaction, actor_id, statement, settings
        )
    return await _open_no_show_case(
        session, listing, interaction, actor_id, kind, statement, settings
    )


async def _remove_marks(
    session: AsyncSession,
    marks: list[Any],
    actor_id: UUID,
    now: datetime,
) -> list[UUID]:
    from campus.modules.reputation import (  # noqa: PLC0415
        NoShowMark,
        NoShowStatus,
    )

    removed: list[UUID] = []
    for mark in marks:
        if mark.status == NoShowStatus.REMOVED.value:
            continue
        await session.execute(
            update(NoShowMark)
            .where(NoShowMark.id == mark.id)
            .values(
                status=NoShowStatus.REMOVED.value,
                disputed_at=None,
                removed_at=now,
                removed_by_id=actor_id,
                updated_at=now,
            )
        )
        removed.append(mark.id)
    return removed


async def _restore_marks(
    session: AsyncSession, marks: list[Any], now: datetime
) -> list[UUID]:
    from campus.modules.reputation import (  # noqa: PLC0415
        NoShowMark,
        NoShowStatus,
    )

    restored: list[UUID] = []
    for mark in marks:
        if mark.status == NoShowStatus.DISPUTED.value:
            await session.execute(
                update(NoShowMark)
                .where(NoShowMark.id == mark.id)
                .values(
                    status=NoShowStatus.COUNTED.value,
                    disputed_at=None,
                    updated_at=now,
                )
            )
            restored.append(mark.id)
    return restored


def _require_interaction(dispute: Dispute) -> UUID:
    if dispute.interaction_id is None:
        raise ProblemError(DISPUTE_ACTION_INVALID)
    return dispute.interaction_id


async def _apply_decision(  # noqa: PLR0912, PLR0913, PLR0917 - the decision
    session: AsyncSession,
    dispute: Dispute,
    listing: Listing,
    interaction: Interaction | None,
    action: DisputeAction,
    actor_id: UUID,
    reason: str,
    settings: Settings,
) -> None:
    now = clock.now()
    marks = await case_marks(session, dispute)
    if action == DisputeAction.KEEP:
        await _restore_marks(session, marks, now)
        listing.version += 1
    elif action == DisputeAction.LIFT_NO_SHOW:
        await _remove_marks(session, marks, actor_id, now)
        if interaction is not None:
            if interaction.status == InteractionStatus.COMPLETED.value:
                pass
            elif interaction.status != InteractionStatus.NO_SHOW.value:
                raise ProblemError(DISPUTE_STATE)
        listing.version += 1
    elif action == DisputeAction.COMPLETE:
        await _remove_marks(session, marks, actor_id, now)
        if interaction is None:
            raise ProblemError(DISPUTE_ACTION_INVALID)
        if interaction.status == InteractionStatus.COMPLETED.value:
            listing.version += 1
        elif interaction.status == InteractionStatus.NO_SHOW.value:
            await transition(
                session,
                listing,
                interaction,
                InteractionStatus.COMPLETED,
                actor_id,
                settings=settings,
                completion_method=CompletionMethod.MODERATOR,
                action="dispute_completed",
                details={"rule": "moderator_decision", "dispute_id": str(dispute.id)},
                reason=reason,
                moderator=True,
            )
            # A not-returned loan is complete only when its item came back.
            interaction.return_due_at = None
            await cancel_return_reminder(session, interaction)
        else:
            raise ProblemError(DISPUTE_STATE)
    elif action in (DisputeAction.CONFIRM_PAYMENT, DisputeAction.REJECT_PAYMENT):
        claim = await case_claim(session, dispute)
        if claim is None:
            raise ProblemError(DISPUTE_STATE)
        await resolve_payment_claim(
            session,
            claim,
            actor_id,
            approve=action == DisputeAction.CONFIRM_PAYMENT,
            now=now,
        )
        listing.version += 1
        append_event(
            session,
            listing,
            actor_id,
            "payment_decided",
            interaction.status if interaction is not None else listing.status,
            interaction,
            reason=reason,
            details={
                "dispute_id": str(dispute.id),
                "claim_id": str(claim.id),
                "status": claim.status,
                "decision": action.value,
            },
        )
    else:  # pragma: no cover - the action table rejects every other value
        raise ProblemError(DISPUTE_ACTION_INVALID)


async def decide_dispute(  # noqa: PLR0913, PLR0917 - the decision request
    session: AsyncSession,
    dispute_id: UUID,
    actor_id: UUID,
    action: DisputeAction,
    reason: str | None,
    version: int,
    settings: Settings,
) -> Dispute:
    """Apply one decision under the case and listing locks; 409 on a stale one."""
    listing_id = await session.scalar(
        select(Dispute.listing_id).where(Dispute.id == dispute_id)
    )
    if listing_id is None:
        raise ProblemError(NOT_FOUND)
    listing = await locked(session, listing_id)
    # populate_existing: a prior read in this session must not hide the
    # version written by the transaction that held the lock before us.
    dispute = await session.scalar(
        select(Dispute)
        .where(Dispute.id == dispute_id)
        .with_for_update()
        .execution_options(populate_existing=True)
    )
    if dispute is None:
        raise ProblemError(NOT_FOUND)
    if dispute.version != version:
        raise DisputeVersionConflictError(dispute.version)
    if dispute.status != DisputeStatus.OPEN.value:
        raise ProblemError(DISPUTE_ALREADY_RESOLVED)
    allowed = DISPUTE_ACTIONS_BY_KIND.get(dispute.kind, frozenset())
    if action not in allowed:
        raise ProblemError(DISPUTE_ACTION_INVALID)
    normalized = normalize_reason(reason, settings)
    interaction = (
        None
        if dispute.interaction_id is None
        else await session.get(Interaction, dispute.interaction_id)
    )
    if interaction is None and dispute.interaction_id is not None:
        raise ProblemError(NOT_FOUND)
    participants = await _participant_ids(session, dispute, listing)
    before = {"status": dispute.status, "version": dispute.version, "action": None}
    await _apply_decision(
        session,
        dispute,
        listing,
        interaction,
        action,
        actor_id,
        normalized,
        settings,
    )
    dispute.status = DisputeStatus.RESOLVED.value
    dispute.resolved_at = clock.now()
    dispute.action = action.value
    dispute.resolution = normalized
    dispute.resolved_by_id = actor_id
    dispute.version += 1
    dispute.updated_at = dispute.resolved_at
    append_event(
        session,
        listing,
        actor_id,
        "dispute_resolved",
        interaction.status if interaction is not None else listing.status,
        interaction,
        reason=normalized,
        details={
            "dispute_id": str(dispute.id),
            "kind": dispute.kind,
            "decision": action.value,
            "version": dispute.version,
        },
    )
    await record_action(
        session,
        actor_id=actor_id,
        action="moderation.dispute.resolve",
        object_type="dispute",
        object_id=dispute.id,
        reason=normalized,
        participant_ids=participants,
        before=before,
        after={
            "status": dispute.status,
            "version": dispute.version,
            "action": dispute.action,
        },
        details={
            "kind": dispute.kind,
            "listing_id": str(dispute.listing_id),
            "interaction_id": (
                None if dispute.interaction_id is None else str(dispute.interaction_id)
            ),
        },
    )
    if dispute.kind in (
        DisputeKind.NO_SHOW.value,
        DisputeKind.NOT_RETURNED.value,
    ):
        queue_profile_refresh(session, participants)
    _decision_notification(session, dispute, participants)
    queue_dispute(session, dispute, participants)
    await session.flush()
    return dispute


@outbox_handlers.register(DISPUTE_TOPIC)
async def _publish_dispute(_session: AsyncSession, job: JobInfo) -> None:
    """Publish the committed wakeup to the personal channel of each party."""
    from campus.modules.realtime import publish_personal  # noqa: PLC0415

    payload = dict(job.payload)
    recipients = [UUID(str(value)) for value in payload.pop("recipients", [])]
    for recipient in recipients:
        await publish_personal(recipient, payload, uuid5(job.id, str(recipient)))


__all__ = [
    "DISPUTE_ACTION_INVALID",
    "DISPUTE_ALREADY_RESOLVED",
    "DISPUTE_CLOSED",
    "DISPUTE_FORBIDDEN",
    "DISPUTE_KIND_INVALID",
    "DISPUTE_REASON_INVALID",
    "DISPUTE_STATE",
    "DISPUTE_TOO_EARLY",
    "DISPUTE_TOPIC",
    "DISPUTE_UNAVAILABLE",
    "DISPUTE_VERSION_CONFLICT",
    "DisputeVersionConflictError",
    "OpenedCase",
    "case_claim",
    "case_marks",
    "case_participants",
    "decide_dispute",
    "normalize_reason",
    "open_dispute",
    "queue_dispute",
]
