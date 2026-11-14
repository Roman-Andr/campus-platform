"""Giveaway endpoints, using the shared listing aggregate."""

from collections.abc import Sequence
from datetime import datetime
from typing import Annotated, Any
from uuid import UUID

from fastapi import Query, Request, Response
from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    SerializerFunctionWrapHandler,
    model_serializer,
)
from sqlalchemy import and_, delete, or_, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import joinedload

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
    request_locale,
)
from campus.core.web.auth import CurrentUser
from campus.core.web.datetimes import Instant
from campus.core.web.pagination import paginate, sort_by
from campus.core.web.problems import NOT_FOUND, ProblemResponse, problem_response
from campus.modules.identity import ProfiledUser, User
from campus.modules.listings.models import (
    Audience,
    Category,
    Favorite,
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
    INVALID_CATEGORY,
    INVALID_CONTENT,
    RATE_LIMIT,
    STALE,
    TYPE_POLICIES,
    change_listing,
    locked,
    rate_limit,
    record,
    reject_pending,
    require_live,
    transition,
    visible,
)
from campus.modules.university import AccountType, City

router = api_router(
    prefix="/listings",
    tags=["Listings"],
    responses={
        403: {"model": Problem},
        404: {"model": Problem},
        409: {"model": Problem},
        429: {"model": Problem},
    },
)


class GiveawayInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    title: str
    description: str
    visibility: Visibility = Visibility.CITY
    audience: Audience = Audience.STUDENTS
    category_id: UUID | None = None
    draft: bool = False


class ListingEdit(BaseModel):
    model_config = ConfigDict(extra="forbid")
    title: str
    description: str
    version: int = Field(ge=1)
    category_id: UUID | None = None


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
    city_timezone: str
    dormitory_id: UUID | None
    faculty_id: UUID | None
    status: ListingStatus
    version: int
    created_at: Instant
    expires_at: Instant | None
    category_id: UUID | None
    hidden_reason: str | None
    favorite: bool = Field(
        default=False, description="Whether the current user bookmarked it."
    )


class InteractionOutput(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    listing_id: UUID
    participant_name: str
    participant_id: UUID
    status: InteractionStatus
    stage: str | None
    response_due_at: Instant | None


class ParticipationListing(BaseModel):
    """Enough of the listing to show a participation row without a fetch."""

    model_config = ConfigDict(from_attributes=True)
    id: UUID
    kind: str
    title: str
    status: ListingStatus
    city_timezone: str


class ParticipationOutput(InteractionOutput):
    created_at: Instant
    listing: ParticipationListing


class FavoriteRow(BaseModel):
    model_config = ConfigDict(from_attributes=True, arbitrary_types_allowed=True)
    listing_id: UUID
    created_at: datetime
    listing: Listing


def omit_null(schema: dict[str, Any]) -> None:
    """Describe an optional object as a plain reference, not a null union."""
    [ref] = [item for item in schema.pop("anyOf") if item.get("type") != "null"]
    schema.update(ref)
    schema.pop("default", None)


class FavoriteOutput(BaseModel):
    listing_id: UUID
    created_at: Instant
    available: bool = Field(
        description="False when hidden, expired, closed or out of the user's area."
    )
    listing: ListingOutput | None = Field(
        default=None,
        description="The listing; absent, with no content, when unavailable.",
        json_schema_extra=omit_null,
    )

    # Unannotated on purpose: a return annotation would replace the schema.
    @model_serializer(mode="wrap")
    def _omit_listing(self, handler: SerializerFunctionWrapHandler):  # type: ignore[no-untyped-def]
        data = handler(self)
        if data.get("listing") is None:
            data.pop("listing", None)
        return data


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
    created_at: Instant
    reason: str | None
    stage: str | None
    via_assistant: bool
    offline_qr: bool


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
    if listing is None:
        raise ProblemError(NOT_FOUND)
    if listing.author_id == user.id or visible(listing, user):
        return listing
    # Existing participants retain the card needed to finish and review.
    participant = await session.scalar(
        select(Interaction.id).where(
            Interaction.listing_id == listing.id,
            Interaction.participant_id == user.id,
        )
    )
    if participant is None:
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
    if (
        user.account_type == AccountType.EMPLOYEE
        and data.audience != Audience.COMMUNITY
    ):
        raise ProblemError(FORBIDDEN)
    if data.visibility == Visibility.DORMITORY and (
        user.dormitory_id is None or user.account_type == AccountType.EMPLOYEE
    ):
        raise ProblemError(FORBIDDEN)
    if data.category_id is not None or not data.draft:
        await check_category(session, data.category_id)
    if not data.draft:
        await publication_quota(session, user.id, settings)
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
        city=await session.get(City, user.city_id),
        faculty_id=user.faculty_id if data.visibility == Visibility.FACULTY else None,
        dormitory_id=user.dormitory_id
        if data.visibility == Visibility.DORMITORY
        else None,
        status=ListingStatus.DRAFT if data.draft else ListingStatus.ACTIVE,
        category_id=data.category_id,
        expires_at=None if data.draft else clock.now() + settings.listing_lifetime,
    )
    session.add(listing)
    await session.flush()
    session.add(Item(listing_id=listing.id, mode="giveaway"))
    record(
        session, listing, user.id, "draft_created" if data.draft else "published", None
    )
    if not data.draft:
        await expiry_deadline(session, listing)
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
    result = await paginate(session, query, page, ListingOutput)
    await mark_favorites(session, user.id, result.items)
    return result


