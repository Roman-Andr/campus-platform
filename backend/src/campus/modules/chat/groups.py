"""Group chats of events and purchases; membership follows the domain state.

A listing owns one group chat, created by the first accepted participation.
The membership is a projection of the domain: the organiser of the listing
and every participant whose interaction is accepted right now. The projector
re-reads that state in the transaction that changes it, so a repeated or
delayed call converges to the same rows and can never re-add a participant
whose acceptance was already cancelled. The chat and its channel grants are
written in that same transaction; a rollback leaves neither.

The projector takes the listing row lock from its caller, like every other
mutation of the listing aggregate. Two first acceptances of one listing are
therefore serialized, and the partial unique index on the group listing backs
the same rule up for any caller that races without the lock.
"""

from uuid import UUID

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from campus.core import clock
from campus.modules.chat.models import (
    GROUP_CHAT_KINDS,
    GROUP_CHATS,
    Chat,
    ChatMember,
)
from campus.modules.listings import Interaction, InteractionStatus, Listing
from campus.modules.realtime import grant_chat_access, revoke_chat_access


async def group_chat_of(
    session: AsyncSession, listing_id: UUID, *, lock: bool = False
) -> Chat | None:
    """The group chat of a listing, if it has already been created."""
    query = select(Chat).where(
        Chat.kind.in_(GROUP_CHATS),
        Chat.listing_id == listing_id,
    )
    if lock:
        query = query.with_for_update(of=Chat)
    return await session.scalar(query)


async def group_member_ids(session: AsyncSession, listing: Listing) -> set[UUID]:
    """The organiser and every accepted participant of the listing now."""
    participants = await session.scalars(
        select(Interaction.participant_id).where(
            Interaction.listing_id == listing.id,
            Interaction.status == InteractionStatus.ACCEPTED,
        )
    )
    return {listing.author_id, *participants}


async def ensure_group_chat(session: AsyncSession, listing: Listing) -> Chat:
    """The group chat of ``listing``, created once even under a race.

    The partial unique index decides the race: the losing insert returns no
    row and the stored chat is locked and returned instead. The caller holds
    the listing lock, so this path is reached only by a caller outside the
    normal transaction order (a retried job or a direct service call).
    """
    existing = await group_chat_of(session, listing.id, lock=True)
    if existing is not None:
        return existing
    now = clock.now()
    created_id = await session.scalar(
        insert(Chat)
        .values(
            kind=listing.kind,
            user_low_id=None,
            user_high_id=None,
            listing_id=listing.id,
            interaction_id=None,
            last_sequence=0,
            created_at=now,
            updated_at=now,
        )
        .on_conflict_do_nothing()
        .returning(Chat.id)
    )
    if created_id is not None:
        return await session.get_one(Chat, created_id)
    stored = await group_chat_of(session, listing.id, lock=True)
    if stored is None:  # pragma: no cover - the unique index guarantees it
        message = "the conflicting group chat is not visible"
        raise RuntimeError(message)
    return stored


async def sync_group_chat(session: AsyncSession, listing: Listing) -> Chat | None:
    """Make the group chat membership equal to the current domain state.

    Every active participant is a member with an active realtime grant, every
    other membership is closed and its grant is revoked in the same
    transaction. A repeated call changes nothing, and a group chat is never
    created for a listing kind that has none.
    """
    if listing.kind not in GROUP_CHAT_KINDS:
        return None
    chat = await ensure_group_chat(session, listing)
    desired = await group_member_ids(session, listing)
    members = {
        member.user_id: member
        for member in await session.scalars(
            select(ChatMember)
            .where(ChatMember.chat_id == chat.id)
            .order_by(ChatMember.user_id)
            .with_for_update()
        )
    }
    now = clock.now()
    for user_id in sorted(desired, key=str):
        member = members.get(user_id)
        if member is None:
            session.add(ChatMember(chat_id=chat.id, user_id=user_id, joined_at=now))
        elif member.left_at is not None:
            member.left_at = None
            member.joined_at = now
        # A grant can be missing after an older deployment or a lost
        # projection; the live domain state repairs it here.
        await grant_chat_access(session, chat.id, user_id)
    for user_id, member in members.items():
        if user_id in desired or member.left_at is not None:
            continue
        member.left_at = now
        await revoke_chat_access(session, chat.id, user_id)
    chat.empty_since = None if desired else now
    chat.updated_at = now
    await session.flush()
    return chat


async def organizer_id(session: AsyncSession, chat: Chat) -> UUID | None:
    """The organiser of a group chat; ``None`` for a personal dialog."""
    if chat.kind not in GROUP_CHATS or chat.listing_id is None:
        return None
    return await session.scalar(
        select(Listing.author_id).where(Listing.id == chat.listing_id)
    )
