"""Reviews with mutual reveal and one answer (specification 5.1.1, module 5).

A review belongs to a completed interaction and names one side of it: the
author and the subject are its two participants. The rating is 1 to 5
stars, the tags come from the catalogue of the scenario and the text is
optional. Each author writes at most one review per pair and may change it
only before the review is revealed.

Two mutual reviews of an interaction are hidden from each other until both
exist or the 14-day window after the completion closes; the durable reveal
deadline does the second case and catches up after a scheduler outage.
An event review is one-way: a registered participant reviews the organiser,
who answers but never writes his own review, so it is published at once.

The addressee answers a published review once. A review hidden by a
moderator decision (#94) is filtered out of every public read, while its
rating, tags and text stay stored as the primary data for #64.
"""

from dataclasses import dataclass
from datetime import datetime
from typing import Any
from uuid import UUID, uuid5

from sqlalchemy import Select, and_, or_, select
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
    append_event,
    locked,
)
from campus.modules.reputation.models import (
    REVIEW_KINDS,
    Review,
    ReviewReply,
    ReviewTag,
)

REVIEW_REVEAL_TOPIC = "reputation.review_reveal"
REVIEW_TOPIC = "reputation.review"

# Ready-made tags of every scenario; a review may carry none of them. The
# codes are stable: the profile counters of #64 group by them and the
# client translates them.
REVIEW_TAGS: dict[str, tuple[str, ...]] = {
    "giveaway": ("punctual", "item_as_described", "friendly", "clear_communication"),
    "exchange": ("punctual", "fair_offer", "item_as_described", "friendly"),
    "loan": ("punctual", "item_in_order", "returned_on_time", "friendly"),
    "skill": ("clear_explanation", "punctual", "patient", "useful"),
    "help": ("helped_as_promised", "punctual", "responsive", "friendly"),
    "event": ("interesting", "well_organized", "organizer_punctual", "as_described"),
    "purchase": ("punctual", "transparent_terms", "responsive", "as_described"),
}

REVIEW_FORBIDDEN = ProblemType(
    "review_forbidden",
    403,
    N_("Forbidden"),
    N_("Only the two participants of the interaction can review it."),
)
REVIEW_ONE_WAY = ProblemType(
    "review_one_way",
    403,
    N_("Forbidden"),
    N_("An event is reviewed by its participants; the organiser answers."),
)
REVIEW_UNAVAILABLE = ProblemType(
    "review_unavailable",
    409,
    N_("The interaction cannot be reviewed"),
    N_(
        "A review is written after the interaction is completed: by a meeting"
        " confirmation, without a meeting, by an event or by an issued"
        " purchase share."
    ),
)
REVIEW_WINDOW_CLOSED = ProblemType(
    "review_window_closed",
    409,
    N_("The review window has closed"),
    N_("A review is written within {days} days after the interaction is completed."),
)
REVIEW_EXISTS = ProblemType(
    "review_exists",
    409,
    N_("The review already exists"),
    N_("You have already reviewed the other participant of this interaction."),
)
REVIEW_PUBLISHED = ProblemType(
    "review_published",
    409,
    N_("The review is published"),
    N_("A review cannot be changed after it is revealed."),
)
REVIEW_HIDDEN = ProblemType(
    "review_hidden",
    409,
    N_("The review is hidden"),
    N_("A review hidden by a moderator cannot be changed."),
)
REVIEW_RATING_INVALID = ProblemType(
    "review_rating_invalid",
    422,
    N_("Invalid rating"),
    N_("A rating is a whole number of stars from 1 to 5."),
)
REVIEW_TAGS_INVALID = ProblemType(
    "review_tags_invalid",
    422,
    N_("Invalid review tags"),
    N_("The tags must belong to the scenario, be distinct and number at most {max}."),
)
REVIEW_TEXT_INVALID = ProblemType(
    "review_text_invalid",
    422,
    N_("Invalid review text"),
    N_("The review text is at most {max} characters."),
)
REVIEW_REPLY_INVALID = ProblemType(
    "review_reply_invalid",
    422,
    N_("Invalid reply"),
    N_("The reply text is from 1 to {max} characters."),
)
REVIEW_REPLY_EXISTS = ProblemType(
    "review_reply_exists",
    409,
    N_("The review is already answered"),
    N_("The addressee answers a review once."),
)


