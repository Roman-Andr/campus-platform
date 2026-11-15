"""Add offline Ed25519 QR confirmations.

The online scan table becomes the single journal of used confirmation codes:
``mode`` distinguishes online and offline rows, the device-generated
``confirmation_id`` identifies an offline submission even after the
``Idempotency-Key`` expires, and ``payload_hash`` detects an altered payload
reusing that id. Offline arrival time is stored separately from ``issued_at``
so the 24-hour window can be audited.

The acceptance time stays in the append-only listing journal: this migration
only adds a partial index that makes the first accepted event of an
interaction cheap to read. Adding a duplicate timestamp column would create a
second source of truth.

Revision ID: 71a000000001
Revises: 81a000000001
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "71a000000001"
down_revision: str | Sequence[str] | None = "81a000000001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "reputation_qr_scan",
        sa.Column("mode", sa.String(8), server_default="online", nullable=False),
    )
    op.alter_column("reputation_qr_scan", "mode", server_default=None)
    op.add_column(
        "reputation_qr_scan", sa.Column("confirmation_id", sa.Uuid(), nullable=True)
    )
    op.add_column(
        "reputation_qr_scan", sa.Column("payload_hash", sa.String(64), nullable=True)
    )
    op.add_column(
        "reputation_qr_scan",
        sa.Column("received_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.execute(
        "UPDATE reputation_qr_scan SET received_at = created_at"
        " WHERE received_at IS NULL"
    )
    op.alter_column("reputation_qr_scan", "received_at", nullable=False)

    op.create_unique_constraint(
        op.f("uq_reputation_qr_scan_confirmation_id"),
        "reputation_qr_scan",
        ["confirmation_id"],
    )
    op.create_check_constraint(
        op.f("ck_reputation_qr_scan_mode"),
        "reputation_qr_scan",
        "mode IN ('online','offline')",
    )
    op.create_check_constraint(
        op.f("ck_reputation_qr_scan_offline_fields"),
        "reputation_qr_scan",
        "(mode = 'offline') = (confirmation_id IS NOT NULL)"
        " AND (mode = 'offline') = (payload_hash IS NOT NULL)",
    )

    # The first journal event with status 'accepted' is the true acceptance
    # time; offline codes may not predate it.
    op.create_index(
        "ix_listing_event_interaction_accepted",
        "listing_event",
        ["interaction_id", "created_at"],
        postgresql_where=sa.text("status = 'accepted'"),
    )


def downgrade() -> None:
    op.drop_index("ix_listing_event_interaction_accepted", table_name="listing_event")
    op.drop_constraint(
        op.f("ck_reputation_qr_scan_offline_fields"),
        "reputation_qr_scan",
        type_="check",
    )
    op.drop_constraint(
        op.f("ck_reputation_qr_scan_mode"), "reputation_qr_scan", type_="check"
    )
    op.drop_constraint(
        op.f("uq_reputation_qr_scan_confirmation_id"),
        "reputation_qr_scan",
        type_="unique",
    )
    op.drop_column("reputation_qr_scan", "received_at")
    op.drop_column("reputation_qr_scan", "payload_hash")
    op.drop_column("reputation_qr_scan", "confirmation_id")
    op.drop_column("reputation_qr_scan", "mode")
