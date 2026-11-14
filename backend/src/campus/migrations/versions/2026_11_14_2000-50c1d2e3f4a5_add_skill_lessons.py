"""Add skill listings, lesson time options and online meetings.

Revision ID: 50c1d2e3f4a5
Revises: 106a00000001
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "50c1d2e3f4a5"
down_revision: str | Sequence[str] | None = "106a00000001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "listing_skill",
        sa.Column("listing_id", sa.Uuid(), nullable=False),
        sa.Column("direction", sa.String(16), nullable=False),
        sa.CheckConstraint(
            "direction IN ('teach','learn')",
            name=op.f("ck_listing_skill_direction"),
        ),
        sa.ForeignKeyConstraint(
            ["listing_id"],
            ["listing.id"],
            name=op.f("fk_listing_skill_listing_id_listing"),
        ),
        sa.PrimaryKeyConstraint("listing_id", name=op.f("pk_listing_skill")),
    )
    op.create_table(
        "listing_lesson_option",
        sa.Column("interaction_id", sa.Uuid(), nullable=False),
        sa.Column("position", sa.Integer(), nullable=False),
        sa.Column("time", sa.DateTime(timezone=True), nullable=False),
        sa.Column("location", sa.Text(), nullable=True),
        sa.Column("online", sa.Boolean(), nullable=False),
        sa.Column("proposed_by_id", sa.Uuid(), nullable=False),
        sa.Column("status", sa.String(16), nullable=False),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "position >= 0", name=op.f("ck_listing_lesson_option_position")
        ),
        sa.CheckConstraint(
            "(online AND location IS NULL) OR (NOT online AND location IS NOT NULL)",
            name=op.f("ck_listing_lesson_option_place"),
        ),
        sa.CheckConstraint(
            "status IN ('proposed','selected','declined')",
            name=op.f("ck_listing_lesson_option_status"),
        ),
        sa.ForeignKeyConstraint(
            ["interaction_id"],
            ["listing_interaction.id"],
            name=op.f("fk_listing_lesson_option_interaction_id_listing_interaction"),
        ),
        sa.ForeignKeyConstraint(
            ["proposed_by_id"],
            ["identity_user.id"],
            name=op.f("fk_listing_lesson_option_proposed_by_id_identity_user"),
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_listing_lesson_option")),
        sa.UniqueConstraint(
            "interaction_id",
            "position",
            name=op.f("uq_listing_lesson_option_interaction_id_position"),
        ),
    )
    op.create_index(
        "uq_listing_lesson_option_selected",
        "listing_lesson_option",
        ["interaction_id"],
        unique=True,
        postgresql_where=sa.text("status = 'selected'"),
    )
    # A meeting may be online instead of having a place; existing rows stay
    # offline, so their old invariant is preserved.
    op.add_column(
        "listing_meeting",
        sa.Column("online", sa.Boolean(), server_default=sa.false(), nullable=False),
    )
    op.alter_column("listing_meeting", "online", server_default=None)
    op.drop_constraint(
        op.f("ck_listing_meeting_scheduled_complete"),
        "listing_meeting",
        type_="check",
    )
    op.create_check_constraint(
        op.f("ck_listing_meeting_scheduled_complete"),
        "listing_meeting",
        "(scheduled_at IS NULL AND location IS NULL "
        "AND scheduled_by_id IS NULL AND online = false) OR "
        "(scheduled_at IS NOT NULL AND scheduled_by_id IS NOT NULL "
        "AND (online OR location IS NOT NULL))",
    )


def downgrade() -> None:
    # Online meetings cannot be represented by the old constraint; they only
    # come from the skill flow added above.
    op.execute("DELETE FROM listing_meeting WHERE online")
    op.drop_constraint(
        op.f("ck_listing_meeting_scheduled_complete"),
        "listing_meeting",
        type_="check",
    )
    op.create_check_constraint(
        op.f("ck_listing_meeting_scheduled_complete"),
        "listing_meeting",
        "(scheduled_at IS NULL AND location IS NULL "
        "AND scheduled_by_id IS NULL) OR (scheduled_at IS NOT NULL "
        "AND location IS NOT NULL AND scheduled_by_id IS NOT NULL)",
    )
    op.drop_column("listing_meeting", "online")
    op.drop_index(
        "uq_listing_lesson_option_selected",
        table_name="listing_lesson_option",
    )
    op.drop_table("listing_lesson_option")
    op.drop_table("listing_skill")
