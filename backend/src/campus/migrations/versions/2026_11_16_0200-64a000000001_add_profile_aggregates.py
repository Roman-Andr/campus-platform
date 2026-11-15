"""Add the derived rating and counters of profiles.

One row per user caches the deterministic projection of the primary data:
the eligible ratings with their weights, the completion and cancellation
counters, the non-disputed no-shows and the tag counters. The public rating
is computed from these sums and the service-wide mean, so the smoothing
constant stays a configuration value and a review of one user changes only
that user's row.

``user_id`` is unique and cascades with the account. The row is a cache:
the background job and ``python -m campus.admin recompute-reputation``
rewrite it from scratch.

Revision ID: 64a000000001
Revises: 63a000000001
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "64a000000001"
down_revision: str | Sequence[str] | None = "63a000000001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "reputation_profile_aggregate",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("rating_count", sa.Integer(), nullable=False),
        sa.Column("rating_sum", sa.Integer(), nullable=False),
        sa.Column("rating_weight_sum", sa.Float(), nullable=False),
        sa.Column("rating_weighted_sum", sa.Float(), nullable=False),
        sa.Column("completed_interactions", sa.Integer(), nullable=False),
        sa.Column("no_shows", sa.Integer(), nullable=False),
        sa.Column("cancelled_after_acceptance", sa.Integer(), nullable=False),
        sa.Column("late_cancellations", sa.Integer(), nullable=False),
        sa.Column(
            "tag_counts",
            postgresql.JSONB(astext_type=sa.Text()),
            server_default=sa.text("'{}'::jsonb"),
            nullable=False,
        ),
        sa.Column("computed_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "rating_count >= 0",
            name=op.f("ck_reputation_profile_aggregate_rating_count"),
        ),
        sa.CheckConstraint(
            "rating_sum >= 0", name=op.f("ck_reputation_profile_aggregate_rating_sum")
        ),
        sa.CheckConstraint(
            "rating_weight_sum >= 0",
            name=op.f("ck_reputation_profile_aggregate_rating_weight_sum"),
        ),
        sa.CheckConstraint(
            "rating_weighted_sum >= 0",
            name=op.f("ck_reputation_profile_aggregate_rating_weighted_sum"),
        ),
        sa.CheckConstraint(
            "completed_interactions >= 0",
            name=op.f("ck_reputation_profile_aggregate_completed_interactions"),
        ),
        sa.CheckConstraint(
            "no_shows >= 0", name=op.f("ck_reputation_profile_aggregate_no_shows")
        ),
        sa.CheckConstraint(
            "cancelled_after_acceptance >= 0",
            name=op.f("ck_reputation_profile_aggregate_cancelled_after_acceptance"),
        ),
        sa.CheckConstraint(
            "late_cancellations >= 0",
            name=op.f("ck_reputation_profile_aggregate_late_cancellations"),
        ),
        sa.CheckConstraint(
            "jsonb_typeof(tag_counts) = 'object'",
            name=op.f("ck_reputation_profile_aggregate_tag_counts"),
        ),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["identity_user.id"],
            name=op.f("fk_reputation_profile_aggregate_user_id_identity_user"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_reputation_profile_aggregate")),
        sa.UniqueConstraint(
            "user_id", name=op.f("uq_reputation_profile_aggregate_user_id")
        ),
    )


def downgrade() -> None:
    op.drop_table("reputation_profile_aggregate")
