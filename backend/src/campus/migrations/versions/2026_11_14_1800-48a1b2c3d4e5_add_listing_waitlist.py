"""Add the listing waitlist with place offers.

Revision ID: 48a1b2c3d4e5
Revises: 297a00000001
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "48a1b2c3d4e5"
down_revision: str | Sequence[str] | None = "89a0d1700001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

ACTIVE = "status IN ('waiting', 'offered')"
OFFERED = "status = 'offered'"


def upgrade() -> None:
    op.create_table(
        "listing_waitlist",
        sa.Column("listing_id", sa.Uuid(), nullable=False),
        sa.Column("participant_id", sa.Uuid(), nullable=False),
        sa.Column("status", sa.String(16), nullable=False),
        sa.Column("offered_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("offer_expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("interaction_id", sa.Uuid(), nullable=True),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "status IN ('waiting','offered','claimed','declined','expired',"
            "'left','removed')",
            name=op.f("ck_listing_waitlist_status"),
        ),
        sa.CheckConstraint(
            "(offered_at IS NULL) = (offer_expires_at IS NULL)",
            name=op.f("ck_listing_waitlist_offer_times"),
        ),
        sa.ForeignKeyConstraint(
            ["interaction_id"],
            ["listing_interaction.id"],
            name=op.f("fk_listing_waitlist_interaction_id_listing_interaction"),
        ),
        sa.ForeignKeyConstraint(
            ["listing_id"],
            ["listing.id"],
            name=op.f("fk_listing_waitlist_listing_id_listing"),
        ),
        sa.ForeignKeyConstraint(
            ["participant_id"],
            ["identity_user.id"],
            name=op.f("fk_listing_waitlist_participant_id_identity_user"),
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_listing_waitlist")),
    )
    op.create_index(
        "ix_listing_waitlist_queue",
        "listing_waitlist",
        ["listing_id", "created_at", "id"],
        postgresql_where=sa.text(ACTIVE),
    )
    op.create_index(
        "uq_listing_waitlist_offer",
        "listing_waitlist",
        ["listing_id"],
        unique=True,
        postgresql_where=sa.text(OFFERED),
    )
    op.create_index(
        "uq_listing_waitlist_participant",
        "listing_waitlist",
        ["listing_id", "participant_id"],
        unique=True,
        postgresql_where=sa.text(ACTIVE),
    )
    op.add_column(
        "listing_event", sa.Column("waitlist_entry_id", sa.Uuid(), nullable=True)
    )
    op.create_foreign_key(
        op.f("fk_listing_event_waitlist_entry_id_listing_waitlist"),
        "listing_event",
        "listing_waitlist",
        ["waitlist_entry_id"],
        ["id"],
    )


def downgrade() -> None:
    op.drop_constraint(
        op.f("fk_listing_event_waitlist_entry_id_listing_waitlist"),
        "listing_event",
        type_="foreignkey",
    )
    op.drop_column("listing_event", "waitlist_entry_id")
    op.drop_index("uq_listing_waitlist_participant", table_name="listing_waitlist")
    op.drop_index("uq_listing_waitlist_offer", table_name="listing_waitlist")
    op.drop_index("ix_listing_waitlist_queue", table_name="listing_waitlist")
    op.drop_table("listing_waitlist")
