"""Ephemeral chat activity: "typing…" and the open-chat flag.

Both indicators are ephemeral state, never a message: they live in a Redis
hash of the chat and are erased by TTL, so the history, the archive and the
search never see them. A heartbeat is an ordinary API request, so the
server checks the membership of the chat on every beat; a removed member
loses the right to send and to read the indicators immediately, and the read
path also drops fields of members that left since their last beat.

Time is the application clock, not the Redis clock: every field stores the
server timestamp of its last heartbeat, and a field is shown only while it is
younger than the configured TTL. Redis ``EXPIRE`` is a garbage collector for
a key nobody touches any more; the visible state is decided by the stored
timestamps, which makes the TTL testable with controlled time.

The open-chat flag is per device session: closing the chat on one device
removes that device's field, while another open device of the same member
keeps the flag. A lost device stops beating and its field expires.

Every accepted heartbeat and close writes an outbox message that publishes a
metadata-only wakeup to the chat channel. Only members hold a subscription
grant to that channel, so nobody outside the chat can observe the activity;
a missed publication is recovered by reading the REST state, which is the
authority.
"""

import math
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from uuid import UUID

from redis.asyncio import Redis
from redis.exceptions import RedisError
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from campus.core import clock
from campus.core.config import Settings
from campus.core.i18n import N_
from campus.core.outbox import add_message
from campus.core.web import ProblemError, ProblemType
from campus.modules.chat.models import ChatMember
from campus.modules.chat.service import PRESENCE_TOPIC, require_membership

PRESENCE_UNAVAILABLE = ProblemType(
    "chat_presence_unavailable",
    503,
    N_("Chat activity is unavailable"),
    N_("The ephemeral chat state is temporarily unavailable. Try again later."),
)

TYPING_PREFIX = "t"
OPEN_PREFIX = "o"


@dataclass(frozen=True, slots=True)
class PresenceState:
    """The caller's own effective flags and when they expire without a beat."""

    typing: bool
    open: bool
    typing_expires_at: datetime | None
    open_expires_at: datetime | None


@dataclass(frozen=True, slots=True)
class PresenceItem:
    """Activity of another member of the chat."""

    user_id: UUID
    typing: bool
    open: bool


def presence_key(chat_id: UUID) -> str:
    """The Redis hash of one chat's ephemeral activity."""
    return f"chat:presence:{chat_id}"


def _field(prefix: str, user_id: UUID, session_id: UUID) -> str:
    return f"{prefix}:{user_id}:{session_id}"


def _now_ms() -> int:
    return int(clock.now().timestamp() * 1000)


def _fresh(value: str | bytes | None, *, now_ms: int, ttl: timedelta) -> int | None:
    """The heartbeat timestamp if it is inside ``ttl``, otherwise ``None``.

    A stamp slightly in the future is treated as fresh: the server writes
    the stamps, and a controlled clock may be moved backwards in a test.
    """
    if value is None:
        return None
    try:
        stamp = int(value)
    except TypeError, ValueError:
        return None
    if now_ms - stamp > int(ttl.total_seconds() * 1000):
        return None
    return stamp


def _expiry(stamp: int | None, ttl: timedelta) -> datetime | None:
    if stamp is None:
        return None
    return datetime.fromtimestamp(stamp / 1000, tz=UTC) + ttl


def _gc_seconds(settings: Settings) -> int:
    """How long Redis keeps a key that no client touches any more."""
    longest = max(settings.chat_typing_ttl, settings.chat_presence_ttl)
    return max(1, math.ceil(longest.total_seconds()) * 2)


def _decode(field: str | bytes) -> str:
    return field.decode() if isinstance(field, bytes) else field


def _value(value: str | bytes | None) -> str | None:
    if value is None:
        return None
    return value.decode() if isinstance(value, bytes) else value


async def _read_fields(
    redis: Redis, key: str, fields: list[str], *, settings: Settings
) -> dict[str, int | None]:
    """Fresh heartbeat stamps of ``fields``; ``None`` when absent or stale."""
    try:
        raw = await redis.hmget(key, fields)
    except RedisError as error:
        raise ProblemError(PRESENCE_UNAVAILABLE) from error
    now_ms = _now_ms()
    result: dict[str, int | None] = {}
    for field, value in zip(fields, raw, strict=True):
        ttl = (
            settings.chat_typing_ttl
            if field.startswith(f"{TYPING_PREFIX}:")
            else settings.chat_presence_ttl
        )
        result[field] = _fresh(_value(value), now_ms=now_ms, ttl=ttl)
    return result


async def _member_ids(session: AsyncSession, chat_id: UUID) -> set[UUID]:
    return set(
        await session.scalars(
            select(ChatMember.user_id).where(
                ChatMember.chat_id == chat_id,
                ChatMember.left_at.is_(None),
            )
        )
    )


