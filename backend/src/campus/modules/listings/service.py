"""Shared aggregate state machines, policies and transactional side effects."""

import math
from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Any
from uuid import UUID

from sqlalchemy import func, select, text
from sqlalchemy.ext.asyncio import AsyncSession

from campus.core import clock
from campus.core.config import Settings, get_settings
from campus.core.deadlines import cancel_deadline, deadline_handlers, schedule_deadline
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
    Meeting,
    Visibility,
    WaitlistEntry,
    WaitlistStatus,
)
from campus.modules.notifications import (
    LISTING_OFFER,
    LISTING_OFFER_EXPIRED,
    LISTING_WAITLIST_CLEARED,
    LISTING_WAITLIST_JOINED,
    LISTING_WAITLIST_OPEN,
    notify,
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
INVALID_CATEGORY = ProblemType(
    "listing_category_invalid", 422, N_("Choose a listing category.")
)
RATE_LIMIT = ProblemType(
    "listing_rate_limited", 429, N_("Too many listing actions. Try again later.")
)
MEETING_TIME_INVALID = ProblemType(
    "meeting_time_invalid",
    422,
    N_("Invalid meeting time"),
    N_("The meeting time must be in the future."),
)
MEETING_PLACE_INVALID = ProblemType(
    "meeting_place_invalid",
    422,
    N_("Invalid meeting place"),
    N_("The meeting place must not be empty or too long."),
)
MEETING_STATE = ProblemType(
    "meeting_state_conflict",
    409,
    N_("The meeting cannot be changed."),
    N_("The interaction must be accepted and have a current meeting proposal."),
)
MEETING_STALE = ProblemType(
    "meeting_stale",
    409,
    N_("The meeting proposal has changed."),
    N_("Reload the interaction. The current meeting version is {version}."),
)

MEETING_PROPOSED = N_("A meeting time and place were proposed.")
MEETING_SCHEDULED = N_("The meeting is scheduled.")
MEETING_RESCHEDULED = N_("The meeting has been rescheduled.")
MEETING_REMINDER = N_("Your meeting starts soon.")
WAITLIST_FREE = ProblemType(
    "listing_waitlist_free",
    409,
    N_("The listing still has a free place."),
    N_("Book the listing instead of joining its queue."),
)
WAITLIST_DUPLICATE = ProblemType(
    "listing_waitlist_duplicate",
    409,
    N_("You are already in the queue."),
    N_("Leave the queue before joining it again."),
)
WAITLIST_PARTICIPATING = ProblemType(
    "listing_waitlist_participating",
    409,
    N_("You already participate in this listing."),
    N_("Cancel your application before joining the queue."),
)
WAITLIST_UNAVAILABLE = ProblemType(
    "listing_waitlist_unavailable",
    409,
    N_("This listing has no queue."),
    N_("The listing type has no limited places to wait for."),
)
OFFER_PENDING = ProblemType(
    "listing_offer_pending",
    409,
    N_("The place is offered to another participant."),
    N_("Wait for the offer timer to end or join the queue."),
)
OFFER_MISSING = ProblemType(
    "listing_offer_missing",
    409,
    N_("You have no offer of a place."),
)
OFFER_EXPIRED = ProblemType(
    "listing_offer_expired",
    409,
    N_("The offer of a place has expired."),
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

# Closed listings that only history refers to; archive cleanup counts the
# retention period from the moment a listing entered one of them.
ARCHIVED = frozenset(
    {ListingStatus.EXPIRED, ListingStatus.COMPLETED, ListingStatus.CANCELLED}
)


@dataclass(frozen=True)
class TypePolicy:
    """Types extend accepted stages without adding aggregate statuses.

    ``capacity`` is the number of simultaneously active slots; ``None``
    means unlimited, so the listing never has a queue. ``start_time``
    resolves the start of a concrete listing for the rule that opens the
    last places to everyone shortly before it.
    """

    author_response_deadline: bool
    initial_stage: str | None = None
    stage_transitions: frozenset[tuple[str, str]] = frozenset()
    capacity: int | None = None
    start_time: Callable[[Listing], datetime | None] | None = None


TYPE_POLICIES = {
    "giveaway": TypePolicy(author_response_deadline=True, capacity=1),
}


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


def listing_start(listing: Listing) -> datetime | None:
    """Start time of a listing whose type has one; ``None`` otherwise."""
    resolver = TYPE_POLICIES[listing.kind].start_time
    return resolver(listing) if resolver is not None else None


def offer_timing(
    settings: Settings | None = None, payload: dict[str, Any] | None = None
) -> tuple[timedelta, timedelta]:
    """Offer timer and the 'open to all' lead, from config or a job payload.

    A deadline carries the values it was scheduled with, so an expiry that
    is processed later still moves the next offer with the same policy.
    """
    settings = settings or get_settings()
    if payload:
        timeout = payload.get("offer_timeout")
        lead = payload.get("open_all_before")
        if timeout is not None and lead is not None:
            return timedelta(seconds=timeout), timedelta(seconds=lead)
    return settings.listing_offer_timeout, settings.listing_open_to_all_before


def offer_key(entry_id: UUID) -> str:
    return f"waitlist-offer:{entry_id}"


async def active_waitlist(
    session: AsyncSession, listing_id: UUID, participant_id: UUID
) -> WaitlistEntry | None:
    return await session.scalar(
        select(WaitlistEntry).where(
            WaitlistEntry.listing_id == listing_id,
            WaitlistEntry.participant_id == participant_id,
            WaitlistEntry.status.in_((WaitlistStatus.WAITING, WaitlistStatus.OFFERED)),
        )
    )


async def active_offer(session: AsyncSession, listing_id: UUID) -> WaitlistEntry | None:
    return await session.scalar(
        select(WaitlistEntry).where(
            WaitlistEntry.listing_id == listing_id,
            WaitlistEntry.status == WaitlistStatus.OFFERED,
        )
    )


async def has_free_slot(session: AsyncSession, listing: Listing) -> bool:
    """Whether the listing has an unoccupied slot, by its type's capacity."""
    capacity = TYPE_POLICIES[listing.kind].capacity
    if capacity is None:
        return True
    occupied = await session.scalar(
        select(func.count())
        .select_from(Interaction)
        .where(
            Interaction.listing_id == listing.id,
            Interaction.status.in_(
                (InteractionStatus.PENDING, InteractionStatus.ACCEPTED)
            ),
            Interaction.slot.is_not(None),
        )
    )
    return (occupied or 0) < capacity


async def waitlist_position(session: AsyncSession, entry: WaitlistEntry) -> int | None:
    """One-based position among the waiting and offered entries."""
    if entry.status not in (WaitlistStatus.WAITING, WaitlistStatus.OFFERED):
        return None
    ids = list(
        await session.scalars(
            select(WaitlistEntry.id)
            .where(
                WaitlistEntry.listing_id == entry.listing_id,
                WaitlistEntry.status.in_(
                    (WaitlistStatus.WAITING, WaitlistStatus.OFFERED)
                ),
            )
            .order_by(WaitlistEntry.created_at, WaitlistEntry.id)
        )
    )
    return ids.index(entry.id) + 1


def record_waitlist(  # noqa: PLR0913, PLR0917 - event fields
    session: AsyncSession,
    listing: Listing,
    actor_id: UUID | None,
    action: str,
    entry: WaitlistEntry,
    previous: str | None = None,
    *,
    reason: str | None = None,
) -> None:
    """Append a queue entry transition to the listing history."""
    session.add(
        ListingEvent(
            listing_id=listing.id,
            actor_id=actor_id,
            action=action,
            previous_status=previous,
            status=entry.status,
            waitlist_entry_id=entry.id,
            version=listing.version,
            reason=reason,
        )
    )


async def join_waitlist(
    session: AsyncSession, listing: Listing, user: User
) -> WaitlistEntry:
    """Take the last place of the queue, when the listing has no free slot."""
    if TYPE_POLICIES[listing.kind].capacity is None:
        raise ProblemError(WAITLIST_UNAVAILABLE)
    if await active_waitlist(session, listing.id, user.id) is not None:
        raise ProblemError(WAITLIST_DUPLICATE)
    participating = await session.scalar(
        select(Interaction.id).where(
            Interaction.listing_id == listing.id,
            Interaction.participant_id == user.id,
            Interaction.status.in_(
                (InteractionStatus.PENDING, InteractionStatus.ACCEPTED)
            ),
        )
    )
    if participating is not None:
        raise ProblemError(WAITLIST_PARTICIPATING)
    if await has_free_slot(session, listing) and (
        await active_offer(session, listing.id) is None
    ):
        raise ProblemError(WAITLIST_FREE)
    entry = WaitlistEntry(
        listing_id=listing.id, participant_id=user.id, participant=user
    )
    session.add(entry)
    await session.flush()
    record_waitlist(session, listing, user.id, "waitlisted", entry)
    notify(
        session,
        {listing.author_id},
        "listing.waitlist_joined",
        {
            "listing_id": str(listing.id),
            "entry_id": str(entry.id),
            "position": await waitlist_position(session, entry),
        },
        message=LISTING_WAITLIST_JOINED,
    )
    return entry


async def clear_waitlist(session: AsyncSession, listing: Listing, reason: str) -> None:
    """Remove the remaining queue and tell every member about the closure."""
    entries = list(
        await session.scalars(
            select(WaitlistEntry)
            .where(
                WaitlistEntry.listing_id == listing.id,
                WaitlistEntry.status.in_(
                    (WaitlistStatus.WAITING, WaitlistStatus.OFFERED)
                ),
            )
            .order_by(WaitlistEntry.created_at, WaitlistEntry.id)
            .with_for_update()
        )
    )
    for entry in entries:
        previous = entry.status
        entry.status = WaitlistStatus.REMOVED
        if previous == WaitlistStatus.OFFERED:
            await cancel_deadline(session, offer_key(entry.id))
        record_waitlist(
            session, listing, None, "waitlist_cleared", entry, previous, reason=reason
        )
        notify(
            session,
            {entry.participant_id},
            "listing.waitlist_cleared",
            {"listing_id": str(listing.id), "entry_id": str(entry.id)},
            message=LISTING_WAITLIST_CLEARED,
        )


async def open_to_all(session: AsyncSession, listing: Listing) -> None:
    """Announce once that, close to the start, places are open to everyone."""
    entries = list(
        await session.scalars(
            select(WaitlistEntry).where(
                WaitlistEntry.listing_id == listing.id,
                WaitlistEntry.status.in_(
                    (WaitlistStatus.WAITING, WaitlistStatus.OFFERED)
                ),
            )
        )
    )
    if not entries:
        return
    announced = await session.scalar(
        select(ListingEvent.id).where(
            ListingEvent.listing_id == listing.id,
            ListingEvent.action == "waitlist_opened",
        )
    )
    if announced is not None:
        return
    listing.version += 1
    session.add(
        ListingEvent(
            listing_id=listing.id,
            actor_id=None,
            action="waitlist_opened",
            status=listing.status,
            version=listing.version,
        )
    )
    notify(
        session,
        {entry.participant_id for entry in entries},
        "listing.waitlist_open",
        {"listing_id": str(listing.id)},
        message=LISTING_WAITLIST_OPEN,
    )


async def offer_next(  # noqa: PLR0911 - early exits of the offer rule
    session: AsyncSession,
    listing: Listing,
    *,
    offer_timeout: timedelta,
    open_all_before: timedelta,
) -> WaitlistEntry | None:
    """Offer the free slot to the first in the queue, or open it to everyone.

    The caller holds the listing row lock, so the offer and the slot check
    are serialized with reservations and other queue changes.
    """
    if listing.status not in (ListingStatus.ACTIVE, ListingStatus.BUSY):
        return None
    if listing.expires_at is not None and listing.expires_at <= clock.now():
        return None
    if not await has_free_slot(session, listing):
        return None
    if await active_offer(session, listing.id) is not None:
        return None
    now = clock.now()
    starts_at = listing_start(listing)
    if starts_at is not None and starts_at - now <= open_all_before:
        await open_to_all(session, listing)
        return None
    entry = await session.scalar(
        select(WaitlistEntry)
        .where(
            WaitlistEntry.listing_id == listing.id,
            WaitlistEntry.status == WaitlistStatus.WAITING,
        )
        .order_by(WaitlistEntry.created_at, WaitlistEntry.id)
        .limit(1)
        .with_for_update()
    )
    if entry is None:
        return None
    expires_at = now + offer_timeout
    if starts_at is not None:
        expires_at = min(expires_at, starts_at - open_all_before)
    previous = entry.status
    entry.status = WaitlistStatus.OFFERED
    entry.offered_at = now
    entry.offer_expires_at = expires_at
    listing.version += 1
    record_waitlist(session, listing, None, "offered", entry, previous)
    notify(
        session,
        {entry.participant_id},
        "listing.offer",
        {
            "listing_id": str(listing.id),
            "entry_id": str(entry.id),
            "offer_expires_at": expires_at.isoformat(),
        },
        message=LISTING_OFFER,
    )
    await schedule_deadline(
        session,
        "listing.offer",
        expires_at,
        {
            "entry_id": str(entry.id),
            "offer_timeout": int(offer_timeout.total_seconds()),
            "open_all_before": int(open_all_before.total_seconds()),
        },
        key=offer_key(entry.id),
    )
    return entry


async def claim_offer(
    session: AsyncSession,
    listing: Listing,
    user: User,
    settings: Settings,
) -> Interaction:
    """Turn the caller's offer into an application, occupying the slot.

    The caller holds the listing row lock, so a concurrent reservation of
    the same item either happens before (and this offer is gone) or after
    (and is rejected because the listing is busy).
    """
    entry = await active_waitlist(session, listing.id, user.id)
    if entry is None or entry.status != WaitlistStatus.OFFERED:
        raise ProblemError(OFFER_MISSING)
    if entry.offer_expires_at is None or entry.offer_expires_at <= clock.now():
        raise ProblemError(OFFER_EXPIRED)
    require_live(listing)
    if listing.status != ListingStatus.ACTIVE or not await has_free_slot(
        session, listing
    ):
        raise ProblemError(CONFLICT)
    interaction = Interaction(
        listing_id=listing.id,
        participant_id=user.id,
        participant=user,
        response_due_at=clock.now() + settings.listing_response_timeout
        if TYPE_POLICIES[listing.kind].author_response_deadline
        else None,
    )
    session.add(interaction)
    await session.flush()
    previous = entry.status
    entry.status = WaitlistStatus.CLAIMED
    entry.interaction_id = interaction.id
    await cancel_deadline(session, offer_key(entry.id))
    change_listing(session, listing, ListingStatus.BUSY, user.id, "reserved")
    record_waitlist(session, listing, user.id, "offer_accepted", entry, previous)
    if interaction.response_due_at is not None:
        await schedule_deadline(
            session,
            "listing.author_response",
            interaction.response_due_at,
            {
                "listing_id": str(listing.id),
                "interaction_id": str(interaction.id),
            },
            key=f"interaction:{interaction.id}",
        )
    return interaction


async def decline_offer(
    session: AsyncSession,
    listing: Listing,
    user: User,
    *,
    offer_timeout: timedelta,
    open_all_before: timedelta,
) -> WaitlistEntry:
    """Give up an offer; the place is offered to the next member at once."""
    entry = await active_waitlist(session, listing.id, user.id)
    if entry is None or entry.status != WaitlistStatus.OFFERED:
        raise ProblemError(OFFER_MISSING)
    previous = entry.status
    entry.status = WaitlistStatus.DECLINED
    await cancel_deadline(session, offer_key(entry.id))
    listing.version += 1
    record_waitlist(session, listing, user.id, "offer_declined", entry, previous)
    await offer_next(
        session,
        listing,
        offer_timeout=offer_timeout,
        open_all_before=open_all_before,
    )
    return entry


async def leave_waitlist(
    session: AsyncSession,
    listing: Listing,
    user: User,
    *,
    offer_timeout: timedelta,
    open_all_before: timedelta,
) -> None:
    entry = await active_waitlist(session, listing.id, user.id)
    if entry is None:
        raise ProblemError(NOT_FOUND)
    previous = entry.status
    entry.status = WaitlistStatus.LEFT
    action = "waitlist_left"
    if previous == WaitlistStatus.OFFERED:
        action = "offer_declined"
        await cancel_deadline(session, offer_key(entry.id))
        listing.version += 1
    record_waitlist(session, listing, user.id, action, entry, previous)
    if previous == WaitlistStatus.OFFERED:
        await offer_next(
            session,
            listing,
            offer_timeout=offer_timeout,
            open_all_before=open_all_before,
        )


async def expire_offer(
    session: AsyncSession,
    listing: Listing,
    entry: WaitlistEntry,
    *,
    offer_timeout: timedelta,
    open_all_before: timedelta,
) -> None:
    """Mark an unconfirmed offer expired and move it to the next member."""
    previous = entry.status
    entry.status = WaitlistStatus.EXPIRED
    listing.version += 1
    record_waitlist(session, listing, None, "offer_expired", entry, previous)
    notify(
        session,
        {entry.participant_id},
        "listing.offer_expired",
        {"listing_id": str(listing.id), "entry_id": str(entry.id)},
        message=LISTING_OFFER_EXPIRED,
    )
    await offer_next(
        session,
        listing,
        offer_timeout=offer_timeout,
        open_all_before=open_all_before,
    )


@deadline_handlers.register("listing.offer")
async def expire_offered_place(session: AsyncSession, job: JobInfo) -> None:
    entry_id = UUID(job.payload["entry_id"])
    entry = await session.get(WaitlistEntry, entry_id)
    if entry is None:
        return
    listing = await locked(session, entry.listing_id)
    # The entry may have changed while this job waited for the listing lock.
    await session.refresh(entry, with_for_update=True)
    if (
        entry.status != WaitlistStatus.OFFERED
        or entry.offer_expires_at is None
        or entry.offer_expires_at > clock.now()
    ):
        return
    offer_timeout, open_all_before = offer_timing(payload=job.payload)
    await expire_offer(
        session,
        listing,
        entry,
        offer_timeout=offer_timeout,
        open_all_before=open_all_before,
    )


def append_event(  # noqa: PLR0913, PLR0917 - event fields
    session: AsyncSession,
    listing: Listing,
    actor_id: UUID | None,
    action: str,
    previous: str | None,
    interaction: Interaction | None = None,
    *,
    reason: str | None = None,
    details: dict[str, Any] | None = None,
    via_assistant: bool = False,
    offline_qr: bool = False,
) -> None:
    """Append a journal entry without notification; callers notify themselves."""
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
            details=details,
            via_assistant=via_assistant,
            offline_qr=offline_qr,
        )
    )


