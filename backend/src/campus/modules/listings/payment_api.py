"""Payment marks of a fixed group purchase share (#54, #94)."""

from decimal import Decimal
from uuid import UUID

from fastapi import Request
from pydantic import BaseModel, ConfigDict, Field

from campus.core import clock
from campus.core.web import DbSession, Instant, ProblemError
from campus.core.web.problems import NOT_FOUND, ProblemResponse, problem_response
from campus.modules.identity import ProfiledUser
from campus.modules.listings.api import router
from campus.modules.listings.models import (
    Interaction,
    Listing,
    PaymentClaim,
    PaymentClaimStatus,
)
from campus.modules.listings.payments import (
    PAYMENT_FORBIDDEN,
    PAYMENT_STALE,
    PaymentState,
    PaymentVersionConflictError,
    claim_payment,
    payment_state,
    respond_payment,
)
from campus.modules.listings.purchase_api import (
    active_share,
    purchase_amount,
    purchase_listing,
)
from campus.modules.listings.service import locked

__all__ = ["router"]


class PaymentClaimOutput(BaseModel):
    """One payment mark of a share."""

    model_config = ConfigDict(from_attributes=True, frozen=True)

    id: UUID
    status: PaymentClaimStatus
    claimed_at: Instant
    responded_at: Instant | None
    responded_by_id: UUID | None
    version: int


class PaymentStateOutput(BaseModel):
    """The payment mark of a share and the actions its viewer may take."""

    listing_id: UUID
    interaction_id: UUID
    units: int = Field(ge=0)
    unit_price: Decimal
    amount: Decimal
    status: PaymentClaimStatus | None = Field(
        description="The newest mark; null when the participant has not marked one."
    )
    claim: PaymentClaimOutput | None
    can_claim: bool
    can_respond: bool
    can_dispute: bool
    dispute_available_at: Instant | None = Field(
        description="When an unanswered mark becomes disputable; null if it cannot."
    )
    dispute_closes_at: Instant | None
    server_time: Instant


class PaymentDecisionInput(BaseModel):
    """The organiser's answer to the active payment mark."""

    model_config = ConfigDict(extra="forbid")

    approve: bool
    version: int = Field(ge=1)


def claim_output(claim: PaymentClaim | None) -> PaymentClaimOutput | None:
    if claim is None:
        return None
    return PaymentClaimOutput.model_validate(claim)


def payment_output(listing: Listing, state: PaymentState) -> PaymentStateOutput:
    claim = state.claim
    return PaymentStateOutput(
        listing_id=state.listing_id,
        interaction_id=state.interaction_id,
        units=state.units,
        unit_price=listing.purchase_unit_price or Decimal(0),
        amount=purchase_amount(listing, state.units),
        status=None if claim is None else PaymentClaimStatus(claim.status),
        claim=claim_output(claim),
        can_claim=state.can_claim,
        can_respond=state.can_respond,
        can_dispute=state.can_dispute,
        dispute_available_at=state.dispute_available_at,
        dispute_closes_at=state.dispute_closes_at,
        server_time=clock.now(),
    )


async def payment_listing(session: DbSession, listing_id: UUID) -> Listing:
    return await purchase_listing(session, listing_id)


async def share_of(
    session: DbSession,
    listing: Listing,
    interaction_id: UUID,
    actor_id: UUID,
) -> Interaction:
    interaction = await session.get(Interaction, interaction_id)
    if interaction is None or interaction.listing_id != listing.id:
        raise ProblemError(NOT_FOUND)
    if actor_id not in (listing.author_id, interaction.participant_id):
        raise ProblemError(PAYMENT_FORBIDDEN)
    return interaction


@router.get("/{listing_id}/shares/me/payment")
async def my_payment_state(
    listing_id: UUID,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
) -> PaymentStateOutput:
    """The participant's payment mark of their own share."""
    listing = await payment_listing(session, listing_id)
    interaction = await active_share(session, listing, principal.user_id)
    state = await payment_state(
        session,
        listing,
        interaction,
        principal.user_id,
        request.app.state.settings,
    )
    return payment_output(listing, state)


@router.post("/{listing_id}/shares/me/payment/claims", status_code=201)
async def claim_my_payment(
    listing_id: UUID,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
) -> PaymentStateOutput:
    """Mark the share paid; the organiser confirms or rejects it.

    The mark is accepted only while the composition is fixed and the share
    is still accepted. A repeated call without an answer changes nothing.
    """
    listing = await locked(session, listing_id)
    if listing.kind != "purchase":
        raise ProblemError(NOT_FOUND)
    interaction = await active_share(session, listing, principal.user_id)
    state = await claim_payment(
        session,
        listing,
        interaction,
        principal.user_id,
        request.app.state.settings,
    )
    await session.flush()
    return payment_output(listing, state)


@router.get("/{listing_id}/shares/{interaction_id}/payment")
async def share_payment_state(
    listing_id: UUID,
    interaction_id: UUID,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
) -> PaymentStateOutput:
    """The organiser reads the payment mark of one share."""
    listing = await payment_listing(session, listing_id)
    if listing.author_id != principal.user_id:
        raise ProblemError(PAYMENT_FORBIDDEN)
    interaction = await share_of(session, listing, interaction_id, principal.user_id)
    state = await payment_state(
        session,
        listing,
        interaction,
        principal.user_id,
        request.app.state.settings,
    )
    return payment_output(listing, state)


@router.post(
    "/{listing_id}/shares/{interaction_id}/payment/decision",
    response_model=PaymentStateOutput,
)
async def decide_share_payment(  # noqa: PLR0913, PLR0917 - request fields
    listing_id: UUID,
    interaction_id: UUID,
    data: PaymentDecisionInput,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
) -> PaymentStateOutput | ProblemResponse:
    """The organiser confirms or rejects the active payment mark."""
    listing = await locked(session, listing_id)
    if listing.kind != "purchase":
        raise ProblemError(NOT_FOUND)
    interaction = await share_of(session, listing, interaction_id, principal.user_id)
    try:
        state = await respond_payment(
            session,
            listing,
            interaction,
            principal.user_id,
            request.app.state.settings,
            approve=data.approve,
            version=data.version,
        )
    except PaymentVersionConflictError as error:
        return problem_response(
            request,
            PAYMENT_STALE,
            params={"version": error.current_version},
            current_version=error.current_version,
        )
    await session.flush()
    return payment_output(listing, state)
