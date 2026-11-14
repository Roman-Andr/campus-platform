"""Giveaway endpoints, using the shared listing aggregate."""

from datetime import datetime
from uuid import UUID

from fastapi import Request
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import and_, or_, select

from campus.core import clock
from campus.core.config import Settings
from campus.core.deadlines import schedule_deadline
from campus.core.web import (
    DbSession,
    Page,
    PageQuery,
    Problem,
    ProblemError,
    api_router,
)
from campus.core.web.auth import CurrentUser
from campus.core.web.pagination import paginate, sort_by
from campus.core.web.problems import NOT_FOUND, ProblemResponse, problem_response
from campus.modules.identity import ProfiledUser, User
from campus.modules.listings.models import (
    Audience,
    Interaction,
    InteractionStatus,
    Item,
    Listing,
    ListingEvent,
    ListingStatus,
    Visibility,
)
from campus.modules.listings.service import (
    CONFLICT,
    FORBIDDEN,
    INVALID_CONTENT,
    STALE,
    change_listing,
    locked,
    record,
    require_live,
    transition,
    visible,
)
from campus.modules.university import AccountType

router = api_router(
    prefix="/listings",
    tags=["Listings"],
    responses={
        403: {"model": Problem},
        404: {"model": Problem},
        409: {"model": Problem},
    },
)


class GiveawayInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    title: str
    description: str
    visibility: Visibility = Visibility.CITY
    audience: Audience = Audience.STUDENTS


class ListingEdit(BaseModel):
    model_config = ConfigDict(extra="forbid")
    title: str
    description: str
    version: int = Field(ge=1)