@dataclass(frozen=True, slots=True)
class ReviewState:
    """One participant's view of the reviews of one interaction."""

    listing_id: UUID
    interaction_id: UUID
    kind: str
    status: InteractionStatus
    one_way: bool
    completed_at: datetime | None
    window_closes_at: datetime | None
    revealed: bool
    eligible: bool
    can_review: bool
    can_edit: bool
    can_reply: bool
    tags: tuple[str, ...]
    mine: Review | None
    theirs: Review | None


@dataclass(frozen=True, slots=True)
class ReviewInput:
    """The fields a review or its edit carries."""

    rating: int
    tags: list[str]
    text: str | None


def review_tags(kind: str) -> tuple[str, ...]:
    """The ready-made tags of the scenario; empty for an unknown kind."""
    return REVIEW_TAGS.get(kind, ())


def one_way(listing: Listing) -> bool:
    """Whether only the participant writes the review: the event case."""
    return listing.kind == "event"


def completion_moment(
    listing: Listing, interaction: Interaction, now: datetime
) -> datetime | None:
    """When the interaction became reviewable, or ``None``.

    Every scenario but an event passes through the completed status and
    stores the moment. An event signup keeps its accepted status while the
    attendance rules of #61/#66 judge it; the event itself completes it, so
    its completion moment is the end of the event.
    """
    if listing.kind == "event":
        if interaction.status not in (
            InteractionStatus.ACCEPTED,
            InteractionStatus.COMPLETED,
        ):
            return None
        if listing.event_ends_at is None or now < listing.event_ends_at:
            return None
        return listing.event_ends_at
    if interaction.status != InteractionStatus.COMPLETED:
        return None
    return interaction.completed_at


def window_closes(completed_at: datetime, settings: Settings) -> datetime:
    """The end of the review window counted from the completion."""
    return completed_at + settings.review_window


def other_side(listing: Listing, interaction: Interaction, actor_id: UUID) -> UUID:
    """The participant the review of ``actor_id`` is about."""
    return (
        interaction.participant_id
        if actor_id == listing.author_id
        else listing.author_id
    )


def validate_rating(rating: int) -> int:
    if not 1 <= rating <= 5:  # noqa: PLR2004 - the domain range of stars
        raise ProblemError(REVIEW_RATING_INVALID)
    return rating


def validate_tags(kind: str, tags: list[str], settings: Settings) -> tuple[str, ...]:
    """The tags of the scenario, distinct and at most the configured number."""
    allowed = review_tags(kind)
    if len(tags) > settings.review_tags_max or len(set(tags)) != len(tags):
        raise ProblemError(REVIEW_TAGS_INVALID, max=settings.review_tags_max)
    for tag in tags:
        if tag not in allowed:
            raise ProblemError(REVIEW_TAGS_INVALID, max=settings.review_tags_max)
    return tuple(tags)


def validate_text(
    text: str | None, settings: Settings, problem: ProblemType = REVIEW_TEXT_INVALID
) -> str | None:
    """A stripped optional text within the configured limit."""
    if text is None:
        return None
    value = text.strip()
    if not value:
        return None
    if len(value) > settings.review_text_max_length:
        raise ProblemError(problem, max=settings.review_text_max_length)
    return value


def validate_reply(text: str, settings: Settings) -> str:
    value = validate_text(text, settings, REVIEW_REPLY_INVALID)
    if value is None:
        raise ProblemError(REVIEW_REPLY_INVALID, max=settings.review_text_max_length)
    return value


async def review_context(
    session: AsyncSession, listing_id: UUID, interaction_id: UUID
) -> tuple[Listing, Interaction]:
    """The listing and its interaction, locked for a mutation, or 404."""
    listing = await locked(session, listing_id)
    interaction = await session.get(Interaction, interaction_id)
    if interaction is None or interaction.listing_id != listing.id:
        raise ProblemError(NOT_FOUND)
    return listing, interaction


async def review_read_context(
    session: AsyncSession, listing_id: UUID, interaction_id: UUID
) -> tuple[Listing, Interaction]:
    """The listing and its interaction without a row lock, or 404."""
    listing = await session.get(Listing, listing_id)
    if listing is None:
        raise ProblemError(NOT_FOUND)
    interaction = await session.get(Interaction, interaction_id)
    if interaction is None or interaction.listing_id != listing.id:
        raise ProblemError(NOT_FOUND)
    return listing, interaction


