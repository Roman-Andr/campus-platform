"""Add personal chats, membership, message deduplication and messages.

Messages are partitioned by creation time (specification, 5.5.1); the
non-partitioned chat_message_dedup keeps the two unique invariants that a
partitioned table cannot express: one client UUID per chat and one server
sequence per chat. Monthly partitions are created ahead of time and a
default partition catches everything else until the next release adds more.

Revision ID: 78c0a7000001
Revises: 51a1b2c3d4e5
"""

from collections.abc import Sequence
from datetime import UTC, datetime

import sqlalchemy as sa
from alembic import op

revision: str = "78c0a7000001"
down_revision: str | Sequence[str] | None = "51a1b2c3d4e5"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

# Partitions created now; the maintenance task of a later slice extends them.
FIRST_PARTITION = (2026, 11)
PARTITION_COUNT = 26


def month_label(year: int, month: int) -> str:
    return f"{year:04d}_{month:02d}"


def shift_month(year: int, month: int, months: int) -> tuple[int, int]:
    index = year * 12 + (month - 1) + months
    return index // 12, index % 12 + 1


def upgrade() -> None:
    op.create_table(
        "chat",
        sa.Column("kind", sa.String(16), nullable=False),
        sa.Column("user_low_id", sa.Uuid(), nullable=False),
        sa.Column("user_high_id", sa.Uuid(), nullable=False),
        sa.Column("listing_id", sa.Uuid(), nullable=True),
        sa.Column("interaction_id", sa.Uuid(), nullable=True),
        sa.Column("last_sequence", sa.BigInteger(), nullable=False),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("kind IN ('personal')", name=op.f("ck_chat_kind")),
        sa.CheckConstraint(
            "user_low_id <> user_high_id", name=op.f("ck_chat_distinct_members")
        ),
        sa.CheckConstraint(
            "last_sequence >= 0", name=op.f("ck_chat_last_sequence_non_negative")
        ),
        sa.ForeignKeyConstraint(
            ["user_low_id"],
            ["identity_user.id"],
            name=op.f("fk_chat_user_low_id_identity_user"),
        ),
        sa.ForeignKeyConstraint(
            ["user_high_id"],
            ["identity_user.id"],
            name=op.f("fk_chat_user_high_id_identity_user"),
        ),
        sa.ForeignKeyConstraint(
            ["listing_id"], ["listing.id"], name=op.f("fk_chat_listing_id_listing")
        ),
        sa.ForeignKeyConstraint(
            ["interaction_id"],
            ["listing_interaction.id"],
            name=op.f("fk_chat_interaction_id_listing_interaction"),
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_chat")),
    )
    op.create_index(
        "uq_chat_direct_pair",
        "chat",
        ["user_low_id", "user_high_id"],
        unique=True,
        postgresql_where=sa.text("listing_id IS NULL AND interaction_id IS NULL"),
    )
    op.create_index(
        "uq_chat_listing_pair",
        "chat",
        ["listing_id", "user_low_id", "user_high_id"],
        unique=True,
        postgresql_where=sa.text("listing_id IS NOT NULL AND interaction_id IS NULL"),
    )
    op.create_index(
        "uq_chat_interaction",
        "chat",
        ["interaction_id"],
        unique=True,
        postgresql_where=sa.text("interaction_id IS NOT NULL"),
    )
    op.create_table(
        "chat_member",
        sa.Column("chat_id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("joined_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["chat_id"],
            ["chat.id"],
            name=op.f("fk_chat_member_chat_id_chat"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["identity_user.id"],
            name=op.f("fk_chat_member_user_id_identity_user"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("chat_id", "user_id", name=op.f("pk_chat_member")),
    )
    op.create_index("ix_chat_member_user_id", "chat_member", ["user_id"])
    op.create_table(
        "chat_message_dedup",
        sa.Column("chat_id", sa.Uuid(), nullable=False),
        sa.Column("client_id", sa.Uuid(), nullable=False),
        sa.Column("sender_id", sa.Uuid(), nullable=False),
        sa.Column("sequence", sa.BigInteger(), nullable=False),
        sa.Column("message_id", sa.Uuid(), nullable=False),
        sa.Column("message_created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("content_hash", sa.String(64), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "sequence > 0", name=op.f("ck_chat_message_dedup_sequence_positive")
        ),
        sa.ForeignKeyConstraint(
            ["chat_id"],
            ["chat.id"],
            name=op.f("fk_chat_message_dedup_chat_id_chat"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["sender_id"],
            ["identity_user.id"],
            name=op.f("fk_chat_message_dedup_sender_id_identity_user"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint(
            "chat_id", "client_id", name=op.f("pk_chat_message_dedup")
        ),
        sa.UniqueConstraint(
            "chat_id",
            "sequence",
            name=op.f("uq_chat_message_dedup_chat_id_sequence"),
        ),
    )
    op.create_table(
        "chat_message",
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("chat_id", sa.Uuid(), nullable=False),
        sa.Column("sender_id", sa.Uuid(), nullable=False),
        sa.Column("client_id", sa.Uuid(), nullable=False),
        sa.Column("sequence", sa.BigInteger(), nullable=False),
        sa.Column("text", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "sequence > 0", name=op.f("ck_chat_message_sequence_positive")
        ),
        sa.CheckConstraint(
            "length(text) > 0", name=op.f("ck_chat_message_text_not_empty")
        ),
        sa.ForeignKeyConstraint(
            ["chat_id"],
            ["chat.id"],
            name=op.f("fk_chat_message_chat_id_chat"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["sender_id"],
            ["identity_user.id"],
            name=op.f("fk_chat_message_sender_id_identity_user"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", "created_at", name=op.f("pk_chat_message")),
        postgresql_partition_by="RANGE (created_at)",
    )
    op.create_index(
        "ix_chat_message_chat_id_sequence", "chat_message", ["chat_id", "sequence"]
    )
    year, month = FIRST_PARTITION
    for _ in range(PARTITION_COUNT):
        next_year, next_month = shift_month(year, month, 1)
        label = month_label(year, month)
        begin = datetime(year, month, 1, tzinfo=UTC)
        end = datetime(next_year, next_month, 1, tzinfo=UTC)
        op.execute(
            f"CREATE TABLE chat_message_{label} PARTITION OF chat_message"
            f" FOR VALUES FROM ('{begin:%Y-%m-%d}') TO ('{end:%Y-%m-%d}')"
        )
        year, month = next_year, next_month
    op.execute("CREATE TABLE chat_message_default PARTITION OF chat_message DEFAULT")


def downgrade() -> None:
    # Partitions are dropped together with their partitioned parent.
    op.drop_index("ix_chat_message_chat_id_sequence", table_name="chat_message")
    op.drop_table("chat_message")
    op.drop_table("chat_message_dedup")
    op.drop_index("ix_chat_member_user_id", table_name="chat_member")
    op.drop_table("chat_member")
    op.drop_index("uq_chat_interaction", table_name="chat")
    op.drop_index("uq_chat_listing_pair", table_name="chat")
    op.drop_index("uq_chat_direct_pair", table_name="chat")
    op.drop_table("chat")
