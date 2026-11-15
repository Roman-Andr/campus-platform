"""Event attendance: rotating codes, marks and their transactional events.

An event is marked by one of the two modes its organiser chose:

- ``self``: a registered participant scans the organiser's rotating code;
- ``scan``: the organiser scans a registered participant's rotating code.

The window is inclusive on both ends: from ``starts_at`` minus
``CAMPUS_EVENT_ATTENDANCE_OPENS_BEFORE`` until ``ends_at``. Codes are
stateless HMAC-SHA256 tokens signed with a key derived from the auth secret,
so one nonce is deliberately reusable: the same organiser code marks many
participants, while the unique (listing, participant) row keeps a repeat or
a parallel scan of one participant from adding a second mark.

Every mutation locks the listing aggregate first, like signups and
cancellations, so a mode switch, a signup and a mark serialize. The
attendance journal entry and the realtime outbox message are written in the
same transaction as the mark; the list endpoint is the authoritative way to
recover after a missed realtime publication.

The contract for the future no-show feature (#66): one row per participant,
``removed_at IS NULL`` means currently marked, and
:func:`current_attendance_participant_ids` returns only participants with an
accepted signup and an active mark. An empty set means the organiser marked
nobody, so no participant receives a no-show.
"""

import hashlib
import hmac
import json
from dataclasses import dataclass
from datetime import datetime
from typing import Literal
from uuid import UUID, uuid4

from pydantic import AwareDatetime, BaseModel, ConfigDict, ValidationError
from sqlalchemy import and_, select
from sqlalchemy.ext.asyncio import AsyncSession

from campus.core import clock
from campus.core.config import Settings
from campus.core.i18n import N_
from campus.core.jobs import JobInfo
from campus.core.outbox import add_message, outbox_handlers
from campus.core.web import ProblemError, ProblemType
from campus.core.web.auth import secret
from campus.core.web.problems import NOT_FOUND
from campus.modules.listings import (
    AttendanceMode,
    Interaction,
    InteractionStatus,
    Listing,
    ListingStatus,
    append_event,
    locked,
)
from campus.modules.reputation.models import AttendanceRecord
from campus.modules.reputation.service import base64url_decode, base64url_encode

ATTENDANCE_TOPIC = "listing.attendance"
ATTENDANCE_CODE_KIND: Literal["event_attendance"] = "event_attendance"
ATTENDANCE_CODE_VERSION: Literal[1] = 1
_SIGNATURE_SIZE = 32
_SIGNING_CONTEXT = b"campus/event-attendance/v1"
_CODE_MAX_LENGTH = 1024

ATTENDANCE_FORBIDDEN = ProblemType(
    "event_attendance_forbidden",
    403,
    N_("Forbidden"),
    N_("Only the organiser of this event can do this."),
)
ATTENDANCE_NOT_REGISTERED = ProblemType(
    "event_attendance_not_registered",
    403,
    N_("Not registered"),
    N_("Only a participant registered for this event can be marked."),
)
ATTENDANCE_CLOSED = ProblemType(
    "event_attendance_closed",
    409,
    N_("Attendance is closed"),
    N_(
        "Attendance opens {minutes} minutes before the event starts and"
        " closes when the event ends."
    ),
)
ATTENDANCE_UNAVAILABLE = ProblemType(
    "event_attendance_unavailable",
    409,
    N_("Attendance is unavailable"),
    N_("Only an event has attendance."),
)
ATTENDANCE_MODE_CONFLICT = ProblemType(
    "event_attendance_mode_conflict",
    409,
    N_("Wrong attendance mode"),
    N_("This code belongs to the other attendance mode of the event."),
)
ATTENDANCE_CODE_INVALID = ProblemType(
    "event_attendance_code_invalid",
    422,
    N_("Attendance code rejected"),
    N_("The code is malformed or belongs to another event or participant."),
)
ATTENDANCE_CODE_EXPIRED = ProblemType(
    "event_attendance_code_expired",
    409,
    N_("Attendance code expired"),
    N_("Request a new rotating attendance code."),
)
ATTENDANCE_NOT_FOUND = ProblemType(
    "event_attendance_not_found",
    404,
    N_("Attendance mark not found"),
    N_("This participant has no mark at the event."),
)


