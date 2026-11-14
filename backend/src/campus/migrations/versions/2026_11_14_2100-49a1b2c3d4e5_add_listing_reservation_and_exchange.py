"""Add the item reservation deadline and exchange offers.

Revision ID: 49a1b2c3d4e5
Revises: 86a000000001
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "49a1b2c3d4e5"
down_revision: str | Sequence[str] | None = "86a000000001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "listing_interaction",
        sa.Column("reservation_due_at", sa.DateTime(timezone=True)),
    )
    op.add_column(
        "listing_interaction",
        sa.Column("offer_description", sa.Text()),
    )


def downgrade() -> None:
    op.drop_column("listing_interaction", "offer_description")
    op.drop_column("listing_interaction", "reservation_due_at")