async def mark_favorites(
    session: DbSession, user_id: UUID, items: Sequence[ListingOutput]
) -> None:
    if not items:
        return
    marked = set(
        await session.scalars(
            select(Favorite.listing_id).where(
                Favorite.user_id == user_id,
                Favorite.listing_id.in_([item.id for item in items]),
            )
        )
    )
    for item in items:
        item.favorite = item.id in marked


def available(listing: Listing, user: User) -> bool:
    return (
        listing.status in (ListingStatus.ACTIVE, ListingStatus.BUSY)
        and listing.expires_at is not None
        and listing.expires_at > clock.now()
        and visible(listing, user)
    )


class CategoryOutput(BaseModel):
    id: UUID
    code: str
    name: str


class CategoryList(BaseModel):
    items: list[CategoryOutput]


@router.get("/categories")
async def categories(
    request: Request, response: Response, session: DbSession
) -> CategoryList:
    locale = request_locale(request)
    response.headers["Content-Language"] = locale
    response.headers["Vary"] = "Accept-Language"
    rows = await session.scalars(
        select(Category).order_by(Category.name_column(locale), Category.id)
    )
    return CategoryList(
        items=[
            CategoryOutput(id=row.id, code=row.code, name=row.name_in(locale))
            for row in rows
        ]
    )


@router.get("/mine")
async def my_listings(
    session: DbSession,
    principal: CurrentUser,
    page: PageQuery,
    status: Annotated[
        list[ListingStatus] | None,
        Query(description="Only these statuses; all of them by default."),
    ] = None,
) -> Page[ListingOutput]:
    """Own listings of every status: drafts, active, busy and the archive."""
    query = select(Listing).where(Listing.author_id == principal.user_id)
    if status:
        query = query.where(Listing.status.in_(status))
    query = sort_by(
        query,
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
) -> Page[ParticipationOutput]:
    """Own participation in listings of every kind, with status and stage."""
    query = sort_by(
        select(Interaction)
        .options(joinedload(Interaction.listing))
        .where(Interaction.participant_id == principal.user_id),
        "-created_at",
        {"created_at": Interaction.created_at},
        Interaction.id,
    )
    return await paginate(session, query, page, ParticipationOutput)


@router.get("/favorites")
async def my_favorites(
    session: DbSession, principal: CurrentUser, page: PageQuery
) -> Page[FavoriteOutput]:
    """Recently bookmarked first; unavailable listings carry no content."""
    user = await user_for(session, principal)
    query = sort_by(
        select(Favorite).where(Favorite.user_id == user.id),
        "-created_at",
        {"created_at": Favorite.created_at},
        Favorite.listing_id,
    )
    rows = await paginate(session, query, page, FavoriteRow)
    items = []
    for row in rows.items:
        shown = available(row.listing, user)
        items.append(
            FavoriteOutput(
                listing_id=row.listing_id,
                created_at=row.created_at,
                available=shown,
                listing=ListingOutput.model_validate(row.listing) if shown else None,
            )
        )
    for item in items:
        if item.listing is not None:
            item.listing.favorite = True
    return Page[FavoriteOutput](items=items, next_page=rows.next_page)


