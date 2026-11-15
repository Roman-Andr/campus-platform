"""Add message quotes, revisions and chat photo attachments.

Messages gain a quote link and a revision number; hidden revisions of edited
or deleted messages live in ``chat_message_version`` until their 30-day
purge. Chat photos gain a message reference, and complaint snapshots record
the revision they captured plus the processed photo objects that must
outlive the chat. The history view exposes the new columns so the API reads
active and archived rows through one interface.

Revision ID: 81a000000001
Revises: 60a000000001
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "81a000000001"
down_revision: str | Sequence[str] | None = "60a000000001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_OLD_VIEW = """
CREATE VIEW chat_message_history AS
SELECT id, chat_id, sender_id, client_id, sequence, text, deleted_at,
       search_vector, created_at
FROM chat_message
UNION ALL
SELECT id, chat_id, sender_id, client_id, sequence, text, deleted_at,
       search_vector, created_at
FROM chat_message_archive
"""

_NEW_VIEW = """
CREATE VIEW chat_message_history AS
SELECT id, chat_id, sender_id, client_id, sequence, text, reply_to_id,
       version, deleted_at, search_vector, created_at
FROM chat_message
UNION ALL
SELECT id, chat_id, sender_id, client_id, sequence, text, reply_to_id,
       version, deleted_at, search_vector, created_at
FROM chat_message_archive
"""


def upgrade() -> None:
    op.add_column(
        "chat_message",
        sa.Column(
            "version",
            sa.Integer(),
            server_default=sa.text("1"),
            nullable=False,
        ),
    )
    # The application supplies the revision; the default only backfills rows
    # that existed before this migration.
    op.alter_column("chat_message", "version", server_default=None)
    op.add_column("chat_message", sa.Column("reply_to_id", sa.Uuid()))
    op.add_column(
        "chat_message_archive",
        sa.Column(
            "version",
            sa.Integer(),
            server_default=sa.text("1"),
            nullable=False,
        ),
    )
    op.alter_column("chat_message_archive", "version", server_default=None)
    op.add_column("chat_message_archive", sa.Column("reply_to_id", sa.Uuid()))
    op.add_column(
        "chat_message_snapshot",
        sa.Column(
            "version",
            sa.Integer(),
            server_default=sa.text("1"),
            nullable=False,
        ),
    )
    op.alter_column("chat_message_snapshot", "version", server_default=None)
    op.add_column("file", sa.Column("message_id", sa.Uuid()))
    op.add_column("file", sa.Column("message_position", sa.Integer()))
    op.create_check_constraint(
        op.f("ck_file_message_attachment"),
        "file",
        "(message_id IS NULL) = (message_position IS NULL)",
    )
    op.create_check_constraint(
        op.f("ck_file_message_in_chat"),
        "file",
        "message_id IS NULL OR chat_id IS NOT NULL",
    )
    op.create_index(
        "ix_file_message_id",
        "file",
        ["chat_id", "message_id", "message_position"],
        postgresql_where=sa.text("message_id IS NOT NULL"),
    )

    op.create_table(
        "chat_message_version",
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("chat_id", sa.Uuid(), nullable=False),
        sa.Column("message_id", sa.Uuid(), nullable=False),
        sa.Column("version", sa.Integer(), nullable=False),
        sa.Column("kind", sa.String(length=16), nullable=False),
        sa.Column("text", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("purge_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "kind IN ('edit','delete')", name=op.f("ck_chat_message_version_kind")
        ),
        sa.CheckConstraint(
            "version > 0", name=op.f("ck_chat_message_version_version_positive")
        ),
        sa.ForeignKeyConstraint(
            ["chat_id"],
            ["chat.id"],
            name=op.f("fk_chat_message_version_chat_id_chat"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_chat_message_version")),
        sa.UniqueConstraint(
            "message_id",
            "version",
            name=op.f("uq_chat_message_version_message_version"),
        ),
    )
    op.create_index(
        "ix_chat_message_version_purge_at",
        "chat_message_version",
        ["purge_at"],
    )
    op.create_index(
        "ix_chat_message_version_message_id",
        "chat_message_version",
        ["message_id"],
    )

    op.create_table(
        "chat_message_snapshot_photo",
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("snapshot_id", sa.Uuid(), nullable=False),
        sa.Column("file_id", sa.Uuid(), nullable=False),
        sa.Column("key", sa.String(length=200), nullable=False),
        sa.Column("size", sa.Integer(), nullable=False),
        sa.Column("position", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "position >= 0",
            name=op.f("ck_chat_message_snapshot_photo_position"),
        ),
        sa.CheckConstraint(
            "size >= 0",
            name=op.f("ck_chat_message_snapshot_photo_size"),
        ),
        sa.ForeignKeyConstraint(
            ["snapshot_id"],
            ["chat_message_snapshot.id"],
            name=op.f(
                "fk_chat_message_snapshot_photo_snapshot_id_chat_message_snapshot"
            ),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_chat_message_snapshot_photo")),
        sa.UniqueConstraint(
            "snapshot_id",
            "file_id",
            name=op.f("uq_chat_message_snapshot_photo_snapshot_id_file_id"),
        ),
    )
    op.create_index(
        "ix_chat_message_snapshot_photo_file_id",
        "chat_message_snapshot_photo",
        ["file_id"],
    )

    op.execute("DROP VIEW chat_message_history")
    op.execute(_NEW_VIEW)


def downgrade() -> None:
    op.execute("DROP VIEW chat_message_history")
    op.execute(_OLD_VIEW)
    op.drop_index(
        "ix_chat_message_snapshot_photo_file_id",
        table_name="chat_message_snapshot_photo",
    )
    op.drop_table("chat_message_snapshot_photo")
    op.drop_index(
        "ix_chat_message_version_message_id",
        table_name="chat_message_version",
    )
    op.drop_index(
        "ix_chat_message_version_purge_at",
        table_name="chat_message_version",
    )
    op.drop_table("chat_message_version")
    op.drop_index("ix_file_message_id", table_name="file")
    op.drop_constraint(op.f("ck_file_message_in_chat"), "file", type_="check")
    op.drop_constraint(op.f("ck_file_message_attachment"), "file", type_="check")
    op.drop_column("file", "message_position")
    op.drop_column("file", "message_id")
    op.drop_column("chat_message_snapshot", "version")
    op.drop_column("chat_message_archive", "reply_to_id")
    op.drop_column("chat_message_archive", "version")
    op.drop_column("chat_message", "reply_to_id")
    op.drop_column("chat_message", "version")
