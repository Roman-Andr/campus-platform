"""add versioned consents

Revision ID: b87769795a67
Revises: 2ff702db27ed
Create Date: 2026-11-14 10:21:09.646947+00:00
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "b87769795a67"
down_revision: str | Sequence[str] | None = "2ff702db27ed"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "identity_document_version",
        sa.Column("kind", sa.String(length=32), nullable=False),
        sa.Column("version", sa.Integer(), nullable=False),
        sa.Column("text_ru", sa.String(), nullable=False),
        sa.Column("text_en", sa.String(), nullable=False),
        sa.Column("published_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "kind IN ('community_rules', 'privacy_policy', "
            "'personal_data_processing', 'cross_border_transfer')",
            name=op.f("ck_identity_document_version_kind_valid"),
        ),
        sa.CheckConstraint(
            "length(text_ru) > 0 AND length(text_en) > 0",
            name=op.f("ck_identity_document_version_texts_nonempty"),
        ),
        sa.CheckConstraint(
            "version > 0", name=op.f("ck_identity_document_version_version_positive")
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_identity_document_version")),
        sa.UniqueConstraint(
            "kind", "version", name=op.f("uq_identity_document_version_kind_version")
        ),
    )
    op.create_table(
        "identity_consent_decision",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("document_id", sa.Uuid(), nullable=False),
        sa.Column("accepted", sa.Boolean(), nullable=False),
        sa.Column("decided_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("session_id", sa.Uuid(), nullable=False),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["document_id"],
            ["identity_document_version.id"],
            name=op.f(
                "fk_identity_consent_decision_document_id_identity_document_version"
            ),
        ),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["identity_user.id"],
            name=op.f("fk_identity_consent_decision_user_id_identity_user"),
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_identity_consent_decision")),
    )
    op.create_index(
        op.f("ix_identity_consent_decision_document_id"),
        "identity_consent_decision",
        ["document_id"],
        unique=False,
    )
    op.create_index(
        op.f("ix_identity_consent_decision_user_id"),
        "identity_consent_decision",
        ["user_id"],
        unique=False,
    )

    op.execute("""
        CREATE FUNCTION identity_reject_legal_mutation() RETURNS trigger
        LANGUAGE plpgsql AS $$
        BEGIN
            RAISE EXCEPTION 'Legal records are append-only'
                USING ERRCODE = '23514';
        END;
        $$
    """)
    for table in ("identity_consent_decision", "identity_document_version"):
        op.execute(f"""
            CREATE TRIGGER reject_legal_mutation
            BEFORE UPDATE OR DELETE OR TRUNCATE ON {table}
            FOR EACH STATEMENT EXECUTE FUNCTION identity_reject_legal_mutation()
        """)


def downgrade() -> None:
    op.drop_index(
        op.f("ix_identity_consent_decision_user_id"),
        table_name="identity_consent_decision",
    )
    op.drop_index(
        op.f("ix_identity_consent_decision_document_id"),
        table_name="identity_consent_decision",
    )
    op.drop_table("identity_consent_decision")
    op.drop_table("identity_document_version")
    op.execute("DROP FUNCTION identity_reject_legal_mutation()")