def require_participant(
    listing: Listing, interaction: Interaction, actor_id: UUID
) -> None:
    if actor_id not in (listing.author_id, interaction.participant_id):
        raise ProblemError(REVIEW_FORBIDDEN)


def pair_clause(listing: Listing, interaction: Interaction) -> Any:
    """The row filter of the two reviews of one pair.

    A purchase review belongs to the ``organiser -- participant`` pair of
    the whole listing, not to the share row alone: a participant who left
    and joined again keeps one review of the organiser. Every other
    scenario has one interaction per pair, so its key is the interaction.
    """
    if listing.kind == "purchase":
        return and_(
            Review.listing_id == listing.id,
            Review.kind == "purchase",
            or_(
                and_(
                    Review.author_id == listing.author_id,
                    Review.subject_id == interaction.participant_id,
                ),
                and_(
                    Review.author_id == interaction.participant_id,
                    Review.subject_id == listing.author_id,
                ),
            ),
        )
    return Review.interaction_id == interaction.id


def pair_query(listing: Listing, interaction: Interaction) -> Select[Review]:
    return select(Review).where(pair_clause(listing, interaction))


async def pair_reviews(
    session: AsyncSession, listing: Listing, interaction: Interaction
) -> list[Review]:
    return list(await session.scalars(pair_query(listing, interaction)))


async def own_review(
    session: AsyncSession, listing: Listing, interaction: Interaction, author_id: UUID
) -> Review | None:
    return await session.scalar(
        pair_query(listing, interaction).where(Review.author_id == author_id)
    )


async def counterpart_review(
    session: AsyncSession, listing: Listing, interaction: Interaction, viewer_id: UUID
) -> Review | None:
    """The review about ``viewer_id`` written by the other side of the pair."""
    return await session.scalar(
        pair_query(listing, interaction).where(
            Review.subject_id == viewer_id,
            Review.author_id != viewer_id,
        )
    )


def reveal_key(interaction_id: UUID) -> str:
    return f"review-reveal:{interaction_id}"


def public(review: Review) -> bool:
    """Whether the review may be shown to people other than its author."""
    return review.published_at is not None and review.hidden_at is None


async def review_state(
    session: AsyncSession,
    listing: Listing,
    interaction: Interaction,
    viewer_id: UUID,
    settings: Settings,
) -> ReviewState:
    """Compute the participant's view without leaking the hidden side."""
    now = clock.now()
    completed = completion_moment(listing, interaction, now)
    closes = None if completed is None else window_closes(completed, settings)
    within_window = closes is not None and now < closes
    may_review = (
        completed is not None
        and viewer_id in (listing.author_id, interaction.participant_id)
        and listing.kind in REVIEW_KINDS
        and within_window
        and not (one_way(listing) and viewer_id == listing.author_id)
    )
    mine = await own_review(session, listing, interaction, viewer_id)
    theirs = await counterpart_review(session, listing, interaction, viewer_id)
    visible = None if theirs is None or not public(theirs) else theirs
    revealed = visible is not None or (
        mine is not None and mine.published_at is not None
    )
    return ReviewState(
        listing_id=listing.id,
        interaction_id=interaction.id,
        kind=listing.kind,
        status=InteractionStatus(interaction.status),
        one_way=one_way(listing),
        completed_at=completed,
        window_closes_at=closes,
        revealed=revealed,
        eligible=may_review,
        can_review=may_review and mine is None,
        can_edit=(
            mine is not None
            and mine.published_at is None
            and mine.hidden_at is None
            and within_window
        ),
        can_reply=visible is not None and visible.reply is None,
        tags=review_tags(listing.kind),
        mine=mine,
        theirs=visible,
    )


