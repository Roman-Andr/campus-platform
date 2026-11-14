"""Add realtime channel grants.

Revision ID: 77c3f7a00001
Revises: 297a00000001
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "77c3f7a00001"
down_revision: str | Sequence[str] | None = "48a1b2c3d4e5"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "realtime_channel_grant",
        sa.Column("channel", sa.String(255), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True)),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["identity_user.id"],
            name=op.f("fk_realtime_channel_grant_user_id_identity_user"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint(
            "channel", "user_id", name=op.f("pk_realtime_channel_grant")
        ),
    )
    op.create_index(
        "ix_realtime_channel_grant_user_id",
        "realtime_channel_grant",
        ["user_id"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_realtime_channel_grant_user_id", table_name="realtime_channel_grant"
    )
    op.drop_table("realtime_channel_grant")
