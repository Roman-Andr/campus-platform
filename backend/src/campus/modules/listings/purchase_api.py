"""Group purchase publication, share collection and composition fixation."""

from decimal import Decimal
from uuid import UUID

from fastapi import Request, Response
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select

from campus.core.config import Settings
from campus.core.web import DbSession, ProblemError
from campus.core.web.datetimes import Instant
from campus.core.web.problems import NOT_FOUND, ProblemResponse, problem_response
from campus.modules.identity import ProfiledUser
from campus.modules.listings.api import (
    InteractionOutput,
    ListingOutput,
    check_category,
    check_participant,
    check_publish_access,
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
    PurchaseStage,
    Visibility,
)
from campus.modules.listings.service import (
    CONFLICT,
    FORBIDDEN,
    PURCHASE_CLOSED,
    PURCHASE_SHARE_EXISTS,
    STALE,
    cancel_purchase_withdrawal,
    change_purchase_units,
    decide_purchase_withdrawal,
    ensure_can_respond,
    join_purchase,
    leave_purchase,
    locked,
    offer_timing,
    record,
    request_purchase_withdrawal,
    require_live,
    schedule_purchase_deadlines,
    update_purchase_conditions,
    validate_purchase,
    visible,
)
from campus.modules.university import City

__all__ = ["router"]


class PurchaseInput(BaseModel):
    """Fields of a group purchase; the amount is always units x price."""

    model_config = ConfigDict(extra="forbid")
    title: str
    description: str
    visibility: Visibility = Visibility.CITY
    audience: Audience = Audience.STUDENTS
    category_id: UUID | None = None
    price_per_unit: Decimal = Field(gt=0, max_digits=12, decimal_places=2)
    min_units: int = Field(ge=1)
    max_units: int = Field(ge=1)
    collection_deadline: Instant


class PurchaseEdit(BaseModel):
    model_config = ConfigDict(extra="forbid")
    version: int = Field(ge=1)
    price_per_unit: Decimal | None = Field(
        default=None, gt=0, max_digits=12, decimal_places=2
    )
    min_units: int | None = Field(default=None, ge=1)
    max_units: int | None = Field(default=None, ge=1)
    collection_deadline: Instant | None = None


class ShareInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    units: int = Field(ge=1)


class WithdrawalInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    reason: str | None = Field(default=None, max_length=500)


class WithdrawalDecision(BaseModel):
    model_config = ConfigDict(extra="forbid")
    approve: bool
    reason: str | None = Field(default=None, max_length=500)


class PurchaseShareOutput(InteractionOutput):
    """A share with the amount derived from its units and the current price."""

    unit_price: Decimal
    amount: Decimal


class PurchaseComposition(BaseModel):
    """The fixed or collecting composition, visible to the organiser."""

    listing_id: UUID
    stage: PurchaseStage
    unit_price: Decimal
    min_units: int
    max_units: int
    taken_units: int
    fixed_units: int | None
    collection_deadline: Instant
    total_units: int
    total_amount: Decimal
    items: list[PurchaseShareOutput] = Field(default_factory=list)


def purchase_amount(listing: Listing, units: int) -> Decimal:
    price = listing.purchase_unit_price or Decimal(0)
    return (price * units).quantize(Decimal("0.01"))


def share_output(listing: Listing, interaction: Interaction) -> PurchaseShareOutput:
    base = InteractionOutput.model_validate(interaction)
    units = interaction.units or 0
    return PurchaseShareOutput(
        **base.model_dump(),
        unit_price=listing.purchase_unit_price or Decimal(0),
        amount=purchase_amount(listing, units),
    )


async def active_share(
    session: DbSession, listing: Listing, user_id: UUID
) -> Interaction:
    """The caller's accepted share of this purchase."""
    interaction = await session.scalar(
        select(Interaction).where(
            Interaction.listing_id == listing.id,
            Interaction.participant_id == user_id,
            Interaction.status == InteractionStatus.ACCEPTED,
        )
    )
    if interaction is None:
        raise ProblemError(NOT_FOUND)
    return interaction


async def purchase_listing(session: DbSession, listing_id: UUID) -> Listing:
    listing = await session.get(Listing, listing_id)
    if listing is None or listing.kind != "purchase":
        raise ProblemError(NOT_FOUND)
    return listing


async def shares_of(session: DbSession, listing: Listing) -> list[Interaction]:
    return list(
        await session.scalars(
            select(Interaction)
            .where(
                Interaction.listing_id == listing.id,
                Interaction.status == InteractionStatus.ACCEPTED,
            )
            .order_by(Interaction.created_at, Interaction.id)
        )
    )


