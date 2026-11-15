"""add message policy and personal blocks

Revision ID: 84b10c000001
Revises: 78c0a7000001
Create Date: 2026-11-15 02:00:00.000000+00:00
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "84b10c000001"
down_revision: str | Sequence[str] | None = "78c0a7000001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "identity_user",
        sa.Column(
            "message_policy",
            sa.String(length=16),
            server_default=sa.text("'all'"),
            nullable=False,
        ),
    )
    op.create_check_constraint(
        op.f("ck_identity_user_message_policy"),
        "identity_user",
        "message_policy IN ('all', 'related')",
    )
    op.create_table(
        "identity_block",
        sa.Column("blocker_id", sa.Uuid(), nullable=False),
        sa.Column("blocked_id", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "blocker_id <> blocked_id",
            name=op.f("ck_identity_block_not_self"),
        ),
        sa.ForeignKeyConstraint(
            ["blocked_id"],
            ["identity_user.id"],
            name=op.f("fk_identity_block_blocked_id_identity_user"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["blocker_id"],
            ["identity_user.id"],
            name=op.f("fk_identity_block_blocker_id_identity_user"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint(
            "blocker_id", "blocked_id", name=op.f("pk_identity_block")
        ),
    )
    op.create_index(
        op.f("ix_identity_block_blocked_id"),
        "identity_block",
        ["blocked_id"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(op.f("ix_identity_block_blocked_id"), table_name="identity_block")
    op.drop_table("identity_block")
    op.drop_constraint(
        op.f("ck_identity_user_message_policy"),
        "identity_user",
        type_="check",
    )
    op.drop_column("identity_user", "message_policy")
