"""Add permanent consent dispatch receipts.

Revision ID: 90fb233ce001
Revises: 46a1b2c3d4e5
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "90fb233ce001"
down_revision: str | Sequence[str] | None = "46a1b2c3d4e5"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "identity_consent_dispatch",
        sa.Column("event_id", sa.Uuid(), nullable=False),
        sa.Column("consumer", sa.String(50), nullable=False),
        sa.PrimaryKeyConstraint(
            "event_id", "consumer", name=op.f("pk_identity_consent_dispatch")
        ),
    )


def downgrade() -> None:
    op.drop_table("identity_consent_dispatch")
