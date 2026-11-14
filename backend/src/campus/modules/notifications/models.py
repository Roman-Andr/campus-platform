"""Recipient inboxes, per-user delivery settings and event deduplication."""

from datetime import datetime, time
from typing import Any
from uuid import UUID

from sqlalchemy import (
    BigInteger,
    CheckConstraint,
    ForeignKey,
    String,
    Time,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from campus.core import clock
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
    # Important events pass through quiet hours; grouping is a separate
    # policy (#88). Producers set the flag on the event.
    important: Mapped[bool] = mapped_column(default=False)


class Reminder(Base):
    """Current schedule projected by the owning domain in its transaction."""

    __tablename__ = "notification_reminder"

    key: Mapped[str] = mapped_column(String(160), primary_key=True)
    revision: Mapped[UUID]
    starts_at: Mapped[datetime]
    active: Mapped[bool]
    payload: Mapped[dict[str, Any]] = mapped_column(JSONB)


class NotificationSettings(Base):
    """Per-user delivery settings; one row means the user changed them.

    Absent row means the configured defaults: every type is enabled and quiet
    hours are on. Quiet times are wall-clock values of the user's city, never
    of the device or the listing. ``version`` supports optimistic edits.
    """

    __tablename__ = "notification_settings"
    __table_args__ = (
        CheckConstraint("version >= 1", name="version_positive"),
        CheckConstraint(
            "quiet_hours_start <> quiet_hours_end", name="quiet_hours_not_empty"
        ),
    )

    user_id: Mapped[UUID] = mapped_column(
        ForeignKey("identity_user.id", ondelete="CASCADE"), primary_key=True
    )
    version: Mapped[int] = mapped_column(default=1)
    quiet_hours_enabled: Mapped[bool] = mapped_column(default=True)
    quiet_hours_start: Mapped[time] = mapped_column(Time)
    quiet_hours_end: Mapped[time] = mapped_column(Time)
    # Types the user turned off; empty means all notifications are enabled.
    disabled_types: Mapped[list[str]] = mapped_column(JSONB, default=list)
    created_at: Mapped[datetime] = mapped_column(default=clock.now)
    updated_at: Mapped[datetime] = mapped_column(default=clock.now, onupdate=clock.now)


class MutedChat(Base):
    """A chat whose notifications the user muted.

    Chat membership is owned by chat modules and projected to the realtime
    channel grants; the API checks it before storing a chat here.
    """

    __tablename__ = "notification_muted_chat"

    user_id: Mapped[UUID] = mapped_column(
        ForeignKey("identity_user.id", ondelete="CASCADE"), primary_key=True
    )
    chat_id: Mapped[UUID] = mapped_column(primary_key=True)
    created_at: Mapped[datetime] = mapped_column(default=clock.now)
