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
from collections.abc import Sequence
from typing import Any, cast
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
    ChatMessageArchive,
    ChatMessageDedup,
    ChatMessageHistory,
    ChatMessageSnapshot,
    ChatMessageSnapshotPhoto,
    ChatMessageVersion,
)
from campus.modules.files import File
from campus.modules.identity import User, serialize_contact_pair
from campus.modules.listings import (
    RELATED_INTERACTION_STATUSES,
    Interaction,
    Listing,
    can_contact,
    readable,
)
from campus.modules.realtime import grant_chat_access, revoke_chat_access
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
    N_("Personal messaging with this user is not available."),
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

CHAT_MESSAGE_DELETED = ProblemType(
    "chat_message_deleted",
    409,
    N_("The message is deleted."),
    N_("A deleted message cannot be edited."),
)
CHAT_PHOTO_INVALID = ProblemType(
    "chat_photo_invalid",
    422,
    N_("Invalid chat photo."),
    N_("A photo must be ready, belong to this chat and not be attached yet."),
)
CHAT_PHOTO_EXPIRED = ProblemType(
    "chat_photo_expired",
    409,
    N_("The photo upload expired."),
    N_("Request a new chat photo upload."),
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


StoredMessage = ChatMessage | ChatMessageArchive


def message_payload(
    message: StoredMessage, *, action: str = "created"
) -> dict[str, Any]:
    """Realtime wakeup for a stored message; clients load history through the API.

    The payload deliberately carries identifiers only. A queued edit or
    delete must not publish text that the API has already hidden, and an
    outbox row must not become a copy of a version that expires after the
    retention window.
    """
    return {
        "action": action,
        "chat_id": str(message.chat_id),
        "message_id": str(message.id),
        "client_id": str(message.client_id),
        "sender_id": str(message.sender_id),
        "sequence": message.sequence,
        "reply_to_id": str(message.reply_to_id) if message.reply_to_id else None,
        "version": message.version,
        "created_at": message.created_at.isoformat(),
    }


async def stored_message_by_id(
    session: AsyncSession, message_id: UUID
) -> StoredMessage | None:
    """Load a message from the active or archive partition, without a lock."""
    for model in (ChatMessage, ChatMessageArchive):
        message = await session.scalar(select(model).where(model.id == message_id))
        if message is not None:
            return cast(StoredMessage, message)
    return None


async def locked_stored_message(
    session: AsyncSession, message_id: UUID
) -> StoredMessage | None:
    """Lock the message row, whichever partition currently stores it."""
    for model in (ChatMessage, ChatMessageArchive):
        message = await session.scalar(
            select(model).where(model.id == message_id).with_for_update()
        )
        if message is not None:
            return cast(StoredMessage, message)
    return None


async def visible_message(
    session: AsyncSession, chat_id: UUID, message_id: UUID
) -> ChatMessageHistory | None:
    """A message the chat may quote: not deleted and in this chat."""
    return await session.scalar(
        select(ChatMessageHistory).where(
            ChatMessageHistory.id == message_id,
            ChatMessageHistory.chat_id == chat_id,
            ChatMessageHistory.deleted_at.is_(None),
        )
    )


async def message_photos(
    session: AsyncSession,
    message_id: UUID,
    *,
    for_evidence: bool = False,
    for_share: bool = False,
) -> list[File]:
    """Ready photos of a message in display order.

    ``for_evidence`` is used only by the member-scoped complaint evidence
    endpoint: ordinary history calls it with ``False`` and callers never see
    photos of a deleted message. ``for_share`` makes the snapshot copy wait
    for a concurrent purge instead of recording keys of deleted objects.
    """
    query = select(File).where(
        File.message_id == message_id,
        File.status == "ready",
    )
    if not for_evidence:
        query = query.join(
            ChatMessageHistory, ChatMessageHistory.id == File.message_id
        ).where(ChatMessageHistory.deleted_at.is_(None))
    if for_share:
        query = query.with_for_update(read=True, of=File)
    return list(await session.scalars(query.order_by(File.message_position, File.id)))


async def lock_message_photos(
    session: AsyncSession, chat_id: UUID, owner_id: UUID, photo_ids: Sequence[UUID]
) -> list[File]:
    """Validate and lock chat photos for a new message."""
    if not photo_ids:
        return []
    if len(set(photo_ids)) != len(photo_ids):
        raise ProblemError(CHAT_PHOTO_INVALID)
    files = list(
        await session.scalars(
            select(File)
            .where(File.id.in_(photo_ids))
            .order_by(File.id)
            .with_for_update()
        )
    )
    now = clock.now()
    if len(files) != len(photo_ids):
        raise ProblemError(CHAT_PHOTO_INVALID)
    for file in files:
        if (
            file.owner_id != owner_id
            or file.chat_id != chat_id
            or file.purpose != "chat_photo"
            or file.status != "ready"
            or file.message_id is not None
            or file.expires_at <= now
        ):
            raise ProblemError(CHAT_PHOTO_INVALID)
    # Rows are locked in id order to avoid deadlocks; the caller's order is
    # the display order of the message and survives on the file positions.
    by_id = {file.id: file for file in files}
    return [by_id[photo_id] for photo_id in photo_ids]


def _version_row(
    message: StoredMessage, kind: str, *, now: Any, retention: Any
) -> ChatMessageVersion:
    return ChatMessageVersion(
        chat_id=message.chat_id,
        message_id=message.id,
        version=message.version,
        kind=kind,
        text=message.text,
        created_at=now,
        purge_at=now + retention,
    )


async def require_membership(
    session: AsyncSession, chat_id: UUID, user_id: UUID, *, lock: bool = False
) -> Chat:
    """The chat if ``user_id`` is an active member; otherwise hide it with 404.

    ``lock`` serializes a send with leaving and retention cleanup: the chat
    row is locked before the membership is checked, so a member cannot send
    after their leave transaction commits. No role grants access to somebody
    else's chat: moderators and administrators use the separate complaint and
    dispute entry points.
    """
    query = (
        select(Chat)
        .join(ChatMember, ChatMember.chat_id == Chat.id)
        .where(
            Chat.id == chat_id,
            ChatMember.user_id == user_id,
            ChatMember.left_at.is_(None),
        )
    )
    if lock:
        query = query.with_for_update(of=Chat)
    chat = await session.scalar(query)
    if chat is None:
        raise ProblemError(CHAT_NOT_FOUND)
    return chat


async def find_pair_chat(  # noqa: PLR0913
    session: AsyncSession,
    low: UUID,
    high: UUID,
    listing_id: UUID | None,
    interaction_id: UUID | None,
    *,
    lock: bool = False,
) -> Chat | None:
    """The chat that already represents this pair and link, if any.

    ``lock`` waits for a concurrent leave or retention cleanup of this chat;
    if the cleanup won, the lookup returns no row and creation starts a new
    dialog instead of resurrecting a deleted one.
    """
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
    if lock:
        query = query.with_for_update(of=Chat)
    return await session.scalar(query)


async def active_members(session: AsyncSession, chat_id: UUID) -> list[ChatMember]:
    """Memberships that still grant access, with their rows locked."""
    return list(
        await session.scalars(
            select(ChatMember)
            .where(ChatMember.chat_id == chat_id, ChatMember.left_at.is_(None))
            .with_for_update()
        )
    )


async def ensure_member(session: AsyncSession, chat: Chat, user_id: UUID) -> ChatMember:
    """Make ``user_id`` an active member of ``chat`` and cancel retention.

    The caller holds the chat row lock. An existing left membership keeps its
    row (and the history), only ``left_at`` is cleared and the channel grant
    is activated again. The empty-chat clock is cleared for both a new and a
    returning member.
    """
    member = await session.get(ChatMember, (chat.id, user_id), with_for_update=True)
    if member is None:
        member = ChatMember(chat_id=chat.id, user_id=user_id, joined_at=clock.now())
        session.add(member)
    else:
        member.left_at = None
    chat.empty_since = None
    await grant_chat_access(session, chat.id, user_id)
    return member


async def leave_chat(session: AsyncSession, chat_id: UUID, user_id: UUID) -> bool:
    """Leave a chat; the last active member starts the retention clock.

    The membership row stays, so the same dialog and its history are
    restored by a later creation. Repeating the request is a no-op and
    returns ``False``. A user without any membership row gets 404.
    """
    chat = await session.scalar(
        select(Chat).where(Chat.id == chat_id).with_for_update(of=Chat)
    )
    member = await session.scalar(
        select(ChatMember)
        .where(ChatMember.chat_id == chat_id, ChatMember.user_id == user_id)
        .with_for_update()
    )
    if chat is None or member is None:
        raise ProblemError(CHAT_NOT_FOUND)
    if member.left_at is not None:
        return False
    now = clock.now()
    member.left_at = now
    await revoke_chat_access(session, chat_id, user_id)
    remaining = await session.scalar(
        select(func.count())
        .select_from(ChatMember)
        .where(ChatMember.chat_id == chat_id, ChatMember.left_at.is_(None))
    )
    if not remaining:
        chat.empty_since = now
    chat.updated_at = now
    return True


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
    for the two parties of that interaction. A listing chat additionally
    needs the recipient to be the author or a participant with a started
    interaction, so an arbitrary third user cannot be attached to a listing.
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
        if interaction.status not in RELATED_INTERACTION_STATUSES:
            raise ProblemError(NOT_FOUND)
        if listing_id is not None and listing_id != interaction.listing_id:
            raise ProblemError(CHAT_LINK_INVALID)
        return interaction.listing_id
    if listing_id is not None:
        listing = await readable(session, listing_id, creator)
        if listing.author_id == creator.id:
            participant = await session.scalar(
                select(Interaction.id)
                .where(
                    Interaction.listing_id == listing.id,
                    Interaction.participant_id == recipient_id,
                    Interaction.status.in_(RELATED_INTERACTION_STATUSES),
                )
                .limit(1)
            )
            if participant is None:
                raise ProblemError(NOT_FOUND)
        elif recipient_id != listing.author_id:
            raise ProblemError(NOT_FOUND)
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
    await serialize_contact_pair(session, creator_id, recipient_id)
    if not await can_contact(
        session,
        creator_id,
        recipient_id,
        linked=interaction_id is not None or linked_listing_id is not None,
    ):
        raise ProblemError(CHAT_FORBIDDEN)
    low, high = canonical_pair(creator_id, recipient_id)
    existing = await find_pair_chat(
        session, low, high, linked_listing_id, interaction_id, lock=True
    )
    if existing is not None:
        await ensure_member(session, existing, creator_id)
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
            session, low, high, linked_listing_id, interaction_id, lock=True
        )
        if stored is None:  # pragma: no cover - the unique index guarantees it
            msg = "the conflicting chat is not visible"
            raise RuntimeError(msg)
        await ensure_member(session, stored, creator_id)
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
        .select_from(ChatMessageHistory)
        .where(
            ChatMessageHistory.sender_id == sender_id,
            ChatMessageHistory.created_at > window_start,
        )
    )
    if sent is None or sent < settings.chat_message_limit:
        return
    oldest = await session.scalar(
        select(func.min(ChatMessageHistory.created_at)).where(
            ChatMessageHistory.sender_id == sender_id,
            ChatMessageHistory.created_at > window_start,
        )
    )
    retry = 1
    if oldest is not None:
        retry = max(
            1,
            math.ceil((oldest + settings.chat_message_window - now).total_seconds()),
        )
    raise ProblemError(CHAT_RATE_LIMITED, headers={"Retry-After": str(retry)})


