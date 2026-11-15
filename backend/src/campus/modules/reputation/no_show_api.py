"""No-show endpoints: personal marks, event votes and their results."""

from typing import Literal
from uuid import UUID

from fastapi import Request
from pydantic import BaseModel, ConfigDict, Field

from campus.core import clock
from campus.core.web import DbSession, Instant, Problem, ProblemError, api_router
from campus.core.web.problems import NOT_FOUND
from campus.modules.identity import ProfiledUser
from campus.modules.listings import Interaction, InteractionStatus, Listing
from campus.modules.moderation import DisputeStatus
from campus.modules.reputation.models import NoShowKind, NoShowMark, NoShowStatus
from campus.modules.reputation.no_show import (
    NO_SHOW_FORBIDDEN,
    EventNoShowState,
    NoShowState,
    mark_no_show,
    no_show_state,
    vote_event_not_held,
)
from campus.modules.reputation.no_show import (
    event_result as read_event_result,
)

no_show_router = api_router(
    prefix="/listings/{listing_id}/interactions/{interaction_id}/no-show",
    tags=["No-shows"],
    responses={
        401: {"model": Problem},
        403: {"model": Problem},
        404: {"model": Problem},
        409: {"model": Problem},
        422: {"model": Problem},
    },
)
event_no_show_router = api_router(
    prefix="/listings/{listing_id}/event/no-show",
    tags=["Event no-shows"],
    responses={
        401: {"model": Problem},
        403: {"model": Problem},
        404: {"model": Problem},
        409: {"model": Problem},
        422: {"model": Problem},
    },
)


class NoShowReasonInput(BaseModel):
    model_config = ConfigDict(extra="forbid")

    reason: str = Field(
        min_length=1,
        description=(
            "Why the meeting did not take place. The configured limit is"
            " applied by the domain and reported as a problem."
        ),
    )


class NoShowMarkOutput(BaseModel):
    id: UUID
    kind: NoShowKind
    status: NoShowStatus
    reporter_id: UUID | None = Field(
        description="Who marked the no-show; null for an automatic rule."
    )
    subject_id: UUID = Field(description="The participant the no-show is charged to.")
    reason: str | None
    created_at: Instant
    disputed_at: Instant | None
    removed_at: Instant | None


class NoShowDisputeOutput(BaseModel):
    id: UUID
    status: DisputeStatus
    opened_at: Instant
    resolved_at: Instant | None
    resolution: str | None


class NoShowOutput(BaseModel):
    listing_id: UUID
    interaction_id: UUID
    status: InteractionStatus
    basis: Literal["unmarked", "marked", "automatic", "mutual_dispute", "completed"] = (
        Field(
            description=(
                "How the current state was reached: no mark yet, a participant's"
                " allegation, the automatic 7-day rule, mutual allegations under"
                " dispute, or a confirmed completion."
            )
        )
    )
    marks: list[NoShowMarkOutput]
    dispute: NoShowDisputeOutput | None
    no_show_at: Instant | None = Field(
        description="When the interaction became 'did not take place'."
    )
    mark_from: Instant | None = Field(
        description="The first moment a no-show may be marked."
    )
    auto_after: Instant | None = Field(
        description=(
            "When an unmarked interaction becomes 'did not take place'"
            " without a no-show."
        )
    )
    can_mark: bool = Field(
        description="Whether the requesting participant may mark a no-show now."
    )
    server_time: Instant


class EventNoShowOutput(BaseModel):
    listing_id: UUID
    registered: int = Field(ge=0)
    votes: int = Field(ge=0)
    threshold: int = Field(ge=0, description="ceil(registered / 3).")
    not_held: bool = Field(description="Whether the organiser is already charged.")
    organizer_mark: NoShowMarkOutput | None
    participant_marks: list[NoShowMarkOutput]
    vote_opens_at: Instant | None
    vote_closes_at: Instant | None
    can_vote: bool
    voted: bool = Field(description="Whether the requester has already voted.")
    server_time: Instant


def mark_output(mark: NoShowMark) -> NoShowMarkOutput:
    return NoShowMarkOutput(
        id=mark.id,
        kind=NoShowKind(mark.kind),
        status=NoShowStatus(mark.status),
        reporter_id=mark.reporter_id,
        subject_id=mark.subject_id,
        reason=mark.reason,
        created_at=mark.created_at,
        disputed_at=mark.disputed_at,
        removed_at=mark.removed_at,
    )


