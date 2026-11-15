"""Add Ed25519 device keys and one-time online QR scans.

Revision ID: 59a000000001
Revises: 78c0a7000001
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "59a000000001"
down_revision: str | Sequence[str] | None = "78c0a7000001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "reputation_device_key",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("session_id", sa.Uuid(), nullable=False),
        sa.Column("public_key", sa.LargeBinary(32), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "octet_length(public_key) = 32",
            name=op.f("ck_reputation_device_key_public_key_length"),
        ),
        sa.ForeignKeyConstraint(
            ["session_id"],
            ["identity_session.id"],
            name=op.f("fk_reputation_device_key_session_id_identity_session"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["identity_user.id"],
            name=op.f("fk_reputation_device_key_user_id_identity_user"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_reputation_device_key")),
        sa.UniqueConstraint(
            "public_key", name=op.f("uq_reputation_device_key_public_key")
        ),
    )
    op.create_index(
        "ix_reputation_device_key_user",
        "reputation_device_key",
        ["user_id", "created_at"],
    )
    op.create_index(
        "uq_reputation_device_key_session_active",
        "reputation_device_key",
        ["session_id"],
        unique=True,
        postgresql_where=sa.text("revoked_at IS NULL"),
    )

    op.create_table(
        "reputation_qr_scan",
        sa.Column("listing_id", sa.Uuid(), nullable=False),
        sa.Column("interaction_id", sa.Uuid(), nullable=False),
        sa.Column("device_key_id", sa.Uuid(), nullable=False),
        sa.Column("presenter_id", sa.Uuid(), nullable=False),
        sa.Column("scanner_id", sa.Uuid(), nullable=False),
        sa.Column("nonce", sa.Uuid(), nullable=False),
        sa.Column("issued_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("result", sa.String(16), nullable=False),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "presenter_id <> scanner_id",
            name=op.f("ck_reputation_qr_scan_distinct_participants"),
        ),
        sa.CheckConstraint(
            "result = 'completed'",
            name=op.f("ck_reputation_qr_scan_result"),
        ),
        sa.ForeignKeyConstraint(
            ["device_key_id"],
            ["reputation_device_key.id"],
            name=op.f("fk_reputation_qr_scan_device_key_id_reputation_device_key"),
            ondelete="RESTRICT",
        ),
        sa.ForeignKeyConstraint(
            ["interaction_id"],
            ["listing_interaction.id"],
            name=op.f("fk_reputation_qr_scan_interaction_id_listing_interaction"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["listing_id"],
            ["listing.id"],
            name=op.f("fk_reputation_qr_scan_listing_id_listing"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["presenter_id"],
            ["identity_user.id"],
            name=op.f("fk_reputation_qr_scan_presenter_id_identity_user"),
        ),
        sa.ForeignKeyConstraint(
            ["scanner_id"],
            ["identity_user.id"],
            name=op.f("fk_reputation_qr_scan_scanner_id_identity_user"),
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_reputation_qr_scan")),
        sa.UniqueConstraint("nonce", name=op.f("uq_reputation_qr_scan_nonce")),
    )
    op.create_index(
        "ix_reputation_qr_scan_interaction",
        "reputation_qr_scan",
        ["interaction_id", "created_at"],
    )

    # Revoking a session (sign-out, reinstall, recovery or a block) also
    # revokes its device key. This keeps the key lifecycle in one place even
    # when the identity module revokes several sessions at once.
    op.execute(
        """
        CREATE FUNCTION reputation_revoke_session_keys() RETURNS trigger
        LANGUAGE plpgsql AS $$
        BEGIN
            UPDATE reputation_device_key
            SET revoked_at = NEW.revoked_at, updated_at = NEW.revoked_at
            WHERE session_id = NEW.id AND revoked_at IS NULL;
            RETURN NEW;
        END;
        $$
        """
    )
    op.execute(
        "CREATE TRIGGER identity_session_revoke_device_keys "
        "AFTER UPDATE OF revoked_at ON identity_session "
        "FOR EACH ROW "
        "WHEN (OLD.revoked_at IS NULL AND NEW.revoked_at IS NOT NULL) "
        "EXECUTE FUNCTION reputation_revoke_session_keys()"
    )


def downgrade() -> None:
    op.execute("DROP TRIGGER identity_session_revoke_device_keys ON identity_session")
    op.execute("DROP FUNCTION reputation_revoke_session_keys()")
    op.drop_index("ix_reputation_qr_scan_interaction", table_name="reputation_qr_scan")
    op.drop_table("reputation_qr_scan")
    op.drop_index(
        "uq_reputation_device_key_session_active",
        table_name="reputation_device_key",
        postgresql_where=sa.text("revoked_at IS NULL"),
    )
    op.drop_index("ix_reputation_device_key_user", table_name="reputation_device_key")
    op.drop_table("reputation_device_key")
