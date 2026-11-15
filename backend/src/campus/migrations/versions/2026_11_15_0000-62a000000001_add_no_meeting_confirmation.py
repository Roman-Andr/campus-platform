"""Add mutual no-meeting confirmation and completion fields.

Revision ID: 62a000000001
Revises: 49a1b2c3d4e5
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "62a000000001"
down_revision: str | Sequence[str] | None = "49a1b2c3d4e5"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

COMPLETION_COMPLETE = (
    "(completion_method IS NULL AND completed_at IS NULL "
    "AND completion_weight IS NULL) OR "
    "(completion_method IS NOT NULL AND completed_at IS NOT NULL "
    "AND completion_weight IS NOT NULL AND completion_weight >= 0)"
)


def upgrade() -> None:
    op.add_column(
        "listing_interaction",
        sa.Column("completion_method", sa.String(16), nullable=True),
    )
    op.add_column(
        "listing_interaction",
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "listing_interaction",
        sa.Column("completion_weight", sa.Float(), nullable=True),
    )
    op.create_check_constraint(
        op.f("ck_listing_interaction_completion_method"),
        "listing_interaction",
        "completion_method IS NULL OR completion_method IN ('qr','no_meeting')",
    )
    op.create_check_constraint(
        op.f("ck_listing_interaction_completion_complete"),
        "listing_interaction",
        COMPLETION_COMPLETE,
    )
    op.create_table(
        "listing_no_meeting_confirmation",
        sa.Column("interaction_id", sa.Uuid(), nullable=False),
        sa.Column("participant_id", sa.Uuid(), nullable=False),
        sa.Column("agreed_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["interaction_id"],
            ["listing_interaction.id"],
            name=op.f(
                "fk_listing_no_meeting_confirmation_interaction_id_listing_interaction"
            ),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["participant_id"],
            ["identity_user.id"],
            name=op.f(
                "fk_listing_no_meeting_confirmation_participant_id_identity_user"
            ),
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_listing_no_meeting_confirmation")),
        sa.UniqueConstraint(
            "interaction_id",
            "participant_id",
            name=op.f(
                "uq_listing_no_meeting_confirmation_interaction_id_participant_id"
            ),
        ),
    )


def downgrade() -> None:
    op.drop_table("listing_no_meeting_confirmation")
    op.drop_constraint(
        op.f("ck_listing_interaction_completion_complete"),
        "listing_interaction",
        type_="check",
    )
    op.drop_constraint(
        op.f("ck_listing_interaction_completion_method"),
        "listing_interaction",
        type_="check",
    )
    op.drop_column("listing_interaction", "completion_weight")
    op.drop_column("listing_interaction", "completed_at")
    op.drop_column("listing_interaction", "completion_method")