@router.post("/purchases", status_code=201)
async def publish_purchase(
    data: PurchaseInput,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
) -> ListingOutput:
    """Publish a group purchase with its unit price and volume bounds."""
    user = await user_for(session, principal)
    settings: Settings = request.app.state.settings
    check_text(data.title, data.description, settings)
    visibility = data.visibility
    audience = data.audience
    check_publish_access(user, visibility, audience)
    await check_category(session, data.category_id)
    validate_purchase(
        data.price_per_unit,
        data.min_units,
        data.max_units,
        data.collection_deadline,
        settings,
    )
    await publication_quota(session, user.id, settings)
    assert user.city_id is not None  # noqa: S101 - ProfiledUser
    listing = Listing(
        author=user,
        author_id=user.id,
        author_dormitory_id=user.dormitory_id,
        kind="purchase",
        title=data.title,
        description=data.description,
        visibility=visibility,
        audience=audience,
        city_id=user.city_id,
        city=await session.get(City, user.city_id),
        faculty_id=user.faculty_id if visibility == Visibility.FACULTY else None,
        dormitory_id=user.dormitory_id if visibility == Visibility.DORMITORY else None,
        status=ListingStatus.ACTIVE,
        category_id=data.category_id,
        expires_at=data.collection_deadline + settings.listing_lifetime,
        purchase_unit_price=data.price_per_unit,
        purchase_min_units=data.min_units,
        purchase_max_units=data.max_units,
        purchase_collection_deadline=data.collection_deadline,
        purchase_stage=PurchaseStage.COLLECTING,
    )
    session.add(listing)
    await session.flush()
    record(session, listing, user.id, "published", None)
    await schedule_purchase_deadlines(session, listing, settings)
    await expiry_deadline(session, listing)
    return ListingOutput.model_validate(listing)


@router.patch("/{listing_id}/purchase", response_model=ListingOutput)
async def edit_purchase(
    listing_id: UUID,
    data: PurchaseEdit,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
) -> ListingOutput | ProblemResponse:
    """Change price, bounds or deadline while collecting."""
    listing = await locked(session, listing_id)
    if listing.kind != "purchase":
        raise ProblemError(NOT_FOUND)
    if listing.author_id != principal.user_id:
        raise ProblemError(FORBIDDEN)
    if listing.version != data.version:
        return problem_response(
            request,
            STALE,
            params={"version": listing.version},
            current_version=listing.version,
        )
    if listing.purchase_stage != PurchaseStage.COLLECTING:
        raise ProblemError(PURCHASE_CLOSED)
    price = (
        data.price_per_unit
        if data.price_per_unit is not None
        else listing.purchase_unit_price
    )
    min_units = (
        data.min_units if data.min_units is not None else listing.purchase_min_units
    )
    max_units = (
        data.max_units if data.max_units is not None else listing.purchase_max_units
    )
    deadline = (
        data.collection_deadline
        if data.collection_deadline is not None
        else listing.purchase_collection_deadline
    )
    assert price is not None  # noqa: S101 - a purchase row has all fields
    assert min_units is not None  # noqa: S101 - a purchase row has all fields
    assert max_units is not None  # noqa: S101 - a purchase row has all fields
    assert deadline is not None  # noqa: S101 - a purchase row has all fields
    await update_purchase_conditions(
        session,
        listing,
        price=price,
        min_units=min_units,
        max_units=max_units,
        deadline=deadline,
        settings=request.app.state.settings,
    )
    await session.flush()
    return ListingOutput.model_validate(listing)


@router.post("/{listing_id}/shares", status_code=201)
async def join_listing_purchase(
    listing_id: UUID,
    data: ShareInput,
    session: DbSession,
    principal: ProfiledUser,
) -> PurchaseShareOutput:
    """Take a share of units; a purchase share is accepted immediately."""
    listing = await locked(session, listing_id)
    user = await user_for(session, principal)
    if listing.kind != "purchase":
        raise ProblemError(CONFLICT)
    check_participant(listing, user)
    await ensure_can_respond(session, user.id, listing.author_id)
    if not visible(listing, user):
        raise ProblemError(NOT_FOUND)
    require_live(listing)
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
        raise ProblemError(PURCHASE_SHARE_EXISTS)
    interaction = await join_purchase(session, listing, user, data.units)
    await session.flush()
    return share_output(listing, interaction)


@router.get("/{listing_id}/shares/me")
async def my_purchase_share(
    listing_id: UUID, session: DbSession, principal: ProfiledUser
) -> PurchaseShareOutput:
    listing = await purchase_listing(session, listing_id)
    interaction = await active_share(session, listing, principal.user_id)
    return share_output(listing, interaction)


