"""Personal chats, their membership and reliably delivered messages.

A personal chat is the only chat kind of this slice: two members and one
stable pair key, so the database itself keeps one direct chat per pair and
one chat per listing pair or interaction.

Messages are partitioned by creation time (specification, 5.5.1: a year of
messages is about 100 million rows). PostgreSQL requires the partition key
in every unique index of a partitioned table, so the two invariants that
span the whole history live in :class:`ChatMessageDedup`, a small
non-partitioned table written in the same transaction:

- a client-generated message UUID is stored once per chat, forever, not
  only for the retention of an ``Idempotency-Key``;
- the server sequence number is unique inside a chat.

The message row repeats the client UUID and the sequence for reads, while
the dedup table is the authority for both constraints.
"""

from datetime import datetime
from typing import Any
from uuid import UUID

from sqlalchemy import (
    BigInteger,
    CheckConstraint,
    Computed,
    ForeignKey,
    Index,
    PrimaryKeyConstraint,
    String,
    Text,
    UniqueConstraint,
    func,
    text,
)
from sqlalchemy.dialects.postgresql import TSVECTOR
from sqlalchemy.orm import Mapped, mapped_column

from campus.core import clock
from campus.core.db import Base, Entity

PERSONAL_KIND = "personal"
GROUP_CHAT_KINDS = ("event", "purchase")
GROUP_CHATS = frozenset(GROUP_CHAT_KINDS)


class Chat(Entity):
    """A chat: a personal dialog or the group of an event or a purchase.

    A personal chat has two members ordered canonically in ``user_low_id``
    and ``user_high_id``, so the partial unique indexes cannot be fooled by
    reversed arguments. A group chat has no pair: it names the listing that
    owns it, and one listing has one group chat. Its members are the
    organiser and the participants whose interaction is accepted; the chat
    domain re-derives them from that state instead of trusting an event.

    The ``last_sequence`` counter is incremented under the row lock of the
    same transaction that stores a message: concurrent sends of one chat are
    therefore committed in sequence order, and the number, not the device
    time, defines the order clients see.
    """

    __tablename__ = "chat"
    __table_args__ = (
        CheckConstraint("kind IN ('personal','event','purchase')", name="kind"),
        CheckConstraint(
            "(kind = 'personal' AND user_low_id IS NOT NULL "
            "AND user_high_id IS NOT NULL AND user_low_id <> user_high_id) OR "
            "(kind IN ('event','purchase') AND user_low_id IS NULL "
            "AND user_high_id IS NULL)",
            name="members_by_kind",
        ),
        CheckConstraint(
            "(kind IN ('event','purchase') AND listing_id IS NOT NULL "
            "AND interaction_id IS NULL) OR kind = 'personal'",
            name="group_listing",
        ),
        CheckConstraint("last_sequence >= 0", name="last_sequence_non_negative"),
        Index(
            "ix_chat_empty_since",
            "empty_since",
            postgresql_where=text("empty_since IS NOT NULL"),
        ),
        Index(
            "uq_chat_direct_pair",
            "user_low_id",
            "user_high_id",
            unique=True,
            postgresql_where=text("listing_id IS NULL AND interaction_id IS NULL"),
        ),
        Index(
            "uq_chat_listing_pair",
            "listing_id",
            "user_low_id",
            "user_high_id",
            unique=True,
            postgresql_where=text("listing_id IS NOT NULL AND interaction_id IS NULL"),
        ),
        Index(
            "uq_chat_interaction",
            "interaction_id",
            unique=True,
            postgresql_where=text("interaction_id IS NOT NULL"),
        ),
        Index(
            "uq_chat_listing_group",
            "listing_id",
            unique=True,
            postgresql_where=text("kind IN ('event','purchase')"),
        ),
    )

    kind: Mapped[str] = mapped_column(String(16), default=PERSONAL_KIND)
    # The member with the smaller UUID; NULL for a group chat.
    user_low_id: Mapped[UUID | None] = mapped_column(ForeignKey("identity_user.id"))
    user_high_id: Mapped[UUID | None] = mapped_column(ForeignKey("identity_user.id"))
    listing_id: Mapped[UUID | None] = mapped_column(ForeignKey("listing.id"))
    interaction_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("listing_interaction.id")
    )
    last_sequence: Mapped[int] = mapped_column(BigInteger, default=0)
    # When the last active member left; null while somebody is a member.
    empty_since: Mapped[datetime | None]