async def stored_message(
    session: AsyncSession, dedup: ChatMessageDedup
) -> ChatMessageHistory:
    """Load the message recorded by ``dedup``, active or archived.

    The union view makes the replay of an old client UUID independent of the
    partition that currently stores the row.
    """
    message = await session.scalar(
        select(ChatMessageHistory).where(
            ChatMessageHistory.id == dedup.message_id,
            ChatMessageHistory.created_at == dedup.message_created_at,
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
    reply_to_id: UUID | None = None,
    photo_ids: Sequence[UUID] | None = None,
) -> tuple[ChatMessage | ChatMessageHistory, bool]:
    """Store a message once, deduplicated by its client identifier.

    The second result is ``False`` for a repeat of the same client UUID and
    content: the stored message is returned, no new order number is taken
    and the outbox gets no new publication.

    Read the chat without its row lock, take the pair lock, and only then
    take the chat lock. Creation uses the same order, so a concurrent
    message and create cannot wait on each other's locks.
    """
    chat = await require_membership(session, chat_id, sender_id)
    # A personal block changes only a personal dialog. A future group chat is
    # shared by both members and keeps their messages visible, as the
    # specification requires, so it is not filtered by the pair policy.
    if chat.kind == PERSONAL_KIND:
        recipient_id = (
            chat.user_high_id if chat.user_low_id == sender_id else chat.user_low_id
        )
        await serialize_contact_pair(session, sender_id, recipient_id)
        # Recheck membership under the row lock: a concurrent leave may have
        # committed while this request waited for the pair.
        chat = await require_membership(session, chat_id, sender_id, lock=True)
        if not await can_contact(
            session,
            sender_id,
            recipient_id,
            linked=chat.listing_id is not None or chat.interaction_id is not None,
        ):
            raise ProblemError(CHAT_FORBIDDEN)
    else:
        chat = await require_membership(session, chat_id, sender_id, lock=True)
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
    if (
        reply_to_id is not None
        and await visible_message(session, chat_id, reply_to_id) is None
    ):
        raise ProblemError(NOT_FOUND)
    photo_ids = list(photo_ids or [])
    if len(photo_ids) > settings.chat_photo_limit:
        raise ProblemError(CHAT_PHOTO_INVALID)
    photos = await lock_message_photos(session, chat_id, sender_id, photo_ids)
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
        reply_to_id=reply_to_id,
        version=1,
        created_at=now,
    )
    session.add(message)
    for position, file in enumerate(photos):
        file.message_id = message.id
        file.message_position = position
    add_message(session, MESSAGE_TOPIC, message_payload(message))
    return message, True


