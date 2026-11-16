"""Two-sided payment marks of a fixed group purchase share (#54, #94).

The service only records that a participant says the share was paid and
that the organiser confirmed or rejected it: no money moves and no receipt
is kept. A claim without an answer for the configured wait becomes
disputable; while the moderator decides, the claim is suspended, so a
parallel cancellation or rejection cannot erase the obligation. A rejected
claim may be repeated; a confirmed one stays as evidence of the payment.
"""

from dataclasses import dataclass
from datetime import datetime
from uuid import UUID, uuid5

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from campus.core import clock
from campus.core.config import Settings
from campus.core.i18n import N_
from campus.core.web import ProblemError, ProblemType
from campus.modules.listings.models import (
    Interaction,
    InteractionStatus,
    Listing,
    ListingStatus,
    PaymentClaim,
    PaymentClaimStatus,
    PurchaseStage,
)
from campus.modules.listings.service import append_event
from campus.modules.notifications import (
    PAYMENT_CLAIMED,
    PAYMENT_CONFIRMED,
    PAYMENT_REJECTED,
    notify,
)

PAYMENT_FORBIDDEN = ProblemType(
    "purchase_payment_forbidden",
    403,
    N_("Forbidden"),
    N_("Only the participant marks their share paid; only the organiser answers it."),
)
PAYMENT_UNAVAILABLE = ProblemType(
    "purchase_payment_unavailable",
    409,
    N_("A payment cannot be marked here"),
    N_(
        "A payment is marked for a fixed purchase share with a positive number"
        " of units."
    ),
)
PAYMENT_ALREADY_CONFIRMED = ProblemType(
    "purchase_payment_confirmed",
    409,
    N_("The payment is already confirmed"),
    N_("The organiser has already confirmed this share as paid."),
)
PAYMENT_DISPUTED = ProblemType(
    "purchase_payment_disputed",
    409,
    N_("The payment is under dispute"),
    N_("The moderator decides the payment dispute before either side answers."),
)
PAYMENT_CANCELLED = ProblemType(
    "purchase_payment_cancelled",
    409,
    N_("The purchase is cancelled"),
    N_("A cancelled purchase keeps the payment mark for the moderator's decision."),
)
PAYMENT_STALE = ProblemType(
    "purchase_payment_version_conflict",
    409,
    N_("The payment mark was changed"),
    N_("Reload the payment mark. Its current version is {version}."),
)


class PaymentVersionConflictError(ProblemError):
    """The organiser answered a stale payment mark."""

    def __init__(self, current_version: int) -> None:
        super().__init__(PAYMENT_STALE, params={"version": current_version})
        self.current_version = current_version


@dataclass(frozen=True, slots=True)
class PaymentState:
    """One share's payment mark and the actions its viewer may take."""

    listing_id: UUID
    interaction_id: UUID
    units: int
    claim: PaymentClaim | None
    can_claim: bool
    can_respond: bool
    can_dispute: bool
    dispute_available_at: datetime | None
    dispute_closes_at: datetime | None


async def latest_claim(
    session: AsyncSession,
    interaction_id: UUID,
    *,
    for_update: bool = False,
) -> PaymentClaim | None:
    """The newest mark of one share, as the row the organiser answers."""
    query = (
        select(PaymentClaim)
        .where(PaymentClaim.interaction_id == interaction_id)
        .order_by(PaymentClaim.claimed_at.desc(), PaymentClaim.id.desc())
        .limit(1)
    )
    if for_update:
        query = query.with_for_update()
    return await session.scalar(query)


def _can_dispute(
    claim: PaymentClaim | None,
    viewer_id: UUID,
    author_id: UUID,
    settings: Settings,
    now: datetime,
) -> bool:
    if claim is None or claim.status != PaymentClaimStatus.CLAIMED.value:
        return False
    if viewer_id == author_id or claim.participant_id != viewer_id:
        return False
    return (
        claim.claimed_at + settings.payment_dispute_after
        <= now
        <= claim.claimed_at + settings.payment_dispute_window
    )