@router.patch("/{listing_id}/shares/me")
async def change_my_purchase_share(
    listing_id: UUID,
    data: ShareInput,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
) -> PurchaseShareOutput:
    """Change the number of units while the purchase is collecting."""
    listing = await locked(session, listing_id)
    if listing.kind != "purchase":
        raise ProblemError(NOT_FOUND)
    interaction = await active_share(session, listing, principal.user_id)
    offer_timeout, open_all_before = offer_timing(request.app.state.settings)
    await change_purchase_units(
        session,
        listing,
        interaction,
        data.units,
        offer_timeout=offer_timeout,
        open_all_before=open_all_before,
    )
    await session.flush()
    return share_output(listing, interaction)


@router.delete("/{listing_id}/shares/me", status_code=204)
async def leave_my_purchase_share(
    listing_id: UUID,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
) -> Response:
    """Leave while collecting; a fixed purchase needs the organiser's consent."""
    listing = await locked(session, listing_id)
    if listing.kind != "purchase":
        raise ProblemError(NOT_FOUND)
    interaction = await active_share(session, listing, principal.user_id)
    offer_timeout, open_all_before = offer_timing(request.app.state.settings)
    await leave_purchase(
        session,
        listing,
        interaction,
        offer_timeout=offer_timeout,
        open_all_before=open_all_before,
    )
    await session.flush()
    return Response(status_code=204)


@router.post("/{listing_id}/shares/me/withdrawal", status_code=201)
async def request_my_purchase_withdrawal(
    listing_id: UUID,
    data: WithdrawalInput,
    session: DbSession,
    principal: ProfiledUser,
) -> PurchaseShareOutput:
    """Ask the organiser to leave a purchase whose composition is fixed."""
    listing = await locked(session, listing_id)
    if listing.kind != "purchase":
        raise ProblemError(NOT_FOUND)
    interaction = await active_share(session, listing, principal.user_id)
    await request_purchase_withdrawal(session, listing, interaction, data.reason)
    await session.flush()
    return share_output(listing, interaction)


@router.delete("/{listing_id}/shares/me/withdrawal", status_code=204)
async def cancel_my_purchase_withdrawal(
    listing_id: UUID, session: DbSession, principal: ProfiledUser
) -> Response:
    listing = await locked(session, listing_id)
    if listing.kind != "purchase":
        raise ProblemError(NOT_FOUND)
    interaction = await active_share(session, listing, principal.user_id)
    await cancel_purchase_withdrawal(session, interaction)
    await session.flush()
    return Response(status_code=204)


@router.post("/{listing_id}/shares/{interaction_id}/withdrawal/decision")
async def decide_my_purchase_withdrawal(  # noqa: PLR0913, PLR0917 - route fields
    listing_id: UUID,
    interaction_id: UUID,
    data: WithdrawalDecision,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
) -> PurchaseShareOutput:
    """The organiser approves or rejects a participant's withdrawal request."""
    listing = await locked(session, listing_id)
    if listing.kind != "purchase":
        raise ProblemError(NOT_FOUND)
    interaction = await session.get(Interaction, interaction_id)
    if interaction is None or interaction.listing_id != listing.id:
        raise ProblemError(NOT_FOUND)
    offer_timeout, open_all_before = offer_timing(request.app.state.settings)
    await decide_purchase_withdrawal(
        session,
        listing,
        interaction,
        principal.user_id,
        approve=data.approve,
        reason=data.reason,
        offer_timeout=offer_timeout,
        open_all_before=open_all_before,
        settings=request.app.state.settings,
    )
    await session.flush()
    return share_output(listing, interaction)


@router.get("/{listing_id}/shares")
async def purchase_composition(
    listing_id: UUID, session: DbSession, principal: ProfiledUser
) -> PurchaseComposition:
    """The whole composition is visible to the organiser only."""
    listing = await purchase_listing(session, listing_id)
    if listing.author_id != principal.user_id:
        raise ProblemError(FORBIDDEN)
    shares = await shares_of(session, listing)
    price = listing.purchase_unit_price or Decimal(0)
    total_units = sum(share.units or 0 for share in shares)
    assert listing.purchase_stage is not None  # noqa: S101 - purchase row
    assert listing.purchase_min_units is not None  # noqa: S101 - purchase row
    assert listing.purchase_max_units is not None  # noqa: S101 - purchase row
    assert listing.purchase_collection_deadline is not None  # noqa: S101 - row
    return PurchaseComposition(
        listing_id=listing.id,
        stage=PurchaseStage(listing.purchase_stage),
        unit_price=price,
        min_units=listing.purchase_min_units,
        max_units=listing.purchase_max_units,
        taken_units=listing.purchase_taken_units,
        fixed_units=listing.purchase_fixed_units,
        collection_deadline=listing.purchase_collection_deadline,
        total_units=total_units,
        total_amount=purchase_amount(listing, total_units),
        items=[share_output(listing, share) for share in shares],
    )
