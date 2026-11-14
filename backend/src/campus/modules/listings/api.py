"""Giveaway endpoints, using the shared listing aggregate."""

import base64
import binascii
import hashlib
import hmac
import json
from collections.abc import Awaitable, Callable, Sequence
from dataclasses import dataclass
from datetime import datetime
from typing import Annotated, Any, Self
from uuid import UUID

from fastapi import Query, Request, Response
from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    SerializerFunctionWrapHandler,
    model_serializer,
    model_validator,
)
from sqlalchemy import and_, case, delete, func, or_, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession
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
from campus.core.web.pagination import (
    INVALID_CURSOR,
    PageParams,
    cursor_key,
    paginate,
    sort_by,
)
from campus.core.web.problems import NOT_FOUND, ProblemResponse, problem_response
from campus.modules.identity import Permissions, ProfiledUser, Role, User
from campus.modules.listings.models import (
    PERMANENT_KINDS,
    Audience,
    Category,
    Favorite,
    Interaction,
    InteractionStatus,
    Item,
    LessonOption,
    LessonOptionStatus,
    Listing,
    ListingEvent,
    ListingStatus,
    Meeting,
    MeetingStatus,
    Skill,
    SkillDirection,
    Visibility,
    WaitlistEntry,
    WaitlistStatus,
)
from campus.modules.listings.service import (
    CONFLICT,
    EXCHANGE_OFFER_DUPLICATE,
    FORBIDDEN,
    HELP_DEADLINE_INVALID,
    INVALID_CATEGORY,
    INVALID_CONTENT,
    INVALID_EXCHANGE_OFFER,
    INVALID_LESSON_OPTIONS,
    MEETING_PROPOSED,
    MEETING_RESCHEDULED,
    MEETING_SCHEDULED,
    MEETING_STALE,
    MEETING_STATE,
    OFFER_PENDING,
    RATE_LIMIT,
    STALE,
    TYPE_POLICIES,
    accept_lesson_option,
    active_offer,
    active_waitlist,
    change_listing,
    claim_offer,
    clear_waitlist,
    decline_offer,
    extend_reservation,
    join_waitlist,
    leave_waitlist,
    locked,
    offer_timing,
    propose_lesson_counter,
    rate_limit,
    record,
    record_meeting,
    reject_pending,
    require_live,
    schedule_meeting_reminders,
    transition,
    validate_lesson_slot,
    validate_meeting,
    visible,
    waitlist_position,
)
from campus.modules.notifications import notify
from campus.modules.publications import Publication
from campus.modules.university import AccountType, City, Dormitory, Faculty

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


class SkillInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    title: str
    description: str
    direction: SkillDirection
    visibility: Visibility = Visibility.CITY
    audience: Audience = Audience.STUDENTS
    category_id: UUID


class ExchangeOfferInput(BaseModel):
    """What a participant offers in exchange for the author's item."""

    model_config = ConfigDict(extra="forbid")
    description: str


class LessonSlotInput(BaseModel):
    """One proposed lesson time with a place or an online flag."""

    model_config = ConfigDict(extra="forbid")
    time: Instant
    location: str | None = None
    online: bool = False

    @model_validator(mode="after")
    def _exactly_one_place(self) -> Self:
        if self.online == (self.location is not None):
            raise ValueError("give a place or set online, but not both")
        return self


class LessonInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    options: list[LessonSlotInput]


class LessonAcceptInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    option_id: UUID


class HelpRequestInput(BaseModel):
    """A help request stays relevant only until its author-set deadline."""

    model_config = ConfigDict(extra="forbid")
    title: str
    description: str
    visibility: Visibility = Visibility.CITY
    audience: Audience = Audience.STUDENTS
    category_id: UUID | None = None
    actual_until: Instant = Field(
        description="When the request stops being relevant; not after its lifetime."
    )


class ListingEdit(BaseModel):
    model_config = ConfigDict(extra="forbid")
    title: str
    description: str
    version: int = Field(ge=1)
    pinned_until: Instant | None = None
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
    direction: SkillDirection | None = Field(
        default=None, description="Direction of a skill listing; null otherwise."
    )
    pinned_until: Instant | None = None
    hidden_reason: str | None
    event_starts_at: Instant | None = None
    event_ends_at: Instant | None = None
    event_location: str | None = None
    event_capacity: int | None = None
    remaining_places: int | None = None
    favorite: bool = Field(
        default=False, description="Whether the current user bookmarked it."
    )
    archived_at: Instant | None = Field(
        description="When the listing entered the archive; null outside it."
    )
    purged_at: Instant | None = Field(
        description=(
            "When archive cleanup removed the description and photos;"
            " a purged listing cannot be published again."
        )
    )
    preview_url: str | None = Field(
        default=None,
        description="Signed link to the first photo's preview; null without photos.",
    )
    preview_file_id: UUID | None = Field(
        default=None,
        description="The photo whose preview is linked; null without photos.",
    )
    preview_expires_at: Instant | None = Field(
        default=None,
        description="When the preview link expires; null without photos.",
    )


@dataclass(frozen=True, slots=True)
class Preview:
    """A signed preview of the first listing photo, issued by its module."""

    file_id: UUID
    url: str
    expires_at: datetime


type PreviewLoader = Callable[
    [AsyncSession, Settings, Sequence[UUID]], Awaitable[dict[UUID, Preview]]
]

preview_loaders: dict[str, PreviewLoader] = {}


def register_preview_loader(
    name: str,
) -> Callable[[PreviewLoader], PreviewLoader]:
    """Decorator: issue signed previews of listing photos; see the files module."""

    def decorator(loader: PreviewLoader) -> PreviewLoader:
        if name in preview_loaders:
            msg = f"a preview loader {name!r} is already registered"
            raise ValueError(msg)
        preview_loaders[name] = loader
        return loader

    return decorator