async def edit_message(  # noqa: PLR0913 - message fields
    session: AsyncSession,
    *,
    chat_id: UUID,
    message_id: UUID,
    editor_id: UUID,
    text: str,
    settings: Settings,
) -> tuple[StoredMessage, bool]:
    """Edit the author's message and keep the previous text hidden.

    The message row is locked, so concurrent edits and a delete serialize:
    every change stores the text it replaced and no revision is lost. A
    repeated edit with the same text is a no-op; editing a deleted message
    is a conflict.
    """
    message = await locked_stored_message(session, message_id)
    if message is None or message.chat_id != chat_id:
        raise ProblemError(NOT_FOUND)
    await require_membership(session, chat_id, editor_id)
    if message.sender_id != editor_id:
        raise ProblemError(NOT_FOUND)
    if message.deleted_at is not None:
        raise ProblemError(CHAT_MESSAGE_DELETED)
    if not text.strip() or len(text) > settings.chat_message_max_length:
        raise ProblemError(CHAT_MESSAGE_INVALID)
    if text == message.text:
        return message, False
    now = clock.now()
    session.add(
        _version_row(
            message,
            "edit",
            now=now,
            retention=settings.chat_message_version_retention,
        )
    )
    message.text = text
    message.version += 1
    add_message(session, MESSAGE_TOPIC, message_payload(message, action="edited"))
    return message, True


