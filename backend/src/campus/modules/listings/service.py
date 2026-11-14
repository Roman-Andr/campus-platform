"""Shared aggregate state machines, policies and transactional side effects."""

import math
from dataclasses import dataclass
from datetime import timedelta
from uuid import UUID

from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from campus.core import clock
from campus.core.deadlines import deadline_handlers
from campus.core.i18n import N_
from campus.core.jobs import JobInfo
from campus.core.web import ProblemError, ProblemType
from campus.core.web.problems import NOT_FOUND
from campus.modules.identity import User
from campus.modules.listings.models import (
    Audience,
    Interaction,
    InteractionStatus,
    Listing,
    ListingEvent,
    ListingStatus,
    Visibility,
)
from campus.modules.notifications import notify
from campus.modules.university import AccountType

FORBIDDEN = ProblemType("listing_forbidden", 403, N_("This action is not allowed."))
CONFLICT = ProblemType("listing_conflict", 409, N_("The listing state has changed."))
STALE = ProblemType(
    "listing_version_conflict",
    409,
    N_("The listing was edited."),
    N_("Reload the listing. Its current version is {version}."),
)
INVALID_CONTENT = ProblemType(
    "listing_content_invalid", 422, N_("The listing text is empty or too long.")
)
INVALID_CATEGORY = ProblemType(
    "listing_category_invalid", 422, N_("Choose a listing category.")
)
RATE_LIMIT = ProblemType(
    "listing_rate_limited", 429, N_("Too many listing actions. Try again later.")
)

# Completion and no-show are service-only transitions, called by the QR module.
TRANSITIONS = {
    (InteractionStatus.PENDING, InteractionStatus.ACCEPTED): "author",
    (InteractionStatus.PENDING, InteractionStatus.REJECTED): "author",
    (InteractionStatus.PENDING, InteractionStatus.CANCELLED): "participant",
    (InteractionStatus.ACCEPTED, InteractionStatus.CANCELLED): "participant",
    (InteractionStatus.ACCEPTED, InteractionStatus.COMPLETED): "system",
    (InteractionStatus.ACCEPTED, InteractionStatus.NO_SHOW): "system",
}
LISTING_TRANSITIONS = {
    ListingStatus.DRAFT: {ListingStatus.ACTIVE, ListingStatus.CANCELLED},
    ListingStatus.ACTIVE: {
        ListingStatus.BUSY,
        ListingStatus.CANCELLED,
        ListingStatus.EXPIRED,
        ListingStatus.HIDDEN,
    },
    ListingStatus.BUSY: {
        ListingStatus.ACTIVE,
        ListingStatus.COMPLETED,
        ListingStatus.CANCELLED,
        ListingStatus.EXPIRED,
        ListingStatus.HIDDEN,
    },
    ListingStatus.EXPIRED: {
        ListingStatus.ACTIVE,
        ListingStatus.BUSY,
        ListingStatus.HIDDEN,
    },
    ListingStatus.COMPLETED: {ListingStatus.HIDDEN},
    ListingStatus.CANCELLED: {ListingStatus.HIDDEN},
    ListingStatus.HIDDEN: set(),
}


@dataclass(frozen=True)
class TypePolicy:
    """Types extend accepted stages without adding aggregate statuses."""

    author_response_deadline: bool
    initial_stage: str | None = None
    stage_transitions: frozenset[tuple[str, str]] = frozenset()


TYPE_POLICIES = {"giveaway": TypePolicy(author_response_deadline=True)}


def visible(listing: Listing, user: User) -> bool:
    if listing.status in (ListingStatus.DRAFT, ListingStatus.HIDDEN):
        return False
    if listing.visibility != Visibility.UNIVERSITY and listing.city_id != user.city_id:
        return False
    if user.account_type != AccountType.STUDENT and (
        listing.audience == Audience.STUDENTS
        or listing.visibility == Visibility.DORMITORY
    ):
        return False
    if listing.visibility == Visibility.DORMITORY:
        return listing.dormitory_id == user.dormitory_id
    if listing.visibility == Visibility.FACULTY:
        return listing.faculty_id == user.faculty_id
    return True


