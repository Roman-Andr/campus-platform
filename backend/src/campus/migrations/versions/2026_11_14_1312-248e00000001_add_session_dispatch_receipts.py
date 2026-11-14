"""add session dispatch receipts

Revision ID: 248e00000001
Revises: f45a001b0001
Create Date: 2026-11-14 13:12:10.958407+00:00
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "248e00000001"
down_revision: str | Sequence[str] | None = "f45a001b0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "identity_session_dispatch",
        sa.Column("event_id", sa.Uuid(), nullable=False),
        sa.Column("consumer", sa.String(50), nullable=False),
        sa.PrimaryKeyConstraint(
            "event_id", "consumer", name=op.f("pk_identity_session_dispatch")
        ),
    )


def downgrade() -> None:
    op.drop_table("identity_session_dispatch")
