"""Delivery settings of a user and the policy applied before external channels.

The notification row is always stored: quiet hours, a disabled type and a
muted chat only suppress external delivery (the in-app feed stays complete).
Quiet hours use the wall clock of the user's city, read live from the
profile, so a city change applies without touching the settings row.
Important events bypass quiet hours, but not an explicit type or chat mute;
grouping and priority are a separate policy (#88).
"""

from dataclasses import dataclass
from datetime import datetime, time
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from campus.core import clock
from campus.core.config import Settings, get_settings
from campus.core.timezones import in_local_interval
from campus.modules.identity import User
from campus.modules.notifications.models import (
    MutedChat,
    Notification,
    NotificationSettings,
)
from campus.modules.realtime import can_access, chat_channel
from campus.modules.university import City


@dataclass(frozen=True, slots=True)
class EffectiveSettings:
    """What applies to a user now, with the configured defaults filled in."""

    version: int
    disabled_types: frozenset[str]
    quiet_hours_enabled: bool
    quiet_hours_start: time
    quiet_hours_end: time
    muted_chats: frozenset[UUID]


def default_settings(settings: Settings) -> EffectiveSettings:
    """Settings of a user who has never changed them."""
    return EffectiveSettings(
        version=0,
        disabled_types=frozenset(),
        quiet_hours_enabled=settings.notification_quiet_hours_enabled,
        quiet_hours_start=settings.notification_quiet_hours_start,
        quiet_hours_end=settings.notification_quiet_hours_end,
        muted_chats=frozenset(),
    )


async def effective_settings(
    session: AsyncSession, user_id: UUID, settings: Settings
) -> EffectiveSettings:
    """The stored settings of ``user_id`` or the configured defaults."""
    row = await session.get(NotificationSettings, user_id)
    if row is None:
        return default_settings(settings)
    muted = frozenset(
        await session.scalars(
            select(MutedChat.chat_id).where(MutedChat.user_id == user_id)
        )
    )
    return EffectiveSettings(
        version=row.version,
        disabled_types=frozenset(row.disabled_types),
        quiet_hours_enabled=row.quiet_hours_enabled,
        quiet_hours_start=row.quiet_hours_start,
        quiet_hours_end=row.quiet_hours_end,
        muted_chats=muted,
    )


async def user_timezone(
    session: AsyncSession, user_id: UUID, settings: Settings
) -> str:
    """IANA zone of the user's city; the configured fallback until known."""
    timezone = await session.scalar(
        select(City.timezone)
        .join(User, User.city_id == City.id)
        .where(User.id == user_id)
    )
    return str(timezone or settings.notification_default_timezone)


def quiet_hours_active(
    moment: datetime, current: EffectiveSettings, timezone: str
) -> bool:
    """Whether ``moment`` falls into the user's quiet hours in ``timezone``."""
    return current.quiet_hours_enabled and in_local_interval(
        moment, current.quiet_hours_start, current.quiet_hours_end, timezone
    )


async def is_chat_member(session: AsyncSession, user_id: UUID, chat_id: UUID) -> bool:
    """Whether the user has an active realtime grant for the chat."""
    return await can_access(session, chat_channel(chat_id).name, user_id)


def muted_chat_id(notification: Notification) -> UUID | None:
    """The chat of a chat notification, if the payload names one."""
    raw = notification.params.get("chat_id")
    if raw is None:
        return None
    try:
        return UUID(str(raw))
    except ValueError:
        return None


async def external_delivery_allowed(
    session: AsyncSession,
    notification: Notification,
    *,
    settings: Settings | None = None,
    moment: datetime | None = None,
) -> bool:
    """Whether an external channel may send ``notification`` now.

    The feed row is already stored; this decision covers push, e-mail and
    other out-of-app providers. In-app realtime delivery does not call it.
    """
    settings = settings or get_settings()
    current = await effective_settings(session, notification.recipient_id, settings)
    if notification.type in current.disabled_types:
        return False
    chat_id = muted_chat_id(notification)
    if chat_id is not None and chat_id in current.muted_chats:
        return False
    if notification.important:
        return True
    timezone = await user_timezone(session, notification.recipient_id, settings)
    return not quiet_hours_active(moment or clock.now(), current, timezone)
