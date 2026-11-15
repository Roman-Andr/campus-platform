"""Shared aggregate state machines, policies and transactional side effects."""

import math
from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Any
from uuid import UUID, uuid5

from sqlalchemy import and_, func, or_, select, text
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
    PERMANENT_KINDS,
    Audience,
    CancellationActor,
    CompletionMethod,
    Interaction,
    InteractionStatus,
    LessonOption,
    LessonOptionStatus,
    Listing,
    ListingEvent,
    ListingStatus,
    Meeting,
    NoMeetingConfirmation,
    PurchaseStage,
    Visibility,
    WaitlistEntry,
    WaitlistStatus,
)
from campus.modules.notifications import (
    LISTING_CANCELLED,
    LISTING_OFFER,
    LISTING_OFFER_EXPIRED,
    LISTING_WAITLIST_CLEARED,
    LISTING_WAITLIST_JOINED,
    LISTING_WAITLIST_OPEN,
    PURCHASE_CANCELLED,
    PURCHASE_CANCELLED_BY_AUTHOR,
    PURCHASE_CONDITIONS_CHANGED,
    PURCHASE_FIXED,
    PURCHASE_REMINDER,
    PURCHASE_WITHDRAWAL_DECIDED,
    PURCHASE_WITHDRAWAL_REQUESTED,
    NotificationEvent,
    notify,
    register_validator,
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

INVALID_LESSON_OPTIONS = ProblemType(
    "lesson_options_invalid",
    422,
    N_("Invalid lesson time options"),
    N_("A lesson has from {min} to {max} time options."),
)
HELP_DEADLINE_INVALID = ProblemType(
    "help_deadline_invalid",
    422,
    N_("Invalid help deadline"),
    N_("The help request must expire in the future and within the listing lifetime."),
)

INVALID_EXCHANGE_OFFER = ProblemType(
    "exchange_offer_invalid",
    422,
    N_("Invalid offer"),
    N_("Describe the item you offer."),
)
EXCHANGE_OFFER_DUPLICATE = ProblemType(
    "exchange_offer_duplicate",
    409,
    N_("You already offered an item."),
    N_("Wait for the author's decision."),
)
NO_MEETING_UNAVAILABLE = ProblemType(
    "listing_no_meeting_unavailable",
    409,
    N_("This interaction cannot be completed without a meeting."),
    N_(
        "Only an accepted online lesson or a help interaction without an"
        " agreed meeting can be completed this way."
    ),
)
PURCHASE_DEADLINE_INVALID = ProblemType(
    "listing_purchase_deadline_invalid",
    422,
    N_("Invalid purchase deadline"),
    N_(
        "The collection deadline must be in the future and within the listing lifetime."
    ),
)
PURCHASE_VOLUME_INVALID = ProblemType(
    "listing_purchase_volume_invalid",
    422,
    N_("Invalid purchase volume"),
    N_("The minimum must not exceed the maximum, and both must be positive."),
)
PURCHASE_CLOSED = ProblemType(
    "listing_purchase_closed",
    409,
    N_("The purchase is no longer collecting."),
    N_("Only the composition exchange is available at this stage."),
)
PURCHASE_UNITS_UNAVAILABLE = ProblemType(
    "listing_purchase_units_unavailable",
    409,
    N_("Not enough units left."),
    N_("Only {available} units are available."),
)
PURCHASE_CAPACITY_CONFLICT = ProblemType(
    "listing_purchase_capacity_conflict",
    409,
    N_("The maximum is below the taken volume."),
    N_("The current volume is {taken} units."),
)
PURCHASE_APPROVAL_REQUIRED = ProblemType(
    "listing_purchase_leave_requires_approval",
    409,
    N_("The composition is fixed."),
    N_("Ask the organiser before leaving the purchase."),
)
PURCHASE_NOT_FIXED = ProblemType(
    "listing_purchase_not_fixed",
    409,
    N_("The composition is not fixed yet."),
    N_("Leave the purchase directly while it is collecting."),
)
PURCHASE_SHARE_EXISTS = ProblemType(
    "listing_purchase_share_exists",
    409,
    N_("You already joined the purchase."),
)
PURCHASE_WITHDRAWAL_EXISTS = ProblemType(
    "listing_purchase_withdrawal_exists",
    409,
    N_("You already asked to leave the purchase."),
)
PURCHASE_WITHDRAWAL_MISSING = ProblemType(
    "listing_purchase_withdrawal_missing",
    409,
    N_("You have no pending request to leave."),
)
CANCEL_REASON_REQUIRED = ProblemType(
    "listing_cancel_reason_required",
    422,
    N_("A cancellation reason is required."),
    N_("Accepted interactions can only be cancelled with a reason."),
)
CANCEL_REASON_INVALID = ProblemType(
    "listing_cancel_reason_invalid",
    422,
    N_("Invalid cancellation reason."),
    N_("The reason must be at most {max} characters."),
)

MEETING_PROPOSED = N_("A meeting time and place were proposed.")
# Two participants must confirm; the first consent only records the intent.
NO_MEETING_CONFIRMATIONS = 2
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
    "event": TypePolicy(
        False, capacity=1, start_time=lambda listing: listing.event_starts_at
    ),
    "giveaway": TypePolicy(author_response_deadline=True, capacity=1),
    # An exchange takes several offers; the author chooses one, no queue.
    "exchange": TypePolicy(author_response_deadline=False, capacity=None),
    # A skill listing is permanent and takes lessons from many participants.
    "skill": TypePolicy(author_response_deadline=True, capacity=None),
    # Applications are unlimited and stay pending; the author selects one.
    "help": TypePolicy(author_response_deadline=False),
    # A purchase takes shares of units; the author collects them until the
    # deadline, then the composition is fixed. The queue uses volumes.
    "purchase": TypePolicy(
        author_response_deadline=False,
        initial_stage=PurchaseStage.COLLECTING,
    ),
}

# Item kinds whose accepted reservation expires unless a meeting is scheduled.
RESERVATION_KINDS = frozenset({"giveaway", "exchange"})
RESERVATION_EXPIRED = "reservation_expired"
EXCHANGE_OFFER_DECLINED = "another_offer_accepted"


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


def interaction_start(listing: Listing, interaction: Interaction) -> datetime | None:
    """The moment before which a participant cancellation may be late."""
    meeting = interaction.meeting
    if meeting is not None and meeting.scheduled_at is not None:
        return meeting.scheduled_at
    return listing.event_starts_at


def normalized_cancellation_reason(
    reason: str | None, settings: Settings, *, required: bool
) -> str | None:
    """Strip an author's reason; require it for a listing with accepted people."""
    text = (reason or "").strip()
    if not text:
        if required:
            raise ProblemError(CANCEL_REASON_REQUIRED)
        return None
    if len(text) > settings.listing_cancellation_reason_max_length:
        raise ProblemError(
            CANCEL_REASON_INVALID,
            max=settings.listing_cancellation_reason_max_length,
        )
    return text


async def accepted_interactions(
    session: AsyncSession, listing_id: UUID
) -> list[Interaction]:
    return list(
        await session.scalars(
            select(Interaction).where(
                Interaction.listing_id == listing_id,
                Interaction.status == InteractionStatus.ACCEPTED,
            )
        )
    )


def is_late_cancellation(
    listing: Listing, interaction: Interaction, settings: Settings
) -> bool:
    """Whether a participant cancellation counts as late (#55).

    A change of conditions initiated by the other party makes the exit
    penalty-free. A fixed purchase share is late regardless of a meeting;
    after the collection is frozen its volume is already committed.
    """
    if interaction.status != InteractionStatus.ACCEPTED:
        return False
    if (
        interaction.conditions_changed_at is not None
        and interaction.conditions_changed_by_id != interaction.participant_id
    ):
        return False
    if listing.kind == "purchase":
        return listing.purchase_stage == PurchaseStage.FIXED
    start = interaction_start(listing, interaction)
    return (
        start is not None
        and start - clock.now() < settings.listing_late_cancellation_threshold
    )


def mark_conditions_changed(interaction: Interaction, actor_id: UUID) -> None:
    """Remember an author-side change that removes the late-cancel penalty."""
    interaction.conditions_changed_at = clock.now()
    interaction.conditions_changed_by_id = actor_id


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
    if listing.kind == "purchase":
        return await purchase_available_units(session, listing) > 0
    capacity = (
        listing.event_capacity
        if listing.kind == "event"
        else TYPE_POLICIES[listing.kind].capacity
    )
    if listing.kind == "event":
        return bool(listing.remaining_places)
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