class AttendanceCodePayload(BaseModel):
    """The signed document carried by a rotating attendance code."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    v: Literal[1]
    kind: Literal["event_attendance"]
    listing_id: UUID
    mode: AttendanceMode
    # The organiser for a self-mark code, the participant for a scan code.
    subject_id: UUID
    nonce: UUID
    issued_at: AwareDatetime


@dataclass(frozen=True, slots=True)
class IssuedAttendanceCode:
    listing_id: UUID
    mode: AttendanceMode
    code: str
    issued_at: datetime
    expires_at: datetime


@dataclass(frozen=True, slots=True)
class AttendanceResult:
    listing_id: UUID
    record: AttendanceRecord
    result: Literal["marked", "already_marked", "removed", "already_removed"]
    version: int
    registered: bool


@dataclass(frozen=True, slots=True)
class AttendanceOverview:
    listing_id: UUID
    mode: AttendanceMode | None
    version: int
    records: list[AttendanceRecord]
    registered_ids: set[UUID]


def attendance_window(
    listing: Listing, settings: Settings
) -> tuple[datetime, datetime]:
    """The inclusive window in which attendance is accepted."""
    assert listing.event_starts_at is not None  # noqa: S101 - event listing
    assert listing.event_ends_at is not None  # noqa: S101 - event listing
    return (
        listing.event_starts_at - settings.event_attendance_opens_before,
        listing.event_ends_at,
    )


def require_attendance_open(
    listing: Listing, settings: Settings, now: datetime
) -> None:
    """Refuse marking outside the inclusive event window."""
    if listing.kind != "event":
        raise ProblemError(ATTENDANCE_UNAVAILABLE)
    # The window, not the transient status, defines the boundary: the expiry
    # job may run at the very end, while the end itself is still inclusive.
    if listing.status in (
        ListingStatus.CANCELLED,
        ListingStatus.COMPLETED,
        ListingStatus.DRAFT,
        ListingStatus.HIDDEN,
    ):
        raise ProblemError(ATTENDANCE_CLOSED, minutes=_opens_minutes(settings))
    opens_at, closes_at = attendance_window(listing, settings)
    if now < opens_at:
        raise ProblemError(
            ATTENDANCE_CLOSED,
            minutes=_opens_minutes(settings),
            available_at=opens_at,
        )
    if now > closes_at:
        raise ProblemError(ATTENDANCE_CLOSED, minutes=_opens_minutes(settings))


def _opens_minutes(settings: Settings) -> int:
    return int(settings.event_attendance_opens_before.total_seconds() // 60)


def current_mode(listing: Listing) -> AttendanceMode | None:
    if listing.event_attendance_mode is None:
        return None
    return AttendanceMode(listing.event_attendance_mode)


def _signing_key(settings: Settings) -> bytes:
    """Domain-separated attendance key derived from the auth secret."""
    return hmac.new(secret(settings), _SIGNING_CONTEXT, hashlib.sha256).digest()


def _encode_payload(payload: AttendanceCodePayload, settings: Settings) -> str:
    raw = json.dumps(
        payload.model_dump(mode="json"),
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode()
    signature = hmac.new(_signing_key(settings), raw, hashlib.sha256).digest()
    return f"{base64url_encode(raw)}.{base64url_encode(signature)}"


def decode_attendance_code(
    code: str, settings: Settings, now: datetime
) -> AttendanceCodePayload:
    """Verify the code signature and lifetime; raise the matching problem."""
    if not code or len(code) > _CODE_MAX_LENGTH:
        raise ProblemError(ATTENDANCE_CODE_INVALID)
    encoded, _, signature = code.partition(".")
    try:
        if not signature:
            raise ValueError
        raw = base64url_decode(encoded, maximum=_CODE_MAX_LENGTH)
        supplied = base64url_decode(signature, maximum=128)
        if len(supplied) != _SIGNATURE_SIZE:
            raise ValueError
        expected = hmac.new(_signing_key(settings), raw, hashlib.sha256).digest()
        if not hmac.compare_digest(supplied, expected):
            raise ValueError
        payload = AttendanceCodePayload.model_validate_json(raw)
    except ValueError, ValidationError:
        raise ProblemError(ATTENDANCE_CODE_INVALID) from None
    if payload.issued_at > now:
        raise ProblemError(ATTENDANCE_CODE_INVALID)
    if now - payload.issued_at > settings.event_attendance_code_ttl:
        raise ProblemError(ATTENDANCE_CODE_EXPIRED)
    return payload


def _issue(
    listing: Listing,
    mode: AttendanceMode,
    subject_id: UUID,
    now: datetime,
    settings: Settings,
) -> IssuedAttendanceCode:
    expires_at = now + settings.event_attendance_code_ttl
    payload = AttendanceCodePayload(
        v=ATTENDANCE_CODE_VERSION,
        kind=ATTENDANCE_CODE_KIND,
        listing_id=listing.id,
        mode=mode,
        subject_id=subject_id,
        nonce=uuid4(),
        issued_at=now,
    )
    return IssuedAttendanceCode(
        listing_id=listing.id,
        mode=mode,
        code=_encode_payload(payload, settings),
        issued_at=now,
        expires_at=expires_at,
    )


async def issue_organizer_code(
    session: AsyncSession,
    listing_id: UUID,
    organizer_id: UUID,
    settings: Settings,
) -> IssuedAttendanceCode:
    """Issue the organiser's rotating self-mark code."""
    listing = await session.get(Listing, listing_id)
    if listing is None:
        raise ProblemError(NOT_FOUND)
    if listing.author_id != organizer_id:
        raise ProblemError(ATTENDANCE_FORBIDDEN)
    now = clock.now()
    require_attendance_open(listing, settings, now)
    if current_mode(listing) is not AttendanceMode.SELF:
        raise ProblemError(ATTENDANCE_MODE_CONFLICT)
    return _issue(listing, AttendanceMode.SELF, organizer_id, now, settings)


