"""Add full-text search to chat messages across all time partitions.

The vector is a stored generated column on the partitioned parent, so every
existing and future ``chat_message_*`` partition gets the same Russian and
English dictionaries. The partial GIN index covers only messages whose
``deleted_at`` is null: deleting a message removes it from the search
access path, while editing ``text`` lets PostgreSQL recompute the vector.
Original revisions are stored outside this table (#81) and are not indexed.

Revision ID: 82search00001
Revises: 78c0a7000001
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "82search00001"
down_revision: str | Sequence[str] | None = "78c0a7000001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "chat_message",
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "chat_message",
        sa.Column(
            "search_vector",
            postgresql.TSVECTOR(),
            sa.Computed(
                "to_tsvector('russian', text) || to_tsvector('english', text)",
                persisted=True,
            ),
            nullable=False,
        ),
    )
    op.create_index(
        "ix_chat_message_search",
        "chat_message",
        ["search_vector"],
        postgresql_using="gin",
        postgresql_where=sa.text("deleted_at IS NULL"),
    )


def downgrade() -> None:
    op.drop_index("ix_chat_message_search", table_name="chat_message")
    op.drop_column("chat_message", "search_vector")
    op.drop_column("chat_message", "deleted_at")
