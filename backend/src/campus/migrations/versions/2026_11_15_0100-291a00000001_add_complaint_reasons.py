"""add the complaint reason catalogue

Revision ID: 291a00000001
Revises: 87a000000001
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "291a00000001"
down_revision: str | Sequence[str] | None = "62a000000001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

CODE_PATTERN = r"^[a-z][a-z0-9_]*$"
CLAUSE_MAX_LENGTH = 200


def upgrade() -> None:
    op.create_table(
        "moderation_complaint_reason",
        sa.Column("code", sa.String(length=64), nullable=False),
        sa.Column("name_ru", sa.String(length=200), nullable=False),
        sa.Column("name_en", sa.String(length=200), nullable=False),
        sa.Column("rules_document_id", sa.Uuid(), nullable=False),
        sa.Column("rules_clause", sa.String(length=CLAUSE_MAX_LENGTH), nullable=False),
        sa.Column("active", sa.Boolean(), nullable=False),
        sa.Column("version", sa.Integer(), nullable=False),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            f"code ~ '{CODE_PATTERN}'",
            name=op.f("ck_moderation_complaint_reason_code_format"),
        ),
        sa.CheckConstraint(
            "length(name_ru) > 0 AND length(name_en) > 0",
            name=op.f("ck_moderation_complaint_reason_names_nonempty"),
        ),
        sa.CheckConstraint(
            f"char_length(rules_clause) BETWEEN 1 AND {CLAUSE_MAX_LENGTH}",
            name=op.f("ck_moderation_complaint_reason_clause_length"),
        ),
        sa.CheckConstraint(
            "version > 0", name=op.f("ck_moderation_complaint_reason_version_positive")
        ),
        sa.ForeignKeyConstraint(
            ["rules_document_id"],
            ["identity_document_version.id"],
            name=op.f(
                "fk_moderation_complaint_reason_rules_document_id_"
                "identity_document_version"
            ),
            ondelete="RESTRICT",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_moderation_complaint_reason")),
        sa.UniqueConstraint("code", name=op.f("uq_moderation_complaint_reason_code")),
    )
    op.create_index(
        op.f("ix_moderation_complaint_reason_rules_document_id"),
        "moderation_complaint_reason",
        ["rules_document_id"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(
        op.f("ix_moderation_complaint_reason_rules_document_id"),
        table_name="moderation_complaint_reason",
    )
    op.drop_table("moderation_complaint_reason")
