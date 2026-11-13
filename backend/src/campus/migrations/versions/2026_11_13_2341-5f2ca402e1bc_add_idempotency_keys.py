"""Add idempotency keys

Revision ID: 5f2ca402e1bc
Revises: e5f03e21d21a
Create Date: 2026-11-13 23:41:06.614900+00:00
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "5f2ca402e1bc"
down_revision: str | Sequence[str] | None = "e5f03e21d21a"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # Idempotency-Key values and stored responses (specification, 4.3).
    op.create_table(
        "idempotency_key",
        sa.Column("scope", sa.String(length=64), nullable=False),
        sa.Column("key", sa.Uuid(), nullable=False),
        sa.Column("fingerprint", sa.LargeBinary(length=32), nullable=False),
        sa.Column("status_code", sa.SmallInteger(), nullable=True),
        sa.Column("response_body", sa.LargeBinary(), nullable=True),
        sa.Column(
            "response_headers", postgresql.JSONB(astext_type=sa.Text()), nullable=True
        ),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("scope", "key", name=op.f("pk_idempotency_key")),
    )
    op.create_index(
        op.f("ix_idempotency_key_expires_at"),
        "idempotency_key",
        ["expires_at"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(op.f("ix_idempotency_key_expires_at"), table_name="idempotency_key")
    op.drop_table("idempotency_key")
