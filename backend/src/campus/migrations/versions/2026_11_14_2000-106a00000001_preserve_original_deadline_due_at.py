"""Preserve the original deadline time across retries.

Revision ID: 106a00000001
Revises: 77c3f7a00001
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "106a00000001"
down_revision: str | Sequence[str] | None = "57search00001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("deadline", sa.Column("due_at", sa.DateTime(timezone=True)))
    # Original due times of already retried rows cannot be reconstructed.
    op.execute("UPDATE deadline SET due_at = available_at")
    op.alter_column("deadline", "due_at", nullable=False)


def downgrade() -> None:
    op.drop_column("deadline", "due_at")
