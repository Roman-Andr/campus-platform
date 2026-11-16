"""Complaint reason catalogue and dispute cases.

Reasons are never hard-deleted: complaints reference them and keep their own
immutable snapshot of the basis (#91), while the catalogue row keeps the
published rules version and clause it was bound to. A deactivated reason is
hidden from the complaint form but stays readable for the panel and history.

A dispute is one case about one interaction or one event. #66 opens the case
of mutual no-show allegations; the moderator decision and the other dispute
grounds belong to #94.
"""

from datetime import datetime
from enum import StrEnum
from uuid import UUID

from sqlalchemy import (
    CheckConstraint,
    ForeignKey,
    Index,
    String,
    Text,
    UniqueConstraint,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from campus.core import clock
from campus.core.db import Entity, LocalizedName
from campus.modules.identity import DocumentVersion
from campus.modules.listings import Interaction, Listing

CODE_MAX_LENGTH = 64
CLAUSE_MAX_LENGTH = 200
CODE_PATTERN = r"^[a-z][a-z0-9_]*$"


class ComplaintReason(LocalizedName, Entity):
    """A selectable complaint reason and the rules clause it stands for."""

    __tablename__ = "moderation_complaint_reason"
    __table_args__ = (
        UniqueConstraint("code"),
        CheckConstraint(f"code ~ '{CODE_PATTERN}'", name="code_format"),
        CheckConstraint(
            "length(name_ru) > 0 AND length(name_en) > 0", name="names_nonempty"
        ),
        CheckConstraint(
            f"char_length(rules_clause) BETWEEN 1 AND {CLAUSE_MAX_LENGTH}",
            name="clause_length",
        ),
        CheckConstraint("version > 0", name="version_positive"),
    )

    code: Mapped[str] = mapped_column(String(CODE_MAX_LENGTH))
    rules_document_id: Mapped[UUID] = mapped_column(
        ForeignKey("identity_document_version.id", ondelete="RESTRICT"), index=True
    )
    rules_clause: Mapped[str] = mapped_column(String(CLAUSE_MAX_LENGTH))
    active: Mapped[bool] = mapped_column(default=True)
    # Optimistic concurrency of the panel; a stale edit is rejected.
    version: Mapped[int] = mapped_column(default=1)

    rules_document: Mapped[DocumentVersion] = relationship(lazy="raise")

    @property
    def rules_version(self) -> int:
        """Version number of the rules document the reason is bound to."""
        return self.rules_document.version


class DisputeKind(StrEnum):
    """The disputed subject of a case.

    ``not_returned`` is the borrower disputing the owner's "not returned"
    mark of a loan; ``payment`` is an unconfirmed payment mark of a group
    purchase share (#54, #94).
    """

    NO_SHOW = "no_show"
    NOT_RETURNED = "not_returned"
    PAYMENT = "payment"


class DisputeStatus(StrEnum):
    """Open cases wait for a moderator decision (#94)."""

    OPEN = "open"
    RESOLVED = "resolved"


class DisputeAction(StrEnum):
    """The outcome of a moderator decision.

    ``keep`` leaves the disputed facts in force; ``lift_no_show`` removes
    the no-show marks while the interaction stays "did not take place";
    ``complete`` closes the interaction as completed; the payment actions
    answer the suspended payment mark. ``late_qr`` and ``legacy`` are
    system resolutions: a QR code formed before the mark, and a case
    created before #94 existed.
    """

    KEEP = "keep"
    LIFT_NO_SHOW = "lift_no_show"
    COMPLETE = "complete"
    CONFIRM_PAYMENT = "confirm_payment"
    REJECT_PAYMENT = "reject_payment"
    LATE_QR = "late_qr"
    LEGACY = "legacy"


DISPUTE_ACTIONS_BY_KIND: dict[str, frozenset[DisputeAction]] = {
    DisputeKind.NO_SHOW.value: frozenset(
        {DisputeAction.KEEP, DisputeAction.LIFT_NO_SHOW, DisputeAction.COMPLETE}
    ),
    DisputeKind.NOT_RETURNED.value: frozenset(
        {DisputeAction.KEEP, DisputeAction.LIFT_NO_SHOW, DisputeAction.COMPLETE}
    ),
    DisputeKind.PAYMENT.value: frozenset(
        {DisputeAction.CONFIRM_PAYMENT, DisputeAction.REJECT_PAYMENT}
    ),
}


class Dispute(Entity):
    """One case about one interaction or one event.

    #66 opens the case automatically when both participants accuse each
    other of a no-show; the other participants open a case about a mark
    against them, and a purchase participant opens one about an unanswered
    payment mark (#94). The unique interaction keeps a pair of mutual
    allegations from opening two cases. A case about an event vote has no
    interaction. ``event_at`` is the moment of the disputed event the
    seven-day opening window is counted from, not the start of the
    interaction. ``version`` is the optimistic lock of the single decision:
    two moderators cannot overwrite each other.
    """

    __tablename__ = "moderation_dispute"
    __table_args__ = (
        CheckConstraint("kind IN ('no_show','not_returned','payment')", name="kind"),
        CheckConstraint("status IN ('open','resolved')", name="status"),
        CheckConstraint(
            "action IS NULL OR action IN ("
            "'keep','lift_no_show','complete','confirm_payment',"
            "'reject_payment','late_qr','legacy')",
            name="action",
        ),
        CheckConstraint("version > 0", name="version_positive"),
        CheckConstraint(
            "(status = 'resolved') = (resolved_at IS NOT NULL)", name="resolution_time"
        ),
        CheckConstraint(
            "(resolved_at IS NULL) = (resolution IS NULL)", name="resolution_reason"
        ),
        CheckConstraint(
            "(status = 'resolved') = (action IS NOT NULL)", name="resolution_action"
        ),
        CheckConstraint(
            "(kind = 'payment') = (payment_claim_id IS NOT NULL)",
            name="payment_subject",
        ),
        CheckConstraint(
            "statement IS NULL OR char_length(statement) > 0",
            name="statement_not_empty",
        ),
        CheckConstraint("event_at <= opened_at", name="event_before_opening"),
        UniqueConstraint("payment_claim_id"),
        Index(
            "uq_moderation_dispute_interaction_subject",
            "interaction_id",
            unique=True,
            postgresql_where=text("kind IN ('no_show','not_returned')"),
        ),
        Index(
            "uq_moderation_dispute_event",
            "listing_id",
            unique=True,
            postgresql_where=text("interaction_id IS NULL"),
        ),
        Index("ix_moderation_dispute_status", "status", "opened_at"),
        Index("ix_moderation_dispute_kind", "kind", "opened_at"),
    )

    kind: Mapped[str] = mapped_column(String(16), default=DisputeKind.NO_SHOW)
    status: Mapped[str] = mapped_column(String(16), default=DisputeStatus.OPEN)
    listing_id: Mapped[UUID] = mapped_column(
        ForeignKey("listing.id", ondelete="CASCADE")
    )
    interaction_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("listing_interaction.id", ondelete="CASCADE")
    )
    payment_claim_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("listing_payment_claim.id", ondelete="RESTRICT")
    )
    # The participant who opened the case; empty for a case opened before #94.
    opened_by_id: Mapped[UUID | None] = mapped_column(ForeignKey("identity_user.id"))
    # The moment of the disputed event, from which the opening window runs.
    event_at: Mapped[datetime]
    opened_at: Mapped[datetime] = mapped_column(default=clock.now)
    # The opener's account of the case; the mark itself keeps its reason.
    statement: Mapped[str | None] = mapped_column(Text)
    resolved_at: Mapped[datetime | None]
    # The decision in force and the moderator's justification.
    action: Mapped[str | None] = mapped_column(String(32))
    resolution: Mapped[str | None] = mapped_column(Text)
    resolved_by_id: Mapped[UUID | None] = mapped_column(ForeignKey("identity_user.id"))
    # Optimistic concurrency of the moderator panel (#94).
    version: Mapped[int] = mapped_column(default=1)

    listing: Mapped[Listing] = relationship(lazy="raise", viewonly=True)
    interaction: Mapped[Interaction | None] = relationship(lazy="raise", viewonly=True)

    @property
    def author_id(self) -> UUID:
        """The author of the listing, for the queue without a second query."""
        return self.listing.author_id

    @property
    def participant_id(self) -> UUID | None:
        """The other participant of an interaction case, if any."""
        return None if self.interaction is None else self.interaction.participant_id
