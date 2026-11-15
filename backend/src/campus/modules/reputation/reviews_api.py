"""Review endpoints: mutual reveal, the edit and the single answer."""

from typing import Annotated
from uuid import UUID

from fastapi import Request
from pydantic import BaseModel, ConfigDict, Field, StringConstraints, model_validator

from campus.core import clock
from campus.core.web import (
    CurrentUser,
    DbSession,
    Instant,
    Page,
    PageQuery,
    Problem,
    api_router,
    paginate,
    sort_by,
)
from campus.modules.identity import ProfiledUser
from campus.modules.listings import InteractionStatus
from campus.modules.reputation.models import Review, ReviewReply
from campus.modules.reputation.reviews import (
    ReviewInput,
    ReviewState,
    create_review,
    edit_review,
    reply_to_review,
    require_participant,
    review_read_context,
    review_state,
    reviews_about,
)

review_router = api_router(
    prefix="/listings/{listing_id}/interactions/{interaction_id}/review",
    tags=["Reviews"],
    responses={
        401: {"model": Problem},
        403: {"model": Problem},
        404: {"model": Problem},
        409: {"model": Problem},
        422: {"model": Problem},
    },
)
reviews_router = api_router(
    prefix="/users/{user_id}/reviews",
    tags=["Reviews"],
    responses={
        401: {"model": Problem},
        404: {"model": Problem},
        422: {"model": Problem},
    },
)

TagCode = Annotated[str, StringConstraints(min_length=1, max_length=32)]


class ReviewInputBody(BaseModel):
    model_config = ConfigDict(extra="forbid")

    rating: int = Field(
        ge=1,
        le=5,
        description="Stars from 1 to 5; the other side is not supposed to know it"
        " before the reveal.",
    )
    tags: list[TagCode] = Field(
        default_factory=list,
        description="Ready-made tag codes of the listing scenario; foreign codes"
        " are rejected.",
    )
    text: str | None = Field(
        default=None,
        description="Optional text. The configured limit is applied by the domain"
        " and reported as a problem.",
    )


class ReplyInputBody(BaseModel):
    model_config = ConfigDict(extra="forbid")

    text: str = Field(
        min_length=1,
        description="The single public answer of the addressee.",
    )