async def join_waitlist(  # noqa: PLR0912 - capacity and purchase rules
    session: AsyncSession,
    listing: Listing,
    user: User,
    units: int | None = None,
) -> WaitlistEntry:
    """Take the last place of the queue, when the listing has no free slot."""
    if listing.kind == "event" and (
        listing.event_starts_at is None or listing.event_starts_at <= clock.now()
    ):
        raise ProblemError(CONFLICT)
    if listing.kind == "purchase":
        if purchase_collection_ended(listing):
            raise ProblemError(PURCHASE_CLOSED)
        if listing.purchase_stage not in (
            PurchaseStage.COLLECTING,
            PurchaseStage.FIXED,
        ):
            raise ProblemError(CONFLICT)
        if units is None or units < 1:
            raise ProblemError(PURCHASE_VOLUME_INVALID)
        if await purchase_share_exists(session, listing.id, user.id):
            raise ProblemError(PURCHASE_SHARE_EXISTS)
    elif TYPE_POLICIES[listing.kind].capacity is None:
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
    if listing.kind == "event":
        free = (listing.remaining_places or 0) > len(
            await event_offers(session, listing)
        )
    elif listing.kind == "purchase":
        # While collecting, a free volume is taken directly; after fixation
        # only freed units are offered through the queue.
        free = (
            listing.purchase_stage == PurchaseStage.COLLECTING
            and await has_free_slot(session, listing)
        )
    else:
        free = await has_free_slot(session, listing) and (
            await active_offer(session, listing.id) is None
        )
    if free:
        raise ProblemError(WAITLIST_FREE)
    entry = WaitlistEntry(
        listing_id=listing.id,
        participant_id=user.id,
        participant=user,
        units=units if listing.kind == "purchase" else None,
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
    if listing.kind == "event":
        # A new cancellation or edit can reopen places; processing the
        # scheduled boundary after a request must not notify the queue twice.
        latest = await session.scalar(
            select(ListingEvent.action)
            .where(
                ListingEvent.listing_id == listing.id,
                or_(
                    ListingEvent.action.in_(
                        ("waitlist_opened", "edited", "conditions_changed")
                    ),
                    and_(
                        ListingEvent.action == "transition",
                        ListingEvent.status == "cancelled",
                    ),
                ),
            )
            .order_by(ListingEvent.created_at.desc(), ListingEvent.id.desc())
            .limit(1)
        )
        if latest == "waitlist_opened":
            return
    elif announced is not None:
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
    if listing.kind == "event":
        await offer_event_places(session, listing, offer_timeout, open_all_before)
        return None
    if listing.kind == "purchase":
        await offer_purchase_units(session, listing, offer_timeout, open_all_before)
        return None
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
    if listing.kind == "event":
        return await accept_event_offer(session, listing, user, settings)
    if listing.kind == "purchase":
        return await claim_purchase_offer(session, listing, user)
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
        # New rows start without relationships; validation reads them.
        meeting=None,
        options=[],
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
    if (
        listing.kind == "event"
        and listing.event_starts_at is not None
        and listing.event_starts_at - clock.now() <= open_all_before
    ):
        await release_event_offers(session, listing)
        if listing.remaining_places:
            await open_to_all(session, listing)
        return
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


def purchase_stage_of(listing: Listing) -> PurchaseStage | None:
    """The current purchase stage; ``None`` for other listing kinds."""
    if listing.purchase_stage is None:
        return None
    return PurchaseStage(listing.purchase_stage)


def purchase_collection_ended(listing: Listing) -> bool:
    """Whether the collection deadline passed before the deadline job ran."""
    return (
        listing.purchase_stage == PurchaseStage.COLLECTING
        and listing.purchase_collection_deadline is not None
        and listing.purchase_collection_deadline <= clock.now()
    )


async def purchase_offered_units(session: AsyncSession, listing: Listing) -> int:
    """Units currently held by queue offers, which are not free."""
    value = await session.scalar(
        select(func.coalesce(func.sum(WaitlistEntry.offer_units), 0)).where(
            WaitlistEntry.listing_id == listing.id,
            WaitlistEntry.status == WaitlistStatus.OFFERED,
        )
    )
    return int(value or 0)


async def purchase_available_units(session: AsyncSession, listing: Listing) -> int:
    """Unreserved volume a participant can take or queue for."""
    limit = listing.purchase_limit
    if limit is None:
        return 0
    taken = listing.purchase_taken_units or 0
    return max(limit - taken - await purchase_offered_units(session, listing), 0)


def validate_purchase(
    price: Any,
    min_units: int,
    max_units: int,
    deadline: datetime,
    settings: Settings,
) -> None:
    """Reject a volume order and a deadline outside the listing lifetime."""
    if price <= 0 or min_units < 1 or max_units < min_units:
        raise ProblemError(PURCHASE_VOLUME_INVALID)
    now = clock.now()
    if deadline <= now or deadline > now + settings.listing_lifetime:
        raise ProblemError(PURCHASE_DEADLINE_INVALID)


async def schedule_purchase_deadlines(
    session: AsyncSession, listing: Listing, settings: Settings
) -> None:
    deadline = listing.purchase_collection_deadline
    if deadline is None:
        return
    await schedule_deadline(
        session,
        "listing.purchase_deadline",
        deadline,
        {"listing_id": str(listing.id)},
        key=f"purchase-deadline:{listing.id}",
    )
    reminder_at = deadline - settings.listing_purchase_reminder_before
    if reminder_at > clock.now():
        await schedule_deadline(
            session,
            "listing.purchase_reminder",
            reminder_at,
            {"listing_id": str(listing.id)},
            key=f"purchase-reminder:{listing.id}",
        )


async def cancel_purchase_deadlines(session: AsyncSession, listing_id: UUID) -> None:
    await cancel_deadline(session, f"purchase-deadline:{listing_id}")
    await cancel_deadline(session, f"purchase-reminder:{listing_id}")


async def purchase_share_exists(
    session: AsyncSession, listing_id: UUID, participant_id: UUID
) -> bool:
    """Whether the user already has a live share of this purchase."""
    return (
        await session.scalar(
            select(Interaction.id).where(
                Interaction.listing_id == listing_id,
                Interaction.participant_id == participant_id,
                Interaction.status.in_(
                    (InteractionStatus.PENDING, InteractionStatus.ACCEPTED)
                ),
            )
        )
        is not None
    )


def purchase_share_details(listing: Listing, units: int) -> dict[str, Any]:
    return {"units": units, "unit_price": str(listing.purchase_unit_price)}


async def join_purchase(
    session: AsyncSession, listing: Listing, user: User, units: int
) -> Interaction:
    """Take a share of a collecting purchase; the share is accepted at once."""
    if listing.purchase_stage != PurchaseStage.COLLECTING:
        raise ProblemError(PURCHASE_CLOSED)
    if purchase_collection_ended(listing):
        raise ProblemError(PURCHASE_CLOSED)
    if await purchase_share_exists(session, listing.id, user.id):
        raise ProblemError(PURCHASE_SHARE_EXISTS)
    available = await purchase_available_units(session, listing)
    if units > available:
        raise ProblemError(PURCHASE_UNITS_UNAVAILABLE, available=available)
    interaction = Interaction(
        listing_id=listing.id,
        participant_id=user.id,
        participant=user,
        slot=None,
        status=InteractionStatus.ACCEPTED,
        stage=PurchaseStage.COLLECTING,
        units=units,
        response_due_at=None,
        # New rows start without relationships; validation reads them.
        meeting=None,
        options=[],
    )
    session.add(interaction)
    await session.flush()
    listing.purchase_taken_units += units
    listing.version += 1
    record(
        session,
        listing,
        user.id,
        "share_joined",
        None,
        interaction,
        details=purchase_share_details(listing, units),
    )
    return interaction


async def change_purchase_units(  # noqa: PLR0913 - share and offer context
    session: AsyncSession,
    listing: Listing,
    interaction: Interaction,
    units: int,
    *,
    offer_timeout: timedelta,
    open_all_before: timedelta,
) -> None:
    """Change a share while collecting; freed units go to the queue."""
    if listing.purchase_stage != PurchaseStage.COLLECTING:
        raise ProblemError(PURCHASE_CLOSED)
    if purchase_collection_ended(listing):
        raise ProblemError(PURCHASE_CLOSED)
    if interaction.status != InteractionStatus.ACCEPTED:
        raise ProblemError(CONFLICT)
    current = interaction.units or 0
    limit = listing.purchase_limit or 0
    available = limit - listing.purchase_taken_units + current
    if units > available:
        raise ProblemError(PURCHASE_UNITS_UNAVAILABLE, available=available)
    interaction.units = units
    listing.purchase_taken_units += units - current
    listing.version += 1
    record(
        session,
        listing,
        interaction.participant_id,
        "share_changed",
        interaction.status,
        interaction,
        details={
            "units": units,
            "previous_units": current,
            "unit_price": str(listing.purchase_unit_price),
        },
    )
    if units < current:
        await offer_next(
            session,
            listing,
            offer_timeout=offer_timeout,
            open_all_before=open_all_before,
        )


async def leave_purchase(
    session: AsyncSession,
    listing: Listing,
    interaction: Interaction,
    *,
    offer_timeout: timedelta,
    open_all_before: timedelta,
) -> None:
    """Leave a collecting purchase; after fixation the organiser decides."""
    stage = purchase_stage_of(listing)
    if stage == PurchaseStage.FIXED:
        raise ProblemError(PURCHASE_APPROVAL_REQUIRED)
    if stage != PurchaseStage.COLLECTING:
        raise ProblemError(PURCHASE_CLOSED)
    if purchase_collection_ended(listing):
        raise ProblemError(PURCHASE_CLOSED)
    if interaction.status != InteractionStatus.ACCEPTED:
        raise ProblemError(CONFLICT)
    units = interaction.units or 0
    interaction.status = InteractionStatus.CANCELLED
    interaction.stage = None
    interaction.cancelled_by = CancellationActor.PARTICIPANT.value
    interaction.cancellation_reason = None
    interaction.late_cancelled = False
    listing.purchase_taken_units = max(0, listing.purchase_taken_units - units)
    listing.version += 1
    record(
        session,
        listing,
        interaction.participant_id,
        "share_left",
        InteractionStatus.ACCEPTED,
        interaction,
        details={"units": units, "late": False},
    )
    await offer_next(
        session,
        listing,
        offer_timeout=offer_timeout,
        open_all_before=open_all_before,
    )


async def request_purchase_withdrawal(
    session: AsyncSession,
    listing: Listing,
    interaction: Interaction,
    reason: str | None,
) -> None:
    """Ask the organiser to leave a fixed composition."""
    if purchase_stage_of(listing) != PurchaseStage.FIXED:
        raise ProblemError(PURCHASE_NOT_FIXED)
    if interaction.status != InteractionStatus.ACCEPTED:
        raise ProblemError(CONFLICT)
    if interaction.leave_requested_at is not None:
        raise ProblemError(PURCHASE_WITHDRAWAL_EXISTS)
    interaction.leave_requested_at = clock.now()
    listing.version += 1
    append_event(
        session,
        listing,
        interaction.participant_id,
        "leave_requested",
        interaction.status,
        interaction,
        reason=reason,
        details={"units": interaction.units or 0},
    )
    notify(
        session,
        {listing.author_id},
        "listing.purchase.withdrawal_requested",
        {
            "listing_id": str(listing.id),
            "interaction_id": str(interaction.id),
            "units": interaction.units or 0,
        },
        message=PURCHASE_WITHDRAWAL_REQUESTED,
    )


async def cancel_purchase_withdrawal(
    session: AsyncSession, interaction: Interaction
) -> None:
    if interaction.leave_requested_at is None:
        raise ProblemError(PURCHASE_WITHDRAWAL_MISSING)
    interaction.leave_requested_at = None
    append_event(
        session,
        listing := await _listing_of(session, interaction),
        interaction.participant_id,
        "leave_cancelled",
        interaction.status,
        interaction,
    )
    listing.version += 1


async def _listing_of(session: AsyncSession, interaction: Interaction) -> Listing:
    listing = await session.get(Listing, interaction.listing_id)
    assert listing is not None  # noqa: S101 - interaction rows keep their listing
    return listing


async def decide_purchase_withdrawal(  # noqa: PLR0913 - decision fields
    session: AsyncSession,
    listing: Listing,
    interaction: Interaction,
    actor_id: UUID,
    *,
    approve: bool,
    reason: str | None,
    offer_timeout: timedelta,
    open_all_before: timedelta,
    settings: Settings | None = None,
) -> None:
    """The organiser approves or rejects a request to leave a fixed purchase."""
    if listing.author_id != actor_id:
        raise ProblemError(FORBIDDEN)
    if purchase_stage_of(listing) != PurchaseStage.FIXED:
        raise ProblemError(PURCHASE_NOT_FIXED)
    if interaction.leave_requested_at is None:
        raise ProblemError(PURCHASE_WITHDRAWAL_MISSING)
    interaction.leave_requested_at = None
    listing.version += 1
    if approve:
        units = interaction.units or 0
        late = is_late_cancellation(listing, interaction, settings or get_settings())
        interaction.status = InteractionStatus.CANCELLED
        interaction.stage = None
        interaction.cancelled_by = CancellationActor.PARTICIPANT.value
        interaction.cancellation_reason = reason
        interaction.late_cancelled = late
        listing.purchase_taken_units = max(0, listing.purchase_taken_units - units)
        append_event(
            session,
            listing,
            actor_id,
            "leave_approved",
            InteractionStatus.ACCEPTED,
            interaction,
            reason=reason,
            details={"units": units, "late": late},
        )
        notify(
            session,
            {interaction.participant_id},
            "listing.purchase.withdrawal_decided",
            {
                "listing_id": str(listing.id),
                "interaction_id": str(interaction.id),
                "approved": True,
            },
            message=PURCHASE_WITHDRAWAL_DECIDED,
        )
        await offer_next(
            session,
            listing,
            offer_timeout=offer_timeout,
            open_all_before=open_all_before,
        )
    else:
        append_event(
            session,
            listing,
            actor_id,
            "leave_rejected",
            interaction.status,
            interaction,
            reason=reason,
        )
        notify(
            session,
            {interaction.participant_id},
            "listing.purchase.withdrawal_decided",
            {
                "listing_id": str(listing.id),
                "interaction_id": str(interaction.id),
                "approved": False,
            },
            message=PURCHASE_WITHDRAWAL_DECIDED,
        )


async def update_purchase_conditions(  # noqa: PLR0913 - edited fields
    session: AsyncSession,
    listing: Listing,
    *,
    price: Any,
    min_units: int,
    max_units: int,
    deadline: datetime,
    settings: Settings,
) -> None:
    """Edit a collecting purchase, recalculating the amounts explicitly.

    The amount is always units x price, so changing the price changes every
    participant's amount at once; participants and the queue are notified.
    """
    if listing.purchase_stage != PurchaseStage.COLLECTING:
        raise ProblemError(PURCHASE_CLOSED)
    if purchase_collection_ended(listing):
        raise ProblemError(PURCHASE_CLOSED)
    validate_purchase(price, min_units, max_units, deadline, settings)
    offered = await purchase_offered_units(session, listing)
    committed = listing.purchase_taken_units + offered
    if max_units < committed:
        raise ProblemError(PURCHASE_CAPACITY_CONFLICT, taken=committed)
    previous = {
        "price_per_unit": str(listing.purchase_unit_price),
        "min_units": listing.purchase_min_units,
        "max_units": listing.purchase_max_units,
        "collection_deadline": (
            listing.purchase_collection_deadline.isoformat()
            if listing.purchase_collection_deadline
            else None
        ),
    }
    listing.purchase_unit_price = price
    listing.purchase_min_units = min_units
    listing.purchase_max_units = max_units
    listing.purchase_collection_deadline = deadline
    listing.version += 1
    record(
        session,
        listing,
        listing.author_id,
        "conditions_changed",
        listing.status,
        details={
            "price_per_unit": str(price),
            "min_units": min_units,
            "max_units": max_units,
            "collection_deadline": deadline.isoformat(),
            "previous": previous,
        },
    )
    for share in await accepted_interactions(session, listing.id):
        mark_conditions_changed(share, listing.author_id)
    await cancel_purchase_deadlines(session, listing.id)
    await schedule_purchase_deadlines(session, listing, settings)
    recipients = await purchase_participants(session, listing)
    recipients |= {
        entry.participant_id
        for entry in await session.scalars(
            select(WaitlistEntry).where(
                WaitlistEntry.listing_id == listing.id,
                WaitlistEntry.status.in_(
                    (WaitlistStatus.WAITING, WaitlistStatus.OFFERED)
                ),
            )
        )
    }
    notify(
        session,
        recipients,
        "listing.purchase.conditions_changed",
        {
            "listing_id": str(listing.id),
            "price_per_unit": str(price),
            "min_units": min_units,
            "max_units": max_units,
            "collection_deadline": deadline.isoformat(),
            "version": listing.version,
        },
        message=PURCHASE_CONDITIONS_CHANGED,
    )


async def purchase_participants(session: AsyncSession, listing: Listing) -> set[UUID]:
    shares = await session.scalars(
        select(Interaction).where(
            Interaction.listing_id == listing.id,
            Interaction.status == InteractionStatus.ACCEPTED,
        )
    )
    return {share.participant_id for share in shares}


async def expire_purchase_offers(session: AsyncSession, listing: Listing) -> None:
    """Expire unconfirmed queue offers when the composition freezes.

    An offer is not a share: only accepted units enter the fixed
    composition. Leaving the offer alive would let it be claimed against a
    composition that no longer has free units.
    """
    entries = list(
        await session.scalars(
            select(WaitlistEntry)
            .where(
                WaitlistEntry.listing_id == listing.id,
                WaitlistEntry.status == WaitlistStatus.OFFERED,
            )
            .with_for_update()
        )
    )
    for entry in entries:
        previous = entry.status
        entry.status = WaitlistStatus.EXPIRED
        listing.version += 1
        await cancel_deadline(session, offer_key(entry.id))
        record_waitlist(session, listing, None, "offer_expired", entry, previous)
        notify(
            session,
            {entry.participant_id},
            "listing.offer_expired",
            {"listing_id": str(listing.id), "entry_id": str(entry.id)},
            message=LISTING_OFFER_EXPIRED,
        )


async def fix_purchase_composition(session: AsyncSession, listing: Listing) -> None:
    """Freeze the composition when the collection deadline is met."""
    if listing.purchase_stage != PurchaseStage.COLLECTING:
        return
    await expire_purchase_offers(session, listing)
    shares = list(
        await session.scalars(
            select(Interaction).where(
                Interaction.listing_id == listing.id,
                Interaction.status == InteractionStatus.ACCEPTED,
            )
        )
    )
    listing.purchase_stage = PurchaseStage.FIXED
    listing.purchase_fixed_units = listing.purchase_taken_units
    listing.version += 1
    for share in shares:
        share.stage = PurchaseStage.FIXED
        append_event(
            session,
            listing,
            None,
            "stage_changed",
            share.status,
            share,
            details={"stage": PurchaseStage.FIXED},
        )
    append_event(
        session,
        listing,
        None,
        "composition_fixed",
        listing.status,
        details={
            "units": listing.purchase_fixed_units,
            "unit_price": str(listing.purchase_unit_price),
        },
    )
    notify(
        session,
        {share.participant_id for share in shares},
        "listing.purchase.fixed",
        {
            "listing_id": str(listing.id),
            "units": listing.purchase_fixed_units,
            "unit_price": str(listing.purchase_unit_price),
        },
        message=PURCHASE_FIXED,
    )
    await cancel_purchase_deadlines(session, listing.id)


async def cancel_purchase(
    session: AsyncSession,
    listing: Listing,
    reason: str | None,
    *,
    actor_id: UUID | None = None,
) -> None:
    """Cancel a collecting purchase and every share in it.

    The organiser supplies a reason that every participant can read; a
    deadline cancellation is attributed to the server instead.
    """
    if listing.purchase_stage != PurchaseStage.COLLECTING:
        raise ProblemError(PURCHASE_CLOSED)
    shares = await accepted_interactions(session, listing.id)
    recipients = {share.participant_id for share in shares}
    actor = (
        CancellationActor.AUTHOR if actor_id is not None else CancellationActor.SYSTEM
    )
    for share in shares:
        share.status = InteractionStatus.CANCELLED
        share.stage = None
        share.cancelled_by = actor.value
        share.cancellation_reason = reason if actor_id is not None else None
        share.late_cancelled = False
        append_event(
            session,
            listing,
            actor_id,
            "purchase_cancelled",
            InteractionStatus.ACCEPTED,
            share,
            reason=reason,
            details={
                "units": share.units or 0,
                "by_author": actor_id is not None,
                "late": False,
            },
        )
    listing.purchase_taken_units = 0
    listing.purchase_fixed_units = None
    listing.purchase_stage = PurchaseStage.CANCELLED
    listing.version += 1
    await clear_waitlist(session, listing, reason or "listing_cancelled")
    change_listing(
        session,
        listing,
        ListingStatus.CANCELLED,
        actor_id,
        "cancelled",
        reason=reason,
    )
    notify(
        session,
        recipients,
        "listing.purchase.cancelled",
        {"listing_id": str(listing.id), "reason": reason},
        message=(
            PURCHASE_CANCELLED_BY_AUTHOR if actor_id is not None else PURCHASE_CANCELLED
        ),
        message_params={"reason": reason or ""} if actor_id is not None else None,
    )
    await cancel_purchase_deadlines(session, listing.id)


async def cancel_listing_by_author(
    session: AsyncSession,
    listing: Listing,
    actor_id: UUID,
    reason: str | None,
    settings: Settings,
) -> None:
    """Cancel a listing, including its accepted interactions (#55).

    Accepted interactions are cancelled with the author's reason and marked
    as after-acceptance; pending applications are rejected and the queue is
    cleared. The caller has already locked the listing and checked rights.
    """
    accepted = await accepted_interactions(session, listing.id)
    reason = normalized_cancellation_reason(reason, settings, required=bool(accepted))
    change_listing(
        session,
        listing,
        ListingStatus.CANCELLED,
        actor_id,
        "cancelled",
        reason=reason,
    )
    for interaction in accepted:
        await cancel_meeting_reminders(session, interaction.id)
        await cancel_deadline(session, reservation_key(interaction.id))
        interaction.status = InteractionStatus.CANCELLED
        interaction.stage = None
        interaction.reservation_due_at = None
        interaction.cancelled_by = CancellationActor.AUTHOR.value
        interaction.cancellation_reason = reason
        interaction.late_cancelled = False
        if listing.kind == "event":
            listing.event_registered = max(0, listing.event_registered - 1)
        append_event(
            session,
            listing,
            actor_id,
            "cancelled_by_author",
            InteractionStatus.ACCEPTED,
            interaction,
            reason=reason,
            details={"after_acceptance": True, "late": False},
        )
        notify(
            session,
            {interaction.participant_id},
            "listing.cancelled",
            {
                "listing_id": str(listing.id),
                "interaction_id": str(interaction.id),
                "reason": reason,
            },
            message=LISTING_CANCELLED,
            message_params={"reason": reason or ""},
        )
    await reject_pending(session, listing, "listing_cancelled")
    await clear_waitlist(session, listing, "listing_cancelled")
    await session.flush()


async def close_purchase_collection(session: AsyncSession, listing: Listing) -> None:
    """Catch-up rule at the collection deadline: fix or cancel, once."""
    if listing.purchase_stage != PurchaseStage.COLLECTING:
        return
    deadline = listing.purchase_collection_deadline
    if deadline is not None and deadline > clock.now():
        return
    min_units = listing.purchase_min_units or 0
    if listing.purchase_taken_units >= min_units and listing.purchase_taken_units > 0:
        await fix_purchase_composition(session, listing)
    else:
        await cancel_purchase(session, listing, "min_units_not_reached")


async def offer_purchase_units(
    session: AsyncSession,
    listing: Listing,
    offer_timeout: timedelta,
    open_all_before: timedelta,
) -> None:
    """Offer freed units to the queue in FIFO order, partially if needed."""
    # Purchases never open places to everyone: they keep the queue.
    if purchase_stage_of(listing) not in (
        PurchaseStage.COLLECTING,
        PurchaseStage.FIXED,
    ):
        return
    if listing.status not in (ListingStatus.ACTIVE, ListingStatus.BUSY):
        return
    if listing.expires_at is not None and listing.expires_at <= clock.now():
        return
    free = await purchase_available_units(session, listing)
    if free <= 0:
        return
    entries = list(
        await session.scalars(
            select(WaitlistEntry)
            .where(
                WaitlistEntry.listing_id == listing.id,
                WaitlistEntry.status == WaitlistStatus.WAITING,
            )
            .order_by(WaitlistEntry.created_at, WaitlistEntry.id)
            .with_for_update()
        )
    )
    now = clock.now()
    for entry in entries:
        if free <= 0:
            break
        requested = entry.units or free
        offered = min(requested, free)
        previous = entry.status
        entry.status = WaitlistStatus.OFFERED
        entry.offer_slot = None
        entry.offer_units = offered
        entry.offered_at = now
        entry.offer_expires_at = now + offer_timeout
        listing.version += 1
        record_waitlist(session, listing, None, "offered", entry, previous)
        notify(
            session,
            {entry.participant_id},
            "listing.offer",
            {
                "listing_id": str(listing.id),
                "entry_id": str(entry.id),
                "units": offered,
                "offer_expires_at": entry.offer_expires_at.isoformat(),
            },
            message=LISTING_OFFER,
        )
        await schedule_deadline(
            session,
            "listing.offer",
            entry.offer_expires_at,
            {
                "entry_id": str(entry.id),
                "offer_timeout": int(offer_timeout.total_seconds()),
                "open_all_before": int(open_all_before.total_seconds()),
            },
            key=offer_key(entry.id),
        )
        free -= offered


async def claim_purchase_offer(
    session: AsyncSession, listing: Listing, user: User
) -> Interaction:
    """Turn an offered volume into an accepted share."""
    entry = await active_waitlist(session, listing.id, user.id)
    if entry is None or entry.status != WaitlistStatus.OFFERED:
        raise ProblemError(OFFER_MISSING)
    if entry.offer_expires_at is None or entry.offer_expires_at <= clock.now():
        raise ProblemError(OFFER_EXPIRED)
    require_live(listing)
    if purchase_collection_ended(listing):
        raise ProblemError(PURCHASE_CLOSED)
    if purchase_stage_of(listing) not in (
        PurchaseStage.COLLECTING,
        PurchaseStage.FIXED,
    ):
        raise ProblemError(CONFLICT)
    if await purchase_share_exists(session, listing.id, user.id):
        raise ProblemError(PURCHASE_SHARE_EXISTS)
    units = entry.offer_units or entry.units or 0
    limit = listing.purchase_limit or 0
    if units < 1 or listing.purchase_taken_units + units > limit:
        raise ProblemError(CONFLICT)
    interaction = Interaction(
        listing_id=listing.id,
        participant_id=user.id,
        participant=user,
        slot=None,
        status=InteractionStatus.ACCEPTED,
        stage=listing.purchase_stage,
        units=units,
        response_due_at=None,
        meeting=None,
        options=[],
    )
    session.add(interaction)
    await session.flush()
    previous = entry.status
    entry.status = WaitlistStatus.CLAIMED
    entry.interaction_id = interaction.id
    await cancel_deadline(session, offer_key(entry.id))
    listing.purchase_taken_units += units
    listing.version += 1
    record_waitlist(session, listing, user.id, "offer_accepted", entry, previous)
    record(
        session,
        listing,
        user.id,
        "share_joined",
        None,
        interaction,
        details=purchase_share_details(listing, units),
    )
    return interaction


@deadline_handlers.register("listing.purchase_deadline")
async def expire_purchase_collection(session: AsyncSession, job: JobInfo) -> None:
    listing = await locked(session, UUID(job.payload["listing_id"]))
    if listing.purchase_stage != PurchaseStage.COLLECTING:
        return
    await close_purchase_collection(session, listing)


@deadline_handlers.register("listing.purchase_reminder")
async def remind_purchase_participants(session: AsyncSession, job: JobInfo) -> None:
    listing = await locked(session, UUID(job.payload["listing_id"]))
    if (
        listing.purchase_stage != PurchaseStage.COLLECTING
        or listing.status != ListingStatus.ACTIVE
        or listing.purchase_collection_deadline is None
        or listing.purchase_collection_deadline <= clock.now()
    ):
        return
    recipients = await purchase_participants(session, listing)
    if not recipients:
        return
    notify(
        session,
        recipients,
        "listing.purchase.reminder",
        {
            "listing_id": str(listing.id),
            "collection_deadline": listing.purchase_collection_deadline.isoformat(),
        },
        message=PURCHASE_REMINDER,
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


def change_listing(  # noqa: PLR0913 - transition fields
    session: AsyncSession,
    listing: Listing,
    target: ListingStatus,
    actor_id: UUID | None,
    action: str,
    *,
    reason: str | None = None,
) -> None:
    if target not in LISTING_TRANSITIONS[ListingStatus(listing.status)]:
        raise ProblemError(CONFLICT)
    previous = listing.status
    listing.status = target
    listing.version += 1
    listing.archived_at = clock.now() if target in ARCHIVED else None
    record(
        session,
        listing,
        actor_id,
        action,
        previous,
        reason=reason if reason is not None else listing.hidden_reason,
    )


def reservation_key(interaction_id: UUID) -> str:
    return f"interaction:{interaction_id}"


async def schedule_reservation(
    session: AsyncSession,
    listing: Listing,
    interaction: Interaction,
    settings: Settings,
) -> None:
    """Start the reservation window of a newly accepted item interaction."""
    if listing.kind not in RESERVATION_KINDS:
        return
    # The reservation reuses the interaction deadline key, replacing the
    # author response timer, so the pending response time no longer applies.
    interaction.response_due_at = None
    due_at = clock.now() + settings.listing_reservation_timeout
    interaction.reservation_due_at = due_at
    await schedule_deadline(
        session,
        "listing.reservation",
        due_at,
        {
            "listing_id": str(listing.id),
            "interaction_id": str(interaction.id),
            "offer_timeout": int(settings.listing_offer_timeout.total_seconds()),
            "open_all_before": int(settings.listing_open_to_all_before.total_seconds()),
        },
        key=reservation_key(interaction.id),
    )


async def extend_reservation(
    session: AsyncSession,
    listing: Listing,
    interaction: Interaction,
    meeting_at: datetime,
) -> None:
    """A scheduled meeting keeps the reservation until its time.

    The pending expiry is dropped: the reservation no longer ends without a
    meeting, and the interaction is finished by the meeting scenario.
    """
    if listing.kind not in RESERVATION_KINDS:
        return
    interaction.reservation_due_at = meeting_at
    await cancel_deadline(session, reservation_key(interaction.id))


async def release_reservation(
    session: AsyncSession,
    listing: Listing,
    interaction: Interaction,
    *,
    offer_timeout: timedelta,
    open_all_before: timedelta,
) -> None:
    """Cancel an accepted interaction whose reservation has run out.

    The listing reopens without a late-cancellation mark, and the first in
    the queue is offered the released place.
    """
    previous = interaction.status
    interaction.status = InteractionStatus.CANCELLED
    interaction.stage = None
    interaction.reservation_due_at = None
    interaction.cancelled_by = CancellationActor.SYSTEM.value
    interaction.cancellation_reason = None
    interaction.late_cancelled = False
    released = False
    if listing.status == ListingStatus.BUSY:
        if listing.expires_at is not None and listing.expires_at <= clock.now():
            await expire(session, listing)
        else:
            change_listing(session, listing, ListingStatus.ACTIVE, None, "released")
            released = True
    else:
        listing.version += 1
    record(
        session,
        listing,
        None,
        RESERVATION_EXPIRED,
        previous,
        interaction,
        reason=RESERVATION_EXPIRED,
        details={"late": False},
    )
    if released and listing.kind == "giveaway":
        await offer_next(
            session,
            listing,
            offer_timeout=offer_timeout,
            open_all_before=open_all_before,
        )


@deadline_handlers.register("listing.reservation")
async def expire_reservation(session: AsyncSession, job: JobInfo) -> None:
    # The listing lock serializes every interaction mutation; the interaction
    # is read after it, so a concurrent cancel or completion is visible here.
    listing = await locked(session, UUID(job.payload["listing_id"]))
    interaction = await session.get(Interaction, UUID(job.payload["interaction_id"]))
    if interaction is None:
        return
    if (
        interaction.status != InteractionStatus.ACCEPTED
        or interaction.reservation_due_at is None
        or interaction.reservation_due_at > clock.now()
    ):
        return
    meeting = await session.scalar(
        select(Meeting).where(Meeting.interaction_id == interaction.id)
    )
    if meeting is not None and meeting.scheduled_at is not None:
        return
    offer_timeout, open_all_before = offer_timing(payload=job.payload)
    await release_reservation(
        session,
        listing,
        interaction,
        offer_timeout=offer_timeout,
        open_all_before=open_all_before,
    )


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


async def has_executor(session: AsyncSession, listing_id: UUID) -> bool:
    """Whether a help request already has the selected executor."""
    selected = await session.scalar(
        select(Interaction.id).where(
            Interaction.listing_id == listing_id,
            Interaction.status == InteractionStatus.ACCEPTED,
            Interaction.executor.is_(True),
        )
    )
    return selected is not None


async def expire(session: AsyncSession, listing: Listing) -> None:
    """Accepted interactions survive closure and may finish afterwards.

    A help request with a selected executor does not close on its
    availability deadline: it continues until the executor finishes or
    refuses. Without an executor the request closes and its reserve is
    rejected.
    """
    if listing.status not in (ListingStatus.ACTIVE, ListingStatus.BUSY):
        return
    if listing.kind == "help" and await has_executor(session, listing.id):
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
        (listing.expires_at is None and listing.kind not in PERMANENT_KINDS)
        or (listing.expires_at is not None and listing.expires_at <= clock.now())
        or listing.status not in (ListingStatus.ACTIVE, ListingStatus.BUSY)
    ):
        raise ProblemError(CONFLICT)


async def reject_exchange_offers(
    session: AsyncSession,
    listing: Listing,
    selected: Interaction,
    actor_id: UUID | None,
) -> None:
    """Reject every other pending offer once the author has chosen one."""
    offers = list(
        await session.scalars(
            select(Interaction)
            .where(
                Interaction.listing_id == listing.id,
                Interaction.id != selected.id,
                Interaction.status == InteractionStatus.PENDING,
            )
            # The eager meeting is an outer join; lock only the interaction.
            .with_for_update(of=Interaction)
        )
    )
    for offer in offers:
        offer.status = InteractionStatus.REJECTED
        record(
            session,
            listing,
            actor_id,
            "auto_rejected",
            InteractionStatus.PENDING,
            offer,
            reason=EXCHANGE_OFFER_DECLINED,
        )


async def claim_listing(  # noqa: PLR0913, PLR0917 - aggregate claim
    session: AsyncSession,
    listing: Listing,
    interaction: Interaction,
    target: InteractionStatus,
    actor_id: UUID | None,
    previous: str,
) -> bool:
    """Give the accepted interaction an exclusive claim on the listing.

    Help requests select one application and keep the rest as a reserve;
    exchange offers reject the others and reserve the listing for the chosen
    one. Returns whether the claim already updated the listing, so the caller
    does not bump its version twice.
    """
    if target == InteractionStatus.ACCEPTED and listing.kind == "help":
        # The author selects one application; the remaining ones stay pending
        # as a reserve. The partial unique index backs this check up.
        if listing.status != ListingStatus.ACTIVE:
            raise ProblemError(CONFLICT)
        interaction.executor = True
        change_listing(
            session, listing, ListingStatus.BUSY, actor_id, "executor_selected"
        )
        return True
    if (
        listing.kind == "exchange"
        and previous == InteractionStatus.PENDING
        and target == InteractionStatus.ACCEPTED
    ):
        await reject_exchange_offers(session, listing, interaction, actor_id)
        change_listing(session, listing, ListingStatus.BUSY, actor_id, "reserved")
        return True
    return False


async def transition(  # noqa: PLR0912, PLR0913, PLR0915 - aggregate transition
    session: AsyncSession,
    listing: Listing,
    interaction: Interaction,
    target: InteractionStatus,
    actor_id: UUID | None,
    *,
    settings: Settings | None = None,
    completion_method: CompletionMethod | None = None,
    action: str = "transition",
    details: dict[str, Any] | None = None,
    reason: str | None = None,
) -> None:
    expected = TRANSITIONS.get((InteractionStatus(interaction.status), target))
    if expected is None:
        raise ProblemError(CONFLICT)
    # Accepting a lesson also schedules its meeting, so it has its own route.
    if listing.kind == "skill" and target == InteractionStatus.ACCEPTED:
        raise ProblemError(CONFLICT)
    # Only one exchange offer occupies the listing; the row lock serializes
    # two simultaneous choices, so the second one loses here.
    if (
        listing.kind == "exchange"
        and target == InteractionStatus.ACCEPTED
        and listing.status != ListingStatus.ACTIVE
    ):
        raise ProblemError(CONFLICT)
    # Purchase shares have their own endpoints: joining, changing units and
    # leaving depend on the collection stage and the volume counter.
    if listing.kind == "purchase":
        raise ProblemError(CONFLICT)
    settings = settings or get_settings()
    completion = target == InteractionStatus.COMPLETED and completion_method is not None
    if completion:
        # A participant confirms the completion. A service-only transition
        # without a completion method uses the role table below instead.
        if actor_id not in (listing.author_id, interaction.participant_id):
            raise ProblemError(FORBIDDEN)
    else:
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
    late = False
    if target == InteractionStatus.CANCELLED:
        late = previous == InteractionStatus.ACCEPTED and is_late_cancellation(
            listing, interaction, settings
        )
        interaction.cancelled_by = CancellationActor.PARTICIPANT.value
        interaction.cancellation_reason = normalized_cancellation_reason(
            reason, settings, required=False
        )
        interaction.late_cancelled = late
    interaction.status = target
    interaction.stage = (
        TYPE_POLICIES[listing.kind].initial_stage
        if target == InteractionStatus.ACCEPTED
        else None
    )
    if completion and completion_method is not None:
        interaction.completion_method = completion_method
        interaction.completed_at = clock.now()
        interaction.completion_weight = (
            settings.rating_weight_no_meeting
            if completion_method == CompletionMethod.NO_MEETING
            else settings.rating_weight_qr
        )
    if previous == InteractionStatus.ACCEPTED:
        # Reminders and the reservation belong to an accepted interaction only.
        await cancel_meeting_reminders(session, interaction.id)
        await cancel_deadline(session, reservation_key(interaction.id))
        interaction.reservation_due_at = None
    claimed = await claim_listing(
        session, listing, interaction, target, actor_id, previous
    )
    released = False
    # A giveaway reservation makes the listing busy while still pending, so
    # ending any interaction releases it. Help requests stay active while
    # applications are pending and become busy only for the selected executor,
    # whose refusal or cancellation returns the request to the reserve.
    releases_slot = listing.kind != "help" or previous == InteractionStatus.ACCEPTED
    if listing.kind == "event":
        if target == InteractionStatus.CANCELLED:
            listing.event_registered -= 1
            released = True
        listing.version += 1
    elif (
        target
        in (
            InteractionStatus.REJECTED,
            InteractionStatus.CANCELLED,
            InteractionStatus.NO_SHOW,
        )
        and listing.status == ListingStatus.BUSY
        and releases_slot
    ):
        # A deadline that has elapsed must not reintroduce a listing to the feed.
        if listing.expires_at is not None and listing.expires_at <= clock.now():
            await expire(session, listing)
        else:
            change_listing(session, listing, ListingStatus.ACTIVE, actor_id, "released")
            released = True
    elif target == InteractionStatus.COMPLETED and listing.status == ListingStatus.BUSY:
        change_listing(session, listing, ListingStatus.COMPLETED, actor_id, "completed")
        if listing.kind == "help":
            await reject_pending(session, listing, "help_completed")
        await clear_waitlist(session, listing, "listing_completed")
    elif not claimed:
        listing.version += 1
    event_details = dict(details or {})
    if target == InteractionStatus.CANCELLED:
        event_details["late"] = late
        event_details["after_acceptance"] = previous == InteractionStatus.ACCEPTED
    record(
        session,
        listing,
        actor_id,
        action,
        previous,
        interaction,
        details=event_details or None,
    )
    if target == InteractionStatus.ACCEPTED:
        await schedule_reservation(session, listing, interaction, settings)
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


def validate_place(place: str, settings: Settings) -> str:
    """Return the normalized place, rejecting an empty or too long one."""
    normalized = place.strip()
    if not normalized or len(normalized) > settings.meeting_place_max_length:
        raise ProblemError(MEETING_PLACE_INVALID)
    return normalized


def validate_meeting(time: datetime, place: str, settings: Settings) -> str:
    """Return the normalized place; reject a past time and a bad place."""
    if time <= clock.now():
        raise ProblemError(MEETING_TIME_INVALID)
    return validate_place(place, settings)


def validate_lesson_slot(
    time: datetime, location: str | None, online: bool, settings: Settings
) -> tuple[datetime, str | None, bool]:
    """Validate one lesson time option; an online lesson has no place."""
    if time <= clock.now():
        raise ProblemError(MEETING_TIME_INVALID)
    if online:
        return time, None, True
    if location is None:
        raise ProblemError(MEETING_PLACE_INVALID)
    return time, validate_place(location, settings), False


def no_meeting_time(listing: Listing, interaction: Interaction) -> datetime | None:
    """The agreed moment of an interaction completed without a meeting.

    An online lesson uses its scheduled time. Help without an agreed meeting
    has no scheduled moment yet, so the first consent becomes the agreed
    server moment and the second participant confirms exactly that.
    """
    if listing.kind == "skill" and interaction.meeting is not None:
        return interaction.meeting.scheduled_at
    return None


def require_no_meeting(listing: Listing, interaction: Interaction) -> None:
    """Reject every interaction that cannot be confirmed without a meeting."""
    if interaction.status == InteractionStatus.COMPLETED:
        if interaction.without_meeting:
            return
        raise ProblemError(NO_MEETING_UNAVAILABLE)
    if interaction.status != InteractionStatus.ACCEPTED:
        raise ProblemError(NO_MEETING_UNAVAILABLE)
    if listing.kind == "skill":
        meeting = interaction.meeting
        if meeting is None or not meeting.online or meeting.scheduled_at is None:
            raise ProblemError(NO_MEETING_UNAVAILABLE)
    elif listing.kind == "help":
        # A help request may be done without a meeting; once a meeting has
        # been proposed or scheduled, only its QR confirmation can complete it.
        if interaction.meeting is not None:
            raise ProblemError(NO_MEETING_UNAVAILABLE)
    else:
        raise ProblemError(NO_MEETING_UNAVAILABLE)


async def no_meeting_confirmations(
    session: AsyncSession, interaction: Interaction
) -> list[NoMeetingConfirmation]:
    """Both consents of the interaction, earliest first."""
    return list(
        await session.scalars(
            select(NoMeetingConfirmation)
            .where(NoMeetingConfirmation.interaction_id == interaction.id)
            .order_by(NoMeetingConfirmation.created_at, NoMeetingConfirmation.id)
        )
    )


async def confirm_no_meeting(
    session: AsyncSession,
    listing: Listing,
    interaction: Interaction,
    actor_id: UUID,
    *,
    settings: Settings | None = None,
) -> list[NoMeetingConfirmation]:
    """Record one participant's consent, completing the interaction on the second.

    The caller locks the listing row, so consents, cancellation and the
    completion are serialized: two simultaneous consents complete exactly
    once, and a cancelled interaction is never completed.
    """
    require_no_meeting(listing, interaction)
    if actor_id not in (listing.author_id, interaction.participant_id):
        raise ProblemError(FORBIDDEN)
    if interaction.status == InteractionStatus.COMPLETED:
        return await no_meeting_confirmations(session, interaction)
    confirmations = await no_meeting_confirmations(session, interaction)
    if any(item.participant_id == actor_id for item in confirmations):
        return confirmations
    agreed_at = (
        confirmations[0].agreed_at
        if confirmations
        else no_meeting_time(listing, interaction) or clock.now()
    )
    confirmation = NoMeetingConfirmation(
        interaction_id=interaction.id,
        participant_id=actor_id,
        agreed_at=agreed_at,
    )
    session.add(confirmation)
    await session.flush()
    confirmations.append(confirmation)
    details: dict[str, Any] = {
        "method": CompletionMethod.NO_MEETING.value,
        "agreed_at": agreed_at.isoformat(),
        "confirmed_by": [str(item.participant_id) for item in confirmations],
    }
    if len(confirmations) >= NO_MEETING_CONFIRMATIONS:
        await transition(
            session,
            listing,
            interaction,
            InteractionStatus.COMPLETED,
            actor_id,
            settings=settings,
            completion_method=CompletionMethod.NO_MEETING,
            action="no_meeting_completed",
            details=details,
        )
    else:
        record(
            session,
            listing,
            actor_id,
            "no_meeting_confirmed",
            interaction.status,
            interaction,
            details=details,
        )
    await session.flush()
    return confirmations


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


async def accept_lesson_option(  # noqa: PLR0912, PLR0913, PLR0917 - aggregate and actor
    session: AsyncSession,
    listing: Listing,
    interaction: Interaction,
    option: LessonOption,
    actor_id: UUID,
    settings: Settings,
) -> Meeting:
    """Select a proposed time option and schedule the resulting meeting.

    The responder's options are accepted by the author, the author's
    counter-option by the responder; nobody else may answer them.
    """
    if listing.kind != "skill":
        raise ProblemError(CONFLICT)
    if option.interaction_id != interaction.id:
        raise ProblemError(NOT_FOUND)
    if (
        interaction.status != InteractionStatus.PENDING
        or option.status != LessonOptionStatus.PROPOSED
    ):
        raise ProblemError(CONFLICT)
    if option.proposed_by_id == listing.author_id:
        expected = interaction.participant_id
    elif option.proposed_by_id == interaction.participant_id:
        expected = listing.author_id
    else:
        raise ProblemError(CONFLICT)
    if actor_id != expected:
        raise ProblemError(FORBIDDEN)
    require_live(listing)
    if (
        interaction.response_due_at is not None
        and interaction.response_due_at <= clock.now()
    ):
        raise ProblemError(CONFLICT)
    if option.time <= clock.now():
        raise ProblemError(MEETING_TIME_INVALID)
    for other in interaction.options:
        if other.status == LessonOptionStatus.PROPOSED:
            other.status = LessonOptionStatus.DECLINED
    option.status = LessonOptionStatus.SELECTED
    interaction.status = InteractionStatus.ACCEPTED
    interaction.stage = TYPE_POLICIES[listing.kind].initial_stage
    interaction.response_due_at = None
    await cancel_deadline(session, f"interaction:{interaction.id}")
    meeting = interaction.meeting
    if meeting is None:
        meeting = Meeting(interaction_id=interaction.id, version=1)
        interaction.meeting = meeting
    else:
        meeting.version += 1
    meeting.scheduled_at = option.time
    meeting.location = option.location
    meeting.online = option.online
    meeting.scheduled_by_id = option.proposed_by_id
    meeting.proposed_at = None
    meeting.proposed_location = None
    meeting.proposed_by_id = None
    details = {
        "time": option.time.isoformat(),
        "location": option.location,
        "online": option.online,
        "proposed_by_id": str(option.proposed_by_id),
    }
    record_meeting(
        session,
        listing,
        interaction,
        actor_id,
        "meeting_scheduled",
        details,
    )
    await schedule_meeting_reminders(session, settings, listing, interaction, meeting)
    recipient = (
        interaction.participant_id
        if actor_id == listing.author_id
        else listing.author_id
    )
    notify(
        session,
        {recipient},
        "listing.meeting.scheduled",
        {
            "listing_id": str(listing.id),
            "interaction_id": str(interaction.id),
            **details,
            "version": meeting.version,
        },
        message=MEETING_SCHEDULED,
    )
    await session.flush()
    return meeting


async def propose_lesson_counter(  # noqa: PLR0913, PLR0917 - aggregate and proposal
    session: AsyncSession,
    listing: Listing,
    interaction: Interaction,
    actor_id: UUID,
    time: datetime,
    location: str | None,
    online: bool,
    settings: Settings,
) -> LessonOption:
    """Let the author offer a counter-option to the responder's options."""
    if listing.kind != "skill":
        raise ProblemError(CONFLICT)
    if actor_id != listing.author_id:
        raise ProblemError(FORBIDDEN)
    if interaction.status != InteractionStatus.PENDING:
        raise ProblemError(CONFLICT)
    require_live(listing)
    if (
        interaction.response_due_at is not None
        and interaction.response_due_at <= clock.now()
    ):
        raise ProblemError(CONFLICT)
    time, location, online = validate_lesson_slot(time, location, online, settings)
    for old in interaction.options:
        if old.proposed_by_id == actor_id and old.status == LessonOptionStatus.PROPOSED:
            old.status = LessonOptionStatus.DECLINED
    option = LessonOption(
        interaction_id=interaction.id,
        position=max((item.position for item in interaction.options), default=-1) + 1,
        time=time,
        location=location,
        online=online,
        proposed_by_id=actor_id,
        status=LessonOptionStatus.PROPOSED,
    )
    interaction.options.append(option)
    interaction.response_due_at = None
    await cancel_deadline(session, f"interaction:{interaction.id}")
    details: dict[str, Any] = {
        "time": time.isoformat(),
        "location": location,
        "online": online,
    }
    record_meeting(
        session,
        listing,
        interaction,
        actor_id,
        "meeting_proposed",
        details,
    )
    notify(
        session,
        {interaction.participant_id},
        "listing.meeting.proposed",
        {
            "listing_id": str(listing.id),
            "interaction_id": str(interaction.id),
            **details,
        },
        message=MEETING_PROPOSED,
    )
    await session.flush()
    return option


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
    if listing.status not in (ListingStatus.ACTIVE, ListingStatus.BUSY):
        return
    if interaction is None or interaction.status != InteractionStatus.ACCEPTED:
        return
    meeting = await session.scalar(
        select(Meeting).where(Meeting.interaction_id == interaction.id)
    )
    if (
        meeting is None
        or meeting.scheduled_at is None
        or meeting.scheduled_at <= clock.now()
        or meeting.version != job.payload.get("version")
    ):
        return
    notify(
        session,
        {interaction.participant_id}
        if listing.kind == "event"
        else {listing.author_id, interaction.participant_id},
        "listing.meeting.reminder",
        {
            "listing_id": str(listing.id),
            "interaction_id": str(interaction.id),
            "time": meeting.scheduled_at.isoformat(),
            "location": meeting.location,
            "kind": job.payload.get("kind"),
            "version": meeting.version,
        },
        message=MEETING_REMINDER,
        event_id=uuid5(job.id, "notification"),
    )


@register_validator("listing.meeting.reminder")
async def current_meeting_reminder(
    session: AsyncSession, event: NotificationEvent
) -> bool:
    # Lock the aggregate exactly as its source transitions do. A queued
    # reminder from before a transfer/cancellation must not enter the inbox.
    listing = await locked(session, UUID(event.params["listing_id"]))
    interaction = await session.get(Interaction, UUID(event.params["interaction_id"]))
    if interaction is None or interaction.status != InteractionStatus.ACCEPTED:
        return False
    meeting = await session.scalar(
        select(Meeting).where(Meeting.interaction_id == interaction.id)
    )
    return (
        listing.status in (ListingStatus.ACTIVE, ListingStatus.BUSY)
        and meeting is not None
        and meeting.version == event.params.get("version")
        and meeting.scheduled_at is not None
        and meeting.scheduled_at > clock.now()
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


EVENT_TIME_INVALID = ProblemType(
    "event_time_invalid",
    422,
    N_("The event must start in the future and end after its start."),
)
EVENT_CAPACITY_CONFLICT = ProblemType(
    "event_capacity_conflict",
    409,
    N_("The capacity cannot be less than the number registered."),
)
EVENT_CONDITIONS_CHANGED = N_("The event time or location has changed.")


def validate_event(
    starts_at: datetime, ends_at: datetime, location: str, settings: Settings
) -> str:
    if starts_at <= clock.now() or ends_at <= starts_at:
        raise ProblemError(EVENT_TIME_INVALID)
    return validate_meeting(starts_at, location, settings)


async def event_offers(session: AsyncSession, listing: Listing) -> list[WaitlistEntry]:
    return list(
        await session.scalars(
            select(WaitlistEntry).where(
                WaitlistEntry.listing_id == listing.id,
                WaitlistEntry.status == WaitlistStatus.OFFERED,
            )
        )
    )


async def release_event_offers(session: AsyncSession, listing: Listing) -> None:
    for entry in await event_offers(session, listing):
        entry.status = WaitlistStatus.WAITING
        await cancel_deadline(session, offer_key(entry.id))
        record_waitlist(session, listing, None, "offer_released", entry, "offered")
    await session.flush()


async def offer_event_places(
    session: AsyncSession,
    listing: Listing,
    offer_timeout: timedelta,
    open_all_before: timedelta,
) -> None:
    if (
        listing.status != ListingStatus.ACTIVE
        or listing.event_starts_at is None
        or listing.event_starts_at <= clock.now()
    ):
        return
    if listing.event_starts_at - clock.now() <= open_all_before:
        await release_event_offers(session, listing)
        if listing.remaining_places:
            await open_to_all(session, listing)
        return
    available = (listing.remaining_places or 0) - len(
        await event_offers(session, listing)
    )
    if available <= 0:
        return
    entries = list(
        await session.scalars(
            select(WaitlistEntry)
            .where(
                WaitlistEntry.listing_id == listing.id,
                WaitlistEntry.status == WaitlistStatus.WAITING,
            )
            .order_by(WaitlistEntry.created_at, WaitlistEntry.id)
            .limit(available)
        )
    )
    for entry in entries:
        entry.status = WaitlistStatus.OFFERED
        entry.offer_slot = None
        entry.offered_at = clock.now()
        entry.offer_expires_at = min(
            clock.now() + offer_timeout, listing.event_starts_at - open_all_before
        )
        listing.version += 1
        record_waitlist(session, listing, None, "offered", entry, "waiting")
        notify(
            session,
            {entry.participant_id},
            "listing.offer",
            {
                "listing_id": str(listing.id),
                "entry_id": str(entry.id),
                "offer_expires_at": entry.offer_expires_at.isoformat(),
            },
            message=LISTING_OFFER,
        )
        await schedule_deadline(
            session,
            "listing.offer",
            entry.offer_expires_at,
            {
                "entry_id": str(entry.id),
                "offer_timeout": int(offer_timeout.total_seconds()),
                "open_all_before": int(open_all_before.total_seconds()),
            },
            key=offer_key(entry.id),
        )


async def register_event(
    session: AsyncSession, listing: Listing, user: User, settings: Settings
) -> Interaction:
    require_live(listing)
    if (
        listing.event_starts_at is None
        or listing.event_starts_at <= clock.now()
        or not listing.remaining_places
    ):
        raise ProblemError(CONFLICT)
    interaction = Interaction(
        listing_id=listing.id,
        participant_id=user.id,
        participant=user,
        slot=None,
        # New rows start without relationships; validation reads them.
        meeting=None,
        options=[],
    )
    session.add(interaction)
    await session.flush()
    record(session, listing, user.id, "requested", None, interaction)
    interaction.status = InteractionStatus.ACCEPTED
    listing.event_registered += 1
    listing.version += 1
    meeting = Meeting(
        interaction_id=interaction.id,
        scheduled_at=listing.event_starts_at,
        location=listing.event_location,
        scheduled_by_id=listing.author_id,
        version=1,
    )
    interaction.meeting = meeting
    session.add(meeting)
    await session.flush()
    record(
        session, listing, user.id, "transition", InteractionStatus.PENDING, interaction
    )
    await schedule_meeting_reminders(session, settings, listing, interaction, meeting)
    return interaction


async def accept_event_offer(
    session: AsyncSession, listing: Listing, user: User, settings: Settings
) -> Interaction:
    entry = await active_waitlist(session, listing.id, user.id)
    if entry is None or entry.status != WaitlistStatus.OFFERED:
        raise ProblemError(OFFER_MISSING)
    if entry.offer_expires_at is None or entry.offer_expires_at <= clock.now():
        raise ProblemError(OFFER_EXPIRED)
    interaction = await register_event(session, listing, user, settings)
    entry.status = WaitlistStatus.CLAIMED
    entry.interaction_id = interaction.id
    await cancel_deadline(session, offer_key(entry.id))
    record_waitlist(session, listing, user.id, "offer_accepted", entry, "offered")
    return interaction


async def schedule_event_open(
    session: AsyncSession, listing: Listing, settings: Settings
) -> None:
    if listing.event_starts_at is not None:
        await schedule_deadline(
            session,
            "listing.event_open",
            listing.event_starts_at - settings.listing_open_to_all_before,
            {"listing_id": str(listing.id)},
            key=f"event-open:{listing.id}",
        )


@deadline_handlers.register("listing.event_open")
async def open_event_places(session: AsyncSession, job: JobInfo) -> None:
    listing = await locked(session, UUID(job.payload["listing_id"]))
    if listing.status != ListingStatus.ACTIVE:
        return
    await release_event_offers(session, listing)
    if listing.remaining_places:
        await open_to_all(session, listing)