async def delete_message(
    session: AsyncSession,
    *,
    chat_id: UUID,
    message_id: UUID,
    author_id: UUID,
    settings: Settings,
) -> bool:
    """Hide the author's message and keep its text as a 30-day revision.

    The base row stops carrying the text immediately: the space is a
    non-empty placeholder required by the table constraint, is not indexed
    by full-text search and is never returned by the history API. The
    hidden revision remains available only through complaint evidence.
    """
    message = await locked_stored_message(session, message_id)
    if message is None or message.chat_id != chat_id:
        raise ProblemError(NOT_FOUND)
    await require_membership(session, chat_id, author_id)
    if message.sender_id != author_id:
        raise ProblemError(NOT_FOUND)
    if message.deleted_at is not None:
        return False
    now = clock.now()
    session.add(
        _version_row(
            message,
            "delete",
            now=now,
            retention=settings.chat_message_version_retention,
        )
    )
    message.text = " "
    message.deleted_at = now
    message.version += 1
    add_message(session, MESSAGE_TOPIC, message_payload(message, action="deleted"))
    return True


async def message_evidence(
    session: AsyncSession, *, chat_id: UUID, message_id: UUID
) -> tuple[StoredMessage, list[ChatMessageVersion], list[File]] | None:
    """Hidden revisions and photos available to a complaint within 30 days."""
    message = await stored_message_by_id(session, message_id)
    if message is None or message.chat_id != chat_id:
        return None
    now = clock.now()
    versions = list(
        await session.scalars(
            select(ChatMessageVersion)
            .where(
                ChatMessageVersion.message_id == message_id,
                ChatMessageVersion.purge_at > now,
            )
            .order_by(ChatMessageVersion.version)
        )
    )
    photos = await message_photos(session, message_id, for_evidence=True)
    return message, versions, photos


