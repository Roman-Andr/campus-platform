"""Add the selected help executor and its unique index.

Revision ID: 51a1b2c3d4e5
Revises: 85a000000001
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "51a1b2c3d4e5"
down_revision: str | Sequence[str] | None = "85a000000001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

EXECUTOR = "status = 'accepted' AND executor"


def upgrade() -> None:
    op.add_column(
        "listing_interaction",
        sa.Column("executor", sa.Boolean(), server_default=sa.false(), nullable=False),
    )
    op.alter_column("listing_interaction", "executor", server_default=None)
    # At most one accepted executor per help request; all other applications
    # stay pending as the reserve. A plain unique constraint would also match
    # cancelled, completed or rejected rows, so the predicate is partial.
    op.create_index(
        "uq_listing_one_executor",
        "listing_interaction",
        ["listing_id"],
        unique=True,
        postgresql_where=sa.text(EXECUTOR),
    )


def downgrade() -> None:
    op.drop_index("uq_listing_one_executor", table_name="listing_interaction")
    op.drop_column("listing_interaction", "executor")
