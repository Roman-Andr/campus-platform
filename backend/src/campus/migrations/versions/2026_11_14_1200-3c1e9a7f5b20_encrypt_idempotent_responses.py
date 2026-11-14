"""encrypt idempotent responses

Stored responses become one encrypted column. Existing rows hold plaintext
responses, including issued tokens, so they are deleted: a repeat of such a
request within the key TTL runs again (and sign-in or refresh is rejected
because its code or token is already used).

Revision ID: 3c1e9a7f5b20
Revises: b97cb4e36b48
Create Date: 2026-11-14 12:00:00.000000+00:00
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "3c1e9a7f5b20"
down_revision: str | Sequence[str] | None = "b97cb4e36b48"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute("DELETE FROM idempotency_key")
    op.add_column(
        "idempotency_key", sa.Column("response", sa.LargeBinary(), nullable=True)
    )
    op.drop_column("idempotency_key", "status_code")
    op.drop_column("idempotency_key", "response_body")
    op.drop_column("idempotency_key", "response_headers")


def downgrade() -> None:
    # Encrypted responses cannot be converted back without the keys.
    op.execute("DELETE FROM idempotency_key")
    op.add_column(
        "idempotency_key",
        sa.Column(
            "response_headers", postgresql.JSONB(astext_type=sa.Text()), nullable=True
        ),
    )
    op.add_column(
        "idempotency_key", sa.Column("response_body", sa.LargeBinary(), nullable=True)
    )
    op.add_column(
        "idempotency_key", sa.Column("status_code", sa.SmallInteger(), nullable=True)
    )
    op.drop_column("idempotency_key", "response")
