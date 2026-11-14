"""Add scheduled meetings of accepted interactions.

Revision ID: 47a1b2c3d4e5
Revises: 56feed000001
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "47a1b2c3d4e5"
down_revision: str | Sequence[str] | None = "74a1b2c3d4e5"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "listing_meeting",
        sa.Column("interaction_id", sa.Uuid(), nullable=False),
        sa.Column("scheduled_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("location", sa.Text(), nullable=True),
        sa.Column("scheduled_by_id", sa.Uuid(), nullable=True),
        sa.Column("proposed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("proposed_location", sa.Text(), nullable=True),
        sa.Column("proposed_by_id", sa.Uuid(), nullable=True),
        sa.Column("version", sa.Integer(), nullable=False),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "version >= 1", name=op.f("ck_listing_meeting_version_positive")
        ),
        sa.CheckConstraint(
            "(scheduled_at IS NULL AND location IS NULL "
            "AND scheduled_by_id IS NULL) OR (scheduled_at IS NOT NULL "
            "AND location IS NOT NULL AND scheduled_by_id IS NOT NULL)",
            name=op.f("ck_listing_meeting_scheduled_complete"),
        ),
        sa.CheckConstraint(
            "(proposed_at IS NULL AND proposed_location IS NULL "
            "AND proposed_by_id IS NULL) OR (proposed_at IS NOT NULL "
            "AND proposed_location IS NOT NULL AND proposed_by_id IS NOT NULL)",
            name=op.f("ck_listing_meeting_proposal_complete"),
        ),
        sa.CheckConstraint(
            "scheduled_at IS NOT NULL OR proposed_at IS NOT NULL",
            name=op.f("ck_listing_meeting_has_values"),
        ),
        sa.ForeignKeyConstraint(
            ["interaction_id"],
            ["listing_interaction.id"],
            name=op.f("fk_listing_meeting_interaction_id_listing_interaction"),
        ),
        sa.ForeignKeyConstraint(
            ["scheduled_by_id"],
            ["identity_user.id"],
            name=op.f("fk_listing_meeting_scheduled_by_id_identity_user"),
        ),
        sa.ForeignKeyConstraint(
            ["proposed_by_id"],
            ["identity_user.id"],
            name=op.f("fk_listing_meeting_proposed_by_id_identity_user"),
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_listing_meeting")),
        sa.UniqueConstraint(
            "interaction_id", name=op.f("uq_listing_meeting_interaction_id")
        ),
    )
    # Journal entries may carry structured details of the action, e.g. the
    # previous and the new time of a rescheduled meeting.
    op.add_column(
        "listing_event",
        sa.Column("details", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("listing_event", "details")
    op.drop_table("listing_meeting")
