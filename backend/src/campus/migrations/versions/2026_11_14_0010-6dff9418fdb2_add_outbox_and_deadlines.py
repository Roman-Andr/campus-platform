"""Add outbox and deadlines

Revision ID: 6dff9418fdb2
Revises: dc8a2482d824
Create Date: 2026-11-14 00:10:00.000000+00:00
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "6dff9418fdb2"
down_revision: str | Sequence[str] | None = "dc8a2482d824"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # Background jobs of the shared kernel (campus.core.jobs): side effects
    # after commit and deadlines processed by the scheduler.
    op.create_table(
        "deadline",
        sa.Column("key", sa.String(length=200), nullable=True),
        sa.Column("topic", sa.String(length=100), nullable=False),
        sa.Column("payload", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("available_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("attempts", sa.Integer(), nullable=False),
        sa.Column("last_error", sa.Text(), nullable=True),
        sa.Column("processed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("failed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_deadline")),
    )
    op.create_index(
        "ix_deadline_pending",
        "deadline",
        ["available_at"],
        unique=False,
        postgresql_where=sa.text("processed_at IS NULL AND failed_at IS NULL"),
    )
    op.create_index(
        "uq_deadline_pending_key",
        "deadline",
        ["key"],
        unique=True,
        postgresql_where=sa.text("processed_at IS NULL AND failed_at IS NULL"),
    )
    op.create_table(
        "outbox_message",
        sa.Column("topic", sa.String(length=100), nullable=False),
        sa.Column("payload", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("available_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("attempts", sa.Integer(), nullable=False),
        sa.Column("last_error", sa.Text(), nullable=True),
        sa.Column("processed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("failed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_outbox_message")),
    )
    op.create_index(
        "ix_outbox_message_pending",
        "outbox_message",
        ["available_at"],
        unique=False,
        postgresql_where=sa.text("processed_at IS NULL AND failed_at IS NULL"),
    )


def downgrade() -> None:
    # Indexes are dropped together with their tables.
    op.drop_table("outbox_message")
    op.drop_table("deadline")