async def heartbeat(  # noqa: PLR0913 - one field per heartbeat
    session: AsyncSession,
    redis: Redis,
    *,
    chat_id: UUID,
    user_id: UUID,
    session_id: UUID,
    typing: bool | None,
    open_: bool | None,
    settings: Settings,
) -> PresenceState:
    """Refresh the caller's typing and/or open-chat flag of this device.

    ``None`` leaves a flag as it is, so a client that only repeats the typing
    ping does not silently close its chat. Closing the chat (``open_=False``)
    also stops typing of that device: a closed chat cannot be composing.
    """
    await require_membership(session, chat_id, user_id)
    now = clock.now()
    stamp = str(int(now.timestamp() * 1000))
    key = presence_key(chat_id)
    typing_field = _field(TYPING_PREFIX, user_id, session_id)
    open_field = _field(OPEN_PREFIX, user_id, session_id)
    updates: dict[str, str] = {}
    removals: list[str] = []
    if open_ is False:
        removals.extend((typing_field, open_field))
    else:
        if typing is not None:
            if typing:
                updates[typing_field] = stamp
            else:
                removals.append(typing_field)
        if open_ is not None:
            if open_:
                updates[open_field] = stamp
            else:
                removals.append(open_field)
    try:
        for field, value in updates.items():
            await redis.hset(key, field, value)
        if updates:
            await redis.expire(key, _gc_seconds(settings))
        if removals:
            await redis.hdel(key, *removals)
    except RedisError as error:
        raise ProblemError(PRESENCE_UNAVAILABLE) from error

    own = await _read_fields(redis, key, [typing_field, open_field], settings=settings)
    state = PresenceState(
        typing=own[typing_field] is not None,
        open=own[open_field] is not None,
        typing_expires_at=_expiry(own[typing_field], settings.chat_typing_ttl),
        open_expires_at=_expiry(own[open_field], settings.chat_presence_ttl),
    )
    add_message(
        session,
        PRESENCE_TOPIC,
        {
            "chat_id": str(chat_id),
            "user_id": str(user_id),
            "typing": state.typing,
            "open": state.open,
            "occurred_at": now.isoformat(),
        },
    )
    return state


async def close(
    session: AsyncSession,
    redis: Redis,
    *,
    chat_id: UUID,
    user_id: UUID,
    session_id: UUID,
) -> None:
    """Remove this device's open-chat flag and typing, and tell the chat.

    Repeating the close is harmless: removing absent fields changes nothing,
    and the wakeup only tells clients to reload the authoritative REST state.
    """
    await require_membership(session, chat_id, user_id)
    now = clock.now()
    key = presence_key(chat_id)
    try:
        await redis.hdel(
            key,
            _field(TYPING_PREFIX, user_id, session_id),
            _field(OPEN_PREFIX, user_id, session_id),
        )
    except RedisError as error:
        raise ProblemError(PRESENCE_UNAVAILABLE) from error
    add_message(
        session,
        PRESENCE_TOPIC,
        {
            "chat_id": str(chat_id),
            "user_id": str(user_id),
            "typing": False,
            "open": False,
            "occurred_at": now.isoformat(),
        },
    )


async def read_presence(
    session: AsyncSession,
    redis: Redis,
    *,
    chat_id: UUID,
    user_id: UUID,
    settings: Settings,
) -> list[PresenceItem]:
    """Activity of the other active members of the chat.

    The caller must be a member. Fields of users who are not active members
    any more are dropped even before their TTL: a participant removed from a
    group cannot keep broadcasting presence. The caller's own flags are not
    repeated; the heartbeat response carries them.
    """
    await require_membership(session, chat_id, user_id)
    members = await _member_ids(session, chat_id)
    try:
        raw = await redis.hgetall(presence_key(chat_id))
    except RedisError as error:
        raise ProblemError(PRESENCE_UNAVAILABLE) from error
    now_ms = _now_ms()
    typing_ttl_ms = int(settings.chat_typing_ttl.total_seconds() * 1000)
    presence_ttl_ms = int(settings.chat_presence_ttl.total_seconds() * 1000)
    typing: set[UUID] = set()
    open_: set[UUID] = set()
    for raw_field, raw_value in raw.items():
        field = _decode(raw_field)
        prefix, _, rest = field.partition(":")
        owner, _, _session = rest.partition(":")
        try:
            owner_id = UUID(owner)
        except ValueError:  # pragma: no cover - only this module writes fields
            continue
        if owner_id not in members or owner_id == user_id:
            continue
        try:
            stamp = int(_value(raw_value) or "")
        except ValueError:  # pragma: no cover - only this module writes fields
            continue
        ttl_ms = typing_ttl_ms if prefix == TYPING_PREFIX else presence_ttl_ms
        if now_ms - stamp > ttl_ms:
            continue
        if prefix == TYPING_PREFIX:
            typing.add(owner_id)
        elif prefix == OPEN_PREFIX:
            open_.add(owner_id)
    return [
        PresenceItem(member, member in typing, member in open_)
        for member in sorted(typing | open_, key=str)
    ]