async def create_review(  # noqa: PLR0913, PLR0917 - request context
    session: AsyncSession,
    listing_id: UUID,
    interaction_id: UUID,
    actor_id: UUID,
    data: ReviewInput,
    settings: Settings,
) -> ReviewState:
    """Write the participant's review of a completed interaction."""
    listing, interaction = await review_context(session, listing_id, interaction_id)
    require_participant(listing, interaction, actor_id)
    if listing.kind not in REVIEW_KINDS:
        raise ProblemError(REVIEW_UNAVAILABLE)
    now = clock.now()
    completed = completion_moment(listing, interaction, now)
    if completed is None:
        raise ProblemError(REVIEW_UNAVAILABLE)
    closes = window_closes(completed, settings)
    if now >= closes:
        raise ProblemError(REVIEW_WINDOW_CLOSED, days=settings.review_window.days)
    if one_way(listing) and actor_id == listing.author_id:
        raise ProblemError(REVIEW_ONE_WAY)
    subject_id = other_side(listing, interaction, actor_id)
    if await own_review(session, listing, interaction, actor_id) is not None:
        raise ProblemError(REVIEW_EXISTS)
    review = Review(
        listing_id=listing.id,
        interaction_id=interaction.id,
        kind=listing.kind,
        author_id=actor_id,
        subject_id=subject_id,
        rating=validate_rating(data.rating),
        text=validate_text(data.text, settings),
        reveal_at=closes,
        published_at=None,
        hidden_at=None,
        hidden_by_id=None,
    )
    review.tags = [
        ReviewTag(tag=tag) for tag in validate_tags(listing.kind, data.tags, settings)
    ]
    session.add(review)
    if one_way(listing):
        review.published_at = now
        await _record_reveal(session, listing, interaction, 1, now)
    else:
        counterpart = await counterpart_review(session, listing, interaction, actor_id)
        if counterpart is None:
            await schedule_deadline(
                session,
                REVIEW_REVEAL_TOPIC,
                closes,
                {
                    "listing_id": str(listing.id),
                    "interaction_id": str(interaction.id),
                },
                key=reveal_key(interaction.id),
            )
        else:
            review.published_at = now
            revealed = 1
            if counterpart.published_at is None:
                counterpart.published_at = now
                revealed += 1
            await cancel_deadline(session, reveal_key(interaction.id))
            await _record_reveal(session, listing, interaction, revealed, now)
    await session.flush()
    return await review_state(session, listing, interaction, actor_id, settings)


async def edit_review(  # noqa: PLR0913, PLR0917 - request context
    session: AsyncSession,
    listing_id: UUID,
    interaction_id: UUID,
    actor_id: UUID,
    data: ReviewInput,
    settings: Settings,
) -> ReviewState:
    """Replace the fields of the author's review before it is revealed."""
    listing, interaction = await review_context(session, listing_id, interaction_id)
    require_participant(listing, interaction, actor_id)
    review = await own_review(session, listing, interaction, actor_id)
    if review is None:
        raise ProblemError(NOT_FOUND)
    if review.hidden_at is not None:
        raise ProblemError(REVIEW_HIDDEN)
    now = clock.now()
    completed = completion_moment(listing, interaction, now)
    if (
        review.published_at is not None
        or completed is None
        or now >= window_closes(completed, settings)
    ):
        raise ProblemError(REVIEW_PUBLISHED)
    review.rating = validate_rating(data.rating)
    review.text = validate_text(data.text, settings)
    review.tags = [
        ReviewTag(tag=tag) for tag in validate_tags(listing.kind, data.tags, settings)
    ]
    await session.flush()
    return await review_state(session, listing, interaction, actor_id, settings)


async def reply_to_review(  # noqa: PLR0913, PLR0917 - request context
    session: AsyncSession,
    listing_id: UUID,
    interaction_id: UUID,
    actor_id: UUID,
    text: str,
    settings: Settings,
) -> ReviewState:
    """The addressee answers the revealed review about them exactly once."""
    listing, interaction = await review_context(session, listing_id, interaction_id)
    require_participant(listing, interaction, actor_id)
    review = await counterpart_review(session, listing, interaction, actor_id)
    if review is None or not public(review):
        # The review is not readable by the addressee yet: its existence is
        # hidden as well, so the answer is a plain 404.
        raise ProblemError(NOT_FOUND)
    if review.reply is not None:
        raise ProblemError(REVIEW_REPLY_EXISTS)
    reply = ReviewReply(
        review_id=review.id,
        author_id=actor_id,
        text=validate_reply(text, settings),
    )
    # Keep the loaded review in step with the new row: the same objects stay
    # in the session, and the state would otherwise read the cached empty
    # relationship instead of the answer just written.
    review.reply = reply
    listing.version += 1
    append_event(
        session,
        listing,
        actor_id,
        "review_replied",
        interaction.status,
        interaction,
        details={"review_id": str(review.id)},
    )
    queue_review(
        session,
        listing,
        {
            "kind": "replied",
            "interaction_id": str(interaction.id),
            "review_id": str(review.id),
        },
        {review.author_id},
    )
    await session.flush()
    return await review_state(session, listing, interaction, actor_id, settings)