class ReviewReplyOutput(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    review_id: UUID
    author_id: UUID
    author_name: str
    text: str
    created_at: Instant
    updated_at: Instant


class ReviewOutput(BaseModel):
    id: UUID
    interaction_id: UUID
    listing_id: UUID
    kind: str
    author_id: UUID
    author_name: str
    subject_id: UUID
    rating: int
    tags: list[str]
    text: str | None
    created_at: Instant
    updated_at: Instant
    reveal_at: Instant
    published_at: Instant | None = Field(
        description="When the review became readable; null while it is hidden."
    )
    hidden: bool = Field(
        description="Whether a moderator hid the review; only its author sees"
        " this flag and the review itself."
    )
    reply: ReviewReplyOutput | None

    @model_validator(mode="before")
    @classmethod
    def from_review(cls, value: object) -> object:
        """Convert an ORM review; the public list is paginated this way."""
        if not isinstance(value, Review):
            return value
        return {
            "id": value.id,
            "interaction_id": value.interaction_id,
            "listing_id": value.listing_id,
            "kind": value.kind,
            "author_id": value.author_id,
            "author_name": value.author_name,
            "subject_id": value.subject_id,
            "rating": value.rating,
            "tags": [tag.tag for tag in value.tags],
            "text": value.text,
            "created_at": value.created_at,
            "updated_at": value.updated_at,
            "reveal_at": value.reveal_at,
            "published_at": value.published_at,
            "hidden": value.hidden_at is not None,
            "reply": None if value.reply is None else reply_output(value.reply),
        }


class ReviewStateOutput(BaseModel):
    listing_id: UUID
    interaction_id: UUID
    kind: str
    status: InteractionStatus
    one_way: bool = Field(
        description="An event: only its participants review the organiser."
    )
    completed_at: Instant | None = Field(
        description="When the interaction became reviewable; null if it never was."
    )
    window_closes_at: Instant | None = Field(
        description="The end of the review window, counted from the completion."
    )
    revealed: bool = Field(
        description="Whether the reviews of the interaction are revealed."
    )
    eligible: bool = Field(
        description="Whether this participant may write a review now."
    )
    can_review: bool
    can_edit: bool
    can_reply: bool
    tags: list[str] = Field(description="The tag catalogue of the scenario.")
    mine: ReviewOutput | None = Field(description="The requester's own review.")
    theirs: ReviewOutput | None = Field(
        description="The review about the requester; only when revealed and not hidden."
    )
    server_time: Instant


def reply_output(reply: ReviewReply) -> ReviewReplyOutput:
    return ReviewReplyOutput(
        id=reply.id,
        review_id=reply.review_id,
        author_id=reply.author_id,
        author_name=reply.author_name,
        text=reply.text,
        created_at=reply.created_at,
        updated_at=reply.updated_at,
    )


def review_output(review: Review) -> ReviewOutput:
    return ReviewOutput.model_validate(review)


def state_output(state: ReviewState) -> ReviewStateOutput:
    return ReviewStateOutput(
        listing_id=state.listing_id,
        interaction_id=state.interaction_id,
        kind=state.kind,
        status=state.status,
        one_way=state.one_way,
        completed_at=state.completed_at,
        window_closes_at=state.window_closes_at,
        revealed=state.revealed,
        eligible=state.eligible,
        can_review=state.can_review,
        can_edit=state.can_edit,
        can_reply=state.can_reply,
        tags=list(state.tags),
        mine=None if state.mine is None else review_output(state.mine),
        theirs=None if state.theirs is None else review_output(state.theirs),
        server_time=clock.now(),
    )


@review_router.post("", status_code=201)
async def create_interaction_review(  # noqa: PLR0913, PLR0917 - request context
    listing_id: UUID,
    interaction_id: UUID,
    data: ReviewInputBody,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
) -> ReviewStateOutput:
    """Write the participant's review of a completed interaction.

    Allowed within the configured window (14 days by default) after the
    completion. Two mutual reviews are revealed together when both exist or
    when the window closes; an event review is published at once and the
    organiser cannot write the reverse one.
    """
    state = await create_review(
        session,
        listing_id,
        interaction_id,
        principal.user_id,
        ReviewInput(rating=data.rating, tags=list(data.tags), text=data.text),
        request.app.state.settings,
    )
    return state_output(state)


@review_router.get("")
async def interaction_review(
    listing_id: UUID,
    interaction_id: UUID,
    request: Request,
    session: DbSession,
    principal: CurrentUser,
) -> ReviewStateOutput:
    """The requester's review, the revealed other one and the windows.

    A review of the other participant is not shown before the reveal; the
    response then has no ``theirs`` and ``revealed`` is false.
    """
    listing, interaction = await review_read_context(
        session, listing_id, interaction_id
    )
    require_participant(listing, interaction, principal.user_id)
    state = await review_state(
        session,
        listing,
        interaction,
        principal.user_id,
        request.app.state.settings,
    )
    return state_output(state)


@review_router.patch("")
async def edit_interaction_review(  # noqa: PLR0913, PLR0917 - request context
    listing_id: UUID,
    interaction_id: UUID,
    data: ReviewInputBody,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
) -> ReviewStateOutput:
    """Replace the rating, tags and text of the own review before the reveal."""
    state = await edit_review(
        session,
        listing_id,
        interaction_id,
        principal.user_id,
        ReviewInput(rating=data.rating, tags=list(data.tags), text=data.text),
        request.app.state.settings,
    )
    return state_output(state)


@review_router.post("/reply", status_code=201)
async def reply_to_interaction_review(  # noqa: PLR0913, PLR0917 - request context
    listing_id: UUID,
    interaction_id: UUID,
    data: ReplyInputBody,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
) -> ReviewStateOutput:
    """The addressee answers the revealed review about them once.

    The author of the review and third parties are refused; a review that
    is not revealed yet is a plain 404, so its existence does not leak.
    """
    state = await reply_to_review(
        session,
        listing_id,
        interaction_id,
        principal.user_id,
        data.text,
        request.app.state.settings,
    )
    return state_output(state)


@reviews_router.get("")
async def user_reviews(
    user_id: UUID,
    request: Request,
    session: DbSession,
    principal: CurrentUser,  # noqa: ARG001 - the sign-in check is the dependency
    page: PageQuery,
) -> Page[ReviewOutput]:
    """The public reviews about a user: revealed and not hidden only."""
    query = sort_by(
        reviews_about(user_id),
        "-created_at",
        {"created_at": Review.created_at},
        Review.id,
    )
    return await paginate(
        session,
        query,
        page,
        ReviewOutput,
        settings=request.app.state.settings,
        context=f"user-reviews:{user_id}",
    )
