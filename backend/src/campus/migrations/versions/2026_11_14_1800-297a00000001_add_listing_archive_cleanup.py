"""Add listing archive cleanup.

Revision ID: 297a00000001
Revises: 56feed000001
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "297a00000001"
down_revision: str | None = "56feed000001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("listing", sa.Column("archived_at", sa.DateTime(timezone=True)))
    op.add_column("listing", sa.Column("purged_at", sa.DateTime(timezone=True)))
    # Existing archived listings entered the archive with their latest
    # status change; the journal records it, the update time bounds it.
    op.execute(
        """
        UPDATE listing SET archived_at = coalesce(
            (
                SELECT max(e.created_at) FROM listing_event e
                WHERE e.listing_id = listing.id
                  AND e.interaction_id IS NULL
                  AND e.status = listing.status
            ),
            listing.updated_at
        )
        WHERE status IN ('expired', 'completed', 'cancelled')
        """
    )
    op.create_index(
        "ix_listing_archive_cleanup",
        "listing",
        ["archived_at", "id"],
        postgresql_where=sa.text("archived_at IS NOT NULL AND purged_at IS NULL"),
    )


def downgrade() -> None:
    op.drop_index("ix_listing_archive_cleanup", table_name="listing")
    op.drop_column("listing", "purged_at")
    op.drop_column("listing", "archived_at")