def record(  # noqa: PLR0913, PLR0917 - event fields
    session: AsyncSession,
    listing: Listing,
    actor_id: UUID | None,
    action: str,
    previous: str | None,
    interaction: Interaction | None = None,
    *,
    reason: str | None = None,
    details: dict[str, Any] | None = None,
    via_assistant: bool = False,
    offline_qr: bool = False,
) -> None:
    append_event(
        session,
        listing,
        actor_id,
        action,
        previous,
        interaction,
        reason=reason,
        details=details,
        via_assistant=via_assistant,
        offline_qr=offline_qr,
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
    listing.archived_at = clock.now() if target in ARCHIVED else None
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
    await clear_waitlist(session, listing, "listing_expired")
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
    released = False
    if listing.status == ListingStatus.BUSY:
        change_listing(session, listing, ListingStatus.ACTIVE, None, "released")
        released = True
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
    if released:
        offer_timeout, open_all_before = offer_timing(payload=job.payload)
        await offer_next(
            session,
            listing,
            offer_timeout=offer_timeout,
            open_all_before=open_all_before,
        )


def require_live(listing: Listing) -> None:
    if (
        (listing.expires_at is None and listing.kind != "publication")
        or (listing.expires_at is not None and listing.expires_at <= clock.now())
        or listing.status not in (ListingStatus.ACTIVE, ListingStatus.BUSY)
    ):
        raise ProblemError(CONFLICT)


async def transition(  # noqa: PLR0913 - aggregate transition
    session: AsyncSession,
    listing: Listing,
    interaction: Interaction,
    target: InteractionStatus,
    actor_id: UUID | None,
    *,
    settings: Settings | None = None,
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
    if previous == InteractionStatus.ACCEPTED:
        # Reminders belong to an accepted interaction only.
        await cancel_meeting_reminders(session, interaction.id)
    released = False
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
            released = True
    elif target == InteractionStatus.COMPLETED and listing.status == ListingStatus.BUSY:
        change_listing(session, listing, ListingStatus.COMPLETED, actor_id, "completed")
        await clear_waitlist(session, listing, "listing_completed")
    else:
        listing.version += 1
    record(session, listing, actor_id, "transition", previous, interaction)
    if released:
        offer_timeout, open_all_before = offer_timing(settings)
        await offer_next(
            session,
            listing,
            offer_timeout=offer_timeout,
            open_all_before=open_all_before,
        )
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


def validate_meeting(time: datetime, place: str, settings: Settings) -> str:
    """Return the normalized place; reject a past time and a bad place."""
    if time <= clock.now():
        raise ProblemError(MEETING_TIME_INVALID)
    normalized = place.strip()
    if not normalized or len(normalized) > settings.meeting_place_max_length:
        raise ProblemError(MEETING_PLACE_INVALID)
    return normalized


def record_meeting(  # noqa: PLR0913, PLR0917 - event fields
    session: AsyncSession,
    listing: Listing,
    interaction: Interaction,
    actor_id: UUID,
    action: str,
    details: dict[str, Any],
) -> None:
    """Journal a meeting action; the endpoint notifies the other participant."""
    previous = interaction.status
    listing.version += 1
    append_event(
        session,
        listing,
        actor_id,
        action,
        previous,
        interaction,
        details=details,
    )


MEETING_REMINDER_TOPIC = "listing.meeting_reminder"
MEETING_REMINDER_KINDS = ("long", "short")


def meeting_reminder_key(interaction_id: UUID, kind: str) -> str:
    return f"meeting:{interaction_id}:{kind}"


async def cancel_meeting_reminders(session: AsyncSession, interaction_id: UUID) -> None:
    """Drop the pending reminders of a meeting, if any are still scheduled."""
    for kind in MEETING_REMINDER_KINDS:
        await cancel_deadline(session, meeting_reminder_key(interaction_id, kind))


async def schedule_meeting_reminders(
    session: AsyncSession,
    settings: Settings,
    listing: Listing,
    interaction: Interaction,
    meeting: Meeting,
) -> None:
    """Replace the reminders of a meeting with the ones of its current time.

    A reminder whose time has already passed is not scheduled: a meeting
    arranged less than 24 hours ahead gets only the reminders still ahead.
    """
    await cancel_meeting_reminders(session, interaction.id)
    scheduled_at = meeting.scheduled_at
    if scheduled_at is None:
        return
    offsets = {
        "long": settings.meeting_reminder_long,
        "short": settings.meeting_reminder_short,
    }
    for kind, offset in offsets.items():
        due_at = scheduled_at - offset
        if due_at <= clock.now():
            continue
        await schedule_deadline(
            session,
            MEETING_REMINDER_TOPIC,
            due_at,
            {
                "listing_id": str(listing.id),
                "interaction_id": str(interaction.id),
                "version": meeting.version,
                "kind": kind,
                "time": scheduled_at.isoformat(),
            },
            key=meeting_reminder_key(interaction.id, kind),
        )


@deadline_handlers.register(MEETING_REMINDER_TOPIC)
async def remind_meeting(session: AsyncSession, job: JobInfo) -> None:
    listing = await locked(session, UUID(job.payload["listing_id"]))
    interaction = await session.get(Interaction, UUID(job.payload["interaction_id"]))
    if interaction is None or interaction.status != InteractionStatus.ACCEPTED:
        return
    meeting = await session.scalar(
        select(Meeting).where(Meeting.interaction_id == interaction.id)
    )
    if (
        meeting is None
        or meeting.scheduled_at is None
        or meeting.version != job.payload.get("version")
    ):
        return
    notify(
        session,
        {listing.author_id, interaction.participant_id},
        "listing.meeting.reminder",
        {
            "listing_id": str(listing.id),
            "interaction_id": str(interaction.id),
            "time": meeting.scheduled_at.isoformat(),
            "location": meeting.location,
            "kind": job.payload.get("kind"),
        },
        message=MEETING_REMINDER,
    )


async def hide(
    session: AsyncSession, listing: Listing, actor_id: UUID, reason: str
) -> None:
    """Moderation's trusted entry point; the caller checks moderator scope."""
    if not reason.strip():
        raise ProblemError(INVALID_CONTENT)
    listing.hidden_reason = reason
    change_listing(session, listing, ListingStatus.HIDDEN, actor_id, "hidden")
    await reject_pending(session, listing, "listing_hidden")
    await clear_waitlist(session, listing, "listing_hidden")


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