async def locked(session: AsyncSession, listing_id: UUID) -> Listing:
    listing = await session.scalar(
        select(Listing).where(Listing.id == listing_id).with_for_update(of=Listing)
    )
    if listing is None:
        raise ProblemError(NOT_FOUND)
    return listing


def record(  # noqa: PLR0913, PLR0917 - event fields
    session: AsyncSession,
    listing: Listing,
    actor_id: UUID | None,
    action: str,
    previous: str | None,
    interaction: Interaction | None = None,
    *,
    reason: str | None = None,
    via_assistant: bool = False,
    offline_qr: bool = False,
) -> None:
    session.add(
        ListingEvent(
            listing_id=listing.id,
            actor_id=actor_id,
            action=action,
            previous_status=previous,
            status=interaction.status if interaction else listing.status,
            interaction_id=interaction.id if interaction else None,
            version=listing.version,
            reason=reason,
            stage=interaction.stage if interaction else None,
            via_assistant=via_assistant,
            offline_qr=offline_qr,
        )
    )
    recipients = {listing.author_id}
    if interaction:
        recipients.add(interaction.participant_id)
    notify(
        session,
        recipients,
        "listing.activity",
        {
            "listing_id": str(listing.id),
            "interaction_id": str(interaction.id) if interaction else None,
            "action": action,
            "status": interaction.status if interaction else listing.status,
            "reason": reason,
            "version": listing.version,
        },
    )


def change_listing(
    session: AsyncSession,
    listing: Listing,
    target: ListingStatus,
    actor_id: UUID | None,
    action: str,
) -> None:
    if target not in LISTING_TRANSITIONS[ListingStatus(listing.status)]:
        raise ProblemError(CONFLICT)
    previous = listing.status
    listing.status = target
    listing.version += 1
    record(session, listing, actor_id, action, previous, reason=listing.hidden_reason)


async def reject_pending(session: AsyncSession, listing: Listing, reason: str) -> None:
    pending = await session.scalars(
        select(Interaction).where(
            Interaction.listing_id == listing.id,
            Interaction.status == InteractionStatus.PENDING,
        )
    )
    for interaction in pending:
        interaction.status = InteractionStatus.REJECTED
        record(
            session,
            listing,
            None,
            "auto_rejected",
            InteractionStatus.PENDING,
            interaction,
            reason=reason,
        )


async def expire(session: AsyncSession, listing: Listing) -> None:
    """Accepted interactions survive closure and may finish afterwards."""
    if listing.status not in (ListingStatus.ACTIVE, ListingStatus.BUSY):
        return
    change_listing(session, listing, ListingStatus.EXPIRED, None, "expired")
    await reject_pending(session, listing, "listing_expired")
    await session.flush()


@deadline_handlers.register("listing.expire")
async def expire_listing(session: AsyncSession, job: JobInfo) -> None:
    listing = await locked(session, UUID(job.payload["listing_id"]))
    if listing.expires_at is not None and listing.expires_at <= clock.now():
        await expire(session, listing)


@deadline_handlers.register("listing.author_response")
async def expire_response(session: AsyncSession, job: JobInfo) -> None:
    listing = await locked(session, UUID(job.payload["listing_id"]))
    interaction = await session.get(Interaction, UUID(job.payload["interaction_id"]))
    if (
        interaction is None
        or interaction.status != InteractionStatus.PENDING
        or interaction.response_due_at is None
        or interaction.response_due_at > clock.now()
    ):
        return
    if listing.expires_at is not None and listing.expires_at <= clock.now():
        await expire(session, listing)
        return
    interaction.status = InteractionStatus.REJECTED
    if listing.status == ListingStatus.BUSY:
        change_listing(session, listing, ListingStatus.ACTIVE, None, "released")
    else:
        listing.version += 1
    record(
        session,
        listing,
        None,
        "auto_rejected",
        InteractionStatus.PENDING,
        interaction,
        reason="author_timeout",
    )