@router.put("/{listing_id}/favorite", status_code=204)
async def add_favorite(
    listing_id: UUID, session: DbSession, principal: CurrentUser
) -> None:
    """Repeating the request, even concurrently, keeps a single bookmark."""
    user = await user_for(session, principal)
    listing = await session.get(Listing, listing_id)
    if listing is None or not visible(listing, user):
        raise ProblemError(NOT_FOUND)
    await session.execute(
        insert(Favorite)
        .values(user_id=user.id, listing_id=listing.id, created_at=clock.now())
        .on_conflict_do_nothing()
    )


@router.delete("/{listing_id}/favorite", status_code=204)
async def remove_favorite(
    listing_id: UUID, session: DbSession, principal: CurrentUser
) -> None:
    """Removal works for unavailable listings too and is a no-op if absent."""
    await session.execute(
        delete(Favorite).where(
            Favorite.user_id == principal.user_id, Favorite.listing_id == listing_id
        )
    )


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
    user = await user_for(session, principal)
    result = ListingOutput.model_validate(await readable(session, listing_id, user))
    await mark_favorites(session, user.id, [result])
    return result


@router.patch("/{listing_id}", response_model=ListingOutput)
async def edit_listing(
    listing_id: UUID,
    data: ListingEdit,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
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
    if listing.status != ListingStatus.DRAFT:
        require_live(listing)
    if data.category_id is not None:
        await check_category(session, data.category_id)
        listing.category_id = data.category_id
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
    principal: ProfiledUser,
) -> ListingOutput:
    """Closing rejects pending applications and preserves accepted interactions."""
    listing = await locked(session, listing_id)
    if listing.author_id != principal.user_id:
        raise ProblemError(FORBIDDEN)
    if listing.status != ListingStatus.DRAFT:
        require_live(listing)
    change_listing(
        session, listing, ListingStatus.CANCELLED, principal.user_id, "cancelled"
    )
    await reject_pending(session, listing, "listing_cancelled")
    await session.flush()
    return ListingOutput.model_validate(listing)


@router.post("/{listing_id}/reservations", status_code=201)
async def reserve_giveaway(
    listing_id: UUID,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
) -> InteractionOutput:
    listing = await locked(session, listing_id)
    user = await user_for(session, principal)
    if (
        user.account_type == AccountType.EMPLOYEE
        and listing.audience == Audience.STUDENTS
    ):
        raise ProblemError(FORBIDDEN)
    if user.id == listing.author_id or user.account_type not in (
        AccountType.STUDENT,
        AccountType.EMPLOYEE,
    ):
        raise ProblemError(FORBIDDEN)
    if not visible(listing, user):
        raise ProblemError(NOT_FOUND)
    require_live(listing)
    if listing.status != ListingStatus.ACTIVE or listing.kind != "giveaway":
        raise ProblemError(CONFLICT)
    settings: Settings = request.app.state.settings
    retry = await rate_limit(
        session,
        user.id,
        "requested",
        settings.listing_response_limit,
        settings.listing_response_window,
    )
    if retry is not None:
        raise ProblemError(RATE_LIMIT, headers={"Retry-After": str(retry)})
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
    change_listing(session, listing, ListingStatus.BUSY, user.id, "reserved")
    record(session, listing, user.id, "requested", None, interaction)
    if interaction.response_due_at is not None:
        await schedule_deadline(
            session,
            "listing.author_response",
            interaction.response_due_at,
            {"listing_id": str(listing.id), "interaction_id": str(interaction.id)},
            key=f"interaction:{interaction.id}",
        )
    return InteractionOutput.model_validate(interaction)


