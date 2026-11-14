"""Event publication, condition changes and atomic signup."""

from typing import Literal
from uuid import UUID

from fastapi import Request
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select

from campus.core import clock
from campus.core.config import Settings
from campus.core.web import DbSession, ProblemError
from campus.core.web.datetimes import Instant
from campus.core.web.problems import NOT_FOUND
from campus.modules.identity import ProfiledUser
from campus.modules.listings.api import (
    GiveawayInput,
    InteractionOutput,
    ListingOutput,
    check_category,
    check_participant,
    check_text,
    expiry_deadline,
    publication_quota,
    router,
    user_for,
)
from campus.modules.listings.models import (
    Audience,
    Interaction,
    InteractionStatus,
    Listing,
    ListingStatus,
    Visibility,
    WaitlistEntry,
    WaitlistStatus,
)
from campus.modules.listings.service import (
    CONFLICT,
    EVENT_CAPACITY_CONFLICT,
    EVENT_CONDITIONS_CHANGED,
    FORBIDDEN,
    STALE,
    active_waitlist,
    claim_offer,
    event_offers,
    join_waitlist,
    locked,
    offer_next,
    record,
    record_waitlist,
    register_event,
    release_event_offers,
    require_live,
    schedule_event_open,
    schedule_meeting_reminders,
    validate_event,
    visible,
)
from campus.modules.notifications import notify
from campus.modules.university import AccountType, City

__all__ = ["router"]


class EventInput(GiveawayInput):
    starts_at: Instant
    ends_at: Instant
    location: str
    capacity: int = Field(ge=1)
    draft: Literal[False] = False


class EventEdit(BaseModel):
    model_config = ConfigDict(extra="forbid")
    version: int = Field(ge=1)
    starts_at: Instant
    ends_at: Instant
    location: str
    capacity: int = Field(ge=1)


class SignupInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    join_queue: bool = False


class SignupOutput(BaseModel):
    result: Literal["registered", "queued", "full"]
    interaction: InteractionOutput | None = None
    remaining_places: int


@router.post("/events", status_code=201)
async def publish_event(
    data: EventInput, request: Request, session: DbSession, principal: ProfiledUser
) -> ListingOutput:
    settings: Settings = request.app.state.settings
    location = validate_event(data.starts_at, data.ends_at, data.location, settings)
    user = await user_for(session, principal)
    if user.account_type not in (AccountType.STUDENT, AccountType.EMPLOYEE):
        raise ProblemError(FORBIDDEN)
    if (
        data.visibility == Visibility.UNIVERSITY
        or (data.visibility == Visibility.FACULTY and user.faculty_id is None)
        or (
            user.account_type == AccountType.EMPLOYEE
            and data.audience != Audience.COMMUNITY
        )
        or (
            data.visibility == Visibility.DORMITORY
            and (user.dormitory_id is None or user.account_type == AccountType.EMPLOYEE)
        )
    ):
        raise ProblemError(FORBIDDEN)
    check_text(data.title, data.description, settings)
    await check_category(session, data.category_id)
    await publication_quota(session, user.id, settings)
    assert user.city_id is not None  # noqa: S101 - ProfiledUser
    listing = Listing(
        author=user,
        author_id=user.id,
        author_dormitory_id=user.dormitory_id,
        kind="event",
        title=data.title,
        description=data.description,
        visibility=data.visibility,
        audience=data.audience,
        city_id=user.city_id,
        city=await session.get(City, user.city_id),
        faculty_id=user.faculty_id if data.visibility == Visibility.FACULTY else None,
        dormitory_id=user.dormitory_id
        if data.visibility == Visibility.DORMITORY
        else None,
        status=ListingStatus.ACTIVE,
        category_id=data.category_id,
        expires_at=data.ends_at,
        event_starts_at=data.starts_at,
        event_ends_at=data.ends_at,
        event_location=location,
        event_capacity=data.capacity,
        event_registered=0,
    )
    session.add(listing)
    await session.flush()
    record(session, listing, user.id, "published", None)
    await expiry_deadline(session, listing)
    await schedule_event_open(session, listing, settings)
    return ListingOutput.model_validate(listing)


