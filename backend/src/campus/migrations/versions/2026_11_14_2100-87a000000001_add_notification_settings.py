"""add notification settings and quiet hours

Revision ID: 87a000000001
Revises: 51a1b2c3d4e5
Create Date: 2026-11-14 21:00:00.000000+00:00
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "87a000000001"
down_revision: str | Sequence[str] | None = "51a1b2c3d4e5"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "notification_settings",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("version", sa.Integer(), nullable=False),
        sa.Column("quiet_hours_enabled", sa.Boolean(), nullable=False),
        sa.Column("quiet_hours_start", sa.Time(), nullable=False),
        sa.Column("quiet_hours_end", sa.Time(), nullable=False),
        sa.Column(
            "disabled_types",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
        ),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "version >= 1",
            name=op.f("ck_notification_settings_version_positive"),
        ),
        sa.CheckConstraint(
            "quiet_hours_start <> quiet_hours_end",
            name=op.f("ck_notification_settings_quiet_hours_not_empty"),
        ),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["identity_user.id"],
            name=op.f("fk_notification_settings_user_id_identity_user"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("user_id", name=op.f("pk_notification_settings")),
    )
    op.create_table(
        "notification_muted_chat",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("chat_id", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["identity_user.id"],
            name=op.f("fk_notification_muted_chat_user_id_identity_user"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint(
            "user_id", "chat_id", name=op.f("pk_notification_muted_chat")
        ),
    )
    op.add_column("notification", sa.Column("important", sa.Boolean(), nullable=True))
    op.execute("UPDATE notification SET important = false")
    op.alter_column("notification", "important", nullable=False)


def downgrade() -> None:
    op.drop_column("notification", "important")
    op.drop_table("notification_muted_chat")
    op.drop_table("notification_settings")
