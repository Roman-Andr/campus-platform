"""Participant and moderator APIs of the dispute cases (#94)."""

from typing import Annotated, Any, Literal
from uuid import UUID

from fastapi import Depends, Query, Request, Response
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import and_, exists, or_, select
from sqlalchemy.orm import selectinload

from campus.core import clock
from campus.core.web import (
    DbSession,
    Instant,
    Page,
    PageQuery,
    api_router,
    paginate,
    sort_by,
)
from campus.core.web.problems import (
    NOT_FOUND,
    Problem,
    ProblemError,
    ProblemResponse,
    problem_response,
)
from campus.modules.identity import Permissions, ProfiledUser, Role, require_roles
from campus.modules.listings import (
    Interaction,
    InteractionStatus,
    Listing,
    ListingEvent,
)
from campus.modules.moderation.disputes import (
    DISPUTE_FORBIDDEN,
    DISPUTE_VERSION_CONFLICT,
    DisputeVersionConflictError,
    case_claim,
    case_marks,
    case_participants,
    decide_dispute,
    open_dispute,
)
from campus.modules.moderation.models import (
    Dispute,
    DisputeAction,
    DisputeKind,
    DisputeStatus,
)

DISPUTE_EVENT_STATUSES = (
    InteractionStatus.ACCEPTED,
    InteractionStatus.COMPLETED,
    InteractionStatus.NO_SHOW,
)

disputes_router = api_router(
    prefix="/disputes",
    tags=["Disputes"],
    responses={
        401: {"model": Problem},
        403: {"model": Problem},
        404: {"model": Problem},
        409: {"model": Problem},
        422: {"model": Problem},
    },
)
disputes_admin_router = api_router(
    prefix="/disputes",
    tags=["Disputes admin"],
    dependencies=[Depends(require_roles(Role.MODERATOR, Role.ADMINISTRATOR))],
    responses={
        401: {"model": Problem},
        403: {"model": Problem},
        404: {"model": Problem},
        409: {"model": Problem},
        422: {"model": Problem},
    },
)


class DisputeSummaryOut(BaseModel):
    """One case in a queue or a party's list."""

    model_config = ConfigDict(from_attributes=True, frozen=True)

    id: UUID
    kind: DisputeKind
    status: DisputeStatus
    listing_id: UUID
    interaction_id: UUID | None
    opened_by_id: UUID | None
    event_at: Instant
    opened_at: Instant
    resolved_at: Instant | None
    action: DisputeAction | None
    version: int
    author_id: UUID = Field(description="The author of the listing of the case.")
    participant_id: UUID | None = Field(
        description="The other participant of an interaction case; null for an event."
    )


class AdminDisputeSummaryOut(DisputeSummaryOut):
    """A queue row with the target-time marker of the panel."""

    model_config = ConfigDict(from_attributes=True, frozen=False)

    overdue: bool = Field(
        default=False,
        description="Whether the case waits longer than the configured target time.",
    )


class DisputeMarkOut(BaseModel):
    """A no-show mark of a case; kept as history after a decision."""

    model_config = ConfigDict(from_attributes=True, frozen=True)

    id: UUID
    kind: str
    status: str
    reporter_id: UUID | None
    subject_id: UUID
    reason: str | None
    created_at: Instant
    disputed_at: Instant | None
    removed_at: Instant | None


class DisputePaymentOut(BaseModel):
    """The suspended payment mark of a payment case."""

    model_config = ConfigDict(from_attributes=True, frozen=True)

    id: UUID
    status: str
    claimed_at: Instant
    responded_at: Instant | None
    responded_by_id: UUID | None
    version: int


class DisputeEventOut(BaseModel):
    """One row of the interaction or event chronology of the case."""

    model_config = ConfigDict(from_attributes=True, frozen=True)

    id: UUID
    action: str
    actor_id: UUID | None
    previous_status: str | None
    status: str
    reason: str | None
    details: dict[str, Any] | None
    via_assistant: bool
    offline_qr: bool
    created_at: Instant


class DisputeDetailOut(DisputeSummaryOut):
    """A case with its parties, subject, chronology and resolution."""

    statement: str | None
    resolution: str | None
    resolved_by_id: UUID | None
    participants: list[UUID]
    marks: list[DisputeMarkOut]
    payment: DisputePaymentOut | None
    history: list[DisputeEventOut]


