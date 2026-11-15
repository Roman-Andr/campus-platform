"""Add no-show marks, event no-show votes and dispute cases.

A no-show is one row in ``reputation_no_show``: the charged participant, the
optional reporter, a required reason for a personal allegation and a status
that tells whether the mark counts, is suspended by a mutual dispute or was
lifted by a late QR code or an event vote. The partial unique indexes keep
one mark per interaction and subject and one organiser mark per event.

``reputation_event_no_show_vote`` keeps one vote of one registered
participant; the unique (listing, voter) key makes a repeated vote a no-op.

``moderation_dispute`` is the case opened by mutual no-show allegations; one
case per interaction, plus one case per event without an interaction. The
moderator decision (#94) is not part of this migration.

The journal index lets the late-QR flow find the moment an interaction
became "did not take place" without a scan of the history.

Revision ID: 66a000000001
Revises: 61a000000001
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "66a000000001"
down_revision: str | Sequence[str] | None = "61a000000001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "moderation_dispute",
        sa.Column("kind", sa.String(length=16), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("listing_id", sa.Uuid(), nullable=False),
        sa.Column("interaction_id", sa.Uuid(), nullable=True),
        sa.Column("opened_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("resolved_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("resolution", sa.Text(), nullable=True),
        sa.Column("resolved_by_id", sa.Uuid(), nullable=True),
        sa.Column("version", sa.Integer(), nullable=False),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "kind IN ('no_show')", name=op.f("ck_moderation_dispute_kind")
        ),
        sa.CheckConstraint(
            "status IN ('open','resolved')", name=op.f("ck_moderation_dispute_status")
        ),
        sa.CheckConstraint(
            "version > 0", name=op.f("ck_moderation_dispute_version_positive")
        ),
        sa.CheckConstraint(
            "(status = 'resolved') = (resolved_at IS NOT NULL)",
            name=op.f("ck_moderation_dispute_resolution_time"),
        ),
        sa.CheckConstraint(
            "(resolved_at IS NULL) = (resolution IS NULL)",
            name=op.f("ck_moderation_dispute_resolution_reason"),
        ),
        sa.ForeignKeyConstraint(
            ["interaction_id"],
            ["listing_interaction.id"],
            name=op.f("fk_moderation_dispute_interaction_id_listing_interaction"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["listing_id"],
            ["listing.id"],
            name=op.f("fk_moderation_dispute_listing_id_listing"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["resolved_by_id"],
            ["identity_user.id"],
            name=op.f("fk_moderation_dispute_resolved_by_id_identity_user"),
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_moderation_dispute")),
        sa.UniqueConstraint(
            "interaction_id", name=op.f("uq_moderation_dispute_interaction_id")
        ),
    )
    op.create_index(
        "uq_moderation_dispute_event",
        "moderation_dispute",
        ["listing_id"],
        unique=True,
        postgresql_where=sa.text("interaction_id IS NULL"),
    )
    op.create_index(
        "ix_moderation_dispute_status",
        "moderation_dispute",
        ["status", "opened_at"],
    )

    op.create_table(
        "reputation_no_show",
        sa.Column("listing_id", sa.Uuid(), nullable=False),
        sa.Column("interaction_id", sa.Uuid(), nullable=True),
        sa.Column("reporter_id", sa.Uuid(), nullable=True),
        sa.Column("subject_id", sa.Uuid(), nullable=False),
        sa.Column("kind", sa.String(length=16), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("reason", sa.Text(), nullable=True),
        sa.Column("disputed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("removed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("removed_by_id", sa.Uuid(), nullable=True),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "kind IN ('personal','event_auto','event_vote')",
            name=op.f("ck_reputation_no_show_kind"),
        ),
        sa.CheckConstraint(
            "status IN ('counted','disputed','removed')",
            name=op.f("ck_reputation_no_show_status"),
        ),
        sa.CheckConstraint(
            "(kind = 'personal') = (reason IS NOT NULL)",
            name=op.f("ck_reputation_no_show_reason_presence"),
        ),
        sa.CheckConstraint(
            "reason IS NULL OR char_length(reason) > 0",
            name=op.f("ck_reputation_no_show_reason_not_empty"),
        ),
        sa.CheckConstraint(
            "reporter_id IS NULL OR reporter_id <> subject_id",
            name=op.f("ck_reputation_no_show_distinct_people"),
        ),
        sa.CheckConstraint(
            "(interaction_id IS NULL) = (kind = 'event_vote')",
            name=op.f("ck_reputation_no_show_mark_scope"),
        ),
        sa.CheckConstraint(
            "(status = 'disputed') = (disputed_at IS NOT NULL)",
            name=op.f("ck_reputation_no_show_dispute_time"),
        ),
        sa.CheckConstraint(
            "(status = 'removed') = (removed_at IS NOT NULL)",
            name=op.f("ck_reputation_no_show_removal_time"),
        ),
        sa.ForeignKeyConstraint(
            ["interaction_id"],
            ["listing_interaction.id"],
            name=op.f("fk_reputation_no_show_interaction_id_listing_interaction"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["listing_id"],
            ["listing.id"],
            name=op.f("fk_reputation_no_show_listing_id_listing"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["removed_by_id"],
            ["identity_user.id"],
            name=op.f("fk_reputation_no_show_removed_by_id_identity_user"),
        ),
        sa.ForeignKeyConstraint(
            ["reporter_id"],
            ["identity_user.id"],
            name=op.f("fk_reputation_no_show_reporter_id_identity_user"),
        ),
        sa.ForeignKeyConstraint(
            ["subject_id"],
            ["identity_user.id"],
            name=op.f("fk_reputation_no_show_subject_id_identity_user"),
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_reputation_no_show")),
    )
    op.create_index(
        "uq_reputation_no_show_interaction_subject",
        "reputation_no_show",
        ["interaction_id", "subject_id"],
        unique=True,
        postgresql_where=sa.text("interaction_id IS NOT NULL"),
    )
    op.create_index(
        "uq_reputation_no_show_event_subject",
        "reputation_no_show",
        ["listing_id", "subject_id"],
        unique=True,
        postgresql_where=sa.text("interaction_id IS NULL"),
    )
    op.create_index(
        "ix_reputation_no_show_subject",
        "reputation_no_show",
        ["subject_id", "status", "created_at"],
    )
    op.create_index(
        "ix_reputation_no_show_listing",
        "reputation_no_show",
        ["listing_id", "created_at"],
    )

    op.create_table(
        "reputation_event_no_show_vote",
        sa.Column("listing_id", sa.Uuid(), nullable=False),
        sa.Column("interaction_id", sa.Uuid(), nullable=False),
        sa.Column("voter_id", sa.Uuid(), nullable=False),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["interaction_id"],
            ["listing_interaction.id"],
            name=op.f(
                "fk_reputation_event_no_show_vote_interaction_id_listing_interaction"
            ),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["listing_id"],
            ["listing.id"],
            name=op.f("fk_reputation_event_no_show_vote_listing_id_listing"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["voter_id"],
            ["identity_user.id"],
            name=op.f("fk_reputation_event_no_show_vote_voter_id_identity_user"),
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_reputation_event_no_show_vote")),
        sa.UniqueConstraint(
            "listing_id",
            "voter_id",
            name=op.f("uq_reputation_event_no_show_vote_listing_id_voter_id"),
        ),
    )
    op.create_index(
        "ix_reputation_event_no_show_vote_listing",
        "reputation_event_no_show_vote",
        ["listing_id", "created_at"],
    )

    op.create_index(
        "ix_listing_event_interaction_no_show",
        "listing_event",
        ["interaction_id", "created_at"],
        postgresql_where=sa.text("status = 'no_show'"),
    )


def downgrade() -> None:
    op.drop_index("ix_listing_event_interaction_no_show", table_name="listing_event")
    op.drop_index(
        "ix_reputation_event_no_show_vote_listing",
        table_name="reputation_event_no_show_vote",
    )
    op.drop_table("reputation_event_no_show_vote")
    op.drop_index("ix_reputation_no_show_listing", table_name="reputation_no_show")
    op.drop_index("ix_reputation_no_show_subject", table_name="reputation_no_show")
    op.drop_index(
        "uq_reputation_no_show_event_subject", table_name="reputation_no_show"
    )
    op.drop_index(
        "uq_reputation_no_show_interaction_subject", table_name="reputation_no_show"
    )
    op.drop_table("reputation_no_show")
    op.drop_index("ix_moderation_dispute_status", table_name="moderation_dispute")
    op.drop_index("uq_moderation_dispute_event", table_name="moderation_dispute")
    op.drop_table("moderation_dispute")
