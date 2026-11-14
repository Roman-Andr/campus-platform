"""Complaint reason catalogue bound to a published community rules version.

Reasons are never hard-deleted: complaints reference them and keep their own
immutable snapshot of the basis (#91), while the catalogue row keeps the
published rules version and clause it was bound to. A deactivated reason is
hidden from the complaint form but stays readable for the panel and history.
"""

from uuid import UUID

from sqlalchemy import CheckConstraint, ForeignKey, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

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
