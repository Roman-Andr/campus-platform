"""Add private photo files.

Revision ID: f45a001b0001
Revises: a69b001e4f20
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "f45a001b0001"
down_revision: str | None = "a69b001e4f20"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "file",
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("owner_id", sa.Uuid(), nullable=False),
        sa.Column("purpose", sa.String(32), nullable=False),
        sa.Column("key", sa.String(200), nullable=False),
        sa.Column("status", sa.String(16), nullable=False),
        sa.Column("size", sa.Integer(), nullable=False),
        sa.Column("rejection_reason", sa.String(64)),
        sa.Column("upload_expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("listing_id", sa.Uuid()),
        sa.Column("position", sa.Integer()),
        sa.PrimaryKeyConstraint("id"),
        sa.ForeignKeyConstraint(["owner_id"], ["identity_user.id"]),
        sa.ForeignKeyConstraint(["listing_id"], ["listing.id"]),
        sa.UniqueConstraint("key"),
        sa.CheckConstraint(
            "status IN ('pending','processing','ready','rejected')", name="status"
        ),
        sa.CheckConstraint("size >= 0", name="size"),
        sa.CheckConstraint("position IS NULL OR position >= 0", name="position"),
        sa.CheckConstraint(
            "(listing_id IS NULL) = (position IS NULL)", name="attachment"
        ),
    )
    op.create_index("ix_file_listing_id", "file", ["listing_id"])


def downgrade() -> None:
    op.drop_table("file")