def require_live(listing: Listing) -> None:
    if (
        (listing.expires_at is None and listing.kind != "publication")
        or (listing.expires_at is not None and listing.expires_at <= clock.now())
        or listing.status not in (ListingStatus.ACTIVE, ListingStatus.BUSY)
    ):
        raise ProblemError(CONFLICT)


async def transition(
    session: AsyncSession,
    listing: Listing,
    interaction: Interaction,
    target: InteractionStatus,
    actor_id: UUID | None,
) -> None:
    expected = TRANSITIONS.get((InteractionStatus(interaction.status), target))
    if expected is None:
        raise ProblemError(CONFLICT)
    allowed_id = {
        "author": listing.author_id,
        "participant": interaction.participant_id,
        "system": None,
    }[expected]
    if actor_id != allowed_id:
        raise ProblemError(FORBIDDEN)
    if interaction.status == InteractionStatus.PENDING:
        require_live(listing)
        if (
            interaction.response_due_at is not None
            and interaction.response_due_at <= clock.now()
        ):
            raise ProblemError(CONFLICT)
    previous = interaction.status
    interaction.status = target
    interaction.stage = (
        TYPE_POLICIES[listing.kind].initial_stage
        if target == InteractionStatus.ACCEPTED
        else None
    )
    if (
        target
        in (
            InteractionStatus.REJECTED,
            InteractionStatus.CANCELLED,
            InteractionStatus.NO_SHOW,
        )
        and listing.status == ListingStatus.BUSY
    ):
        # A deadline that has elapsed must not reintroduce a listing to the feed.
        if listing.expires_at is not None and listing.expires_at <= clock.now():
            await expire(session, listing)
        else:
            change_listing(session, listing, ListingStatus.ACTIVE, actor_id, "released")
    elif target == InteractionStatus.COMPLETED and listing.status == ListingStatus.BUSY:
        change_listing(session, listing, ListingStatus.COMPLETED, actor_id, "completed")
    else:
        listing.version += 1
    record(session, listing, actor_id, "transition", previous, interaction)
    await session.flush()


def change_stage(
    session: AsyncSession,
    listing: Listing,
    interaction: Interaction,
    target: str,
    actor_id: UUID,
) -> None:
    """A type's trusted workflow calls this while holding the aggregate lock."""
    if actor_id not in (listing.author_id, interaction.participant_id):
        raise ProblemError(FORBIDDEN)
    if (
        interaction.status != InteractionStatus.ACCEPTED
        or (interaction.stage, target)
        not in TYPE_POLICIES[listing.kind].stage_transitions
    ):
        raise ProblemError(CONFLICT)
    interaction.stage = target
    listing.version += 1
    record(session, listing, actor_id, "stage_changed", interaction.status, interaction)


async def hide(
    session: AsyncSession, listing: Listing, actor_id: UUID, reason: str
) -> None:
    """Moderation's trusted entry point; the caller checks moderator scope."""
    if not reason.strip():
        raise ProblemError(INVALID_CONTENT)
    listing.hidden_reason = reason
    change_listing(session, listing, ListingStatus.HIDDEN, actor_id, "hidden")
    await reject_pending(session, listing, "listing_hidden")


async def rate_limit(
    session: AsyncSession, user_id: UUID, action: str, limit: int, window: timedelta
) -> int | None:
    """Serialize a user's attempts and count committed journal entries in SQL.

    The transaction lock makes concurrent requests respect the same limit;
    failed mutations and idempotent replays do not consume the quota.
    """
    await session.execute(
        text("SELECT pg_advisory_xact_lock(hashtextextended(:key, 0))"),
        {"key": f"listing-rate:{user_id}:{action}"},
    )
    times = list(
        await session.scalars(
            select(ListingEvent.created_at)
            .where(
                ListingEvent.actor_id == user_id,
                ListingEvent.action == action,
                ListingEvent.created_at > clock.now() - window,
            )
            .order_by(ListingEvent.created_at)
        )
    )
    if len(times) >= limit:
        return max(
            1,
            math.ceil(
                (times[len(times) - limit] + window - clock.now()).total_seconds()
            ),
        )
    return None
