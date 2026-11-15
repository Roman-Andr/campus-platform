"""Add cancellation actor, reason, late mark and changed conditions.

Revision ID: 55a1b2c3d4e5
Revises: 78c0a7000001
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "55a1b2c3d4e5"
down_revision: str | Sequence[str] | None = "78c0a7000001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "listing_interaction",
        sa.Column("cancelled_by", sa.String(16), nullable=True),
    )
    op.add_column(
        "listing_interaction",
        sa.Column("cancellation_reason", sa.Text(), nullable=True),
    )
    op.add_column(
        "listing_interaction",
        sa.Column(
            "late_cancelled",
            sa.Boolean(),
            server_default=sa.false(),
            nullable=False,
        ),
    )
    op.alter_column("listing_interaction", "late_cancelled", server_default=None)
    op.add_column(
        "listing_interaction",
        sa.Column("conditions_changed_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "listing_interaction",
        sa.Column(
            "conditions_changed_by_id",
            sa.Uuid(),
            sa.ForeignKey(
                "identity_user.id",
                name=op.f(
                    "fk_listing_interaction_conditions_changed_by_id_identity_user"
                ),
            ),
            nullable=True,
        ),
    )
    op.create_check_constraint(
        op.f("ck_listing_interaction_cancelled_by"),
        "listing_interaction",
        "cancelled_by IS NULL OR cancelled_by IN ('author','participant','system')",
    )
    op.create_check_constraint(
        op.f("ck_listing_interaction_cancellation_complete"),
        "listing_interaction",
        "(cancelled_by IS NULL AND cancellation_reason IS NULL "
        "AND NOT late_cancelled) OR status = 'cancelled'",
    )
    op.create_index(
        "ix_listing_interaction_late_cancelled",
        "listing_interaction",
        ["participant_id"],
        postgresql_where=sa.text("late_cancelled"),
    )


def downgrade() -> None:
    op.drop_index(
        "ix_listing_interaction_late_cancelled",
        table_name="listing_interaction",
    )
    op.drop_constraint(
        op.f("ck_listing_interaction_cancellation_complete"),
        "listing_interaction",
        type_="check",
    )
    op.drop_constraint(
        op.f("ck_listing_interaction_cancelled_by"),
        "listing_interaction",
        type_="check",
    )
    op.drop_column("listing_interaction", "conditions_changed_by_id")
    op.drop_column("listing_interaction", "conditions_changed_at")
    op.drop_column("listing_interaction", "late_cancelled")
    op.drop_column("listing_interaction", "cancellation_reason")
    op.drop_column("listing_interaction", "cancelled_by")
