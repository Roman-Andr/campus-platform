"""Aggregate operations and the explicit interaction transition table."""

from uuid import UUID

from sqlalchemy import select
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

# Actor is relative to the aggregate. All unlisted edges are forbidden.
TRANSITIONS = {
    (InteractionStatus.PENDING, InteractionStatus.ACCEPTED): "author",
    (InteractionStatus.PENDING, InteractionStatus.REJECTED): "author",
    (InteractionStatus.PENDING, InteractionStatus.CANCELLED): "participant",
    (InteractionStatus.ACCEPTED, InteractionStatus.CANCELLED): "participant",
}


def visible(listing: Listing, user: User) -> bool:
    if listing.city_id != user.city_id:
        return False
    if user.account_type == AccountType.EMPLOYEE and (
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
        select(Listing).where(Listing.id == listing_id).with_for_update()
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
        )
    )


def change_listing(
    session: AsyncSession,
    listing: Listing,
    target: ListingStatus,
    actor_id: UUID | None,
    action: str,
) -> None:
    previous = listing.status
    listing.status = target
    listing.version += 1
    record(session, listing, actor_id, action, previous)


async def expire(session: AsyncSession, listing: Listing) -> None:
    """An expired aggregate rejects pending requests, preserving accepted ones.

    Accepted interactions may finish later (QR is outside this slice).
    """
    if listing.status not in (ListingStatus.ACTIVE, ListingStatus.BUSY):
        return
    change_listing(session, listing, ListingStatus.EXPIRED, None, "expired")
    pending = await session.scalar(
        select(Interaction).where(
            Interaction.listing_id == listing.id,
            Interaction.status == InteractionStatus.PENDING,
        )
    )
    if pending is not None:
        previous = pending.status
        pending.status = InteractionStatus.REJECTED
        record(session, listing, None, "expired", previous, pending)
    await session.flush()


@deadline_handlers.register("listing.expire")
async def expire_listing(session: AsyncSession, job: JobInfo) -> None:
    listing = await locked(session, UUID(job.payload["listing_id"]))
    if listing.expires_at <= clock.now():
        await expire(session, listing)


def require_live(listing: Listing) -> None:
    if listing.expires_at <= clock.now() or listing.status not in (
        ListingStatus.ACTIVE,
        ListingStatus.BUSY,
    ):
        raise ProblemError(CONFLICT)


async def transition(
    session: AsyncSession,
    listing: Listing,
    interaction: Interaction,
    target: InteractionStatus,
    actor_id: UUID,
) -> None:
    expected = TRANSITIONS.get((InteractionStatus(interaction.status), target))
    if expected is None:
        raise ProblemError(CONFLICT)
    allowed_id = (
        listing.author_id if expected == "author" else interaction.participant_id
    )
    if actor_id != allowed_id:
        raise ProblemError(FORBIDDEN)
    require_live(listing)
    previous = interaction.status
    interaction.status = target
    if target in (InteractionStatus.REJECTED, InteractionStatus.CANCELLED):
        change_listing(session, listing, ListingStatus.ACTIVE, actor_id, "released")
    else:
        listing.version += 1
    record(session, listing, actor_id, "transition", previous, interaction)
    await session.flush()
