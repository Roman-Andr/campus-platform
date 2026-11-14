"""add recipient notifications

Revision ID: 85a000000001
Revises: 106a00000001
Create Date: 2026-11-14 18:46:49.530181+00:00
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "85a000000001"
down_revision: str | Sequence[str] | None = "106a00000001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "notification_dispatch",
        sa.Column("event_id", sa.Uuid(), nullable=False),
        sa.Column("consumer", sa.String(length=50), nullable=False),
        sa.PrimaryKeyConstraint(
            "event_id", "consumer", name=op.f("pk_notification_dispatch")
        ),
    )
    op.create_table(
        "notification_reminder",
        sa.Column("key", sa.String(length=160), nullable=False),
        sa.Column("revision", sa.Uuid(), nullable=False),
        sa.Column("starts_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("active", sa.Boolean(), nullable=False),
        sa.Column("payload", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.PrimaryKeyConstraint("key", name=op.f("pk_notification_reminder")),
    )
    op.create_table(
        "notification",
        sa.Column("event_id", sa.Uuid(), nullable=False),
        sa.Column("recipient_id", sa.Uuid(), nullable=False),
        sa.Column("sequence", sa.BigInteger(), nullable=False),
        sa.Column("type", sa.String(length=80), nullable=False),
        sa.Column("object_id", sa.Uuid(), nullable=True),
        sa.Column("occurred_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("text", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("params", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["recipient_id"],
            ["identity_user.id"],
            name=op.f("fk_notification_recipient_id_identity_user"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_notification")),
        sa.UniqueConstraint(
            "event_id",
            "recipient_id",
            name=op.f("uq_notification_event_id_recipient_id"),
        ),
        sa.UniqueConstraint(
            "recipient_id",
            "sequence",
            name=op.f("uq_notification_recipient_id_sequence"),
        ),
    )
    op.create_table(
        "notification_inbox",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("sequence", sa.BigInteger(), nullable=False),
        sa.Column("read_sequence", sa.BigInteger(), nullable=False),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["identity_user.id"],
            name=op.f("fk_notification_inbox_user_id_identity_user"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("user_id", name=op.f("pk_notification_inbox")),
    )


def downgrade() -> None:
    op.drop_table("notification_inbox")
    op.drop_table("notification")
    op.drop_table("notification_reminder")
    op.drop_table("notification_dispatch")
