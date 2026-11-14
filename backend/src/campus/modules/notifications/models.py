"""Recipient inboxes and permanent event deduplication."""

from datetime import datetime
from typing import Any
from uuid import UUID

from sqlalchemy import BigInteger, ForeignKey, String, UniqueConstraint
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from campus.core.db import Base, Entity
from campus.core.event_dispatch import DispatchReceipt


class NotificationDispatch(DispatchReceipt):
    __tablename__ = "notification_dispatch"


class Inbox(Base):
    """Serialize allocation with commit, so recovery never skips late commits."""

    __tablename__ = "notification_inbox"

    user_id: Mapped[UUID] = mapped_column(
        ForeignKey("identity_user.id", ondelete="CASCADE"), primary_key=True
    )
    sequence: Mapped[int] = mapped_column(BigInteger, default=0)
    read_sequence: Mapped[int] = mapped_column(BigInteger, default=0)


class Notification(Entity):
    __tablename__ = "notification"
    __table_args__ = (
        UniqueConstraint("event_id", "recipient_id"),
        UniqueConstraint("recipient_id", "sequence"),
    )

    event_id: Mapped[UUID]
    recipient_id: Mapped[UUID] = mapped_column(
        ForeignKey("identity_user.id", ondelete="CASCADE")
    )
    sequence: Mapped[int] = mapped_column(BigInteger)
    type: Mapped[str] = mapped_column(String(80))
    object_id: Mapped[UUID | None]
    occurred_at: Mapped[datetime]
    text: Mapped[dict[str, str]] = mapped_column(JSONB)
    params: Mapped[dict[str, Any]] = mapped_column(JSONB)


class Reminder(Base):
    """Current schedule projected by the owning domain in its transaction."""

    __tablename__ = "notification_reminder"

    key: Mapped[str] = mapped_column(String(160), primary_key=True)
    revision: Mapped[UUID]
    starts_at: Mapped[datetime]
    active: Mapped[bool]
    payload: Mapped[dict[str, Any]] = mapped_column(JSONB)
