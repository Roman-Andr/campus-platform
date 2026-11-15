"""Add six-digit confirmation codes.

Revision ID: 60a000000001
Revises: 84merge00001
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "60a000000001"
down_revision: str | Sequence[str] | None = "84merge00001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "reputation_confirmation_code",
        sa.Column("listing_id", sa.Uuid(), nullable=False),
        sa.Column("interaction_id", sa.Uuid(), nullable=False),
        sa.Column("presenter_id", sa.Uuid(), nullable=False),
        sa.Column("code_hash", sa.String(length=64), nullable=False),
        sa.Column("issued_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("attempts", sa.Integer(), nullable=False),
        sa.Column("consumed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "attempts >= 0",
            name=op.f("ck_reputation_confirmation_code_attempts"),
        ),
        sa.CheckConstraint(
            "char_length(code_hash) = 64",
            name=op.f("ck_reputation_confirmation_code_code_hash"),
        ),
        sa.CheckConstraint(
            "expires_at > issued_at",
            name=op.f("ck_reputation_confirmation_code_validity"),
        ),
        sa.ForeignKeyConstraint(
            ["interaction_id"],
            ["listing_interaction.id"],
            name=op.f(
                "fk_reputation_confirmation_code_interaction_id_listing_interaction"
            ),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["listing_id"],
            ["listing.id"],
            name=op.f("fk_reputation_confirmation_code_listing_id_listing"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["presenter_id"],
            ["identity_user.id"],
            name=op.f("fk_reputation_confirmation_code_presenter_id_identity_user"),
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_reputation_confirmation_code")),
        sa.UniqueConstraint(
            "interaction_id",
            name=op.f("uq_reputation_confirmation_code_interaction_id"),
        ),
    )


def downgrade() -> None:
    op.drop_table("reputation_confirmation_code")