async def issue_participant_code(
    session: AsyncSession,
    listing_id: UUID,
    participant_id: UUID,
    settings: Settings,
) -> IssuedAttendanceCode:
    """Issue the personal rotating code the organiser scans."""
    listing = await session.get(Listing, listing_id)
    if listing is None:
        raise ProblemError(NOT_FOUND)
    now = clock.now()
    require_attendance_open(listing, settings, now)
    if current_mode(listing) is not AttendanceMode.SCAN:
        raise ProblemError(ATTENDANCE_MODE_CONFLICT)
    await accepted_interaction(session, listing.id, participant_id)
    return _issue(listing, AttendanceMode.SCAN, participant_id, now, settings)


async def accepted_interaction(
    session: AsyncSession, listing_id: UUID, participant_id: UUID
) -> Interaction:
    """The accepted event signup, or ``event_attendance_not_registered``."""
    interaction = await session.scalar(
        select(Interaction).where(
            Interaction.listing_id == listing_id,
            Interaction.participant_id == participant_id,
            Interaction.status == InteractionStatus.ACCEPTED,
        )
    )
    if interaction is None:
        raise ProblemError(ATTENDANCE_NOT_REGISTERED)
    return interaction


async def check_in_self(
    session: AsyncSession,
    listing_id: UUID,
    participant_id: UUID,
    code: str,
    settings: Settings,
) -> AttendanceResult:
    """Mark the authenticated participant from the organiser's scanned code."""
    now = clock.now()
    listing = await locked(session, listing_id)
    require_attendance_open(listing, settings, now)
    if current_mode(listing) is not AttendanceMode.SELF:
        raise ProblemError(ATTENDANCE_MODE_CONFLICT)
    payload = decode_attendance_code(code, settings, now)
    if (
        payload.listing_id != listing.id
        or payload.mode is not AttendanceMode.SELF
        or payload.subject_id != listing.author_id
    ):
        raise ProblemError(ATTENDANCE_CODE_INVALID)
    interaction = await accepted_interaction(session, listing.id, participant_id)
    return await record_mark(
        session,
        listing,
        interaction,
        participant_id,
        AttendanceMode.SELF,
        participant_id,
        now,
    )