async def snapshot_message(
    session: AsyncSession,
    *,
    complaint_id: UUID,
    message_id: UUID,
    version: int | None = None,
    settings: Settings,
) -> ChatMessageSnapshot:
    """Copy a message and its photos into an immutable complaint attachment.

    The copy has no foreign keys to the chat, the message or the sender, so
    deleting the chat later does not erase the evidence. A deleted message
    is captured only while its hidden revision is inside the retention
    window: after the boundary the text is erased even if the cleanup job
    has not run yet.

    ``version`` selects one revision returned by :func:`message_evidence`
    instead of the current text. The revision must still be inside its own
    retention window; an already purged revision is refused. Repeating the
    capture for the same complaint and message returns the first snapshot,
    whose ``version`` reports the revision actually preserved.
    """
    snapshot = await session.scalar(
        select(ChatMessageSnapshot).where(
            ChatMessageSnapshot.complaint_id == complaint_id,
            ChatMessageSnapshot.message_id == message_id,
        )
    )
    if snapshot is not None:
        return snapshot
    message = await session.scalar(
        select(ChatMessageHistory).where(ChatMessageHistory.id == message_id)
    )
    if message is None:
        raise ProblemError(NOT_FOUND)
    now = clock.now()
    if (
        message.deleted_at is not None
        and message.deleted_at <= now - settings.chat_message_version_retention
    ):
        # The boundary applies to every capture of a deleted message, not
        # only to the default current-text path.
        raise ProblemError(NOT_FOUND)
    text, captured_version = message.text, message.version
    if version is not None:
        revision = await session.scalar(
            select(ChatMessageVersion).where(
                ChatMessageVersion.message_id == message_id,
                ChatMessageVersion.chat_id == message.chat_id,
                ChatMessageVersion.version == version,
                ChatMessageVersion.purge_at > now,
            )
        )
        if revision is not None:
            text, captured_version = revision.text, revision.version
        elif version != message.version or message.deleted_at is not None:
            # A visible current revision has no hidden row; a deleted
            # message always has a deletion revision until it expires.
            raise ProblemError(NOT_FOUND)
    elif message.deleted_at is not None:
        # A complaint filed after deletion must capture the hidden deletion
        # revision, not the placeholder left in the base row.
        hidden = await session.scalar(
            select(ChatMessageVersion)
            .where(
                ChatMessageVersion.message_id == message_id,
                ChatMessageVersion.purge_at > now,
            )
            .order_by(ChatMessageVersion.version.desc())
            .limit(1)
        )
        if hidden is None:
            raise ProblemError(NOT_FOUND)
        text, captured_version = hidden.text, hidden.version
    snapshot = ChatMessageSnapshot(
        complaint_id=complaint_id,
        chat_id=message.chat_id,
        message_id=message.id,
        sender_id=message.sender_id,
        sequence=message.sequence,
        text=text,
        version=captured_version,
        message_created_at=message.created_at,
        captured_at=now,
    )
    session.add(snapshot)
    await session.flush()
    photos = await message_photos(
        session, message_id, for_evidence=True, for_share=True
    )
    for position, file in enumerate(photos):
        session.add(
            ChatMessageSnapshotPhoto(
                snapshot_id=snapshot.id,
                file_id=file.id,
                key=file.key,
                size=file.size,
                position=position,
            )
        )
    await session.flush()
    return snapshot


async def snapshot_photos(
    session: AsyncSession, snapshot_id: UUID
) -> list[ChatMessageSnapshotPhoto]:
    """Processed photo objects copied into one complaint attachment."""
    return list(
        await session.scalars(
            select(ChatMessageSnapshotPhoto)
            .where(ChatMessageSnapshotPhoto.snapshot_id == snapshot_id)
            .order_by(ChatMessageSnapshotPhoto.position, ChatMessageSnapshotPhoto.id)
        )
    )