class DisputeOpenInput(BaseModel):
    """A participant opens a case about a disputed event."""

    model_config = ConfigDict(extra="forbid")

    kind: DisputeKind
    listing_id: UUID
    interaction_id: UUID | None = None
    reason: str = Field(
        min_length=1,
        description=(
            "The participant's account of the case; the configured limit is"
            " applied by the domain and reported as a problem."
        ),
    )


class DisputeDecisionInput(BaseModel):
    """One moderator decision; the version rejects a stale one."""

    model_config = ConfigDict(extra="forbid")

    version: int = Field(ge=1)
    action: DisputeAction
    reason: str = Field(
        min_length=1,
        description="The justification recorded in the journal and the audit.",
    )


def summary_of(dispute: Dispute) -> DisputeSummaryOut:
    return DisputeSummaryOut.model_validate(dispute)


async def _history(
    session: DbSession,
    dispute: Dispute,
    listing: Listing,
    viewer_id: UUID | None,
    *,
    moderator: bool,
) -> list[ListingEvent]:
    query = select(ListingEvent).where(ListingEvent.listing_id == dispute.listing_id)
    if dispute.interaction_id is not None:
        query = query.where(ListingEvent.interaction_id == dispute.interaction_id)
    elif not moderator and viewer_id != listing.author_id:
        # An event case is visible to its registered participants, but the
        # chronology of other participants' interactions is not.
        query = query.where(ListingEvent.interaction_id.is_(None))
    query = query.order_by(ListingEvent.created_at, ListingEvent.id).limit(200)
    return list(await session.scalars(query))


async def detail_of(
    session: DbSession,
    dispute: Dispute,
    participants: set[UUID],
    viewer_id: UUID | None = None,
    *,
    moderator: bool = False,
) -> DisputeDetailOut:
    marks = await case_marks(session, dispute)
    claim = await case_claim(session, dispute)
    history = await _history(
        session,
        dispute,
        dispute.listing,
        viewer_id,
        moderator=moderator,
    )
    summary = summary_of(dispute)
    return DisputeDetailOut(
        **summary.model_dump(),
        statement=dispute.statement,
        resolution=dispute.resolution,
        resolved_by_id=dispute.resolved_by_id,
        participants=sorted(participants, key=str),
        marks=[DisputeMarkOut.model_validate(mark) for mark in marks],
        payment=None if claim is None else DisputePaymentOut.model_validate(claim),
        history=[DisputeEventOut.model_validate(event) for event in history],
    )


def _case_query() -> Any:
    return select(Dispute).options(
        selectinload(Dispute.listing),
        selectinload(Dispute.interaction),
    )


async def load_case(
    session: DbSession, dispute_id: UUID, *, viewer_id: UUID | None = None
) -> tuple[Dispute, Listing, set[UUID]]:
    dispute = await session.scalar(_case_query().where(Dispute.id == dispute_id))
    if dispute is None:
        raise ProblemError(NOT_FOUND)
    listing = dispute.listing
    participants = await case_participants(session, dispute, listing)
    if viewer_id is not None and viewer_id not in participants:
        raise ProblemError(DISPUTE_FORBIDDEN)
    return dispute, listing, participants


def mine(user_id: UUID) -> Any:
    """Cases the user is a party of: author, interaction participant or signup."""
    registered = exists().where(
        and_(
            Interaction.listing_id == Dispute.listing_id,
            Interaction.participant_id == user_id,
            Interaction.status.in_(DISPUTE_EVENT_STATUSES),
        )
    )
    return or_(
        Listing.author_id == user_id,
        Dispute.interaction_id.in_(
            select(Interaction.id).where(Interaction.participant_id == user_id)
        ),
        and_(Dispute.interaction_id.is_(None), registered),
    )


@disputes_router.get("")
async def list_my_disputes(  # noqa: PLR0913, PLR0917 - request filters
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
    page: PageQuery,
    status: Annotated[
        DisputeStatus | None, Query(description="Only open or only decided cases.")
    ] = None,
    kind: Annotated[DisputeKind | None, Query()] = None,
    listing_id: Annotated[UUID | None, Query()] = None,
    interaction_id: Annotated[UUID | None, Query()] = None,
    order_by: Literal["opened_at", "-opened_at"] = "-opened_at",
) -> Page[DisputeSummaryOut]:
    """The caller's cases, newest first by default."""
    query = _case_query().join(Listing, Listing.id == Dispute.listing_id)
    query = query.where(mine(principal.user_id))
    if status is not None:
        query = query.where(Dispute.status == status)
    if kind is not None:
        query = query.where(Dispute.kind == kind)
    if listing_id is not None:
        query = query.where(Dispute.listing_id == listing_id)
    if interaction_id is not None:
        query = query.where(Dispute.interaction_id == interaction_id)
    query = sort_by(
        query,
        order_by,
        {"opened_at": Dispute.opened_at},
        Dispute.id,
    )
    return await paginate(
        session,
        query,
        page,
        DisputeSummaryOut,
        settings=request.app.state.settings,
        context=f"{status}:{kind}:{listing_id}:{interaction_id}",
    )