async def payment_state(
    session: AsyncSession,
    listing: Listing,
    interaction: Interaction,
    viewer_id: UUID,
    settings: Settings,
) -> PaymentState:
    """Read a share's payment mark; both sides and the panel share it."""
    claim = await latest_claim(session, interaction.id)
    now = clock.now()
    participant = viewer_id == interaction.participant_id
    organizer = viewer_id == listing.author_id
    available_at = (
        None
        if claim is None or not participant
        else claim.claimed_at + settings.payment_dispute_after
    )
    closes_at = (
        None
        if claim is None or not participant
        else claim.claimed_at + settings.payment_dispute_window
    )
    return PaymentState(
        listing_id=listing.id,
        interaction_id=interaction.id,
        units=interaction.units or 0,
        claim=claim,
        can_claim=(
            participant
            and interaction.status == InteractionStatus.ACCEPTED
            and listing.kind == "purchase"
            and listing.purchase_stage == PurchaseStage.FIXED.value
            and listing.status != ListingStatus.CANCELLED
            and (claim is None or claim.status == PaymentClaimStatus.REJECTED.value)
        ),
        can_respond=(
            organizer
            and claim is not None
            and claim.status == PaymentClaimStatus.CLAIMED.value
            and listing.status != ListingStatus.CANCELLED
        ),
        can_dispute=_can_dispute(claim, viewer_id, listing.author_id, settings, now),
        dispute_available_at=available_at,
        dispute_closes_at=closes_at,
    )


def _validate_claimable(
    listing: Listing, interaction: Interaction, actor_id: UUID
) -> None:
    if (
        listing.kind != "purchase"
        or listing.purchase_stage != PurchaseStage.FIXED.value
        or listing.status == ListingStatus.CANCELLED
        or interaction.status != InteractionStatus.ACCEPTED
        or (interaction.units or 0) < 1
    ):
        raise ProblemError(PAYMENT_UNAVAILABLE)
    if actor_id != interaction.participant_id:
        raise ProblemError(PAYMENT_FORBIDDEN)


async def claim_payment(
    session: AsyncSession,
    listing: Listing,
    interaction: Interaction,
    actor_id: UUID,
    settings: Settings,
) -> PaymentState:
    """The participant marks their share paid; a repeat changes nothing.

    The caller holds the listing lock, so a parallel claim leaves one row.
    """
    _validate_claimable(listing, interaction, actor_id)
    now = clock.now()
    claim = await latest_claim(session, interaction.id)
    if claim is not None:
        if claim.status == PaymentClaimStatus.CONFIRMED.value:
            raise ProblemError(PAYMENT_ALREADY_CONFIRMED)
        if claim.status == PaymentClaimStatus.DISPUTED.value:
            raise ProblemError(PAYMENT_DISPUTED)
        if claim.status == PaymentClaimStatus.CLAIMED.value:
            # A retry without an Idempotency-Key changes nothing.
            return await payment_state(
                session, listing, interaction, actor_id, settings
            )
    claim = PaymentClaim(
        listing_id=listing.id,
        interaction_id=interaction.id,
        participant_id=actor_id,
        status=PaymentClaimStatus.CLAIMED.value,
        claimed_at=now,
        responded_at=None,
        responded_by_id=None,
        version=1,
        created_at=now,
        updated_at=now,
    )
    session.add(claim)
    await session.flush()
    listing.version += 1
    append_event(
        session,
        listing,
        actor_id,
        "payment_claimed",
        interaction.status,
        interaction,
        details={
            "claim_id": str(claim.id),
            "units": interaction.units or 0,
            "rule": "two_sided",
        },
    )
    notify(
        session,
        {listing.author_id},
        "listing.purchase.payment",
        {
            "listing_id": str(listing.id),
            "interaction_id": str(interaction.id),
            "claim_id": str(claim.id),
            "status": PaymentClaimStatus.CLAIMED.value,
        },
        message=PAYMENT_CLAIMED,
        event_id=uuid5(claim.id, "claimed"),
    )
    await session.flush()
    return await payment_state(session, listing, interaction, actor_id, settings)


