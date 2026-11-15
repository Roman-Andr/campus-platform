"""Add event attendance mode and per-participant marks.

An event listing gains the attendance mode chosen by its organiser. A mark
of one registered participant is one row in ``reputation_attendance``: the
unique (listing, participant) key keeps self-scans, organiser scans and
retries from adding a second row, while the row itself is reusable after a
removed mark. The event's signup is named by ``interaction_id``; the
``method`` records which of the two modes took the mark.

Revision ID: 61a000000001
Revises: 71a000000001
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "61a000000001"
down_revision: str | Sequence[str] | None = "56a000000001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "listing",
        sa.Column("event_attendance_mode", sa.String(length=8), nullable=True),
    )
    # Events published before this migration keep the self-marking default.
    op.execute("UPDATE listing SET event_attendance_mode = 'self' WHERE kind = 'event'")
    op.create_check_constraint(
        op.f("ck_listing_event_attendance_mode"),
        "listing",
        "(kind = 'event' AND event_attendance_mode IN ('self', 'scan')) OR "
        "(kind != 'event' AND event_attendance_mode IS NULL)",
    )

    op.create_table(
        "reputation_attendance",
        sa.Column("listing_id", sa.Uuid(), nullable=False),
        sa.Column("participant_id", sa.Uuid(), nullable=False),
        sa.Column("interaction_id", sa.Uuid(), nullable=False),
        sa.Column("method", sa.String(length=8), nullable=False),
        sa.Column("marked_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("marked_by_id", sa.Uuid(), nullable=False),
        sa.Column("removed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("removed_by_id", sa.Uuid(), nullable=True),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "method IN ('self', 'scan')",
            name=op.f("ck_reputation_attendance_method"),
        ),
        sa.CheckConstraint(
            "(removed_at IS NULL AND removed_by_id IS NULL) OR "
            "(removed_at IS NOT NULL AND removed_by_id IS NOT NULL)",
            name=op.f("ck_reputation_attendance_removal_complete"),
        ),
        sa.ForeignKeyConstraint(
            ["interaction_id"],
            ["listing_interaction.id"],
            name=op.f("fk_reputation_attendance_interaction_id_listing_interaction"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["listing_id"],
            ["listing.id"],
            name=op.f("fk_reputation_attendance_listing_id_listing"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["marked_by_id"],
            ["identity_user.id"],
            name=op.f("fk_reputation_attendance_marked_by_id_identity_user"),
        ),
        sa.ForeignKeyConstraint(
            ["participant_id"],
            ["identity_user.id"],
            name=op.f("fk_reputation_attendance_participant_id_identity_user"),
        ),
        sa.ForeignKeyConstraint(
            ["removed_by_id"],
            ["identity_user.id"],
            name=op.f("fk_reputation_attendance_removed_by_id_identity_user"),
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_reputation_attendance")),
        sa.UniqueConstraint(
            "listing_id",
            "participant_id",
            name=op.f("uq_reputation_attendance_listing_id_participant_id"),
        ),
    )
    op.create_index(
        "ix_reputation_attendance_listing",
        "reputation_attendance",
        ["listing_id", "marked_at", "id"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_reputation_attendance_listing", table_name="reputation_attendance"
    )
    op.drop_table("reputation_attendance")
    op.drop_constraint(
        op.f("ck_listing_event_attendance_mode"), "listing", type_="check"
    )
    op.drop_column("listing", "event_attendance_mode")