@disputes_router.get("/{dispute_id}")
async def get_my_dispute(
    dispute_id: UUID,
    session: DbSession,
    principal: ProfiledUser,
) -> DisputeDetailOut:
    """One case of the caller with its chronology and current subject."""
    dispute, _listing, participants = await load_case(
        session, dispute_id, viewer_id=principal.user_id
    )
    return await detail_of(session, dispute, participants, principal.user_id)


@disputes_router.post("", status_code=201)
async def open_my_dispute(
    data: DisputeOpenInput,
    response: Response,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
) -> DisputeDetailOut:
    """Open one case about a disputed event.

    A repeated opening of the same event returns the existing case with 200
    and never creates a second one. The seven-day window is counted from the
    disputed event (the mark or the payment mark), not from the interaction.
    """
    opened = await open_dispute(
        session,
        data.listing_id,
        data.interaction_id,
        principal.user_id,
        data.kind,
        data.reason,
        request.app.state.settings,
    )
    dispute, _listing, participants = await load_case(
        session, opened.dispute.id, viewer_id=principal.user_id
    )
    if not opened.created:
        response.status_code = 200
    return await detail_of(session, dispute, participants, principal.user_id)


@disputes_admin_router.get("")
async def admin_list_disputes(  # noqa: PLR0913, PLR0917 - request filters
    request: Request,
    session: DbSession,
    page: PageQuery,
    status: Annotated[DisputeStatus | None, Query()] = None,
    kind: Annotated[DisputeKind | None, Query()] = None,
    listing_id: Annotated[UUID | None, Query()] = None,
    order_by: Literal["opened_at", "-opened_at"] = "opened_at",
) -> Page[AdminDisputeSummaryOut]:
    """The panel queue, oldest first by default; overdue cases are marked."""
    query = _case_query()
    if status is not None:
        query = query.where(Dispute.status == status)
    if kind is not None:
        query = query.where(Dispute.kind == kind)
    if listing_id is not None:
        query = query.where(Dispute.listing_id == listing_id)
    query = sort_by(
        query,
        order_by,
        {"opened_at": Dispute.opened_at},
        Dispute.id,
    )
    page_out = await paginate(
        session,
        query,
        page,
        AdminDisputeSummaryOut,
        settings=request.app.state.settings,
        context=f"{status}:{kind}:{listing_id}",
    )
    now = clock.now()
    target = request.app.state.settings.dispute_target_time
    for item in page_out.items:
        item.overdue = (
            item.status == DisputeStatus.OPEN and item.opened_at + target < now
        )
    return page_out


@disputes_admin_router.get("/{dispute_id}")
async def admin_get_dispute(dispute_id: UUID, session: DbSession) -> DisputeDetailOut:
    """One case with its parties, subject, chronology and resolution."""
    dispute, _listing, participants = await load_case(session, dispute_id)
    return await detail_of(session, dispute, participants, moderator=True)


@disputes_admin_router.post("/{dispute_id}/decision", response_model=DisputeDetailOut)
async def admin_decide_dispute(
    dispute_id: UUID,
    data: DisputeDecisionInput,
    request: Request,
    session: DbSession,
    permissions: Permissions,
) -> DisputeDetailOut | ProblemResponse:
    """Decide one case; a stale version or a second decision is refused.

    The own-case mark of the audit journal is derived from the parties of
    the case, so a moderator deciding their own case is recorded as such.
    """
    try:
        await decide_dispute(
            session,
            dispute_id,
            permissions.user_id,
            data.action,
            data.reason,
            data.version,
            request.app.state.settings,
        )
    except DisputeVersionConflictError as error:
        return problem_response(
            request,
            DISPUTE_VERSION_CONFLICT,
            params={"version": error.current_version},
            current_version=error.current_version,
        )
    dispute, _listing, participants = await load_case(session, dispute_id)
    return await detail_of(session, dispute, participants, moderator=True)


__all__ = [
    "AdminDisputeSummaryOut",
    "DisputeDetailOut",
    "disputes_admin_router",
    "disputes_router",
]
