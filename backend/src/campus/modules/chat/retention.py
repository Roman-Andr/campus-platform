"""Archiving of old messages and cleanup of empty chats (specification, 5.3.2).

Run by the cleanup task (``CAMPUS_CLEANUP_CRON``). Two independent jobs
share this module:

- Messages older than ``chat_message_archive_after`` are moved out of the
  active partitioned table into the yearly ``chat_message_archive``
  partitions. The row keeps its id, client UUID and server sequence; the
  ``chat_message_history`` view serves both tables, so history and a future
  search still see one logical history. A move deletes and re-inserts the row
  in one transaction; an active sender never writes a row older than the
  cutoff (the API takes ``created_at`` from the clock), and ``SKIP LOCKED``
  makes concurrent archive runs disjoint.
- A chat whose last active member left is deleted with its photos after
  ``chat_retention``. A new membership clears ``empty_since`` and cancels the
  cleanup. The chat row is locked with ``SKIP LOCKED``; the cleanup rechecks
  active memberships under the lock, so a rejoin either commits before the
  check and wins, or waits until the chat is gone and creates a new chat.
  Photos are deleted from S3 before their rows and the chat are committed.
  Missing objects are allowed; a storage failure rolls the chat back for the
  next run. The report contains counts and per-chat failures only.

Complaint snapshots live in ``chat_message_snapshot`` without foreign keys
to the chat, so deleting a chat never deletes evidence of a complaint.
Copied photos keep their processed objects in S3: the cleanup deletes the
``file`` row and the original source but never the ``/photo`` and
``/preview`` objects referenced by ``chat_message_snapshot_photo``.
"""

from datetime import datetime
from uuid import UUID

import structlog
from sqlalchemy import delete, select, text, tuple_
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from campus.core import clock
from campus.core.config import Settings
from campus.core.storage import Storage, storage_io
from campus.core.tasks import register_cleanup
from campus.modules.chat.models import (
    Chat,
    ChatMember,
    ChatMessageHistory,
    ChatMessageSnapshotPhoto,
)
from campus.modules.files import File
from campus.modules.realtime import revoke_chat_access

logger = structlog.get_logger(__name__)

# Explicit columns keep the move stable when either table gains a column.
_ARCHIVE_SQL = text(
    """
    WITH due AS (
        SELECT id, created_at
        FROM chat_message
        WHERE created_at < :cutoff
        ORDER BY created_at, id
        LIMIT :batch
        FOR UPDATE SKIP LOCKED
    ),
    moved AS (
        DELETE FROM chat_message message
        USING due
        WHERE message.id = due.id
          AND message.created_at = due.created_at
        RETURNING message.id, message.chat_id, message.sender_id,
                  message.client_id, message.sequence, message.text,
                  message.reply_to_id, message.version, message.deleted_at,
                  message.created_at
    )
    INSERT INTO chat_message_archive
        (id, chat_id, sender_id, client_id, sequence, text, reply_to_id,
         version, deleted_at, created_at)
    SELECT id, chat_id, sender_id, client_id, sequence, text, reply_to_id,
           version, deleted_at, created_at
    FROM moved
    ON CONFLICT (id, created_at) DO NOTHING
    RETURNING id
    """
)

_EVIDENCE_SUFFIXES = ("/photo", "/preview")


async def _snapshot_protected_file_ids(
    session: AsyncSession, files: list[File]
) -> set[UUID]:
    """Files whose processed objects belong to a complaint attachment."""
    ids = [file.id for file in files]
    if not ids:
        return set()
    return set(
        await session.scalars(
            select(ChatMessageSnapshotPhoto.file_id).where(
                ChatMessageSnapshotPhoto.file_id.in_(ids)
            )
        )
    )


async def _delete_file_objects(
    storage: Storage, file: File, *, keep_evidence: bool
) -> None:
    """Delete the original source; processed objects may be case evidence."""
    await storage_io(storage.delete, file.key + "/source")
    if keep_evidence:
        return
    for suffix in _EVIDENCE_SUFFIXES:
        await storage_io(storage.delete, file.key + suffix)


async def archive_messages(
    sessions: async_sessionmaker[AsyncSession], settings: Settings
) -> dict[str, int]:
    """Move due messages to archive partitions in bounded transactions."""
    cutoff = clock.now() - settings.chat_message_archive_after
    report = {"archived": 0, "batches": 0, "failed": 0}
    while report["archived"] < settings.chat_message_archive_limit:
        batch = min(
            settings.chat_message_archive_batch,
            settings.chat_message_archive_limit - report["archived"],
        )
        try:
            async with sessions() as db, db.begin():
                moved = list(
                    await db.scalars(
                        _ARCHIVE_SQL,
                        {"cutoff": cutoff, "batch": batch},
                    )
                )
        except Exception as error:
            report["failed"] += 1
            logger.warning(
                "chat_archive_failed",
                error=type(error).__name__,
            )
            break
        if not moved:
            break
        report["archived"] += len(moved)
        report["batches"] += 1
    return report


