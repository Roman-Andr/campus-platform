"""Personal chat domain: creation, membership, deduplication and delivery.

The API endpoints stay thin; the rules of the module live here so that the
worker and the tests exercise the same code:

- only an active student or employee starts a new chat; alumni and former
  employees write only in chats that already exist;
- a listing or interaction link is accepted only from a user who may see
  it, and an interaction chat only between its two parties;
- the server assigns the order number; the client UUID is stored forever
  and rejects different content, independently of the idempotency key;
- the message, its deduplication record and its outbox publication are
  written in one transaction, so a rollback publishes nothing.
"""

import hashlib
import math
import re
from typing import Any
from uuid import UUID, uuid7

from sqlalchemy import func, select, text, update
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from campus.core import clock
from campus.core.config import Settings
from campus.core.i18n import N_
from campus.core.outbox import add_message
from campus.core.web import ProblemError, ProblemType
from campus.core.web.problems import NOT_FOUND
from campus.modules.chat.models import (
    PERSONAL_KIND,
    Chat,
    ChatMember,
    ChatMessage,
    ChatMessageDedup,
)
from campus.modules.identity import User
from campus.modules.listings import Interaction, Listing, readable
from campus.modules.realtime import grant_chat_access
from campus.modules.university import AccountType

MESSAGE_TOPIC = "chat.message"
ACTIVE_ACCOUNT_TYPES = (AccountType.STUDENT, AccountType.EMPLOYEE)

CHAT_NOT_FOUND = ProblemType(
    "chat_not_found",
    404,
    N_("Chat not found"),
    N_("The chat does not exist or you are not a member."),
)
CHAT_FORBIDDEN = ProblemType(
    "chat_forbidden",
    403,
    N_("This action is not allowed."),
    N_("Alumni and former employees can write only in existing chats."),
)
CHAT_SELF = ProblemType("chat_self", 422, N_("A chat must have two different members."))
CHAT_LINK_INVALID = ProblemType(
    "chat_link_invalid",
    422,
    N_("The listing and the interaction do not belong together."),
)
CHAT_MESSAGE_INVALID = ProblemType(
    "chat_message_invalid", 422, N_("The message text is empty or too long.")
)
CHAT_MESSAGE_CONFLICT = ProblemType(
    "chat_message_conflict",
    409,
    N_("The message identifier is already used."),
    N_("The same client message identifier carries different content."),
)
CHAT_RATE_LIMITED = ProblemType(
    "chat_rate_limited", 429, N_("Too many messages. Try again later.")
)
CHAT_SEARCH_INVALID = ProblemType(
    "chat_search_invalid",
    422,
    N_("Invalid search query."),
    N_("The search query must be at most {max_length} characters."),
)


def canonical_pair(first: UUID, second: UUID) -> tuple[UUID, UUID]:
    """The pair as stored: the smaller UUID first, so the index is stable."""
    return (first, second) if first < second else (second, first)


def content_hash(text_value: str) -> str:
    """Hash that makes one client identifier stand for exactly one text."""
    return hashlib.sha256(text_value.encode()).hexdigest()


