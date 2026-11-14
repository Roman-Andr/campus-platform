"""add email code identity

Revision ID: b97cb4e36b48
Revises: 6dff9418fdb2
Create Date: 2026-11-14 00:26:05.864446+00:00
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "b97cb4e36b48"
down_revision: str | Sequence[str] | None = "6dff9418fdb2"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "identity_sign_in_code",
        sa.Column("email", sa.String(length=320), nullable=False),
        sa.Column("code_hash", sa.String(length=64), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("attempts", sa.Integer(), nullable=False),
        sa.Column("consumed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_identity_sign_in_code")),
        sa.UniqueConstraint("email", name=op.f("uq_identity_sign_in_code_email")),
    )
    op.create_table(
        "identity_user",
        sa.Column("email", sa.String(length=320), nullable=False),
        sa.Column("first_name", sa.String(length=100), nullable=False),
        sa.Column("last_name", sa.String(length=100), nullable=False),
        sa.Column("account_type", sa.String(length=16), nullable=False),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "email = lower(email)", name=op.f("ck_identity_user_email_lowercase")
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_identity_user")),
        sa.UniqueConstraint("email", name=op.f("uq_identity_user_email")),
    )
    op.create_table(
        "identity_session",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("device_id", sa.Uuid(), nullable=False),
        sa.Column("device_name", sa.String(length=100), nullable=True),
        sa.Column("platform", sa.String(length=16), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["identity_user.id"],
            name=op.f("fk_identity_session_user_id_identity_user"),
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_identity_session")),
    )
    op.create_index(
        op.f("ix_identity_session_user_id"),
        "identity_session",
        ["user_id"],
        unique=False,
    )
    op.create_table(
        "identity_refresh_token",
        sa.Column("session_id", sa.Uuid(), nullable=False),
        sa.Column("token_hash", sa.String(length=64), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("used_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["session_id"],
            ["identity_session.id"],
            name=op.f("fk_identity_refresh_token_session_id_identity_session"),
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_identity_refresh_token")),
        sa.UniqueConstraint(
            "token_hash", name=op.f("uq_identity_refresh_token_token_hash")
        ),
    )
    op.create_index(
        op.f("ix_identity_refresh_token_session_id"),
        "identity_refresh_token",
        ["session_id"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(
        op.f("ix_identity_refresh_token_session_id"),
        table_name="identity_refresh_token",
    )
    op.drop_table("identity_refresh_token")
    op.drop_index(op.f("ix_identity_session_user_id"), table_name="identity_session")
    op.drop_table("identity_session")
    op.drop_table("identity_user")
    op.drop_table("identity_sign_in_code")