async def scan_attendance(
    session: AsyncSession,
    listing_id: UUID,
    organizer_id: UUID,
    code: str,
    settings: Settings,
) -> AttendanceResult:
    """Mark the participant named by the personal code the organiser scanned."""
    now = clock.now()
    listing = await locked(session, listing_id)
    require_attendance_open(listing, settings, now)
    if listing.author_id != organizer_id:
        raise ProblemError(ATTENDANCE_FORBIDDEN)
    if current_mode(listing) is not AttendanceMode.SCAN:
        raise ProblemError(ATTENDANCE_MODE_CONFLICT)
    payload = decode_attendance_code(code, settings, now)
    if (
        payload.listing_id != listing.id
        or payload.mode is not AttendanceMode.SCAN
        or payload.subject_id == listing.author_id
    ):
        raise ProblemError(ATTENDANCE_CODE_INVALID)
    interaction = await accepted_interaction(session, listing.id, payload.subject_id)
    return await record_mark(
        session,
        listing,
        interaction,
        payload.subject_id,
        AttendanceMode.SCAN,
        organizer_id,
        now,
    )


async def record_mark(  # noqa: PLR0913, PLR0917 - one mark's inputs
    session: AsyncSession,
    listing: Listing,
    interaction: Interaction,
    participant_id: UUID,
    method: AttendanceMode,
    actor_id: UUID,
    now: datetime,
) -> AttendanceResult:
    """Store an idempotent mark under the locked listing aggregate."""
    record = await session.scalar(
        select(AttendanceRecord)
        .where(
            AttendanceRecord.listing_id == listing.id,
            AttendanceRecord.participant_id == participant_id,
        )
        .with_for_update()
    )
    if record is not None and record.removed_at is None:
        return AttendanceResult(
            listing_id=listing.id,
            record=record,
            result="already_marked",
            version=listing.version,
            registered=True,
        )
    if record is None:
        record = AttendanceRecord(
            listing_id=listing.id,
            participant_id=participant_id,
            interaction_id=interaction.id,
            method=method.value,
            marked_at=now,
            marked_by_id=actor_id,
        )
        session.add(record)
        created = True
    else:
        # A removed mark is re-activated in the same row: one participant
        # keeps exactly one attendance record for the whole event.
        record.interaction_id = interaction.id
        record.method = method.value
        record.marked_at = now
        record.marked_by_id = actor_id
        record.removed_at = None
        record.removed_by_id = None
        created = False
    listing.version += 1
    append_event(
        session,
        listing,
        actor_id,
        "attendance_marked",
        None,
        interaction,
        details={"method": method.value, "participant_id": str(participant_id)},
    )
    await session.flush()
    if created:
        # The participant relationship is eager on selects; a freshly
        # inserted row has no participant yet, and serializing the response
        # must not trigger a lazy load outside the async greenlet.
        await session.refresh(record, ["participant"])
    queue_attendance_event(session, listing, record, "marked")
    return AttendanceResult(
        listing_id=listing.id,
        record=record,
        result="marked",
        version=listing.version,
        registered=True,
    )


async def remove_attendance(
    session: AsyncSession,
    listing_id: UUID,
    organizer_id: UUID,
    participant_id: UUID,
) -> AttendanceResult:
    """Remove a participant's mark; only the event organiser may do it."""
    listing = await locked(session, listing_id)
    if listing.author_id != organizer_id:
        raise ProblemError(ATTENDANCE_FORBIDDEN)
    if listing.kind != "event":
        raise ProblemError(ATTENDANCE_UNAVAILABLE)
    record = await session.scalar(
        select(AttendanceRecord)
        .where(
            AttendanceRecord.listing_id == listing.id,
            AttendanceRecord.participant_id == participant_id,
        )
        .with_for_update()
    )
    if record is None:
        raise ProblemError(ATTENDANCE_NOT_FOUND)
    if record.removed_at is not None:
        interaction = await session.get(Interaction, record.interaction_id)
        return AttendanceResult(
            listing_id=listing.id,
            record=record,
            result="already_removed",
            version=listing.version,
            registered=(
                interaction is not None
                and interaction.status == InteractionStatus.ACCEPTED
            ),
        )
    now = clock.now()
    record.removed_at = now
    record.removed_by_id = organizer_id
    listing.version += 1
    interaction = await session.get(Interaction, record.interaction_id)
    append_event(
        session,
        listing,
        organizer_id,
        "attendance_removed",
        record.method,
        interaction,
        details={
            "method": record.method,
            "participant_id": str(participant_id),
        },
    )
    await session.flush()
    queue_attendance_event(session, listing, record, "removed")
    return AttendanceResult(
        listing_id=listing.id,
        record=record,
        result="removed",
        version=listing.version,
        registered=(
            interaction is not None and interaction.status == InteractionStatus.ACCEPTED
        ),
    )