@router.post("/{listing_id}/signup")
async def signup_event(
    listing_id: UUID,
    data: SignupInput,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
) -> SignupOutput:
    # Every writer of places locks this aggregate before checking its counter.
    listing = await locked(session, listing_id)
    user = await user_for(session, principal)
    check_participant(listing, user)
    if not visible(listing, user):
        raise ProblemError(NOT_FOUND)
    require_live(listing)
    if (
        listing.kind != "event"
        or listing.event_starts_at is None
        or listing.event_starts_at <= clock.now()
    ):
        raise ProblemError(CONFLICT)
    existing = await session.scalar(
        select(Interaction).where(
            Interaction.listing_id == listing.id,
            Interaction.participant_id == user.id,
            Interaction.status == InteractionStatus.ACCEPTED,
        )
    )
    if existing is not None:
        return SignupOutput(
            result="registered",
            interaction=InteractionOutput.model_validate(existing),
            remaining_places=listing.remaining_places or 0,
        )
    settings: Settings = request.app.state.settings
    if (
        listing.event_starts_at - clock.now() > settings.listing_open_to_all_before
        or await event_offers(session, listing)
    ):
        await offer_next(
            session,
            listing,
            offer_timeout=settings.listing_offer_timeout,
            open_all_before=settings.listing_open_to_all_before,
        )
    entry = await active_waitlist(session, listing.id, user.id)
    offers = await event_offers(session, listing)
    if entry is not None and entry.status == WaitlistStatus.OFFERED:
        interaction = await claim_offer(session, listing, user, settings)
    elif (listing.remaining_places or 0) > len(offers):
        interaction = await register_event(session, listing, user, settings)
        if entry is not None:
            entry.status = WaitlistStatus.CLAIMED
            entry.interaction_id = interaction.id
            record_waitlist(
                session, listing, user.id, "offer_accepted", entry, "waiting"
            )
    else:
        if data.join_queue and entry is None:
            entry = await join_waitlist(session, listing, user)
        return SignupOutput(
            result="queued" if entry else "full",
            remaining_places=listing.remaining_places or 0,
        )
    await session.flush()
    return SignupOutput(
        result="registered",
        interaction=InteractionOutput.model_validate(interaction),
        remaining_places=listing.remaining_places or 0,
    )


@router.patch("/{listing_id}/event")
async def edit_event(
    listing_id: UUID,
    data: EventEdit,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
) -> ListingOutput:
    listing = await locked(session, listing_id)
    if listing.author_id != principal.user_id:
        raise ProblemError(FORBIDDEN)
    if listing.kind != "event":
        raise ProblemError(CONFLICT)
    require_live(listing)
    if listing.version != data.version:
        raise ProblemError(STALE, version=listing.version)
    settings: Settings = request.app.state.settings
    location = validate_event(data.starts_at, data.ends_at, data.location, settings)
    if data.capacity < listing.event_registered:
        raise ProblemError(EVENT_CAPACITY_CONFLICT)
    changed = (
        listing.event_starts_at,
        listing.event_ends_at,
        listing.event_location,
    ) != (data.starts_at, data.ends_at, location)
    # Replace all pending offers using the new capacity and start time.
    await release_event_offers(session, listing)
    listing.event_starts_at, listing.event_ends_at = data.starts_at, data.ends_at
    listing.event_location, listing.event_capacity = location, data.capacity
    listing.expires_at = data.ends_at
    listing.version += 1
    participants = list(
        await session.scalars(
            select(Interaction).where(
                Interaction.listing_id == listing.id,
                Interaction.status == InteractionStatus.ACCEPTED,
            )
        )
    )
    if changed:
        record(
            session, listing, principal.user_id, "conditions_changed", listing.status
        )
        recipients = {item.participant_id for item in participants}
        recipients.update(
            await session.scalars(
                select(WaitlistEntry.participant_id).where(
                    WaitlistEntry.listing_id == listing.id,
                    WaitlistEntry.status.in_(("waiting", "offered")),
                )
            )
        )
        if recipients:
            notify(
                session,
                recipients,
                "listing.event.conditions_changed",
                {
                    "listing_id": str(listing.id),
                    "starts_at": data.starts_at.isoformat(),
                    "ends_at": data.ends_at.isoformat(),
                    "location": location,
                },
                message=EVENT_CONDITIONS_CHANGED,
            )
        for interaction in participants:
            meeting = interaction.meeting
            if meeting is not None:
                meeting.scheduled_at, meeting.location = data.starts_at, location
                meeting.version += 1
                await schedule_meeting_reminders(
                    session, settings, listing, interaction, meeting
                )
    else:
        record(session, listing, principal.user_id, "edited", listing.status)
    await expiry_deadline(session, listing)
    await schedule_event_open(session, listing, settings)
    await offer_next(
        session,
        listing,
        offer_timeout=settings.listing_offer_timeout,
        open_all_before=settings.listing_open_to_all_before,
    )
    await session.flush()
    return ListingOutput.model_validate(listing)
