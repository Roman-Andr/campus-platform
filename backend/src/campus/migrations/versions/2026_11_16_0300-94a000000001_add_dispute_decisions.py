"""Add the moderator decision, payment marks and the other dispute subjects.

A case now records the moment of the disputed event (the seven-day opening
window is counted from it, not from the start of the interaction), the
participant who opened it and their account of the case. The single
decision stores its action, the justification and the moderator; ``version``
is the optimistic lock that keeps two decisions from overwriting each other.

``listing_payment_claim`` is the two-sided payment mark of a fixed group
purchase share: the participant claims the payment, the organiser confirms
or rejects it, and a claim unanswered for the configured wait becomes
disputable (#54, #94). Partial unique indexes keep one active and one
confirmed claim per share.

Existing cases are backfilled: ``event_at`` becomes ``opened_at`` and a
late-QR resolution becomes the ``late_qr`` action. A moderator-completed
interaction gets its own completion method.

Revision ID: 94a000000001
Revises: 64a000000001
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "94a000000001"
down_revision: str | Sequence[str] | None = "83a000000001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "listing_payment_claim",
        sa.Column("listing_id", sa.Uuid(), nullable=False),
        sa.Column("interaction_id", sa.Uuid(), nullable=False),
        sa.Column("participant_id", sa.Uuid(), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("claimed_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("responded_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("responded_by_id", sa.Uuid(), nullable=True),
        sa.Column("version", sa.Integer(), nullable=False),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "status IN ('claimed','disputed','confirmed','rejected')",
            name=op.f("ck_listing_payment_claim_status"),
        ),
        sa.CheckConstraint(
            "version > 0", name=op.f("ck_listing_payment_claim_version_positive")
        ),
        sa.CheckConstraint(
            "(responded_at IS NULL) = (responded_by_id IS NULL)",
            name=op.f("ck_listing_payment_claim_response_complete"),
        ),
        sa.CheckConstraint(
            "(status IN ('confirmed','rejected')) = (responded_at IS NOT NULL)",
            name=op.f("ck_listing_payment_claim_response_required"),
        ),
        sa.ForeignKeyConstraint(
            ["interaction_id"],
            ["listing_interaction.id"],
            name=op.f("fk_listing_payment_claim_interaction_id_listing_interaction"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["listing_id"],
            ["listing.id"],
            name=op.f("fk_listing_payment_claim_listing_id_listing"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["participant_id"],
            ["identity_user.id"],
            name=op.f("fk_listing_payment_claim_participant_id_identity_user"),
        ),
        sa.ForeignKeyConstraint(
            ["responded_by_id"],
            ["identity_user.id"],
            name=op.f("fk_listing_payment_claim_responded_by_id_identity_user"),
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_listing_payment_claim")),
    )
    op.create_index(
        "uq_listing_payment_claim_active",
        "listing_payment_claim",
        ["interaction_id"],
        unique=True,
        postgresql_where=sa.text("status IN ('claimed','disputed')"),
    )
    op.create_index(
        "uq_listing_payment_claim_confirmed",
        "listing_payment_claim",
        ["interaction_id"],
        unique=True,
        postgresql_where=sa.text("status = 'confirmed'"),
    )
    op.create_index(
        "ix_listing_payment_claim_listing",
        "listing_payment_claim",
        ["listing_id", "created_at"],
    )

    op.drop_constraint(
        op.f("ck_listing_interaction_completion_method"),
        "listing_interaction",
        type_="check",
    )
    op.create_check_constraint(
        op.f("ck_listing_interaction_completion_method"),
        "listing_interaction",
        "completion_method IS NULL OR "
        "completion_method IN ('qr','no_meeting','moderator')",
    )

    op.add_column(
        "moderation_dispute", sa.Column("opened_by_id", sa.Uuid(), nullable=True)
    )
    op.add_column(
        "moderation_dispute",
        sa.Column("event_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "moderation_dispute", sa.Column("statement", sa.Text(), nullable=True)
    )
    op.add_column(
        "moderation_dispute",
        sa.Column("action", sa.String(length=32), nullable=True),
    )
    op.add_column(
        "moderation_dispute", sa.Column("payment_claim_id", sa.Uuid(), nullable=True)
    )
    op.execute(
        "UPDATE moderation_dispute"
        " SET event_at = opened_at,"
        " action = CASE"
        "  WHEN status <> 'resolved' THEN NULL"
        "  WHEN resolution = 'late_qr' THEN 'late_qr'"
        "  ELSE 'legacy' END"
    )
    op.alter_column(
        "moderation_dispute",
        "event_at",
        existing_type=sa.DateTime(timezone=True),
        nullable=False,
    )
    op.drop_constraint(
        op.f("ck_moderation_dispute_kind"), "moderation_dispute", type_="check"
    )
    op.create_check_constraint(
        op.f("ck_moderation_dispute_kind"),
        "moderation_dispute",
        "kind IN ('no_show','not_returned','payment')",
    )
    op.create_check_constraint(
        op.f("ck_moderation_dispute_action"),
        "moderation_dispute",
        "action IS NULL OR action IN ("
        "'keep','lift_no_show','complete','confirm_payment',"
        "'reject_payment','late_qr','legacy')",
    )
    op.create_check_constraint(
        op.f("ck_moderation_dispute_resolution_action"),
        "moderation_dispute",
        "(status = 'resolved') = (action IS NOT NULL)",
    )
    op.create_check_constraint(
        op.f("ck_moderation_dispute_payment_subject"),
        "moderation_dispute",
        "(kind = 'payment') = (payment_claim_id IS NOT NULL)",
    )
    op.create_check_constraint(
        op.f("ck_moderation_dispute_statement_not_empty"),
        "moderation_dispute",
        "statement IS NULL OR char_length(statement) > 0",
    )
    op.create_check_constraint(
        op.f("ck_moderation_dispute_event_before_opening"),
        "moderation_dispute",
        "event_at <= opened_at",
    )
    op.create_foreign_key(
        op.f("fk_moderation_dispute_payment_claim_id_listing_payment_claim"),
        "moderation_dispute",
        "listing_payment_claim",
        ["payment_claim_id"],
        ["id"],
        ondelete="RESTRICT",
    )
    op.create_foreign_key(
        op.f("fk_moderation_dispute_opened_by_id_identity_user"),
        "moderation_dispute",
        "identity_user",
        ["opened_by_id"],
        ["id"],
    )
    op.create_unique_constraint(
        op.f("uq_moderation_dispute_payment_claim_id"),
        "moderation_dispute",
        ["payment_claim_id"],
    )
    op.drop_constraint(
        op.f("uq_moderation_dispute_interaction_id"),
        "moderation_dispute",
        type_="unique",
    )
    op.create_index(
        "uq_moderation_dispute_interaction_subject",
        "moderation_dispute",
        ["interaction_id"],
        unique=True,
        postgresql_where=sa.text("kind IN ('no_show','not_returned')"),
    )
    op.create_index(
        "ix_moderation_dispute_kind",
        "moderation_dispute",
        ["kind", "opened_at"],
    )


def downgrade() -> None:
    # A moderator decision and a payment mark cannot be represented by the
    # old schema. The completed interactions stay completed, but the old
    # check reads a moderator completion as "without a meeting"; payment
    # marks are dropped with their table, and an open dispute loses its
    # subject. Keeping the rows would fail the old constraints instead.
    op.execute(
        "UPDATE listing_interaction SET completion_method = 'no_meeting'"
        " WHERE completion_method = 'moderator'"
    )
    op.drop_index(
        "ix_moderation_dispute_kind",
        table_name="moderation_dispute",
    )
    op.drop_index(
        "uq_moderation_dispute_interaction_subject",
        table_name="moderation_dispute",
    )
    op.create_unique_constraint(
        op.f("uq_moderation_dispute_interaction_id"),
        "moderation_dispute",
        ["interaction_id"],
    )
    op.drop_constraint(
        op.f("uq_moderation_dispute_payment_claim_id"),
        "moderation_dispute",
        type_="unique",
    )
    op.drop_constraint(
        op.f("fk_moderation_dispute_opened_by_id_identity_user"),
        "moderation_dispute",
        type_="foreignkey",
    )
    op.drop_constraint(
        op.f("fk_moderation_dispute_payment_claim_id_listing_payment_claim"),
        "moderation_dispute",
        type_="foreignkey",
    )
    op.drop_constraint(
        op.f("ck_moderation_dispute_event_before_opening"),
        "moderation_dispute",
        type_="check",
    )
    op.drop_constraint(
        op.f("ck_moderation_dispute_statement_not_empty"),
        "moderation_dispute",
        type_="check",
    )
    op.drop_constraint(
        op.f("ck_moderation_dispute_payment_subject"),
        "moderation_dispute",
        type_="check",
    )
    op.drop_constraint(
        op.f("ck_moderation_dispute_resolution_action"),
        "moderation_dispute",
        type_="check",
    )
    op.drop_constraint(
        op.f("ck_moderation_dispute_action"),
        "moderation_dispute",
        type_="check",
    )
    op.drop_constraint(
        op.f("ck_moderation_dispute_kind"), "moderation_dispute", type_="check"
    )
    op.create_check_constraint(
        op.f("ck_moderation_dispute_kind"),
        "moderation_dispute",
        "kind IN ('no_show')",
    )
    op.drop_column("moderation_dispute", "payment_claim_id")
    op.drop_column("moderation_dispute", "action")
    op.drop_column("moderation_dispute", "statement")
    op.drop_column("moderation_dispute", "event_at")
    op.drop_column("moderation_dispute", "opened_by_id")

    op.drop_constraint(
        op.f("ck_listing_interaction_completion_method"),
        "listing_interaction",
        type_="check",
    )
    op.create_check_constraint(
        op.f("ck_listing_interaction_completion_method"),
        "listing_interaction",
        "completion_method IS NULL OR completion_method IN ('qr','no_meeting')",
    )

    op.drop_index(
        "ix_listing_payment_claim_listing", table_name="listing_payment_claim"
    )
    op.drop_index(
        "uq_listing_payment_claim_confirmed", table_name="listing_payment_claim"
    )
    op.drop_index("uq_listing_payment_claim_active", table_name="listing_payment_claim")
    op.drop_table("listing_payment_claim")