async def set_attendance_mode(
    session: AsyncSession,
    listing_id: UUID,
    organizer_id: UUID,
    mode: AttendanceMode,
) -> tuple[Listing, bool]:
    """Switch the event's mode; taken marks stay untouched."""
    listing = await locked(session, listing_id)
    if listing.author_id != organizer_id:
        raise ProblemError(ATTENDANCE_FORBIDDEN)
    if listing.kind != "event":
        raise ProblemError(ATTENDANCE_UNAVAILABLE)
    previous = current_mode(listing)
    if previous is mode:
        return listing, False
    listing.event_attendance_mode = mode.value
    listing.version += 1
    append_event(
        session,
        listing,
        organizer_id,
        "attendance_mode_changed",
        previous.value if previous is not None else None,
        details={"mode": mode.value},
    )
    await session.flush()
    return listing, True


async def attendance_overview(
    session: AsyncSession, listing_id: UUID, organizer_id: UUID
) -> AttendanceOverview:
    """Every mark, including removed ones, for the organiser's recovery."""
    listing = await session.get(Listing, listing_id)
    if listing is None:
        raise ProblemError(NOT_FOUND)
    if listing.author_id != organizer_id:
        raise ProblemError(ATTENDANCE_FORBIDDEN)
    if listing.kind != "event":
        raise ProblemError(ATTENDANCE_UNAVAILABLE)
    records = list(
        await session.scalars(
            select(AttendanceRecord)
            .where(AttendanceRecord.listing_id == listing_id)
            .order_by(AttendanceRecord.marked_at, AttendanceRecord.id)
        )
    )
    registered = set(
        await session.scalars(
            select(Interaction.participant_id).where(
                Interaction.listing_id == listing_id,
                Interaction.status == InteractionStatus.ACCEPTED,
            )
        )
    )
    return AttendanceOverview(
        listing_id=listing.id,
        mode=current_mode(listing),
        version=listing.version,
        records=records,
        registered_ids=registered,
    )


async def current_attendance_participant_ids(
    session: AsyncSession, listing_id: UUID
) -> set[UUID]:
    """Participants registered now and marked now; the no-show contract (#66).

    A participant whose signup was cancelled is not registered any more, and
    a removed mark is not a mark. An empty result means the organiser marked
    nobody among the current signups.
    """
    rows = await session.scalars(
        select(AttendanceRecord.participant_id)
        .join(
            Interaction,
            and_(
                Interaction.listing_id == AttendanceRecord.listing_id,
                Interaction.participant_id == AttendanceRecord.participant_id,
                Interaction.status == InteractionStatus.ACCEPTED,
            ),
        )
        .where(
            AttendanceRecord.listing_id == listing_id,
            AttendanceRecord.removed_at.is_(None),
        )
    )
    return set(rows)


def queue_attendance_event(
    session: AsyncSession,
    listing: Listing,
    record: AttendanceRecord,
    status: Literal["marked", "removed"],
) -> None:
    """Write the realtime wakeup in the transaction that changes the mark."""
    add_message(
        session,
        ATTENDANCE_TOPIC,
        {
            "organizer_id": str(listing.author_id),
            "listing_id": str(listing.id),
            "attendance_id": str(record.id),
            "participant_id": str(record.participant_id),
            "interaction_id": str(record.interaction_id),
            "method": record.method,
            "status": status,
            "marked_at": record.marked_at.isoformat(),
            "version": listing.version,
        },
    )


@outbox_handlers.register(ATTENDANCE_TOPIC)
async def _publish_attendance(_session: AsyncSession, job: JobInfo) -> None:
    """Publish a committed mark to the organiser's personal channel."""
    from campus.modules.realtime import publish_personal  # noqa: PLC0415

    payload = dict(job.payload)
    organizer_id = UUID(str(payload.pop("organizer_id")))
    await publish_personal(organizer_id, payload, job.id)
