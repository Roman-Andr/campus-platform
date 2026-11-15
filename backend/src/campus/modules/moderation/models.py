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
    """The disputed subject of a case."""

    NO_SHOW = "no_show"


class DisputeStatus(StrEnum):
    """Open cases wait for a moderator decision (#94)."""

    OPEN = "open"
    RESOLVED = "resolved"


class Dispute(Entity):
    """One case about one interaction or one event.

    #66 opens the case automatically when both participants accuse each
    other of a no-show; the unique interaction keeps a pair of mutual
    allegations from opening two cases. A case about an event vote has no
    interaction. The moderator decision (#94) changes the status and records
    its reason; a later late-QR resolution may close the case as resolved.
    """

    __tablename__ = "moderation_dispute"
    __table_args__ = (
        CheckConstraint("kind IN ('no_show')", name="kind"),
        CheckConstraint("status IN ('open','resolved')", name="status"),
        CheckConstraint("version > 0", name="version_positive"),
        CheckConstraint(
            "(status = 'resolved') = (resolved_at IS NOT NULL)", name="resolution_time"
        ),
        CheckConstraint(
            "(resolved_at IS NULL) = (resolution IS NULL)", name="resolution_reason"
        ),
        UniqueConstraint("interaction_id"),
        Index(
            "uq_moderation_dispute_event",
            "listing_id",
            unique=True,
            postgresql_where=text("interaction_id IS NULL"),
        ),
        Index("ix_moderation_dispute_status", "status", "opened_at"),
    )

    kind: Mapped[str] = mapped_column(String(16), default=DisputeKind.NO_SHOW)
    status: Mapped[str] = mapped_column(String(16), default=DisputeStatus.OPEN)
    listing_id: Mapped[UUID] = mapped_column(
        ForeignKey("listing.id", ondelete="CASCADE")
    )
    interaction_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("listing_interaction.id", ondelete="CASCADE")
    )
    opened_at: Mapped[datetime] = mapped_column(default=clock.now)
    resolved_at: Mapped[datetime | None]
    resolution: Mapped[str | None] = mapped_column(Text)
    resolved_by_id: Mapped[UUID | None] = mapped_column(ForeignKey("identity_user.id"))
    # Optimistic concurrency of the moderator panel (#94).
    version: Mapped[int] = mapped_column(default=1)