@router.post("/{listing_id}/interactions/{interaction_id}/transition")
async def transition_interaction(
    listing_id: UUID,
    interaction_id: UUID,
    data: TransitionInput,
    session: DbSession,
    principal: ProfiledUser,
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
    query = select(ListingEvent).where(ListingEvent.listing_id == listing_id)
    if listing.author_id != principal.user_id:
        own_interactions = select(Interaction.id).where(
            Interaction.listing_id == listing.id,
            Interaction.participant_id == principal.user_id,
        )
        query = query.where(
            or_(
                ListingEvent.interaction_id.is_(None),
                ListingEvent.interaction_id.in_(own_interactions),
            )
        )
    query = sort_by(
        query, "created_at", {"created_at": ListingEvent.created_at}, ListingEvent.id
    )
    return await paginate(session, query, page, EventOutput)


async def check_category(session: DbSession, category_id: UUID | None) -> None:
    if category_id is None or await session.get(Category, category_id) is None:
        raise ProblemError(INVALID_CATEGORY)


async def publication_quota(
    session: DbSession, user_id: UUID, settings: Settings
) -> None:
    retry = await rate_limit(
        session,
        user_id,
        "published",
        settings.listing_publication_limit,
        settings.listing_publication_window,
    )
    if retry is not None:
        raise ProblemError(RATE_LIMIT, headers={"Retry-After": str(retry)})


async def expiry_deadline(session: DbSession, listing: Listing) -> None:
    assert listing.expires_at is not None  # noqa: S101 - published listing
    await schedule_deadline(
        session,
        "listing.expire",
        listing.expires_at,
        {"listing_id": str(listing.id)},
        key=f"listing:{listing.id}",
    )


@router.post("/{listing_id}/publish")
async def publish_listing(
    listing_id: UUID, request: Request, session: DbSession, principal: ProfiledUser
) -> ListingOutput:
    listing = await locked(session, listing_id)
    if listing.author_id != principal.user_id:
        raise ProblemError(FORBIDDEN)
    if listing.status not in (ListingStatus.DRAFT, ListingStatus.EXPIRED):
        raise ProblemError(CONFLICT)
    user = await user_for(session, principal)
    if user.account_type not in (AccountType.STUDENT, AccountType.EMPLOYEE):
        raise ProblemError(FORBIDDEN)
    if (
        user.account_type == AccountType.EMPLOYEE
        and listing.audience != Audience.COMMUNITY
    ):
        raise ProblemError(FORBIDDEN)
    settings: Settings = request.app.state.settings
    await check_category(session, listing.category_id)
    check_text(listing.title, listing.description, settings)
    await publication_quota(session, user.id, settings)
    # Snapshot the current profile when publishing/re-publishing.
    assert user.city_id is not None  # noqa: S101 - ProfiledUser
    if listing.visibility == Visibility.DORMITORY and (
        user.dormitory_id is None or user.account_type == AccountType.EMPLOYEE
    ):
        raise ProblemError(FORBIDDEN)
    listing.city_id = user.city_id
    city = await session.get(City, user.city_id)
    assert city is not None  # noqa: S101 - the profile has a city foreign key
    listing.city = city
    listing.faculty_id = (
        user.faculty_id if listing.visibility == Visibility.FACULTY else None
    )
    listing.dormitory_id = (
        user.dormitory_id if listing.visibility == Visibility.DORMITORY else None
    )
    # A still accepted single-item interaction keeps the republished item occupied.
    occupied = await session.scalar(
        select(Interaction.id).where(
            Interaction.listing_id == listing.id,
            Interaction.status == InteractionStatus.ACCEPTED,
        )
    )
    listing.expires_at = clock.now() + settings.listing_lifetime
    change_listing(
        session,
        listing,
        ListingStatus.BUSY if occupied else ListingStatus.ACTIVE,
        user.id,
        "published",
    )
    await expiry_deadline(session, listing)
    await session.flush()
    return ListingOutput.model_validate(listing)


@router.post("/{listing_id}/extend")
async def extend_listing(
    listing_id: UUID, request: Request, session: DbSession, principal: ProfiledUser
) -> ListingOutput:
    listing = await locked(session, listing_id)
    if listing.author_id != principal.user_id:
        raise ProblemError(FORBIDDEN)
    require_live(listing)
    listing.expires_at = clock.now() + request.app.state.settings.listing_lifetime
    listing.version += 1
    record(session, listing, principal.user_id, "extended", listing.status)
    await expiry_deadline(session, listing)
    await session.flush()
    return ListingOutput.model_validate(listing)


@router.get("/{listing_id}/interactions/{interaction_id}/events")
async def interaction_events(
    listing_id: UUID,
    interaction_id: UUID,
    session: DbSession,
    principal: CurrentUser,
    page: PageQuery,
) -> Page[EventOutput]:
    listing = await session.get(Listing, listing_id)
    interaction = await session.get(Interaction, interaction_id)
    if listing is None or interaction is None or interaction.listing_id != listing_id:
        raise ProblemError(NOT_FOUND)
    if principal.user_id not in (listing.author_id, interaction.participant_id):
        raise ProblemError(FORBIDDEN)
    query = sort_by(
        select(ListingEvent).where(ListingEvent.interaction_id == interaction_id),
        "created_at",
        {"created_at": ListingEvent.created_at},
        ListingEvent.id,
    )
    return await paginate(session, query, page, EventOutput)