class ChatMember(Base):
    """Membership of a chat; the source of the realtime channel grant."""

    __tablename__ = "chat_member"
    __table_args__ = (Index("ix_chat_member_user_id", "user_id"),)

    chat_id: Mapped[UUID] = mapped_column(
        ForeignKey("chat.id", ondelete="CASCADE"), primary_key=True
    )
    user_id: Mapped[UUID] = mapped_column(
        ForeignKey("identity_user.id", ondelete="CASCADE"), primary_key=True
    )
    joined_at: Mapped[datetime] = mapped_column(default=clock.now)
    # The member left, but the row is kept so a rejoin restores the same
    # dialog and the retention clock can be cancelled.
    left_at: Mapped[datetime | None]


class ChatMessageDedup(Base):
    """Client UUID and server sequence of a chat, unique for good.

    A repeat of the client UUID with other content is rejected from here.
    The row is written once and never expires, so duplicating a message
    whose ``Idempotency-Key`` has already been deleted is still impossible.
    """

    __tablename__ = "chat_message_dedup"
    __table_args__ = (
        UniqueConstraint(
            "chat_id",
            "sequence",
            name="uq_chat_message_dedup_chat_id_sequence",
        ),
        CheckConstraint("sequence > 0", name="sequence_positive"),
    )

    chat_id: Mapped[UUID] = mapped_column(
        ForeignKey("chat.id", ondelete="CASCADE"), primary_key=True
    )
    client_id: Mapped[UUID] = mapped_column(primary_key=True)
    sender_id: Mapped[UUID] = mapped_column(
        ForeignKey("identity_user.id", ondelete="CASCADE")
    )
    sequence: Mapped[int] = mapped_column(BigInteger)
    message_id: Mapped[UUID]
    message_created_at: Mapped[datetime]
    # SHA-256 of the text; kept as the durable text identity of every row.
    content_hash: Mapped[str] = mapped_column(String(64))
    # Versioned fingerprint of the text hash, the quote and the ordered
    # photos. Migration 56a000000001 backfills it where the metadata is
    # provable; a NULL row fails closed instead of accepting a body whose
    # legacy attachments may have been purged.
    content_fingerprint: Mapped[str | None] = mapped_column(String(64))
    created_at: Mapped[datetime] = mapped_column(default=clock.now)


class ChatMessage(Base):
    """A message of a chat; ranged by ``created_at`` into month partitions.

    The key is ``(id, created_at)`` because PostgreSQL requires the
    partition key in the primary key. Look a message up by id together with
    its creation time, taken from :class:`ChatMessageDedup`.

    ``search_vector`` is maintained by PostgreSQL from the current text, so
    an edit reindexes the message without a worker. The partial GIN index
    covers only messages visible in history; deleting a message removes it
    from both the index and search results. The revision table of #81 is not
    part of this vector, so original versions are never searchable.
    """

    __tablename__ = "chat_message"
    __table_args__ = (
        PrimaryKeyConstraint("id", "created_at", name="pk_chat_message"),
        CheckConstraint("sequence > 0", name="sequence_positive"),
        CheckConstraint("length(text) > 0", name="text_not_empty"),
        Index("ix_chat_message_chat_id_sequence", "chat_id", "sequence"),
        Index(
            "ix_chat_message_search",
            "search_vector",
            postgresql_using="gin",
            postgresql_where=text("deleted_at IS NULL"),
        ),
    )

    id: Mapped[UUID] = mapped_column(server_default=func.uuidv7())
    chat_id: Mapped[UUID] = mapped_column(ForeignKey("chat.id", ondelete="CASCADE"))
    sender_id: Mapped[UUID] = mapped_column(
        ForeignKey("identity_user.id", ondelete="CASCADE")
    )
    client_id: Mapped[UUID]
    sequence: Mapped[int] = mapped_column(BigInteger)
    text: Mapped[str] = mapped_column(Text)
    # The message this one quotes; validated to be in the same chat and
    # visible when the reply is sent. No FK: messages are partitioned.
    reply_to_id: Mapped[UUID | None]
    # Incremented by every edit; prior text lives in ChatMessageVersion.
    version: Mapped[int] = mapped_column(default=1)
    # Set by #81 when a message is deleted; search hides such rows.
    deleted_at: Mapped[datetime | None]
    # Both dictionaries feed one vector: a query in either language matches,
    # and PostgreSQL recomputes it whenever ``text`` changes.
    search_vector: Mapped[Any] = mapped_column(
        TSVECTOR,
        Computed(
            "to_tsvector('russian', text) || to_tsvector('english', text)",
            persisted=True,
        ),
        nullable=False,
    )
    created_at: Mapped[datetime] = mapped_column(default=clock.now)