def message_snippet(text_value: str, query: str, limit: int) -> str:
    """A bounded excerpt around the first query word of a search hit.

    The snippet is plain text: the client highlights the query itself. It
    never exceeds ``limit`` characters plus the two ellipsis characters.
    """
    collapsed = " ".join(text_value.split())
    if len(collapsed) <= limit:
        return collapsed
    folded = collapsed.casefold()
    positions = [
        folded.find(word.casefold()) for word in re.findall(r"\w+", query) if word
    ]
    hit = min((position for position in positions if position >= 0), default=0)
    start = max(0, hit - limit // 3)
    end = min(len(collapsed), start + limit)
    if end - start < limit:
        start = max(0, end - limit)
    snippet = collapsed[start:end].strip()
    if start:
        snippet = "…" + snippet
    if end < len(collapsed):
        snippet += "…"
    return snippet


def message_payload(message: ChatMessage) -> dict[str, Any]:
    """Publication of a stored message; clients recover gaps through the API."""
    return {
        "chat_id": str(message.chat_id),
        "message_id": str(message.id),
        "client_id": str(message.client_id),
        "sender_id": str(message.sender_id),
        "sequence": message.sequence,
        "text": message.text,
        "created_at": message.created_at.isoformat(),
    }


async def require_membership(
    session: AsyncSession, chat_id: UUID, user_id: UUID
) -> Chat:
    """The chat if ``user_id`` is a member; otherwise hide it with 404.

    No role grants access to somebody else's chat: moderators and
    administrators use the separate complaint and dispute entry points.
    """
    chat = await session.scalar(
        select(Chat)
        .join(ChatMember, ChatMember.chat_id == Chat.id)
        .where(Chat.id == chat_id, ChatMember.user_id == user_id)
    )
    if chat is None:
        raise ProblemError(CHAT_NOT_FOUND)
    return chat


async def find_pair_chat(
    session: AsyncSession,
    low: UUID,
    high: UUID,
    listing_id: UUID | None,
    interaction_id: UUID | None,
) -> Chat | None:
    """The chat that already represents this pair and link, if any."""
    query = select(Chat).where(
        Chat.kind == "personal",
        Chat.user_low_id == low,
        Chat.user_high_id == high,
    )
    if interaction_id is not None:
        query = query.where(Chat.interaction_id == interaction_id)
    elif listing_id is not None:
        query = query.where(
            Chat.listing_id == listing_id, Chat.interaction_id.is_(None)
        )
    else:
        query = query.where(Chat.listing_id.is_(None), Chat.interaction_id.is_(None))
    return await session.scalar(query)


async def check_link(
    session: AsyncSession,
    creator: User,
    recipient_id: UUID,
    listing_id: UUID | None,
    interaction_id: UUID | None,
) -> UUID | None:
    """Validate the link and return the listing id to store.

    A link never grants access to the object it names: the creator must be
    able to read the listing now, and an interaction chat is possible only
    for the two parties of that interaction.
    """
    if interaction_id is not None:
        interaction = await session.get(Interaction, interaction_id)
        if interaction is None:
            raise ProblemError(NOT_FOUND)
        listing = await session.get(Listing, interaction.listing_id)
        if listing is None:
            raise ProblemError(NOT_FOUND)
        parties = {interaction.participant_id, listing.author_id}
        if creator.id not in parties or recipient_id not in parties:
            raise ProblemError(NOT_FOUND)
        if listing_id is not None and listing_id != interaction.listing_id:
            raise ProblemError(CHAT_LINK_INVALID)
        return interaction.listing_id
    if listing_id is not None:
        await readable(session, listing_id, creator)
        return listing_id
    return None


async def create_personal_chat(
    session: AsyncSession,
    *,
    creator_id: UUID,
    recipient_id: UUID,
    listing_id: UUID | None = None,
    interaction_id: UUID | None = None,
) -> tuple[Chat, bool]:
    """Create the personal chat of two users, or return the existing one.

    The second result says whether this call created the chat. Repeating a
    creation (also concurrently) returns the stored chat instead of a
    duplicate: the partial unique indexes of :class:`Chat` decide.
    """
    if creator_id == recipient_id:
        raise ProblemError(CHAT_SELF)
    creator = await session.get(User, creator_id)
    recipient = await session.get(User, recipient_id)
    if creator is None or recipient is None:
        raise ProblemError(NOT_FOUND)
    if creator.account_type not in ACTIVE_ACCOUNT_TYPES:
        raise ProblemError(CHAT_FORBIDDEN)
    linked_listing_id = await check_link(
        session, creator, recipient_id, listing_id, interaction_id
    )
    low, high = canonical_pair(creator_id, recipient_id)
    existing = await find_pair_chat(
        session, low, high, linked_listing_id, interaction_id
    )
    if existing is not None:
        return existing, False
    now = clock.now()
    # One statement claims the pair: a concurrent creation conflicts on the
    # partial unique index and gets no row back, so it returns the stored
    # chat below instead of failing the request.
    created_id = await session.scalar(
        insert(Chat)
        .values(
            kind=PERSONAL_KIND,
            user_low_id=low,
            user_high_id=high,
            listing_id=linked_listing_id,
            interaction_id=interaction_id,
            last_sequence=0,
            created_at=now,
            updated_at=now,
        )
        .on_conflict_do_nothing()
        .returning(Chat.id)
    )
    if created_id is None:
        stored = await find_pair_chat(
            session, low, high, linked_listing_id, interaction_id
        )
        if stored is None:  # pragma: no cover - the unique index guarantees it
            msg = "the conflicting chat is not visible"
            raise RuntimeError(msg)
        return stored, False
    chat = await session.get_one(Chat, created_id)
    for member_id in (low, high):
        session.add(ChatMember(chat_id=chat.id, user_id=member_id))
        await grant_chat_access(session, chat.id, member_id)
    return chat, True


async def serialize_sender(session: AsyncSession, sender_id: UUID) -> None:
    """Queue this sender's requests, so the limit and dedup see committed rows."""
    await session.execute(
        text("SELECT pg_advisory_xact_lock(hashtextextended(:key, 0))"),
        {"key": f"chat-message:{sender_id}"},
    )


async def check_rate_limit(
    session: AsyncSession, sender_id: UUID, settings: Settings
) -> None:
    """Refuse the message when the user's window is full.

    Call it while holding :func:`serialize_sender` of the sender: concurrent
    requests of one user then count committed messages in turn. Only stored
    messages are counted, so a failed request or a replay consumes nothing.
    """
    now = clock.now()
    window_start = now - settings.chat_message_window
    sent = await session.scalar(
        select(func.count())
        .select_from(ChatMessage)
        .where(
            ChatMessage.sender_id == sender_id,
            ChatMessage.created_at > window_start,
        )
    )
    if sent is None or sent < settings.chat_message_limit:
        return
    oldest = await session.scalar(
        select(func.min(ChatMessage.created_at)).where(
            ChatMessage.sender_id == sender_id,
            ChatMessage.created_at > window_start,
        )
    )
    retry = 1
    if oldest is not None:
        retry = max(
            1,
            math.ceil((oldest + settings.chat_message_window - now).total_seconds()),
        )
    raise ProblemError(CHAT_RATE_LIMITED, headers={"Retry-After": str(retry)})


async def stored_message(session: AsyncSession, dedup: ChatMessageDedup) -> ChatMessage:
    """Load the message recorded by ``dedup``; it exists by construction."""
    message = await session.scalar(
        select(ChatMessage).where(
            ChatMessage.id == dedup.message_id,
            ChatMessage.created_at == dedup.message_created_at,
        )
    )
    if message is None:  # pragma: no cover - written in one transaction
        raise ProblemError(CHAT_NOT_FOUND)
    return message


async def post_message(  # noqa: PLR0913 - message fields
    session: AsyncSession,
    *,
    chat_id: UUID,
    sender_id: UUID,
    client_id: UUID,
    text: str,
    settings: Settings,
) -> tuple[ChatMessage, bool]:
    """Store a message once, deduplicated by its client identifier.

    The second result is ``False`` for a repeat of the same client UUID and
    content: the stored message is returned, no new order number is taken
    and the outbox gets no new publication.
    """
    await require_membership(session, chat_id, sender_id)
    if not text.strip() or len(text) > settings.chat_message_max_length:
        raise ProblemError(CHAT_MESSAGE_INVALID)
    await serialize_sender(session, sender_id)
    digest = content_hash(text)
    existing = await session.scalar(
        select(ChatMessageDedup).where(
            ChatMessageDedup.chat_id == chat_id,
            ChatMessageDedup.client_id == client_id,
        )
    )
    if existing is not None:
        if existing.sender_id != sender_id or existing.content_hash != digest:
            raise ProblemError(CHAT_MESSAGE_CONFLICT)
        return await stored_message(session, existing), False
    await check_rate_limit(session, sender_id, settings)
    now = clock.now()
    # The row lock serializes the counter; the number is committed with the
    # message, so it orders messages by commit, not by a device clock.
    sequence = await session.scalar(
        update(Chat)
        .where(Chat.id == chat_id)
        .values(last_sequence=Chat.last_sequence + 1, updated_at=now)
        .returning(Chat.last_sequence)
    )
    if sequence is None:
        raise ProblemError(CHAT_NOT_FOUND)
    message_id = uuid7()
    claimed = await session.scalar(
        insert(ChatMessageDedup)
        .values(
            chat_id=chat_id,
            client_id=client_id,
            sender_id=sender_id,
            sequence=sequence,
            message_id=message_id,
            message_created_at=now,
            content_hash=digest,
            created_at=now,
        )
        .on_conflict_do_nothing()
        .returning(ChatMessageDedup.client_id)
    )
    if claimed is None:
        # Another sender used the same UUID in this chat; the order number
        # taken above stays unused, which is a gap, not a duplicate.
        stored = await session.scalar(
            select(ChatMessageDedup).where(
                ChatMessageDedup.chat_id == chat_id,
                ChatMessageDedup.client_id == client_id,
            )
        )
        if (
            stored is not None
            and stored.sender_id == sender_id
            and stored.content_hash == digest
        ):
            return await stored_message(session, stored), False
        raise ProblemError(CHAT_MESSAGE_CONFLICT)
    message = ChatMessage(
        id=message_id,
        chat_id=chat_id,
        sender_id=sender_id,
        client_id=client_id,
        sequence=sequence,
        text=text,
        created_at=now,
    )
    session.add(message)
    add_message(session, MESSAGE_TOPIC, message_payload(message))
    return message, True
