"""Add group purchases: price, volume bounds and shares.

Revision ID: 53a1b2c3d4e5
Revises: 87a000000001
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "53a1b2c3d4e5"
down_revision: str | Sequence[str] | None = "291a00000001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

PURCHASE_DETAILS = (
    "kind != 'purchase' OR (purchase_unit_price IS NOT NULL "
    "AND purchase_unit_price > 0 AND purchase_min_units IS NOT NULL "
    "AND purchase_min_units >= 1 AND purchase_max_units IS NOT NULL "
    "AND purchase_max_units >= purchase_min_units "
    "AND purchase_collection_deadline IS NOT NULL "
    "AND purchase_stage IN ('collecting','fixed','cancelled') "
    "AND (purchase_stage != 'fixed' OR purchase_fixed_units IS NOT NULL))"
)
PURCHASE_UNITS = (
    "purchase_taken_units >= 0 AND (purchase_max_units IS NULL "
    "OR purchase_taken_units <= purchase_max_units)"
)
PURCHASE_ABSENT = (
    "kind = 'purchase' OR (purchase_unit_price IS NULL "
    "AND purchase_min_units IS NULL AND purchase_max_units IS NULL "
    "AND purchase_collection_deadline IS NULL AND purchase_stage IS NULL "
    "AND purchase_fixed_units IS NULL AND purchase_taken_units = 0)"
)


def upgrade() -> None:
    op.add_column(
        "listing",
        sa.Column("purchase_unit_price", sa.Numeric(12, 2), nullable=True),
    )
    op.add_column(
        "listing", sa.Column("purchase_min_units", sa.Integer(), nullable=True)
    )
    op.add_column(
        "listing", sa.Column("purchase_max_units", sa.Integer(), nullable=True)
    )
    op.add_column(
        "listing",
        sa.Column(
            "purchase_taken_units",
            sa.Integer(),
            server_default="0",
            nullable=False,
        ),
    )
    op.add_column(
        "listing", sa.Column("purchase_fixed_units", sa.Integer(), nullable=True)
    )
    op.add_column(
        "listing",
        sa.Column(
            "purchase_collection_deadline",
            sa.DateTime(timezone=True),
            nullable=True,
        ),
    )
    op.add_column("listing", sa.Column("purchase_stage", sa.String(16), nullable=True))
    op.create_check_constraint(
        op.f("ck_listing_purchase_details"), "listing", PURCHASE_DETAILS
    )
    op.create_check_constraint(
        op.f("ck_listing_purchase_units"), "listing", PURCHASE_UNITS
    )
    op.create_check_constraint(
        op.f("ck_listing_purchase_absent"), "listing", PURCHASE_ABSENT
    )

    op.add_column(
        "listing_interaction", sa.Column("units", sa.Integer(), nullable=True)
    )
    op.add_column(
        "listing_interaction",
        sa.Column("leave_requested_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_check_constraint(
        op.f("ck_listing_interaction_units"),
        "listing_interaction",
        "units IS NULL OR units > 0",
    )

    op.add_column("listing_waitlist", sa.Column("units", sa.Integer(), nullable=True))
    op.add_column(
        "listing_waitlist", sa.Column("offer_units", sa.Integer(), nullable=True)
    )
    op.create_check_constraint(
        op.f("ck_listing_waitlist_units"),
        "listing_waitlist",
        "units IS NULL OR units > 0",
    )
    op.create_check_constraint(
        op.f("ck_listing_waitlist_offer_units"),
        "listing_waitlist",
        "offer_units IS NULL OR (offer_units > 0 "
        "AND (units IS NULL OR offer_units <= units))",
    )


def downgrade() -> None:
    op.drop_constraint(
        op.f("ck_listing_waitlist_offer_units"), "listing_waitlist", type_="check"
    )
    op.drop_constraint(
        op.f("ck_listing_waitlist_units"), "listing_waitlist", type_="check"
    )
    op.drop_column("listing_waitlist", "offer_units")
    op.drop_column("listing_waitlist", "units")

    op.drop_constraint(
        op.f("ck_listing_interaction_units"), "listing_interaction", type_="check"
    )
    op.drop_column("listing_interaction", "leave_requested_at")
    op.drop_column("listing_interaction", "units")

    op.drop_constraint(op.f("ck_listing_purchase_absent"), "listing", type_="check")
    op.drop_constraint(op.f("ck_listing_purchase_units"), "listing", type_="check")
    op.drop_constraint(op.f("ck_listing_purchase_details"), "listing", type_="check")
    op.drop_column("listing", "purchase_stage")
    op.drop_column("listing", "purchase_collection_deadline")
    op.drop_column("listing", "purchase_fixed_units")
    op.drop_column("listing", "purchase_taken_units")
    op.drop_column("listing", "purchase_max_units")
    op.drop_column("listing", "purchase_min_units")
    op.drop_column("listing", "purchase_unit_price")
