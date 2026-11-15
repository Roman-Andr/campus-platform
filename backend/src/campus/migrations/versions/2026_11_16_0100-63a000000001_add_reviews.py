"""Add reviews, their ready-made tags and the single answer.

A review belongs to one completed interaction and names its author and the
other participant; the event case is a review of a participant about the
organiser. ``reveal_at`` is the end of the review window counted from the
completion, and ``published_at`` is set when the pair is revealed (both
reviews exist or the window closed). ``hidden_at``/``hidden_by_id`` are the
moderation mark of #94: the row and its primary fields stay for the profile
recalculations of #64.

Two partial unique indexes keep the pair keys: one review per interaction
and author for every scenario but a purchase, and one review per
``organiser -- participant`` pair of the whole purchase. A reply is unique
per review: the addressee answers once.

Revision ID: 63a000000001
Revises: 214a000000001
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "63a000000001"
down_revision: str | Sequence[str] | None = "214a000000001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "reputation_review",
        sa.Column("listing_id", sa.Uuid(), nullable=False),
        sa.Column("interaction_id", sa.Uuid(), nullable=False),
        sa.Column("kind", sa.String(length=32), nullable=False),
        sa.Column("author_id", sa.Uuid(), nullable=False),
        sa.Column("subject_id", sa.Uuid(), nullable=False),
        sa.Column("rating", sa.Integer(), nullable=False),
        sa.Column("text", sa.Text(), nullable=True),
        sa.Column("reveal_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("published_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("hidden_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("hidden_by_id", sa.Uuid(), nullable=True),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "kind IN ('giveaway','exchange','loan','skill','help','purchase','event')",
            name=op.f("ck_reputation_review_kind"),
        ),
        sa.CheckConstraint(
            "rating BETWEEN 1 AND 5", name=op.f("ck_reputation_review_rating")
        ),
        sa.CheckConstraint(
            "author_id <> subject_id",
            name=op.f("ck_reputation_review_distinct_people"),
        ),
        sa.CheckConstraint(
            "text IS NULL OR char_length(text) > 0",
            name=op.f("ck_reputation_review_text_not_empty"),
        ),
        sa.CheckConstraint(
            "(hidden_at IS NULL) = (hidden_by_id IS NULL)",
            name=op.f("ck_reputation_review_hidden_complete"),
        ),
        sa.ForeignKeyConstraint(
            ["author_id"],
            ["identity_user.id"],
            name=op.f("fk_reputation_review_author_id_identity_user"),
        ),
        sa.ForeignKeyConstraint(
            ["hidden_by_id"],
            ["identity_user.id"],
            name=op.f("fk_reputation_review_hidden_by_id_identity_user"),
        ),
        sa.ForeignKeyConstraint(
            ["interaction_id"],
            ["listing_interaction.id"],
            name=op.f("fk_reputation_review_interaction_id_listing_interaction"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["listing_id"],
            ["listing.id"],
            name=op.f("fk_reputation_review_listing_id_listing"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["subject_id"],
            ["identity_user.id"],
            name=op.f("fk_reputation_review_subject_id_identity_user"),
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_reputation_review")),
    )
    op.create_index(
        "uq_reputation_review_interaction_author",
        "reputation_review",
        ["interaction_id", "author_id"],
        unique=True,
        postgresql_where=sa.text("kind <> 'purchase'"),
    )
    op.create_index(
        "uq_reputation_review_purchase_pair",
        "reputation_review",
        ["listing_id", "author_id", "subject_id"],
        unique=True,
        postgresql_where=sa.text("kind = 'purchase'"),
    )
    op.create_index(
        "ix_reputation_review_subject",
        "reputation_review",
        ["subject_id", "created_at", "id"],
    )
    op.create_index(
        "ix_reputation_review_pending",
        "reputation_review",
        ["interaction_id"],
        postgresql_where=sa.text("published_at IS NULL"),
    )
    op.create_table(
        "reputation_review_tag",
        sa.Column("review_id", sa.Uuid(), nullable=False),
        sa.Column("tag", sa.String(length=32), nullable=False),
        sa.ForeignKeyConstraint(
            ["review_id"],
            ["reputation_review.id"],
            name=op.f("fk_reputation_review_tag_review_id_reputation_review"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint(
            "review_id", "tag", name=op.f("pk_reputation_review_tag")
        ),
    )
    op.create_table(
        "reputation_review_reply",
        sa.Column("review_id", sa.Uuid(), nullable=False),
        sa.Column("author_id", sa.Uuid(), nullable=False),
        sa.Column("text", sa.Text(), nullable=False),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "char_length(text) > 0",
            name=op.f("ck_reputation_review_reply_text_not_empty"),
        ),
        sa.ForeignKeyConstraint(
            ["author_id"],
            ["identity_user.id"],
            name=op.f("fk_reputation_review_reply_author_id_identity_user"),
        ),
        sa.ForeignKeyConstraint(
            ["review_id"],
            ["reputation_review.id"],
            name=op.f("fk_reputation_review_reply_review_id_reputation_review"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_reputation_review_reply")),
        sa.UniqueConstraint(
            "review_id", name=op.f("uq_reputation_review_reply_review_id")
        ),
    )


def downgrade() -> None:
    # Dropping the review table drops its indexes with it.
    op.drop_table("reputation_review_reply")
    op.drop_table("reputation_review_tag")
    op.drop_table("reputation_review")