async def _purge_chat(
    session: AsyncSession,
    chat_id: UUID,
    cutoff: datetime,
    settings: Settings,
) -> int | None:
    """Delete one due chat; ``None`` if it was re-joined or already gone."""
    chat = await session.scalar(
        select(Chat)
        .where(Chat.id == chat_id, Chat.empty_since <= cutoff)
        .with_for_update(of=Chat, skip_locked=True)
    )
    if chat is None:
        return None
    members = list(
        await session.scalars(
            select(ChatMember)
            .where(ChatMember.chat_id == chat.id)
            .order_by(ChatMember.user_id)
            .with_for_update()
        )
    )
    if any(member.left_at is None for member in members):
        # A rejoin may attach a member without clearing empty_since (for
        # example a future import); keep the chat and repair the marker.
        chat.empty_since = None
        return None
    for member in members:
        await revoke_chat_access(session, chat.id, member.user_id)
    files = list(
        await session.scalars(
            select(File)
            .where(File.chat_id == chat.id)
            .order_by(File.id)
            .with_for_update()
        )
    )
    if files:
        protected = await _snapshot_protected_file_ids(session, files)
        storage = Storage(settings)
        for file in files:
            await _delete_file_objects(
                storage,
                file,
                keep_evidence=file.id in protected,
            )
        for file in files:
            await session.delete(file)
        # File has no relationship object, so make the FK order explicit:
        # the chat cannot be deleted while a chat photo row still points at it.
        await session.flush()
    await session.delete(chat)
    return len(files)


async def purge_empty_chats(
    sessions: async_sessionmaker[AsyncSession], settings: Settings
) -> dict[str, int]:
    """Delete chats that have been empty for the retention period."""
    cutoff = clock.now() - settings.chat_retention
    report = {"chats": 0, "files": 0, "skipped": 0, "failed": 0}
    after: tuple[datetime, UUID] | None = None
    seen = 0
    while seen < settings.chat_cleanup_limit:
        query = (
            select(Chat.empty_since, Chat.id)
            .where(Chat.empty_since.is_not(None), Chat.empty_since <= cutoff)
            .order_by(Chat.empty_since, Chat.id)
            .limit(
                min(
                    settings.chat_cleanup_batch,
                    settings.chat_cleanup_limit - seen,
                )
            )
        )
        if after is not None:
            query = query.where(tuple_(Chat.empty_since, Chat.id) > after)
        async with sessions() as db:
            batch = [(row.empty_since, row.id) for row in await db.execute(query)]
        if not batch:
            break
        seen += len(batch)
        after = batch[-1]
        for _, chat_id in batch:
            try:
                async with sessions() as db, db.begin():
                    files = await _purge_chat(db, chat_id, cutoff, settings)
            except Exception as error:
                report["failed"] += 1
                logger.warning(
                    "chat_purge_failed",
                    chat_id=str(chat_id),
                    error=type(error).__name__,
                )
                continue
            if files is None:
                report["skipped"] += 1
                continue
            report["chats"] += 1
            report["files"] += files
    return report


@register_cleanup("chat_messages")
async def cleanup_chat_messages(
    sessions: async_sessionmaker[AsyncSession], settings: Settings
) -> dict[str, int]:
    """Registered archive job; a database failure is reported, not hidden."""
    return await archive_messages(sessions, settings)


async def purge_message_versions(
    sessions: async_sessionmaker[AsyncSession], settings: Settings
) -> dict[str, int]:
    """Erase hidden revisions and unprotected photos after 30 days.

    Files go first: deleting a revision is cheap and idempotent, while a
    storage failure must leave the revision in place so the next run can
    still find and delete the object. A photo copied into a complaint
    snapshot loses its file row and original source but keeps the processed
    objects the case still refers to.
    """
    cutoff = clock.now() - settings.chat_message_version_retention
    report = {"versions": 0, "files": 0, "protected": 0, "batches": 0, "failed": 0}
    while report["versions"] < settings.chat_message_version_cleanup_limit:
        batch = min(
            settings.chat_message_version_cleanup_batch,
            settings.chat_message_version_cleanup_limit - report["versions"],
        )
        try:
            async with sessions() as db, db.begin():
                files = list(
                    await db.scalars(
                        select(File)
                        .join(
                            ChatMessageHistory,
                            ChatMessageHistory.id == File.message_id,
                        )
                        .where(
                            File.message_id.is_not(None),
                            ChatMessageHistory.deleted_at.is_not(None),
                            ChatMessageHistory.deleted_at <= cutoff,
                        )
                        .order_by(File.id)
                        .limit(batch)
                        .with_for_update(of=File, skip_locked=True)
                    )
                )
                if files:
                    protected = await _snapshot_protected_file_ids(db, files)
                    storage = Storage(settings)
                    for file in files:
                        await _delete_file_objects(
                            storage,
                            file,
                            keep_evidence=file.id in protected,
                        )
                    await db.execute(
                        delete(File).where(File.id.in_([file.id for file in files]))
                    )
                    report["files"] += len(files)
                    report["protected"] += len(protected)
                purged = await db.scalars(
                    text(
                        """
                        DELETE FROM chat_message_version
                        WHERE id IN (
                            SELECT id FROM chat_message_version
                            WHERE purge_at <= :now
                            ORDER BY purge_at, id
                            LIMIT :batch
                            FOR UPDATE SKIP LOCKED
                        )
                        RETURNING id
                        """
                    ),
                    {"now": clock.now(), "batch": batch},
                )
                count = len(list(purged))
        except Exception as error:
            report["failed"] += 1
            logger.warning(
                "chat_message_version_cleanup_failed",
                error=type(error).__name__,
            )
            break
        if files == [] and count == 0:
            break
        report["versions"] += count
        report["batches"] += 1
    return report


@register_cleanup("chat_message_versions")
async def cleanup_message_versions(
    sessions: async_sessionmaker[AsyncSession], settings: Settings
) -> dict[str, int]:
    """Registered 30-day hidden-message cleanup."""
    return await purge_message_versions(sessions, settings)


@register_cleanup("chat_retention")
async def cleanup_empty_chats(
    sessions: async_sessionmaker[AsyncSession], settings: Settings
) -> dict[str, int]:
    """Registered empty-chat cleanup; a failed chat is retried next run."""
    return await purge_empty_chats(sessions, settings)
