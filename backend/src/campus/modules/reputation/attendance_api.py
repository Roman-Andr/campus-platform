"""Event attendance endpoints: rotating codes, marks and their list."""

from typing import Literal
from uuid import UUID

from fastapi import Request
from pydantic import BaseModel, ConfigDict, Field

from campus.core import clock
from campus.core.web import DbSession, Instant, Problem, api_router
from campus.modules.identity import ProfiledUser
from campus.modules.listings import AttendanceMode
from campus.modules.reputation.attendance import (
    AttendanceResult,
    IssuedAttendanceCode,
    attendance_overview,
    check_in_self,
    issue_organizer_code,
    issue_participant_code,
    remove_attendance,
    scan_attendance,
    set_attendance_mode,
)
from campus.modules.reputation.models import AttendanceRecord

attendance_router = api_router(
    prefix="/listings/{listing_id}/event/attendance",
    tags=["Event attendance"],
    responses={
        401: {"model": Problem},
        403: {"model": Problem},
        404: {"model": Problem},
        409: {"model": Problem},
        422: {"model": Problem},
    },
)


class AttendanceModeInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    mode: AttendanceMode


class AttendanceModeOutput(BaseModel):
    listing_id: UUID
    mode: AttendanceMode
    version: int
    changed: bool


class AttendanceCodeInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    code: str = Field(
        min_length=1,
        max_length=1024,
        description="The opaque rotating code read from the other device.",
    )


class AttendanceCodeOutput(BaseModel):
    listing_id: UUID
    mode: AttendanceMode
    code: str = Field(description="Opaque code to show as a QR code.")
    issued_at: Instant
    expires_at: Instant
    server_time: Instant


class AttendanceItemOutput(BaseModel):
    id: UUID
    listing_id: UUID
    participant_id: UUID
    participant_name: str
    interaction_id: UUID
    status: Literal["marked", "removed"]
    method: AttendanceMode
    marked_at: Instant
    marked_by_id: UUID
    removed_at: Instant | None
    removed_by_id: UUID | None
    registered: bool = Field(
        description="Whether the participant still has an accepted signup."
    )


class AttendanceOutput(AttendanceItemOutput):
    result: Literal["marked", "already_marked", "removed", "already_removed"]
    version: int = Field(description="Current version of the event aggregate.")
    server_time: Instant


class AttendanceListOutput(BaseModel):
    listing_id: UUID
    mode: AttendanceMode
    version: int
    items: list[AttendanceItemOutput]
    marked_count: int
    server_time: Instant


def attendance_item(record: AttendanceRecord, registered: bool) -> AttendanceItemOutput:
    status: Literal["marked", "removed"] = (
        "marked" if record.removed_at is None else "removed"
    )
    return AttendanceItemOutput(
        id=record.id,
        listing_id=record.listing_id,
        participant_id=record.participant_id,
        participant_name=record.participant_name,
        interaction_id=record.interaction_id,
        status=status,
        method=AttendanceMode(record.method),
        marked_at=record.marked_at,
        marked_by_id=record.marked_by_id,
        removed_at=record.removed_at,
        removed_by_id=record.removed_by_id,
        registered=registered,
    )


def attendance_output(result: AttendanceResult) -> AttendanceOutput:
    item = attendance_item(result.record, registered=result.registered)
    return AttendanceOutput(
        **item.model_dump(),
        result=result.result,
        version=result.version,
        server_time=clock.now(),
    )


def attendance_code_output(issued: IssuedAttendanceCode) -> AttendanceCodeOutput:
    return AttendanceCodeOutput(
        listing_id=issued.listing_id,
        mode=issued.mode,
        code=issued.code,
        issued_at=issued.issued_at,
        expires_at=issued.expires_at,
        server_time=clock.now(),
    )


@attendance_router.put("/mode")
async def set_event_attendance_mode(
    listing_id: UUID,
    data: AttendanceModeInput,
    session: DbSession,
    principal: ProfiledUser,
) -> AttendanceModeOutput:
    """Choose how participants are marked: self-marking or organiser scans.

    Only the event organiser may switch the mode. Every taken mark stays;
    codes of the previous mode are rejected from now on.
    """
    listing, changed = await set_attendance_mode(
        session, listing_id, principal.user_id, data.mode
    )
    assert listing.event_attendance_mode is not None  # noqa: S101 - set above
    return AttendanceModeOutput(
        listing_id=listing.id,
        mode=AttendanceMode(listing.event_attendance_mode),
        version=listing.version,
        changed=changed,
    )


@attendance_router.get("")
async def list_event_attendance(
    listing_id: UUID,
    session: DbSession,
    principal: ProfiledUser,
) -> AttendanceListOutput:
    """List every mark of the event, including removed ones, for the organiser.

    Realtime publications are only wakeups; this list is the authoritative
    state to restore after a missed publication or a reconnect.
    """
    overview = await attendance_overview(session, listing_id, principal.user_id)
    items = [
        attendance_item(record, record.participant_id in overview.registered_ids)
        for record in overview.records
    ]
    mode = overview.mode
    assert mode is not None  # noqa: S101 - event listings have a mode
    return AttendanceListOutput(
        listing_id=overview.listing_id,
        mode=mode,
        version=overview.version,
        items=items,
        marked_count=sum(1 for record in overview.records if record.active),
        server_time=clock.now(),
    )


@attendance_router.post("/qr")
async def issue_event_attendance_qr(
    listing_id: UUID,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
) -> AttendanceCodeOutput:
    """Issue the organiser's rotating self-mark code.

    The organiser shows it as a QR code; every registered participant may
    scan the same code. It lives for the configured attendance code TTL.
    """
    issued = await issue_organizer_code(
        session,
        listing_id,
        principal.user_id,
        request.app.state.settings,
    )
    return attendance_code_output(issued)


@attendance_router.post("/self")
async def check_in_event(
    listing_id: UUID,
    data: AttendanceCodeInput,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
) -> AttendanceOutput:
    """Mark the authenticated registered participant from the organiser's code.

    A repeat, a retry with another Idempotency-Key and a parallel scan of the
    same participant return the one stored mark instead of adding another.
    """
    result = await check_in_self(
        session,
        listing_id,
        principal.user_id,
        data.code,
        request.app.state.settings,
    )
    return attendance_output(result)


@attendance_router.post("/code")
async def issue_event_attendance_code(
    listing_id: UUID,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
) -> AttendanceCodeOutput:
    """Issue the registered participant's rotating personal code to be scanned."""
    issued = await issue_participant_code(
        session,
        listing_id,
        principal.user_id,
        request.app.state.settings,
    )
    return attendance_code_output(issued)


@attendance_router.post("/scan")
async def scan_event_attendance(
    listing_id: UUID,
    data: AttendanceCodeInput,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
) -> AttendanceOutput:
    """Mark the participant whose personal code the organiser scanned."""
    result = await scan_attendance(
        session,
        listing_id,
        principal.user_id,
        data.code,
        request.app.state.settings,
    )
    return attendance_output(result)


@attendance_router.delete("/{participant_id}")
async def remove_event_attendance(
    listing_id: UUID,
    participant_id: UUID,
    session: DbSession,
    principal: ProfiledUser,
) -> AttendanceOutput:
    """Remove one participant's mark; only the event organiser may do it.

    The row stays as ``removed`` so the organiser's list shows what was
    removed and the participant can be marked again later.
    """
    result = await remove_attendance(
        session, listing_id, principal.user_id, participant_id
    )
    return attendance_output(result)
