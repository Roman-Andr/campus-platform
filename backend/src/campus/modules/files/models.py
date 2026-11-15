"""Reusable private file metadata; object bytes live only in S3."""

from datetime import datetime
from uuid import UUID

from sqlalchemy import CheckConstraint, ForeignKey, Index, String
from sqlalchemy.orm import Mapped, mapped_column

from campus.core.db import Entity


class File(Entity):
    __tablename__ = "file"
    __table_args__ = (
        CheckConstraint(
            "status IN ('pending','processing','ready','rejected')", name="status"
        ),
        CheckConstraint("size >= 0", name="size"),
        CheckConstraint("position IS NULL OR position >= 0", name="position"),
        CheckConstraint("(listing_id IS NULL) = (position IS NULL)", name="attachment"),
        CheckConstraint(
            "num_nonnulls(listing_id, profile_user_id, chat_id) <= 1",
            name="single_owner",
        ),
        Index("ix_file_listing_id", "listing_id"),
        Index("ix_file_chat_id", "chat_id"),
    )
    owner_id: Mapped[UUID] = mapped_column(ForeignKey("identity_user.id"))
    purpose: Mapped[str] = mapped_column(String(32), default="listing_photo")
    key: Mapped[str] = mapped_column(String(200), unique=True)
    status: Mapped[str] = mapped_column(String(16), default="pending")
    size: Mapped[int] = mapped_column(default=0)
    rejection_reason: Mapped[str | None] = mapped_column(String(64))
    upload_expires_at: Mapped[datetime]
    expires_at: Mapped[datetime]
    listing_id: Mapped[UUID | None] = mapped_column(ForeignKey("listing.id"))
    position: Mapped[int | None]
    # The user whose profile photo this is; one photo per profile.
    profile_user_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("identity_user.id"), unique=True
    )
    # A photo attached to a chat. Cleanup deletes these objects explicitly;
    # RESTRICT makes a chat deletion impossible while objects still exist.
    chat_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("chat.id", ondelete="RESTRICT")
    )
