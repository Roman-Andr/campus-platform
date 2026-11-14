"""Add weighted Russian and English full-text listing search."""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "57search00001"
down_revision = "77c3f7a00001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "listing",
        sa.Column(
            "search_vector",
            postgresql.TSVECTOR(),
            sa.Computed(
                "setweight(to_tsvector('russian'::regconfig, title), 'A') || "
                "setweight(to_tsvector('english'::regconfig, title), 'A') || "
                "setweight(to_tsvector('russian'::regconfig, description), 'B') || "
                "setweight(to_tsvector('english'::regconfig, description), 'B')",
                persisted=True,
            ),
            nullable=False,
        ),
    )
    op.create_index(
        "ix_listing_search", "listing", ["search_vector"], postgresql_using="gin"
    )


def downgrade() -> None:
    op.drop_index("ix_listing_search", table_name="listing")
    op.drop_column("listing", "search_vector")