def no_show_output(state: NoShowState) -> NoShowOutput:
    dispute = state.dispute
    return NoShowOutput(
        listing_id=state.listing_id,
        interaction_id=state.interaction_id,
        status=state.status,
        basis=state.basis,
        marks=[mark_output(mark) for mark in state.marks],
        dispute=None
        if dispute is None
        else NoShowDisputeOutput(
            id=dispute.id,
            status=DisputeStatus(dispute.status),
            opened_at=dispute.opened_at,
            resolved_at=dispute.resolved_at,
            resolution=dispute.resolution,
        ),
        no_show_at=state.no_show_at,
        mark_from=state.mark_from,
        auto_after=state.auto_after,
        can_mark=state.can_mark,
        server_time=clock.now(),
    )


def event_output(state: EventNoShowState, viewer_id: UUID) -> EventNoShowOutput:
    return EventNoShowOutput(
        listing_id=state.listing_id,
        registered=state.registered,
        votes=state.votes,
        threshold=state.threshold,
        not_held=state.not_held,
        organizer_mark=None
        if state.organizer_mark is None
        else mark_output(state.organizer_mark),
        participant_marks=[mark_output(mark) for mark in state.participant_marks],
        vote_opens_at=state.vote_opens_at,
        vote_closes_at=state.vote_closes_at,
        can_vote=state.can_vote and viewer_id in state.registered_ids,
        voted=viewer_id in state.voter_ids,
        server_time=clock.now(),
    )


async def no_show_context(
    session: DbSession,
    listing_id: UUID,
    interaction_id: UUID,
    actor_id: UUID,
) -> tuple[Listing, Interaction]:
    """Load the interaction and refuse everybody but its two participants."""
    listing = await session.get(Listing, listing_id)
    if listing is None:
        raise ProblemError(NOT_FOUND)
    interaction = await session.get(Interaction, interaction_id)
    if interaction is None or interaction.listing_id != listing.id:
        raise ProblemError(NOT_FOUND)
    if actor_id not in (listing.author_id, interaction.participant_id):
        raise ProblemError(NO_SHOW_FORBIDDEN)
    return listing, interaction


@no_show_router.post("")
async def mark_interaction_no_show(  # noqa: PLR0913, PLR0917 - request context
    listing_id: UUID,
    interaction_id: UUID,
    data: NoShowReasonInput,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
) -> NoShowOutput:
    """Mark that the meeting did not take place, or answer a mutual allegation.

    A participant may mark the other one no earlier than 24 hours after the
    agreed meeting and no later than 7 days, always with a reason. If both
    participants mark each other, one dispute is opened and neither no-show
    counts until the moderator decides. A repeat by the same participant is a
    no-op.
    """
    state = await mark_no_show(
        session,
        listing_id,
        interaction_id,
        principal.user_id,
        data.reason,
        request.app.state.settings,
    )
    return no_show_output(state)


@no_show_router.get("")
async def interaction_no_show(
    listing_id: UUID,
    interaction_id: UUID,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
) -> NoShowOutput:
    """The current result of the interaction and the basis of every mark."""
    listing, interaction = await no_show_context(
        session, listing_id, interaction_id, principal.user_id
    )
    state = await no_show_state(
        session,
        listing,
        interaction,
        principal.user_id,
        request.app.state.settings,
    )
    return no_show_output(state)


@event_no_show_router.post("/votes")
async def vote_event(
    listing_id: UUID,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
) -> EventNoShowOutput:
    """Vote that an event did not take place.

    A registered participant may vote during the 7 days after the event.
    Repeating the vote changes nothing. At a third of the registrations,
    rounded up, the organiser receives a no-show and the automatic
    participant no-shows are lifted; the organiser can dispute it (#94).
    """
    state = await vote_event_not_held(
        session, listing_id, principal.user_id, request.app.state.settings
    )
    return event_output(state, principal.user_id)


@event_no_show_router.get("")
async def event_no_show(
    listing_id: UUID,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
) -> EventNoShowOutput:
    """Votes, the threshold and the marks of an event."""
    state = await read_event_result(
        session,
        listing_id,
        principal.user_id,
        request.app.state.settings,
    )
    return event_output(state, principal.user_id)
