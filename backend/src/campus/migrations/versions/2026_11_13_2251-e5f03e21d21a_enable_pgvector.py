"""Enable pgvector

Revision ID: e5f03e21d21a
Revises:
Create Date: 2026-11-13 22:51:03.442801+00:00
"""

from collections.abc import Sequence

from alembic import op

revision: str = "e5f03e21d21a"
down_revision: str | Sequence[str] | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # Embeddings for semantic search and the AI assistant (specification,
    # 4.1); the image is PostgreSQL 18 with the extension available.
    op.execute("CREATE EXTENSION IF NOT EXISTS vector")


def downgrade() -> None:
    op.execute("DROP EXTENSION IF EXISTS vector")