async def _record_reveal(
    session: AsyncSession,
    listing: Listing,
    interaction: Interaction,
    reviews: int,
    now: datetime,
) -> None:
    """Bump the aggregate and queue the metadata-only wakeup of a reveal."""
    listing.version += 1
    append_event(
        session,
        listing,
        None,
        "review_published",
        interaction.status,
        interaction,
        details={"reviews": reviews},
    )
    queue_review(
        session,
        listing,
        {"kind": "published", "interaction_id": str(interaction.id)},
        {listing.author_id, interaction.participant_id},
        occurred_at=now,
    )


def queue_review(
    session: AsyncSession,
    listing: Listing,
    payload: dict[str, Any],
    recipients: set[UUID],
    *,
    occurred_at: datetime | None = None,
) -> None:
    """Queue a metadata-only realtime wakeup in the change transaction.

    The payload never carries a rating, a tag or a text: realtime is only a
    hint that a committed change exists, and the client reloads the
    authoritative state through the API.
    """
    add_message(
        session,
        REVIEW_TOPIC,
        {
            "listing_id": str(listing.id),
            "version": listing.version,
            "occurred_at": (occurred_at or clock.now()).isoformat(),
            "recipients": sorted(str(value) for value in recipients),
            **payload,
        },
    )


@outbox_handlers.register(REVIEW_TOPIC)
async def _publish_review(_session: AsyncSession, job: JobInfo) -> None:
    """Publish the committed wakeup to the personal channel of each recipient."""
    from campus.modules.realtime import publish_personal  # noqa: PLC0415

    payload = dict(job.payload)
    recipients = [UUID(str(value)) for value in payload.pop("recipients", [])]
    for recipient in recipients:
        await publish_personal(recipient, payload, uuid5(job.id, str(recipient)))


@deadline_handlers.register(REVIEW_REVEAL_TOPIC)
async def reveal_due_reviews(session: AsyncSession, job: JobInfo) -> None:
    """Publish every review whose window has closed; safe to run again.

    The handler locks the listing aggregate first, so a concurrent second
    review, an edit or another run of the same deadline either commits
    before this one (and the review is already published) or waits and then
    sees the result. A missed deadline is simply due on the next run.
    """
    listing = await locked(session, UUID(job.payload["listing_id"]))
    interaction = await session.get(Interaction, UUID(job.payload["interaction_id"]))
    if interaction is None:
        return
    settings = get_settings()
    now = clock.now()
    completed = completion_moment(listing, interaction, now)
    if completed is None or now < window_closes(completed, settings):
        return
    pending = [
        review
        for review in await pair_reviews(session, listing, interaction)
        if review.published_at is None
    ]
    if not pending:
        return
    for review in pending:
        review.published_at = now
    await _record_reveal(session, listing, interaction, len(pending), now)
    await session.flush()


def reviews_about(subject_id: UUID) -> Select[Review]:
    """The public reviews about a user, newest first."""
    return select(Review).where(
        Review.subject_id == subject_id,
        Review.published_at.is_not(None),
        Review.hidden_at.is_(None),
    )


__all__ = [
    "REVIEW_REVEAL_TOPIC",
    "REVIEW_TAGS",
    "REVIEW_TOPIC",
    "ReviewInput",
    "ReviewState",
    "completion_moment",
    "counterpart_review",
    "create_review",
    "edit_review",
    "one_way",
    "other_side",
    "own_review",
    "pair_query",
    "pair_reviews",
    "public",
    "queue_review",
    "reply_to_review",
    "reveal_due_reviews",
    "reveal_key",
    "review_context",
    "review_read_context",
    "review_state",
    "review_tags",
    "reviews_about",
    "validate_rating",
    "validate_reply",
    "validate_tags",
    "validate_text",
    "window_closes",
]