async def attach_previews(
    session: DbSession, settings: Settings, items: Sequence[ListingOutput]
) -> None:
    """Add the first photo's preview to already visible listings.

    A single query serves the whole page: a feed row must not cost a photo
    request. Visibility is decided by the endpoint that selected the rows;
    this helper never widens it.
    """
    if not items or not preview_loaders:
        return
    ids = [item.id for item in items]
    previews: dict[UUID, Preview] = {}
    for loader in preview_loaders.values():
        previews.update(await loader(session, settings, ids))
    for item in items:
        preview = previews.get(item.id)
        if preview is not None:
            item.preview_url = preview.url
            item.preview_file_id = preview.file_id
            item.preview_expires_at = preview.expires_at


class MeetingOutput(BaseModel):
    """The effective meeting plus the proposal awaiting an answer, if any."""

    model_config = ConfigDict(from_attributes=True)
    id: UUID
    version: int
    status: MeetingStatus
    scheduled_at: Instant | None
    location: str | None
    online: bool
    scheduled_by_id: UUID | None
    proposed_at: Instant | None
    proposed_location: str | None
    proposed_by_id: UUID | None


class LessonOptionOutput(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    position: int
    time: Instant
    location: str | None
    online: bool
    proposed_by_id: UUID
    status: LessonOptionStatus


class InteractionOutput(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    listing_id: UUID
    participant_name: str
    participant_id: UUID
    status: InteractionStatus
    stage: str | None
    response_due_at: Instant | None
    executor: bool = Field(
        description="Whether this application is the selected help executor."
    )
    reservation_due_at: Instant | None = Field(
        default=None,
        description=(
            "When an accepted item reservation ends; extended to the meeting"
            " time once a meeting is scheduled."
        ),
    )
    offer_description: str | None = Field(
        default=None,
        description="The item a participant offers for an exchange; null otherwise.",
    )
    meeting: MeetingOutput | None
    options: list[LessonOptionOutput] = Field(
        default_factory=list,
        description="Time options of a skill lesson; empty for other types.",
    )


class ExchangeOfferList(BaseModel):
    items: list[InteractionOutput]


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


class MeetingProposalInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    time: Instant
    location: str


class MeetingAcceptInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    version: int = Field(ge=1)


class EventOutput(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    interaction_id: UUID | None
    waitlist_entry_id: UUID | None
    actor_id: UUID | None
    action: str
    previous_status: str | None
    status: str
    version: int
    created_at: Instant
    reason: str | None
    stage: str | None
    details: dict[str, Any] | None
    via_assistant: bool
    offline_qr: bool


class WaitlistEntryOutput(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    listing_id: UUID
    participant_name: str
    participant_id: UUID
    status: WaitlistStatus
    position: int | None = None
    offered_at: Instant | None
    offer_expires_at: Instant | None
    interaction_id: UUID | None
    created_at: Instant


class WaitlistQueue(BaseModel):
    items: list[WaitlistEntryOutput]


def waitlist_output(entry: WaitlistEntry, position: int | None) -> WaitlistEntryOutput:
    return WaitlistEntryOutput(
        id=entry.id,
        listing_id=entry.listing_id,
        participant_name=entry.participant_name,
        participant_id=entry.participant_id,
        status=WaitlistStatus(entry.status),
        position=position,
        offered_at=entry.offered_at,
        offer_expires_at=entry.offer_expires_at,
        interaction_id=entry.interaction_id,
        created_at=entry.created_at,
    )


async def own_waitlist_output(
    session: DbSession, entry: WaitlistEntry
) -> WaitlistEntryOutput:
    return waitlist_output(entry, await waitlist_position(session, entry))


def check_text(title: str, description: str, settings: Settings) -> None:
    if (
        not title.strip()
        or not description.strip()
        or len(title) > settings.listing_title_max_length
        or len(description) > settings.listing_description_max_length
    ):
        raise ProblemError(INVALID_CONTENT)


def lesson_slots(
    data: LessonInput, settings: Settings
) -> list[tuple[datetime, str | None, bool]]:
    """Validate the option count, times and places of a lesson request."""
    if not (
        settings.lesson_options_min <= len(data.options) <= settings.lesson_options_max
    ):
        raise ProblemError(
            INVALID_LESSON_OPTIONS,
            min=settings.lesson_options_min,
            max=settings.lesson_options_max,
        )
    return [
        validate_lesson_slot(option.time, option.location, option.online, settings)
        for option in data.options
    ]


def add_lesson_slots(
    interaction: Interaction,
    slots: Sequence[tuple[datetime, str | None, bool]],
    proposer_id: UUID,
) -> None:
    """Attach validated options in their request order."""
    for position, (time, location, online) in enumerate(slots):
        interaction.options.append(
            LessonOption(
                position=position,
                time=time,
                location=location,
                online=online,
                proposed_by_id=proposer_id,
                status=LessonOptionStatus.PROPOSED,
            )
        )


def lesson_details(
    slots: Sequence[tuple[datetime, str | None, bool]],
) -> list[dict[str, Any]]:
    return [
        {"time": time.isoformat(), "location": location, "online": online}
        for time, location, online in slots
    ]


def new_lesson(
    listing: Listing,
    participant_id: UUID,
    settings: Settings,
    proposer_id: UUID,
) -> Interaction:
    """An unlimited-capacity application with an author response deadline."""
    now = clock.now()
    return Interaction(
        listing_id=listing.id,
        participant_id=participant_id,
        slot=None,
        response_due_at=(
            now + settings.listing_response_timeout
            if proposer_id != listing.author_id
            else None
        ),
        meeting=None,
        options=[],
    )


async def schedule_author_response(
    session: DbSession, listing: Listing, interaction: Interaction
) -> None:
    if interaction.response_due_at is None:
        return
    await schedule_deadline(
        session,
        "listing.author_response",
        interaction.response_due_at,
        {"listing_id": str(listing.id), "interaction_id": str(interaction.id)},
        key=f"interaction:{interaction.id}",
    )


async def user_for(session: DbSession, principal: CurrentUser) -> User:
    user = await session.get(User, principal.user_id)
    assert user is not None  # noqa: S101 - authenticated accounts persist
    return user


def check_publish_access(
    user: User, visibility: Visibility, audience: Audience
) -> None:
    """Shared rules of user-created listings and help requests."""
    if visibility == Visibility.UNIVERSITY:
        raise ProblemError(FORBIDDEN)
    if user.account_type not in (AccountType.STUDENT, AccountType.EMPLOYEE):
        raise ProblemError(FORBIDDEN)
    if user.account_type == AccountType.EMPLOYEE and audience != Audience.COMMUNITY:
        raise ProblemError(FORBIDDEN)
    if visibility == Visibility.DORMITORY and (
        user.dormitory_id is None or user.account_type == AccountType.EMPLOYEE
    ):
        raise ProblemError(FORBIDDEN)


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
    check_publish_access(user, data.visibility, data.audience)
    if data.category_id is not None or not data.draft:
        await check_category(session, data.category_id)
    if not data.draft:
        await publication_quota(session, user.id, settings)
    assert user.city_id is not None  # noqa: S101 - ProfiledUser
    listing = Listing(
        author=user,
        author_id=user.id,
        author_dormitory_id=user.dormitory_id,
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


@router.post("/help-requests", status_code=201)
async def publish_help_request(
    data: HelpRequestInput,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
) -> ListingOutput:
    """Publish a help request with an author-set relevance deadline.

    The deadline is the listing's expiry: the request leaves the feed and
    closes automatically at that time unless the author has selected an
    executor. It may not exceed the ordinary listing lifetime.
    """
    user = await user_for(session, principal)
    settings: Settings = request.app.state.settings
    check_text(data.title, data.description, settings)
    check_publish_access(user, data.visibility, data.audience)
    await check_category(session, data.category_id)
    now = clock.now()
    if data.actual_until <= now or data.actual_until > now + settings.listing_lifetime:
        raise ProblemError(HELP_DEADLINE_INVALID)
    await publication_quota(session, user.id, settings)
    assert user.city_id is not None  # noqa: S101 - ProfiledUser
    listing = Listing(
        author=user,
        author_id=user.id,
        author_dormitory_id=user.dormitory_id,
        kind="help",
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
        expires_at=data.actual_until,
    )
    session.add(listing)
    await session.flush()
    record(session, listing, user.id, "published", None)
    await expiry_deadline(session, listing)
    return ListingOutput.model_validate(listing)


@router.post("/exchanges", status_code=201)
async def publish_exchange(
    data: GiveawayInput,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
) -> ListingOutput:
    """Publish an item to exchange: participants offer their own items."""
    user = await user_for(session, principal)
    settings: Settings = request.app.state.settings
    check_text(data.title, data.description, settings)
    if data.visibility == Visibility.UNIVERSITY:
        raise ProblemError(FORBIDDEN)
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
        author_dormitory_id=user.dormitory_id,
        kind="exchange",
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
    session.add(Item(listing_id=listing.id, mode="exchange"))
    record(
        session, listing, user.id, "draft_created" if data.draft else "published", None
    )
    if not data.draft:
        await expiry_deadline(session, listing)
    return ListingOutput.model_validate(listing)


def _feed_mac(settings: Settings, snapshot: str, cursor: str) -> str:
    payload = f"{snapshot}\n{cursor}".encode()
    return hmac.new(cursor_key(settings), payload, hashlib.sha256).hexdigest()


def feed_cursor(settings: Settings, snapshot: datetime, cursor: str) -> str:
    """Wrap a page cursor with the snapshot, authenticated by HMAC."""
    snapshot_text = snapshot.isoformat()
    raw = json.dumps(
        [snapshot_text, cursor, _feed_mac(settings, snapshot_text, cursor)]
    ).encode()
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


def feed_snapshot(page: PageParams, settings: Settings) -> tuple[datetime, PageParams]:
    if page.cursor is None:
        return clock.now(), page
    try:
        raw = base64.urlsafe_b64decode(page.cursor + "=" * (-len(page.cursor) % 4))
        snapshot_text, cursor, mac = json.loads(raw)
        if not (
            isinstance(snapshot_text, str)
            and isinstance(cursor, str)
            and isinstance(mac, str)
        ):
            raise ValueError
        expected = _feed_mac(settings, snapshot_text, cursor)
        if not hmac.compare_digest(mac.encode(), expected.encode()):
            raise ValueError
        snapshot = datetime.fromisoformat(snapshot_text)
        if snapshot.utcoffset() is None or snapshot > clock.now():
            raise ValueError
        if clock.now() - snapshot > settings.feed_snapshot_ttl:
            raise ValueError
        return snapshot, PageParams(page.size, cursor)
    except ValueError, TypeError, binascii.Error, UnicodeDecodeError:
        raise ProblemError(INVALID_CURSOR) from None


@router.post("/skills", status_code=201)
async def publish_skill(
    data: SkillInput,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
) -> ListingOutput:
    """Publish a permanent offer to teach or a request to learn a skill."""
    user = await user_for(session, principal)
    settings: Settings = request.app.state.settings
    check_text(data.title, data.description, settings)
    if data.visibility == Visibility.UNIVERSITY:
        raise ProblemError(FORBIDDEN)
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
    await check_category(session, data.category_id)
    await publication_quota(session, user.id, settings)
    assert user.city_id is not None  # noqa: S101 - ProfiledUser
    listing = Listing(
        author=user,
        author_id=user.id,
        author_dormitory_id=user.dormitory_id,
        kind="skill",
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
        expires_at=None,
        skill=Skill(direction=data.direction),
    )
    session.add(listing)
    await session.flush()
    record(session, listing, user.id, "published", None)
    return ListingOutput.model_validate(listing)


@router.get("")
async def listing_feed(  # noqa: PLR0913, PLR0917 - independent feed filters
    request: Request,
    session: DbSession,
    principal: CurrentUser,
    page: PageQuery,
    area: Visibility = Visibility.CITY,
    kind: str | None = None,
    category_id: UUID | None = None,
    dormitory_id: UUID | None = None,
    q: Annotated[
        str | None,
        Query(
            max_length=500,
            description="RU/EN full-text search; blank returns no matches.",
        ),
    ] = None,
) -> Page[ListingOutput]:
    """Visible pins first, then chronology; cursors bind filters and snapshot time.

    New records appear on refresh. Pin expiry during scrolling does not move
    records between pages; a fresh first page reflects current pin deadlines.
    Dormitory filters apply in city and faculty feeds without widening access.
    A cursor expires after CAMPUS_FEED_SNAPSHOT_TTL.
    With q, title and description match Russian or English morphology and
    relevance replaces pin ordering. Blank searches return an empty page.
    """
    settings: Settings = request.app.state.settings
    user = await user_for(session, principal)
    snapshot, params = feed_snapshot(page, settings)
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
        or_(
            Listing.visibility == Visibility.UNIVERSITY,
            and_(Listing.city_id == user.city_id, or_(*scopes)),
        ),
        Listing.status.in_([ListingStatus.ACTIVE, ListingStatus.BUSY]),
        or_(
            Listing.expires_at > snapshot,
            and_(
                Listing.kind.in_(PERMANENT_KINDS),
                Listing.expires_at.is_(None),
            ),
        ),
        Listing.created_at <= snapshot,
    )
    if user.account_type != AccountType.STUDENT:
        query = query.where(Listing.audience == Audience.COMMUNITY)
    if area != Visibility.CITY:
        query = query.where(Listing.visibility.in_([area, Visibility.UNIVERSITY]))
    if kind is not None:
        query = query.where(Listing.kind == kind)
    if category_id is not None:
        query = query.where(Listing.category_id == category_id)
    if dormitory_id is not None:
        # City/faculty listings retain the author's dormitory as filter metadata.
        query = query.where(
            or_(
                Listing.dormitory_id == dormitory_id,
                and_(
                    Listing.dormitory_id.is_(None),
                    Listing.author_dormitory_id == dormitory_id,
                ),
            )
        )
    pinned = case((Listing.pinned_until > snapshot, 1), else_=0)
    if q is not None:
        q = q.strip()
        terms = func.plainto_tsquery("russian", q).op("||")(
            func.plainto_tsquery("english", q)
        )
        query = query.where(Listing.search_vector.op("@@")(terms))
        query = query.order_by(
            func.ts_rank_cd(Listing.search_vector, terms).desc(),
            Listing.created_at.desc(),
            Listing.id.desc(),
        )
    else:
        query = query.order_by(
            pinned.desc(), Listing.created_at.desc(), Listing.id.desc()
        )
    context = json.dumps(
        [
            str(user.id),
            user.account_type,
            str(user.city_id),
            str(user.faculty_id),
            str(user.dormitory_id),
            area,
            kind,
            str(category_id),
            str(dormitory_id),
            snapshot.isoformat(),
            q,
        ]
    )
    result = await paginate(
        session, query, params, ListingOutput, settings=settings, context=context
    )
    await attach_previews(session, settings, result.items)
    if result.next_page:
        result.next_page = feed_cursor(settings, snapshot, result.next_page)
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
        and (
            (listing.kind in PERMANENT_KINDS and listing.expires_at is None)
            or (listing.expires_at is not None and listing.expires_at > clock.now())
        )
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
    request: Request,
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
    result = await paginate(
        session,
        query,
        page,
        ListingOutput,
        settings=request.app.state.settings,
    )
    await attach_previews(session, request.app.state.settings, result.items)
    return result


@router.get("/reservations/mine")
async def my_reservations(
    request: Request,
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
    return await paginate(
        session,
        query,
        page,
        ParticipationOutput,
        settings=request.app.state.settings,
    )


@router.get("/favorites")
async def my_favorites(
    request: Request, session: DbSession, principal: CurrentUser, page: PageQuery
) -> Page[FavoriteOutput]:
    """Recently bookmarked first; unavailable listings carry no content."""
    user = await user_for(session, principal)
    query = sort_by(
        select(Favorite).where(Favorite.user_id == user.id),
        "-created_at",
        {"created_at": Favorite.created_at},
        Favorite.listing_id,
    )
    rows = await paginate(
        session,
        query,
        page,
        FavoriteRow,
        settings=request.app.state.settings,
    )
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
    await attach_previews(
        session,
        request.app.state.settings,
        [item.listing for item in items if item.listing is not None],
    )
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
    request: Request,
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
    return await paginate(
        session,
        query,
        page,
        InteractionOutput,
        settings=request.app.state.settings,
    )


class PublicationInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    title: str
    description: str
    visibility: Visibility
    city_id: UUID | None = None
    faculty_id: UUID | None = None
    dormitory_id: UUID | None = None
    pinned_until: Instant


@router.post("/publications", status_code=201)
async def publish_publication(
    data: PublicationInput,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
    permissions: Permissions,
) -> ListingOutput:
    """Create an informational publication with no interactions or lifetime."""
    user = await user_for(session, principal)
    if data.visibility in (Visibility.CITY, Visibility.UNIVERSITY):
        permissions.require_role(Role.ADMINISTRATOR)
        if data.faculty_id is not None or data.dormitory_id is not None:
            raise ProblemError(INVALID_CONTENT)
        city_id = data.city_id or user.city_id
    else:
        permissions.require_scope(
            dormitory_id=data.dormitory_id, faculty_id=data.faculty_id
        )
        place: Dormitory | Faculty | None
        if data.visibility == Visibility.DORMITORY and data.dormitory_id:
            place = await session.get(Dormitory, data.dormitory_id)
        elif data.visibility == Visibility.FACULTY and data.faculty_id:
            place = await session.get(Faculty, data.faculty_id)
        else:
            place = None
        if place is None:
            raise ProblemError(FORBIDDEN)
        city_id = place.city_id
        if data.city_id is not None and data.city_id != city_id:
            raise ProblemError(INVALID_CONTENT)
    city = await session.get(City, city_id) if city_id else None
    if city is None or data.pinned_until <= clock.now():
        raise ProblemError(INVALID_CONTENT)
    check_text(data.title, data.description, request.app.state.settings)
    listing = Listing(
        author=user,
        city=city,
        author_id=user.id,
        city_id=city.id,
        author_dormitory_id=user.dormitory_id,
        kind="publication",
        title=data.title,
        description=data.description,
        visibility=data.visibility,
        audience=Audience.COMMUNITY,
        faculty_id=data.faculty_id,
        dormitory_id=data.dormitory_id,
        pinned_until=data.pinned_until,
        expires_at=None,
    )
    session.add(listing)
    await session.flush()
    session.add(Publication(listing_id=listing.id))
    record(session, listing, user.id, "published", None)
    return ListingOutput.model_validate(listing)


@router.post("/{listing_id}/unpin")
async def unpin_publication(
    listing_id: UUID,
    session: DbSession,
    principal: ProfiledUser,
    permissions: Permissions,
) -> ListingOutput:
    """Remove only the pin; the publication remains in the feed."""
    listing = await locked(session, listing_id)
    if listing.author_id != principal.user_id:
        permissions.require_role(Role.ADMINISTRATOR)
    if listing.kind != "publication":
        raise ProblemError(CONFLICT)
    require_live(listing)
    listing.pinned_until = None
    listing.version += 1
    record(session, listing, principal.user_id, "unpinned", listing.status)
    await session.flush()
    return ListingOutput.model_validate(listing)


@router.get("/{listing_id}")
async def get_listing(
    listing_id: UUID,
    request: Request,
    session: DbSession,
    principal: CurrentUser,
) -> ListingOutput:
    user = await user_for(session, principal)
    result = ListingOutput.model_validate(await readable(session, listing_id, user))
    await attach_previews(session, request.app.state.settings, [result])
    await mark_favorites(session, user.id, [result])
    return result


@router.patch("/{listing_id}", response_model=ListingOutput)
async def edit_listing(  # noqa: PLR0913, PLR0917 - request dependencies
    listing_id: UUID,
    data: ListingEdit,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
    permissions: Permissions,
) -> ListingOutput | ProblemResponse:
    listing = await locked(session, listing_id)
    if listing.author_id != principal.user_id and not (
        listing.kind == "publication"
        and any(role.role == Role.ADMINISTRATOR for role in permissions.roles)
    ):
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
    if "pinned_until" in data.model_fields_set:
        if listing.kind != "publication" or (
            data.pinned_until is not None and data.pinned_until <= clock.now()
        ):
            raise ProblemError(INVALID_CONTENT)
        listing.pinned_until = data.pinned_until
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
    permissions: Permissions,
) -> ListingOutput:
    """Closing rejects pending applications and preserves accepted interactions."""
    listing = await locked(session, listing_id)
    if listing.author_id != principal.user_id and not (
        listing.kind == "publication"
        and any(role.role == Role.ADMINISTRATOR for role in permissions.roles)
    ):
        raise ProblemError(FORBIDDEN)
    if listing.status != ListingStatus.DRAFT:
        require_live(listing)
    change_listing(
        session, listing, ListingStatus.CANCELLED, principal.user_id, "cancelled"
    )
    await reject_pending(session, listing, "listing_cancelled")
    await clear_waitlist(session, listing, "listing_cancelled")
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
    # The queue's first member holds the released place until the timer ends.
    if await active_offer(session, listing.id) is not None:
        raise ProblemError(OFFER_PENDING)
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
        meeting=None,
        options=[],
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


@router.post("/{listing_id}/exchange-offers", status_code=201)
async def offer_exchange(
    listing_id: UUID,
    data: ExchangeOfferInput,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
) -> InteractionOutput:
    """Offer an item for exchange; the author later chooses one offer."""
    listing = await locked(session, listing_id)
    user = await user_for(session, principal)
    check_participant(listing, user)
    if not visible(listing, user):
        raise ProblemError(NOT_FOUND)
    require_live(listing)
    if listing.kind != "exchange" or listing.status != ListingStatus.ACTIVE:
        raise ProblemError(CONFLICT)
    settings: Settings = request.app.state.settings
    description = data.description.strip()
    if not description or len(description) > settings.listing_description_max_length:
        raise ProblemError(INVALID_EXCHANGE_OFFER)
    duplicate = await session.scalar(
        select(Interaction.id).where(
            Interaction.listing_id == listing.id,
            Interaction.participant_id == user.id,
            Interaction.status.in_(
                (InteractionStatus.PENDING, InteractionStatus.ACCEPTED)
            ),
        )
    )
    if duplicate is not None:
        raise ProblemError(EXCHANGE_OFFER_DUPLICATE)
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
        slot=None,
        offer_description=description,
        response_due_at=None,
        meeting=None,
        options=[],
    )
    session.add(interaction)
    await session.flush()
    listing.version += 1
    record(
        session,
        listing,
        user.id,
        "requested",
        None,
        interaction,
        details={"offer": description},
    )
    await session.flush()
    return InteractionOutput.model_validate(interaction)


@router.get("/{listing_id}/exchange-offers")
async def exchange_offers(
    listing_id: UUID,
    session: DbSession,
    principal: CurrentUser,
) -> ExchangeOfferList:
    """Every offer for the author; only the caller's own offer otherwise."""
    listing = await session.get(Listing, listing_id)
    if listing is None or listing.kind != "exchange":
        raise ProblemError(NOT_FOUND)
    query = select(Interaction).where(
        Interaction.listing_id == listing.id,
        Interaction.offer_description.is_not(None),
    )
    if principal.user_id != listing.author_id:
        query = query.where(Interaction.participant_id == principal.user_id)
    rows = await session.scalars(query.order_by(Interaction.created_at, Interaction.id))
    return ExchangeOfferList(
        items=[InteractionOutput.model_validate(row) for row in rows]
    )


@router.post("/{listing_id}/lessons", status_code=201)
async def propose_lesson(
    listing_id: UUID,
    data: LessonInput,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
) -> InteractionOutput:
    """Propose a lesson with its time options; the author answers in 24 hours."""
    listing = await locked(session, listing_id)
    user = await user_for(session, principal)
    check_participant(listing, user)
    if not visible(listing, user):
        raise ProblemError(NOT_FOUND)
    require_live(listing)
    if listing.kind != "skill" or listing.status != ListingStatus.ACTIVE:
        raise ProblemError(CONFLICT)
    settings: Settings = request.app.state.settings
    slots = lesson_slots(data, settings)
    retry = await rate_limit(
        session,
        user.id,
        "requested",
        settings.listing_response_limit,
        settings.listing_response_window,
    )
    if retry is not None:
        raise ProblemError(RATE_LIMIT, headers={"Retry-After": str(retry)})
    interaction = new_lesson(listing, user.id, settings, user.id)
    add_lesson_slots(interaction, slots, user.id)
    session.add(interaction)
    await session.flush()
    listing.version += 1
    record(
        session,
        listing,
        user.id,
        "requested",
        None,
        interaction,
        details={"options": lesson_details(slots)},
    )
    await schedule_author_response(session, listing, interaction)
    await session.flush()
    return InteractionOutput.model_validate(interaction)


async def lesson_context(
    session: DbSession, listing_id: UUID, interaction_id: UUID
) -> tuple[Listing, Interaction]:
    listing = await locked(session, listing_id)
    interaction = await session.get(Interaction, interaction_id)
    if interaction is None or interaction.listing_id != listing.id:
        raise ProblemError(NOT_FOUND)
    return listing, interaction


@router.post(
    "/{listing_id}/interactions/{interaction_id}/lesson/accept",
)
async def accept_lesson(  # noqa: PLR0913, PLR0917 - request context
    listing_id: UUID,
    interaction_id: UUID,
    data: LessonAcceptInput,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
) -> InteractionOutput:
    """The author selects one responder option; the responder accepts a counter."""
    listing, interaction = await lesson_context(session, listing_id, interaction_id)
    option = await session.get(LessonOption, data.option_id)
    if option is None or option.interaction_id != interaction.id:
        raise ProblemError(NOT_FOUND)
    await accept_lesson_option(
        session,
        listing,
        interaction,
        option,
        principal.user_id,
        request.app.state.settings,
    )
    return InteractionOutput.model_validate(interaction)


@router.post(
    "/{listing_id}/interactions/{interaction_id}/lesson/counter-proposals",
)
async def counter_propose_lesson(  # noqa: PLR0913, PLR0917 - request context
    listing_id: UUID,
    interaction_id: UUID,
    data: LessonSlotInput,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
) -> InteractionOutput:
    """The author offers a time instead of selecting one of the options."""
    listing, interaction = await lesson_context(session, listing_id, interaction_id)
    await propose_lesson_counter(
        session,
        listing,
        interaction,
        principal.user_id,
        data.time,
        data.location,
        data.online,
        request.app.state.settings,
    )
    return InteractionOutput.model_validate(interaction)


@router.post(
    "/{listing_id}/interactions/{interaction_id}/repeat",
    status_code=201,
)
async def repeat_lesson(  # noqa: PLR0913, PLR0917 - request context
    listing_id: UUID,
    interaction_id: UUID,
    data: LessonInput,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
) -> InteractionOutput:
    """Create the next lesson with the same participant and listing."""
    listing, original = await lesson_context(session, listing_id, interaction_id)
    if principal.user_id not in (listing.author_id, original.participant_id):
        raise ProblemError(FORBIDDEN)
    if listing.kind != "skill":
        raise ProblemError(CONFLICT)
    if original.status not in (
        InteractionStatus.ACCEPTED,
        InteractionStatus.COMPLETED,
    ):
        raise ProblemError(CONFLICT)
    require_live(listing)
    settings: Settings = request.app.state.settings
    slots = lesson_slots(data, settings)
    retry = await rate_limit(
        session,
        principal.user_id,
        "requested",
        settings.listing_response_limit,
        settings.listing_response_window,
    )
    if retry is not None:
        raise ProblemError(RATE_LIMIT, headers={"Retry-After": str(retry)})
    interaction = new_lesson(
        listing,
        original.participant_id,
        settings,
        principal.user_id,
    )
    add_lesson_slots(interaction, slots, principal.user_id)
    session.add(interaction)
    await session.flush()
    listing.version += 1
    record(
        session,
        listing,
        principal.user_id,
        "requested",
        None,
        interaction,
        details={
            "source_interaction_id": str(original.id),
            "options": lesson_details(slots),
        },
    )
    await schedule_author_response(session, listing, interaction)
    await session.flush()
    return InteractionOutput.model_validate(interaction)


@router.post("/{listing_id}/responses", status_code=201)
async def respond_to_help(
    listing_id: UUID,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
) -> InteractionOutput:
    """Apply to a help request; several applications stay pending at once.

    The author later selects one of them. An application does not occupy
    the listing's single executor slot, so the listing stays active until
    the selection.
    """
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
    if listing.kind != "help" or listing.status != ListingStatus.ACTIVE:
        raise ProblemError(CONFLICT)
    already_applied = await session.scalar(
        select(Interaction.id).where(
            Interaction.listing_id == listing.id,
            Interaction.participant_id == user.id,
            Interaction.status.in_(
                (InteractionStatus.PENDING, InteractionStatus.ACCEPTED)
            ),
        )
    )
    if already_applied is not None:
        raise ProblemError(CONFLICT)
    settings: Settings = request.app.state.settings
    retry = await rate_limit(
        session,
        user.id,
        "responded",
        settings.listing_response_limit,
        settings.listing_response_window,
    )
    if retry is not None:
        raise ProblemError(RATE_LIMIT, headers={"Retry-After": str(retry)})
    interaction = Interaction(
        listing_id=listing.id,
        participant_id=user.id,
        participant=user,
        slot=None,
        response_due_at=None,
        meeting=None,
        options=[],
    )
    session.add(interaction)
    await session.flush()
    listing.version += 1
    record(session, listing, user.id, "responded", None, interaction)
    return InteractionOutput.model_validate(interaction)


@router.post("/{listing_id}/interactions/{interaction_id}/transition")
async def transition_interaction(  # noqa: PLR0913, PLR0917 - route fields
    listing_id: UUID,
    interaction_id: UUID,
    data: TransitionInput,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
) -> InteractionOutput:
    listing = await locked(session, listing_id)
    interaction = await session.get(Interaction, interaction_id)
    if interaction is None or interaction.listing_id != listing.id:
        raise ProblemError(NOT_FOUND)
    if principal.user_id not in (listing.author_id, interaction.participant_id):
        raise ProblemError(FORBIDDEN)
    await transition(
        session,
        listing,
        interaction,
        data.status,
        principal.user_id,
        settings=request.app.state.settings,
    )
    return InteractionOutput.model_validate(interaction)


def other_participant(
    listing: Listing, interaction: Interaction, actor_id: UUID
) -> UUID:
    """The participant who did not perform the meeting action."""
    if actor_id == listing.author_id:
        return interaction.participant_id
    return listing.author_id


async def meeting_context(
    session: DbSession, listing_id: UUID, interaction_id: UUID, actor_id: UUID
) -> tuple[Listing, Interaction]:
    """Lock the aggregate and check that ``actor_id`` may change its meeting."""
    listing = await locked(session, listing_id)
    interaction = await session.get(Interaction, interaction_id)
    if interaction is None or interaction.listing_id != listing.id:
        raise ProblemError(NOT_FOUND)
    if actor_id not in (listing.author_id, interaction.participant_id):
        raise ProblemError(FORBIDDEN)
    if interaction.status != InteractionStatus.ACCEPTED or listing.kind == "event":
        raise ProblemError(MEETING_STATE)
    return listing, interaction


@router.post("/{listing_id}/interactions/{interaction_id}/meeting/proposals")
async def propose_meeting(  # noqa: PLR0913, PLR0917 - request context
    listing_id: UUID,
    interaction_id: UUID,
    data: MeetingProposalInput,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
) -> MeetingOutput:
    """Propose a time and place; a counter-proposal replaces the pending one."""
    listing, interaction = await meeting_context(
        session, listing_id, interaction_id, principal.user_id
    )
    settings: Settings = request.app.state.settings
    location = validate_meeting(data.time, data.location, settings)
    meeting = interaction.meeting
    if meeting is None:
        meeting = Meeting(interaction_id=interaction.id, version=1)
        interaction.meeting = meeting
        session.add(meeting)
    else:
        meeting.version += 1
    meeting.proposed_at = data.time
    meeting.proposed_location = location
    meeting.proposed_by_id = principal.user_id
    time = data.time.isoformat()
    record_meeting(
        session,
        listing,
        interaction,
        principal.user_id,
        "meeting_proposed",
        {"time": time, "location": location},
    )
    await session.flush()
    notify(
        session,
        {other_participant(listing, interaction, principal.user_id)},
        "listing.meeting.proposed",
        {
            "listing_id": str(listing.id),
            "interaction_id": str(interaction.id),
            "time": time,
            "location": location,
            "version": meeting.version,
        },
        message=MEETING_PROPOSED,
    )
    return MeetingOutput.model_validate(meeting)


@router.post(
    "/{listing_id}/interactions/{interaction_id}/meeting/accept",
    response_model=MeetingOutput,
)
async def accept_meeting(  # noqa: PLR0913, PLR0917 - request context
    listing_id: UUID,
    interaction_id: UUID,
    data: MeetingAcceptInput,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
) -> MeetingOutput | ProblemResponse:
    """Accept the current proposal; a stale one is rejected with 409."""
    listing, interaction = await meeting_context(
        session, listing_id, interaction_id, principal.user_id
    )
    meeting = interaction.meeting
    if meeting is None:
        raise ProblemError(MEETING_STATE)
    if meeting.version != data.version:
        return problem_response(
            request,
            MEETING_STALE,
            params={"version": meeting.version},
            current_version=meeting.version,
        )
    proposed_at = meeting.proposed_at
    proposed_location = meeting.proposed_location
    proposed_by_id = meeting.proposed_by_id
    if proposed_at is None or proposed_location is None or proposed_by_id is None:
        raise ProblemError(MEETING_STATE)
    settings: Settings = request.app.state.settings
    location = validate_meeting(proposed_at, proposed_location, settings)
    previous_at = meeting.scheduled_at
    previous_location = meeting.location
    scheduled_at = proposed_at.isoformat()
    meeting.scheduled_at = proposed_at
    meeting.location = location
    meeting.scheduled_by_id = proposed_by_id
    meeting.proposed_at = None
    meeting.proposed_location = None
    meeting.proposed_by_id = None
    meeting.version += 1
    details: dict[str, Any] = {"time": scheduled_at, "location": location}
    if previous_at is None:
        action, notification_type, message = (
            "meeting_scheduled",
            "listing.meeting.scheduled",
            MEETING_SCHEDULED,
        )
    else:
        action, notification_type, message = (
            "meeting_rescheduled",
            "listing.meeting.rescheduled",
            MEETING_RESCHEDULED,
        )
        details["previous_time"] = previous_at.isoformat()
        details["previous_location"] = previous_location
    record_meeting(
        session,
        listing,
        interaction,
        principal.user_id,
        action,
        details,
    )
    await extend_reservation(session, listing, interaction, proposed_at)
    await schedule_meeting_reminders(session, settings, listing, interaction, meeting)
    await session.flush()
    notify(
        session,
        {other_participant(listing, interaction, principal.user_id)},
        notification_type,
        {
            "listing_id": str(listing.id),
            "interaction_id": str(interaction.id),
            **details,
            "version": meeting.version,
        },
        message=message,
    )
    return MeetingOutput.model_validate(meeting)


@router.get("/{listing_id}/events")
async def listing_events(
    listing_id: UUID,
    request: Request,
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
        own_entries = select(WaitlistEntry.id).where(
            WaitlistEntry.listing_id == listing.id,
            WaitlistEntry.participant_id == principal.user_id,
        )
        query = query.where(
            or_(
                and_(
                    ListingEvent.interaction_id.is_(None),
                    ListingEvent.waitlist_entry_id.is_(None),
                ),
                ListingEvent.interaction_id.in_(own_interactions),
                ListingEvent.waitlist_entry_id.in_(own_entries),
            )
        )
    query = sort_by(
        query, "created_at", {"created_at": ListingEvent.created_at}, ListingEvent.id
    )
    return await paginate(
        session,
        query,
        page,
        EventOutput,
        settings=request.app.state.settings,
    )


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
    if listing.kind in PERMANENT_KINDS:
        raise ProblemError(CONFLICT)
    if (
        listing.status not in (ListingStatus.DRAFT, ListingStatus.EXPIRED)
        or listing.purged_at is not None
    ):
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
    listing.author_dormitory_id = user.dormitory_id
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
    if listing.kind in PERMANENT_KINDS:
        raise ProblemError(CONFLICT)
    require_live(listing)
    listing.expires_at = clock.now() + request.app.state.settings.listing_lifetime
    listing.version += 1
    record(session, listing, principal.user_id, "extended", listing.status)
    await expiry_deadline(session, listing)
    await session.flush()
    return ListingOutput.model_validate(listing)


@router.get("/{listing_id}/interactions/{interaction_id}/events")
async def interaction_events(  # noqa: PLR0913, PLR0917 - request dependencies
    listing_id: UUID,
    interaction_id: UUID,
    request: Request,
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
    return await paginate(
        session,
        query,
        page,
        EventOutput,
        settings=request.app.state.settings,
    )


def check_participant(listing: Listing, user: User) -> None:
    """Reject the author and roles that cannot respond to this audience."""
    if user.id == listing.author_id:
        raise ProblemError(FORBIDDEN)
    if user.account_type not in (AccountType.STUDENT, AccountType.EMPLOYEE):
        raise ProblemError(FORBIDDEN)
    if (
        user.account_type == AccountType.EMPLOYEE
        and listing.audience == Audience.STUDENTS
    ):
        raise ProblemError(FORBIDDEN)


@router.post("/{listing_id}/waitlist", status_code=201)
async def join_listing_waitlist(
    listing_id: UUID,
    session: DbSession,
    principal: ProfiledUser,
) -> WaitlistEntryOutput:
    """Take the last place of the queue; only occupied listings have one."""
    listing = await locked(session, listing_id)
    user = await user_for(session, principal)
    check_participant(listing, user)
    if not visible(listing, user):
        raise ProblemError(NOT_FOUND)
    require_live(listing)
    if listing.status not in (ListingStatus.ACTIVE, ListingStatus.BUSY):
        raise ProblemError(CONFLICT)
    entry = await join_waitlist(session, listing, user)
    await session.flush()
    return await own_waitlist_output(session, entry)


@router.get("/{listing_id}/waitlist/me")
async def my_waitlist_entry(
    listing_id: UUID, session: DbSession, principal: CurrentUser
) -> WaitlistEntryOutput:
    entry = await active_waitlist(session, listing_id, principal.user_id)
    if entry is None:
        raise ProblemError(NOT_FOUND)
    return await own_waitlist_output(session, entry)


@router.get("/{listing_id}/waitlist")
async def listing_waitlist(
    listing_id: UUID, session: DbSession, principal: CurrentUser
) -> WaitlistQueue:
    """The active queue, visible to the author of the listing."""
    listing = await session.get(Listing, listing_id)
    if listing is None:
        raise ProblemError(NOT_FOUND)
    if listing.author_id != principal.user_id:
        raise ProblemError(FORBIDDEN)
    entries = list(
        await session.scalars(
            select(WaitlistEntry)
            .where(
                WaitlistEntry.listing_id == listing_id,
                WaitlistEntry.status.in_(
                    (WaitlistStatus.WAITING, WaitlistStatus.OFFERED)
                ),
            )
            .order_by(WaitlistEntry.created_at, WaitlistEntry.id)
        )
    )
    return WaitlistQueue(
        items=[
            waitlist_output(entry, position)
            for position, entry in enumerate(entries, start=1)
        ]
    )


@router.get("/waitlist/mine")
async def my_waitlist(
    request: Request, session: DbSession, principal: CurrentUser, page: PageQuery
) -> Page[WaitlistEntryOutput]:
    query = sort_by(
        select(WaitlistEntry).where(WaitlistEntry.participant_id == principal.user_id),
        "-created_at",
        {"created_at": WaitlistEntry.created_at},
        WaitlistEntry.id,
    )
    result = await paginate(
        session,
        query,
        page,
        WaitlistEntryOutput,
        settings=request.app.state.settings,
    )
    for item in result.items:
        entry = await session.get(WaitlistEntry, item.id)
        assert entry is not None  # noqa: S101 - just read from the page
        item.position = await waitlist_position(session, entry)
    return result


@router.delete("/{listing_id}/waitlist", status_code=204)
async def leave_listing_waitlist(
    listing_id: UUID,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
) -> Response:
    listing = await locked(session, listing_id)
    user = await user_for(session, principal)
    offer_timeout, open_all_before = offer_timing(request.app.state.settings)
    await leave_waitlist(
        session,
        listing,
        user,
        offer_timeout=offer_timeout,
        open_all_before=open_all_before,
    )
    await session.flush()
    return Response(status_code=204)


@router.post("/{listing_id}/waitlist/offer/accept", status_code=201)
async def accept_place_offer(
    listing_id: UUID,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
) -> InteractionOutput:
    """Confirming an offer creates the usual pending application."""
    listing = await locked(session, listing_id)
    user = await user_for(session, principal)
    check_participant(listing, user)
    interaction = await claim_offer(session, listing, user, request.app.state.settings)
    return InteractionOutput.model_validate(interaction)


@router.post("/{listing_id}/waitlist/offer/decline")
async def decline_place_offer(
    listing_id: UUID,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
) -> WaitlistEntryOutput:
    listing = await locked(session, listing_id)
    user = await user_for(session, principal)
    offer_timeout, open_all_before = offer_timing(request.app.state.settings)
    entry = await decline_offer(
        session,
        listing,
        user,
        offer_timeout=offer_timeout,
        open_all_before=open_all_before,
    )
    await session.flush()
    return waitlist_output(entry, None)