class ChatMessageArchive(Base):
    """Messages older than the active window, partitioned by year.

    The archive is a separate partitioned table, not a child of
    :class:`ChatMessage`: an old row keeps its id, sequence and client UUID
    but is served to readers through the ``chat_message_history`` union view.
    Moving rows out of the active parent keeps its partitions small while
    the history API and a future search see one logical table.
    """

    __tablename__ = "chat_message_archive"
    __table_args__ = (
        PrimaryKeyConstraint("id", "created_at", name="pk_chat_message_archive"),
        CheckConstraint("sequence > 0", name="sequence_positive"),
        CheckConstraint("length(text) > 0", name="text_not_empty"),
        Index(
            "ix_chat_message_archive_chat_id_sequence",
            "chat_id",
            "sequence",
        ),
        Index(
            "ix_chat_message_archive_search",
            "search_vector",
            postgresql_using="gin",
            postgresql_where=text("deleted_at IS NULL"),
        ),
    )

    id: Mapped[UUID] = mapped_column(server_default=func.uuidv7())
    chat_id: Mapped[UUID] = mapped_column(ForeignKey("chat.id", ondelete="CASCADE"))
    sender_id: Mapped[UUID] = mapped_column(
        ForeignKey("identity_user.id", ondelete="CASCADE")
    )
    client_id: Mapped[UUID]
    sequence: Mapped[int] = mapped_column(BigInteger)
    text: Mapped[str] = mapped_column(Text)
    reply_to_id: Mapped[UUID | None]
    version: Mapped[int] = mapped_column(default=1)
    # Archived rows keep the deletion marker and the generated search vector:
    # moving a row must not change what the history or search returns.
    deleted_at: Mapped[datetime | None]
    search_vector: Mapped[Any] = mapped_column(
        TSVECTOR,
        Computed(
            "to_tsvector('russian', text) || to_tsvector('english', text)",
            persisted=True,
        ),
        nullable=False,
    )
    created_at: Mapped[datetime] = mapped_column(default=clock.now)


class ChatMessageHistory(Base):
    """Read-only union of active and archived messages.

    A view, not a table: the API, search and the deduplication replay read
    the same columns and the same indexes regardless of where the row lives.
    Writes always go to :class:`ChatMessage`.
    """

    __tablename__ = "chat_message_history"
    __table_args__ = (PrimaryKeyConstraint("id", "created_at"),)

    id: Mapped[UUID] = mapped_column(primary_key=True)
    chat_id: Mapped[UUID]
    sender_id: Mapped[UUID]
    client_id: Mapped[UUID]
    sequence: Mapped[int] = mapped_column(BigInteger)
    text: Mapped[str] = mapped_column(Text)
    reply_to_id: Mapped[UUID | None]
    version: Mapped[int]
    deleted_at: Mapped[datetime | None]
    search_vector: Mapped[Any] = mapped_column(TSVECTOR)
    created_at: Mapped[datetime] = mapped_column(primary_key=True)


