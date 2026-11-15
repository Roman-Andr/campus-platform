"""Add message archive partitions, snapshots and chat/file retention.

Old messages move to yearly archive partitions; the ``chat_message_history``
view keeps the history API and a future search reading one logical table.
Chats get an empty-since marker, memberships record a leave and photos may
belong to a chat. Complaint snapshots deliberately have no foreign keys so
they survive the chat cleanup.

Revision ID: 298a00000001
Revises: 78c0a7000001
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "298a00000001"
down_revision: str | Sequence[str] | None = "78c0a7000001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

# Archive years prepared at migration time. A row from an older or newer
# year lands in the default partition; a later migration can split it.
FIRST_ARCHIVE_YEAR = 2020
LAST_ARCHIVE_YEAR = 2035


def upgrade() -> None:
    op.add_column("chat", sa.Column("empty_since", sa.DateTime(timezone=True)))
    op.create_index(
        "ix_chat_empty_since",
        "chat",
        ["empty_since"],
        postgresql_where=sa.text("empty_since IS NOT NULL"),
    )
    op.add_column("chat_member", sa.Column("left_at", sa.DateTime(timezone=True)))

    op.add_column("file", sa.Column("chat_id", sa.Uuid(), nullable=True))
    op.create_foreign_key(
        op.f("fk_file_chat_id_chat"),
        "file",
        "chat",
        ["chat_id"],
        ["id"],
        ondelete="RESTRICT",
    )
    op.create_index("ix_file_chat_id", "file", ["chat_id"])
    op.drop_constraint(op.f("ck_file_single_owner"), "file", type_="check")
    op.create_check_constraint(
        op.f("ck_file_single_owner"),
        "file",
        "num_nonnulls(listing_id, profile_user_id, chat_id) <= 1",
    )

    op.create_table(
        "chat_message_snapshot",
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("complaint_id", sa.Uuid(), nullable=False),
        sa.Column("chat_id", sa.Uuid(), nullable=False),
        sa.Column("message_id", sa.Uuid(), nullable=False),
        sa.Column("sender_id", sa.Uuid(), nullable=False),
        sa.Column("sequence", sa.BigInteger(), nullable=False),
        sa.Column("text", sa.Text(), nullable=False),
        sa.Column("message_created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("captured_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "sequence > 0", name=op.f("ck_chat_message_snapshot_sequence_positive")
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_chat_message_snapshot")),
        sa.UniqueConstraint(
            "complaint_id",
            "message_id",
            name=op.f("uq_chat_message_snapshot_complaint_id_message_id"),
        ),
    )
    op.create_index(
        "ix_chat_message_snapshot_complaint_id",
        "chat_message_snapshot",
        ["complaint_id"],
    )

    op.create_table(
        "chat_message_archive",
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("chat_id", sa.Uuid(), nullable=False),
        sa.Column("sender_id", sa.Uuid(), nullable=False),
        sa.Column("client_id", sa.Uuid(), nullable=False),
        sa.Column("sequence", sa.BigInteger(), nullable=False),
        sa.Column("text", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "sequence > 0", name=op.f("ck_chat_message_archive_sequence_positive")
        ),
        sa.CheckConstraint(
            "length(text) > 0",
            name=op.f("ck_chat_message_archive_text_not_empty"),
        ),
        sa.ForeignKeyConstraint(
            ["chat_id"],
            ["chat.id"],
            name=op.f("fk_chat_message_archive_chat_id_chat"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["sender_id"],
            ["identity_user.id"],
            name=op.f("fk_chat_message_archive_sender_id_identity_user"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint(
            "id", "created_at", name=op.f("pk_chat_message_archive")
        ),
        postgresql_partition_by="RANGE (created_at)",
    )
    for year in range(FIRST_ARCHIVE_YEAR, LAST_ARCHIVE_YEAR + 1):
        op.execute(
            f"CREATE TABLE chat_message_archive_{year}"
            " PARTITION OF chat_message_archive"
            f" FOR VALUES FROM ('{year:04d}-01-01')"
            f" TO ('{year + 1:04d}-01-01')"
        )
    op.execute(
        "CREATE TABLE chat_message_archive_default"
        " PARTITION OF chat_message_archive DEFAULT"
    )
    op.create_index(
        "ix_chat_message_archive_chat_id_sequence",
        "chat_message_archive",
        ["chat_id", "sequence"],
    )
    op.execute(
        """
        CREATE VIEW chat_message_history AS
        SELECT id, chat_id, sender_id, client_id, sequence, text, created_at
        FROM chat_message
        UNION ALL
        SELECT id, chat_id, sender_id, client_id, sequence, text, created_at
        FROM chat_message_archive
        """
    )


def downgrade() -> None:
    op.execute("DROP VIEW chat_message_history")
    op.drop_index(
        "ix_chat_message_archive_chat_id_sequence",
        table_name="chat_message_archive",
    )
    op.drop_table("chat_message_archive")
    op.drop_index(
        "ix_chat_message_snapshot_complaint_id",
        table_name="chat_message_snapshot",
    )
    op.drop_table("chat_message_snapshot")
    op.drop_constraint(op.f("ck_file_single_owner"), "file", type_="check")
    op.create_check_constraint(
        op.f("ck_file_single_owner"),
        "file",
        "listing_id IS NULL OR profile_user_id IS NULL",
    )
    op.drop_index("ix_file_chat_id", table_name="file")
    op.drop_constraint(op.f("fk_file_chat_id_chat"), "file", type_="foreignkey")
    op.drop_column("file", "chat_id")
    op.drop_column("chat_member", "left_at")
    op.drop_index("ix_chat_empty_since", table_name="chat")
    op.drop_column("chat", "empty_since")