class ListingOutput(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    author_name: str
    author_id: UUID
    kind: str
    title: str
    description: str
    visibility: Visibility
    audience: Audience
    city_id: UUID
    dormitory_id: UUID | None
    faculty_id: UUID | None
    status: ListingStatus
    version: int
    created_at: datetime
    expires_at: datetime


class InteractionOutput(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    listing_id: UUID
    participant_name: str
    participant_id: UUID
    status: InteractionStatus


class TransitionInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    status: InteractionStatus


class EventOutput(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    interaction_id: UUID | None
    actor_id: UUID | None
    action: str
    previous_status: str | None
    status: str
    version: int
    created_at: datetime


def check_text(title: str, description: str, settings: Settings) -> None:
    if (
        not title.strip()
        or not description.strip()
        or len(title) > settings.listing_title_max_length
        or len(description) > settings.listing_description_max_length
    ):
        raise ProblemError(INVALID_CONTENT)


async def user_for(session: DbSession, principal: CurrentUser) -> User:
    user = await session.get(User, principal.user_id)
    assert user is not None  # noqa: S101 - authenticated accounts persist
    return user


async def readable(session: DbSession, listing_id: UUID, user: User) -> Listing:
    listing = await session.get(Listing, listing_id)
    if listing is None or (listing.author_id != user.id and not visible(listing, user)):
        raise ProblemError(NOT_FOUND)
    return listing


@router.post("/giveaways", status_code=201)
async def publish_giveaway(
    data: GiveawayInput,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
) -> ListingOutput:
    user = await user_for(session, principal)
    settings: Settings = request.app.state.settings
    check_text(data.title, data.description, settings)
    if user.account_type not in (AccountType.STUDENT, AccountType.EMPLOYEE):
        raise ProblemError(FORBIDDEN)
    if data.visibility == Visibility.DORMITORY and (
        user.dormitory_id is None or user.account_type == AccountType.EMPLOYEE
    ):
        raise ProblemError(FORBIDDEN)
    assert user.city_id is not None  # noqa: S101 - ProfiledUser
    listing = Listing(
        author=user,
        author_id=user.id,
        kind="giveaway",
        title=data.title,
        description=data.description,
        visibility=data.visibility,
        audience=data.audience,
        city_id=user.city_id,
        faculty_id=user.faculty_id if data.visibility == Visibility.FACULTY else None,
        dormitory_id=user.dormitory_id
        if data.visibility == Visibility.DORMITORY
        else None,
        expires_at=clock.now() + settings.listing_lifetime,
    )
    session.add(listing)
    await session.flush()
    session.add(Item(listing_id=listing.id, mode="giveaway"))
    record(session, listing, user.id, "published", None)
    await schedule_deadline(
        session,
        "listing.expire",
        listing.expires_at,
        {"listing_id": str(listing.id)},
        key=f"listing:{listing.id}",
    )
    return ListingOutput.model_validate(listing)


@router.get("")
async def listing_feed(
    session: DbSession,
    principal: CurrentUser,
    page: PageQuery,
    area: Visibility = Visibility.CITY,
) -> Page[ListingOutput]:
    """Newest first. City includes all visible scopes; narrower areas filter them."""
    user = await user_for(session, principal)
    scopes = [
        Listing.visibility == Visibility.CITY,
        and_(
            Listing.visibility == Visibility.FACULTY,
            Listing.faculty_id == user.faculty_id,
        ),
    ]
    if user.dormitory_id is not None and user.account_type == AccountType.STUDENT:
        scopes.append(
            and_(
                Listing.visibility == Visibility.DORMITORY,
                Listing.dormitory_id == user.dormitory_id,
            )
        )
    query = select(Listing).where(
        Listing.city_id == user.city_id,
        or_(*scopes),
        Listing.status.in_([ListingStatus.ACTIVE, ListingStatus.BUSY]),
        Listing.expires_at > clock.now(),
    )
    if user.account_type != AccountType.STUDENT:
        query = query.where(Listing.audience == Audience.COMMUNITY)
    if area != Visibility.CITY:
        query = query.where(Listing.visibility == area)
    query = sort_by(
        query, "-created_at", {"created_at": Listing.created_at}, Listing.id
    )
    return await paginate(session, query, page, ListingOutput)


@router.get("/mine")
async def my_listings(
    session: DbSession,
    principal: CurrentUser,
    page: PageQuery,
) -> Page[ListingOutput]:
    """All own listings, including those no longer in the public feed."""
    query = sort_by(
        select(Listing).where(Listing.author_id == principal.user_id),
        "-created_at",
        {"created_at": Listing.created_at},
        Listing.id,
    )
    return await paginate(session, query, page, ListingOutput)


@router.get("/reservations/mine")
async def my_reservations(
    session: DbSession,
    principal: CurrentUser,
    page: PageQuery,
) -> Page[InteractionOutput]:
    query = sort_by(
        select(Interaction).where(Interaction.participant_id == principal.user_id),
        "-created_at",
        {"created_at": Interaction.created_at},
        Interaction.id,
    )
    return await paginate(session, query, page, InteractionOutput)


@router.get("/{listing_id}/interactions")
async def listing_interactions(
    listing_id: UUID,
    session: DbSession,
    principal: CurrentUser,
    page: PageQuery,
) -> Page[InteractionOutput]:
    listing = await session.get(Listing, listing_id)
    if listing is None:
        raise ProblemError(NOT_FOUND)
    if listing.author_id != principal.user_id:
        raise ProblemError(FORBIDDEN)
    query = sort_by(
        select(Interaction).where(Interaction.listing_id == listing_id),
        "-created_at",
        {"created_at": Interaction.created_at},
        Interaction.id,
    )
    return await paginate(session, query, page, InteractionOutput)


@router.get("/{listing_id}")
async def get_listing(
    listing_id: UUID,
    session: DbSession,
    principal: CurrentUser,
) -> ListingOutput:
    return ListingOutput.model_validate(
        await readable(session, listing_id, await user_for(session, principal))
    )


@router.patch("/{listing_id}", response_model=ListingOutput)
async def edit_listing(
    listing_id: UUID,
    data: ListingEdit,
    request: Request,
    session: DbSession,
    principal: CurrentUser,
) -> ListingOutput | ProblemResponse:
    listing = await locked(session, listing_id)
    if listing.author_id != principal.user_id:
        raise ProblemError(FORBIDDEN)
    if listing.version != data.version:
        return problem_response(
            request,
            STALE,
            params={"version": listing.version},
            current_version=listing.version,
        )
    require_live(listing)
    check_text(data.title, data.description, request.app.state.settings)
    listing.title, listing.description = data.title, data.description
    listing.version += 1
    record(session, listing, principal.user_id, "edited", listing.status)
    await session.flush()
    return ListingOutput.model_validate(listing)


@router.post("/{listing_id}/cancel")
async def cancel_listing(
    listing_id: UUID,
    session: DbSession,
    principal: CurrentUser,
) -> ListingOutput:
    """Only an unoccupied active listing can be cancelled in this slice."""
    listing = await locked(session, listing_id)
    if listing.author_id != principal.user_id:
        raise ProblemError(FORBIDDEN)
    require_live(listing)
    if listing.status != ListingStatus.ACTIVE:
        raise ProblemError(CONFLICT)
    change_listing(
        session, listing, ListingStatus.CANCELLED, principal.user_id, "cancelled"
    )
    await session.flush()
    return ListingOutput.model_validate(listing)


@router.post("/{listing_id}/reservations", status_code=201)
async def reserve_giveaway(
    listing_id: UUID,
    session: DbSession,
    principal: ProfiledUser,
) -> InteractionOutput:
    listing = await locked(session, listing_id)
    user = await user_for(session, principal)
    if not visible(listing, user):
        raise ProblemError(NOT_FOUND)
    if user.id == listing.author_id or user.account_type not in (
        AccountType.STUDENT,
        AccountType.EMPLOYEE,
    ):
        raise ProblemError(FORBIDDEN)
    require_live(listing)
    if listing.status != ListingStatus.ACTIVE or listing.kind != "giveaway":
        raise ProblemError(CONFLICT)
    interaction = Interaction(
        listing_id=listing.id, participant_id=user.id, participant=user
    )
    session.add(interaction)
    await session.flush()
    change_listing(session, listing, ListingStatus.BUSY, user.id, "reserved")
    record(session, listing, user.id, "requested", None, interaction)
    return InteractionOutput.model_validate(interaction)


@router.post("/{listing_id}/interactions/{interaction_id}/transition")
async def transition_interaction(
    listing_id: UUID,
    interaction_id: UUID,
    data: TransitionInput,
    session: DbSession,
    principal: CurrentUser,
) -> InteractionOutput:
    listing = await locked(session, listing_id)
    interaction = await session.get(Interaction, interaction_id)
    if interaction is None or interaction.listing_id != listing.id:
        raise ProblemError(NOT_FOUND)
    if principal.user_id not in (listing.author_id, interaction.participant_id):
        raise ProblemError(FORBIDDEN)
    await transition(session, listing, interaction, data.status, principal.user_id)
    return InteractionOutput.model_validate(interaction)


@router.get("/{listing_id}/events")
async def listing_events(
    listing_id: UUID,
    session: DbSession,
    principal: CurrentUser,
    page: PageQuery,
) -> Page[EventOutput]:
    """History is private to the author and participants."""
    listing = await session.get(Listing, listing_id)
    if listing is None:
        raise ProblemError(NOT_FOUND)
    participant = await session.scalar(
        select(Interaction.id).where(
            Interaction.listing_id == listing.id,
            Interaction.participant_id == principal.user_id,
        )
    )
    if listing.author_id != principal.user_id and participant is None:
        raise ProblemError(FORBIDDEN)
    query = sort_by(
        select(ListingEvent).where(ListingEvent.listing_id == listing_id),
        "created_at",
        {"created_at": ListingEvent.created_at},
        ListingEvent.id,
    )
    return await paginate(session, query, page, EventOutput)