class ChatMessageVersion(Base):
    """Hidden previous text of an edited or deleted message.

    Rows are not part of history, search or realtime. They exist only for
    the restricted complaint-evidence API and are purged by the cleanup job
    ``purge_at``; a snapshot already attached to a complaint has no foreign
    key to this table and survives the purge.
    """

    __tablename__ = "chat_message_version"
    __table_args__ = (
        UniqueConstraint(
            "message_id", "version", name="uq_chat_message_version_message_version"
        ),
        CheckConstraint("version > 0", name="version_positive"),
        CheckConstraint("kind IN ('edit','delete')", name="kind"),
        Index("ix_chat_message_version_purge_at", "purge_at"),
        Index("ix_chat_message_version_message_id", "message_id"),
    )

    id: Mapped[UUID] = mapped_column(primary_key=True, server_default=func.uuidv7())
    chat_id: Mapped[UUID] = mapped_column(ForeignKey("chat.id", ondelete="CASCADE"))
    message_id: Mapped[UUID]
    version: Mapped[int]
    kind: Mapped[str] = mapped_column(String(16))
    text: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(default=clock.now)
    purge_at: Mapped[datetime]


class ChatMessageSnapshot(Base):
    """Immutable copy of a message attached to a complaint.

    Deliberately has no foreign keys to the chat, the message or the sender:
    retaining a complaint must survive the retention cleanup of the chat.
    The complaint case itself is created by the moderation module later; its
    identifier is stored without a foreign key for the same reason. Photos
    are copied into :class:`ChatMessageSnapshotPhoto` for the same reason.
    """

    __tablename__ = "chat_message_snapshot"
    __table_args__ = (
        UniqueConstraint(
            "complaint_id",
            "message_id",
            name="uq_chat_message_snapshot_complaint_id_message_id",
        ),
        CheckConstraint("sequence > 0", name="sequence_positive"),
        Index("ix_chat_message_snapshot_complaint_id", "complaint_id"),
    )

    id: Mapped[UUID] = mapped_column(primary_key=True, server_default=func.uuidv7())
    complaint_id: Mapped[UUID]
    chat_id: Mapped[UUID]
    message_id: Mapped[UUID]
    sender_id: Mapped[UUID]
    sequence: Mapped[int] = mapped_column(BigInteger)
    text: Mapped[str] = mapped_column(Text)
    version: Mapped[int] = mapped_column(default=1)
    message_created_at: Mapped[datetime]
    captured_at: Mapped[datetime] = mapped_column(default=clock.now)


class ChatMessageSnapshotPhoto(Base):
    """Photo object copied into an immutable complaint attachment.

    The row keeps the object key and size, so moderators can still sign a
    link after the chat, its messages and the ``file`` rows are gone. The
    cleanup never deletes the processed photo objects of a file referenced
    here; the original source object is not part of the evidence.
    """

    __tablename__ = "chat_message_snapshot_photo"
    __table_args__ = (
        UniqueConstraint(
            "snapshot_id",
            "file_id",
            name="uq_chat_message_snapshot_photo_snapshot_id_file_id",
        ),
        CheckConstraint("size >= 0", name="size"),
        CheckConstraint("position >= 0", name="position"),
        Index("ix_chat_message_snapshot_photo_file_id", "file_id"),
    )

    id: Mapped[UUID] = mapped_column(primary_key=True, server_default=func.uuidv7())
    snapshot_id: Mapped[UUID] = mapped_column(
        ForeignKey("chat_message_snapshot.id", ondelete="CASCADE")
    )
    # No foreign key: the file row is deleted by retention, the key outlives it.
    file_id: Mapped[UUID]
    key: Mapped[str] = mapped_column(String(200))
    size: Mapped[int]
    position: Mapped[int]
    created_at: Mapped[datetime] = mapped_column(default=clock.now)
