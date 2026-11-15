"""Add the loan return deadline, the author's loan period and stage scans.

A loan is a giveaway-like item with two accepted actions: the handover moves
the interaction to the ``issued`` stage without completing it, and the return
finishes it. The handover moment plus the author's loan period gives
``listing_interaction.return_due_at``: the reminder, the "overdue" flag and
the "not returned" threshold all derive from this single stored deadline.

The author's period lives once, on the item details row, instead of a copy of
the deadline on the listing and on every interaction.

``reputation_qr_scan.result`` gains ``stage_advanced``: a handover scan is
stored like any other scan (its nonce stays single-use) but it does not
complete the interaction.

Revision ID: 214a000000001
Revises: 66a000000001
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "214a000000001"
down_revision: str | Sequence[str] | None = "66a000000001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("listing_item", sa.Column("loan_days", sa.Integer(), nullable=True))
    op.create_check_constraint(
        op.f("ck_listing_item_item_mode"),
        "listing_item",
        "mode IN ('giveaway','exchange','loan')",
    )
    op.create_check_constraint(
        op.f("ck_listing_item_item_loan_days"),
        "listing_item",
        "(mode = 'loan' AND loan_days IS NOT NULL AND loan_days >= 1) OR "
        "(mode <> 'loan' AND loan_days IS NULL)",
    )
    op.add_column(
        "listing_interaction",
        sa.Column("return_due_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.drop_constraint(
        op.f("ck_reputation_qr_scan_result"), "reputation_qr_scan", type_="check"
    )
    op.create_check_constraint(
        op.f("ck_reputation_qr_scan_result"),
        "reputation_qr_scan",
        "result IN ('completed','stage_advanced')",
    )


def downgrade() -> None:
    # The old schema cannot represent a handover scan or a return reminder;
    # refusing the downgrade would strand a deployed database, and keeping the
    # rows would claim a completion that never happened. The interactions
    # themselves stay: an accepted interaction with an unknown stage is read
    # as "a stage action exists" by the old code, which fails closed.
    op.execute(
        "DELETE FROM notification_reminder WHERE payload->>'type' = 'return.reminder'"
    )
    op.execute("DELETE FROM reputation_qr_scan WHERE result = 'stage_advanced'")
    op.drop_constraint(
        op.f("ck_reputation_qr_scan_result"), "reputation_qr_scan", type_="check"
    )
    op.create_check_constraint(
        op.f("ck_reputation_qr_scan_result"),
        "reputation_qr_scan",
        "result = 'completed'",
    )
    op.drop_column("listing_interaction", "return_due_at")
    op.drop_constraint(
        op.f("ck_listing_item_item_loan_days"), "listing_item", type_="check"
    )
    op.drop_constraint(op.f("ck_listing_item_item_mode"), "listing_item", type_="check")
    op.drop_column("listing_item", "loan_days")
