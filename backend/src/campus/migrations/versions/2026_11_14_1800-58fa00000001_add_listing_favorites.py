"""Add listing favorites.

Revision ID: 58fa00000001
Revises: 248e00000001
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "58fa00000001"
down_revision: str | Sequence[str] | None = "248e00000001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "listing_favorite",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("listing_id", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["listing_id"],
            ["listing.id"],
            name=op.f("fk_listing_favorite_listing_id_listing"),
        ),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["identity_user.id"],
            name=op.f("fk_listing_favorite_user_id_identity_user"),
        ),
        sa.PrimaryKeyConstraint(
            "user_id", "listing_id", name=op.f("pk_listing_favorite")
        ),
    )
    op.create_index(
        "ix_listing_favorite_user",
        "listing_favorite",
        ["user_id", "created_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_listing_favorite_user", table_name="listing_favorite")
    op.drop_table("listing_favorite")