async def respond_payment(  # noqa: PLR0913 - the parts of an answer
    session: AsyncSession,
    listing: Listing,
    interaction: Interaction,
    actor_id: UUID,
    settings: Settings,
    *,
    approve: bool,
    version: int,
) -> PaymentState:
    """The organiser confirms or rejects the active mark; the panel decides disputes."""
    if actor_id != listing.author_id:
        raise ProblemError(PAYMENT_FORBIDDEN)
    claim = await latest_claim(session, interaction.id, for_update=True)
    if claim is None or claim.status == PaymentClaimStatus.REJECTED.value:
        raise ProblemError(PAYMENT_UNAVAILABLE)
    if claim.status == PaymentClaimStatus.DISPUTED.value:
        raise ProblemError(PAYMENT_DISPUTED)
    if claim.status == PaymentClaimStatus.CONFIRMED.value:
        raise ProblemError(PAYMENT_ALREADY_CONFIRMED)
    if listing.status == ListingStatus.CANCELLED:
        raise ProblemError(PAYMENT_CANCELLED)
    if claim.version != version:
        raise PaymentVersionConflictError(claim.version)
    now = clock.now()
    claim.status = (
        PaymentClaimStatus.CONFIRMED.value
        if approve
        else PaymentClaimStatus.REJECTED.value
    )
    claim.responded_at = now
    claim.responded_by_id = actor_id
    claim.version += 1
    claim.updated_at = now
    listing.version += 1
    append_event(
        session,
        listing,
        actor_id,
        "payment_confirmed" if approve else "payment_rejected",
        interaction.status,
        interaction,
        details={"claim_id": str(claim.id), "version": claim.version},
    )
    notify(
        session,
        {interaction.participant_id},
        "listing.purchase.payment",
        {
            "listing_id": str(listing.id),
            "interaction_id": str(interaction.id),
            "claim_id": str(claim.id),
            "status": claim.status,
        },
        message=PAYMENT_CONFIRMED if approve else PAYMENT_REJECTED,
        event_id=uuid5(claim.id, f"answered-{claim.version}"),
    )
    await session.flush()
    return await payment_state(session, listing, interaction, actor_id, settings)


async def suspend_payment_claim(
    session: AsyncSession, claim: PaymentClaim, now: datetime
) -> None:
    """Freeze an unanswered mark for the moderator decision (#94)."""
    if claim.status != PaymentClaimStatus.CLAIMED.value:
        if claim.status == PaymentClaimStatus.DISPUTED.value:
            return
        raise ProblemError(PAYMENT_UNAVAILABLE)
    claim.status = PaymentClaimStatus.DISPUTED.value
    claim.version += 1
    claim.updated_at = now
    await session.flush()


async def resolve_payment_claim(
    session: AsyncSession,
    claim: PaymentClaim,
    actor_id: UUID,
    *,
    approve: bool,
    now: datetime,
) -> None:
    """Apply the moderator's answer to a suspended payment mark."""
    if claim.status != PaymentClaimStatus.DISPUTED.value:
        raise ProblemError(PAYMENT_UNAVAILABLE)
    claim.status = (
        PaymentClaimStatus.CONFIRMED.value
        if approve
        else PaymentClaimStatus.REJECTED.value
    )
    claim.responded_at = now
    claim.responded_by_id = actor_id
    claim.version += 1
    claim.updated_at = now
    await session.flush()


__all__ = [
    "PAYMENT_ALREADY_CONFIRMED",
    "PAYMENT_CANCELLED",
    "PAYMENT_DISPUTED",
    "PAYMENT_FORBIDDEN",
    "PAYMENT_STALE",
    "PAYMENT_UNAVAILABLE",
    "PaymentState",
    "PaymentVersionConflictError",
    "claim_payment",
    "latest_claim",
    "payment_state",
    "resolve_payment_claim",
    "respond_payment",
    "suspend_payment_claim",
]
