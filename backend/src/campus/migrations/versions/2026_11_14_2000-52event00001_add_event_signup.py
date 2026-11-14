"""Add event capacity and concurrent queue offers.

Revision ID: 52event00001
Revises: 57search00001
"""

import sqlalchemy as sa
from alembic import op

revision = "52event00001"
down_revision = "57search00001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("listing", sa.Column("event_starts_at", sa.DateTime(timezone=True)))
    op.add_column("listing", sa.Column("event_ends_at", sa.DateTime(timezone=True)))
    op.add_column("listing", sa.Column("event_location", sa.Text()))
    op.add_column("listing", sa.Column("event_capacity", sa.Integer()))
    op.add_column(
        "listing",
        sa.Column("event_registered", sa.Integer(), nullable=False, server_default="0"),
    )
    op.create_check_constraint(
        "event_count",
        "listing",
        "event_registered >= 0 AND (event_capacity IS NULL OR "
        "event_registered <= event_capacity)",
    )
    op.create_check_constraint(
        "event_details",
        "listing",
        "kind != 'event' OR (event_starts_at IS NOT NULL AND "
        "event_ends_at IS NOT NULL AND event_ends_at > event_starts_at AND "
        "event_location IS NOT NULL AND event_capacity IS NOT NULL AND "
        "event_capacity > 0)",
    )
    op.create_index(
        "uq_listing_active_participant",
        "listing_interaction",
        ["listing_id", "participant_id"],
        unique=True,
        postgresql_where=sa.text("status IN ('pending', 'accepted')"),
    )
    op.add_column(
        "listing_waitlist", sa.Column("offer_slot", sa.Integer(), server_default="1")
    )
    op.drop_index("uq_listing_waitlist_offer", table_name="listing_waitlist")
    op.create_index(
        "uq_listing_waitlist_offer",
        "listing_waitlist",
        ["listing_id", "offer_slot"],
        unique=True,
        postgresql_where=sa.text("status = 'offered'"),
    )


def downgrade() -> None:
    op.drop_index("uq_listing_waitlist_offer", table_name="listing_waitlist")
    op.drop_column("listing_waitlist", "offer_slot")
    op.create_index(
        "uq_listing_waitlist_offer",
        "listing_waitlist",
        ["listing_id"],
        unique=True,
        postgresql_where=sa.text("status = 'offered'"),
    )
    op.drop_index("uq_listing_active_participant", table_name="listing_interaction")
    op.drop_constraint("event_details", "listing", type_="check")
    op.drop_constraint("event_count", "listing", type_="check")
    for name in (
        "event_registered",
        "event_capacity",
        "event_location",
        "event_ends_at",
        "event_starts_at",
    ):
        op.drop_column("listing", name)
