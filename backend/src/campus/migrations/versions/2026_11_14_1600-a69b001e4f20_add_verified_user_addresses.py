"""Add verified user addresses and account-bound challenges.

Revision ID: a69b001e4f20
Revises: 90fb233ce001
"""

import sqlalchemy as sa
from alembic import op

revision = "a69b001e4f20"
down_revision = "90fb233ce001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "identity_user_email",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("email", sa.String(320), nullable=False),
        sa.Column("kind", sa.String(16), nullable=False),
        sa.Column("verified_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("email = lower(email)", name="email_lowercase"),
        sa.CheckConstraint("kind IN ('corporate', 'backup')", name="kind_valid"),
        sa.ForeignKeyConstraint(["user_id"], ["identity_user.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("email"),
    )
    op.create_index(
        "ix_identity_user_email_user_id", "identity_user_email", ["user_id"]
    )
    op.create_index(
        "uq_identity_user_email_backup",
        "identity_user_email",
        ["user_id"],
        unique=True,
        postgresql_where=sa.text("kind = 'backup'"),
    )
    op.execute("""
        INSERT INTO identity_user_email
            (user_id, email, kind, verified_at, created_at, updated_at)
        SELECT id, email, 'corporate', created_at, created_at, updated_at
        FROM identity_user
    """)
    op.add_column(
        "identity_sign_in_code",
        sa.Column("purpose", sa.String(16), nullable=False, server_default="sign_in"),
    )
    op.alter_column("identity_sign_in_code", "purpose", server_default=None)
    op.add_column("identity_sign_in_code", sa.Column("user_id", sa.Uuid()))
    op.create_foreign_key(
        None,
        "identity_sign_in_code",
        "identity_user",
        ["user_id"],
        ["id"],
        ondelete="CASCADE",
    )

    op.drop_constraint(
        "uq_identity_sign_in_code_email", "identity_sign_in_code", type_="unique"
    )
    op.create_unique_constraint(
        "uq_identity_sign_in_code_email_purpose_user_id",
        "identity_sign_in_code",
        ["email", "purpose", "user_id"],
        postgresql_nulls_not_distinct=True,
    )


def downgrade() -> None:
    op.execute("DELETE FROM identity_sign_in_code WHERE purpose <> 'sign_in'")
    op.drop_constraint(
        "uq_identity_sign_in_code_email_purpose_user_id",
        "identity_sign_in_code",
        type_="unique",
    )
    op.create_unique_constraint(
        "uq_identity_sign_in_code_email", "identity_sign_in_code", ["email"]
    )
    op.drop_constraint(
        "fk_identity_sign_in_code_user_id_identity_user",
        "identity_sign_in_code",
        type_="foreignkey",
    )
    op.drop_column("identity_sign_in_code", "user_id")
    op.drop_column("identity_sign_in_code", "purpose")
    op.drop_table("identity_user_email")
