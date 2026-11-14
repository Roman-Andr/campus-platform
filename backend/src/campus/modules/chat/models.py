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
from uuid import UUID

from sqlalchemy import (
    BigInteger,
    CheckConstraint,
    ForeignKey,
    Index,
    PrimaryKeyConstraint,
    String,
    Text,
    UniqueConstraint,
    func,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column

from campus.core import clock
from campus.core.db import Base, Entity

PERSONAL_KIND = "personal"


class Chat(Entity):
    """A personal dialog of two users, optionally linked to a listing.

    ``user_low_id`` and ``user_high_id`` order the pair canonically, so the
    partial unique indexes cannot be fooled by reversed arguments. The
    ``last_sequence`` counter is incremented under the row lock of the same
    transaction that stores a message: concurrent sends of one chat are
    therefore committed in sequence order, and the number, not the device
    time, defines the order clients see.
    """

    __tablename__ = "chat"
    __table_args__ = (
        CheckConstraint("kind IN ('personal')", name="kind"),
        CheckConstraint("user_low_id <> user_high_id", name="distinct_members"),
        CheckConstraint("last_sequence >= 0", name="last_sequence_non_negative"),
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
    )

    kind: Mapped[str] = mapped_column(String(16), default=PERSONAL_KIND)
    # The member with the smaller UUID; see the class docstring.
    user_low_id: Mapped[UUID] = mapped_column(ForeignKey("identity_user.id"))
    user_high_id: Mapped[UUID] = mapped_column(ForeignKey("identity_user.id"))
    listing_id: Mapped[UUID | None] = mapped_column(ForeignKey("listing.id"))
    interaction_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("listing_interaction.id")
    )
    last_sequence: Mapped[int] = mapped_column(BigInteger, default=0)


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
    # SHA-256 of the text: the same UUID must carry the same content.
    content_hash: Mapped[str] = mapped_column(String(64))
    created_at: Mapped[datetime] = mapped_column(default=clock.now)


class ChatMessage(Base):
    """A message of a chat; ranged by ``created_at`` into month partitions.

    The key is ``(id, created_at)`` because PostgreSQL requires the
    partition key in the primary key. Look a message up by id together with
    its creation time, taken from :class:`ChatMessageDedup`.
    """

    __tablename__ = "chat_message"
    __table_args__ = (
        PrimaryKeyConstraint("id", "created_at", name="pk_chat_message"),
        CheckConstraint("sequence > 0", name="sequence_positive"),
        CheckConstraint("length(text) > 0", name="text_not_empty"),
        Index("ix_chat_message_chat_id_sequence", "chat_id", "sequence"),
    )

    id: Mapped[UUID] = mapped_column(server_default=func.uuidv7())
    chat_id: Mapped[UUID] = mapped_column(ForeignKey("chat.id", ondelete="CASCADE"))
    sender_id: Mapped[UUID] = mapped_column(
        ForeignKey("identity_user.id", ondelete="CASCADE")
    )
    client_id: Mapped[UUID]
    sequence: Mapped[int] = mapped_column(BigInteger)
    text: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(default=clock.now)
