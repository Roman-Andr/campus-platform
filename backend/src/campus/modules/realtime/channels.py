"""Channel names, their authorization and durable membership revocation.

Two channel kinds exist:

- ``user#<uuid>`` — the personal channel of a user. Centrifugo itself limits
  it to that user (a user-limited channel), and the API checks the same rule
  before issuing a subscription token.
- ``chat:<uuid>`` — a chat channel. Only users with an active
  :class:`~campus.modules.realtime.models.ChannelGrant` may subscribe.

Chat modules (personal and group chats) grant and revoke access through this
module in the transaction that changes their membership. Revocation writes an
outbox message, so a lost acknowledgement is retried and a re-grant that
happens before delivery is respected by the consumer.
"""

from dataclasses import dataclass
from enum import StrEnum
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from campus.core import clock
from campus.core.outbox import add_message
from campus.modules.realtime.models import ChannelGrant

CHANNEL_MAX_LENGTH = 255
UNSUBSCRIBE_TOPIC = "realtime.unsubscribe"


class ChannelKind(StrEnum):
    PERSONAL = "personal"
    CHAT = "chat"


@dataclass(frozen=True, slots=True)
class Channel:
    """A parsed channel name and the identifier it grants access to."""

    name: str
    kind: ChannelKind
    target_id: UUID


def personal_channel(user_id: UUID) -> Channel:
    """The personal channel of ``user_id`` (a Centrifugo user-limited one)."""
    return Channel(f"user#{user_id}", ChannelKind.PERSONAL, user_id)


def chat_channel(chat_id: UUID) -> Channel:
    """The realtime channel of a chat with ``chat_id``."""
    return Channel(f"chat:{chat_id}", ChannelKind.CHAT, chat_id)


def parse_channel(name: str) -> Channel:
    """Parse a channel name; raise ``ValueError`` for anything else."""
    if len(name) > CHANNEL_MAX_LENGTH:
        raise ValueError("channel name is too long")
    if name.startswith("user#"):
        kind, raw = ChannelKind.PERSONAL, name.removeprefix("user#")
    elif name.startswith("chat:"):
        kind, raw = ChannelKind.CHAT, name.removeprefix("chat:")
    else:
        raise ValueError("unknown channel")
    try:
        target_id = UUID(raw)
    except ValueError:
        raise ValueError("channel identifier must be a UUID") from None
    # Only the canonical form is accepted, so one object has one channel.
    if str(target_id) != raw:
        raise ValueError("channel identifier must be a canonical UUID")
    return Channel(name, kind, target_id)


async def can_access(session: AsyncSession, name: str, user_id: UUID) -> bool:
    """Whether ``user_id`` may subscribe to the channel ``name`` now.

    The personal channel is readable by its owner only. A chat channel needs
    an active grant, checked live from the database on every call.
    """
    channel = parse_channel(name)
    if channel.kind is ChannelKind.PERSONAL:
        return channel.target_id == user_id
    granted = await session.scalar(
        select(ChannelGrant.channel).where(
            ChannelGrant.channel == channel.name,
            ChannelGrant.user_id == user_id,
            ChannelGrant.revoked_at.is_(None),
        )
    )
    return granted is not None


async def grant_chat_access(session: AsyncSession, chat_id: UUID, user_id: UUID) -> str:
    """Activate the chat channel grant of ``user_id``; return the channel name.

    Safe to repeat: a concurrent or later grant clears a previous revocation.
    Call it in the transaction that adds the chat membership.
    """
    channel = chat_channel(chat_id)
    await session.execute(
        insert(ChannelGrant)
        .values(channel=channel.name, user_id=user_id)
        .on_conflict_do_update(
            index_elements=[ChannelGrant.channel, ChannelGrant.user_id],
            set_={"revoked_at": None},
        )
    )
    return channel.name


async def revoke_chat_access(
    session: AsyncSession, chat_id: UUID, user_id: UUID
) -> bool:
    """Revoke the chat channel grant and queue a forced unsubscribe.

    Returns whether this call revoked an active grant: repeating it, or
    revoking a grant that never existed, is a no-op without a new message.
    Call it in the transaction that removes the chat membership.
    """
    channel = chat_channel(chat_id)
    grant = await session.scalar(
        select(ChannelGrant)
        .where(
            ChannelGrant.channel == channel.name,
            ChannelGrant.user_id == user_id,
        )
        .with_for_update()
    )
    if grant is None or grant.revoked_at is not None:
        return False
    grant.revoked_at = clock.now()
    add_message(
        session,
        UNSUBSCRIBE_TOPIC,
        {"channel": channel.name, "user_id": str(user_id)},
    )
    return True
