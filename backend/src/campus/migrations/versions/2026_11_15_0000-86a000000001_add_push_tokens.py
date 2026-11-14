"""add FCM push tokens

Revision ID: 86a000000001
Revises: 87a000000001
Create Date: 2026-11-15 00:00:00.000000+00:00
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "86a000000001"
down_revision: str | Sequence[str] | None = "87a000000001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "notification_push_token",
        sa.Column("token", sa.String(length=512), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("session_id", sa.Uuid(), nullable=False),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["identity_user.id"],
            name=op.f("fk_notification_push_token_user_id_identity_user"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["session_id"],
            ["identity_session.id"],
            name=op.f("fk_notification_push_token_session_id_identity_session"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_notification_push_token")),
        sa.UniqueConstraint("token", name=op.f("uq_notification_push_token_token")),
        sa.UniqueConstraint(
            "session_id", name=op.f("uq_notification_push_token_session_id")
        ),
    )
    op.create_index(
        op.f("ix_notification_push_token_user_id"),
        "notification_push_token",
        ["user_id"],
    )


def downgrade() -> None:
    op.drop_index(
        op.f("ix_notification_push_token_user_id"),
        table_name="notification_push_token",
    )
    op.drop_table("notification_push_token")
