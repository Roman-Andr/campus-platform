"""Add the append-only audit journal.

Records of moderator and administrator actions cannot be updated, deleted
or truncated by any role, including the application's own (the table
owner) through direct SQL: BEFORE triggers reject the statements and fire
even with ``session_replication_role = replica``. Deletion is reserved to
the NOLOGIN role ``campus_audit_retention``; only the SECURITY DEFINER
function ``audit_purge_expired`` runs as it, and it never deletes records
younger than three calendar years (1096 days) by the database clock.

Revision ID: 89a0d1700001
Revises: 297a00000001
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "89a0d1700001"
down_revision: str | Sequence[str] | None = "297a00000001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

ROLE = "campus_audit_retention"


def upgrade() -> None:
    op.create_table(
        "audit_record",
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("occurred_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("actor_id", sa.Uuid(), nullable=True),
        sa.Column("action", sa.String(length=100), nullable=False),
        sa.Column("object_type", sa.String(length=64), nullable=False),
        sa.Column("object_id", sa.Uuid(), nullable=True),
        sa.Column("reason", sa.String(length=1000), nullable=True),
        sa.Column(
            "participant_ids",
            postgresql.ARRAY(sa.Uuid()),
            server_default=sa.text("'{}'"),
            nullable=False,
        ),
        sa.Column("own_case", sa.Boolean(), nullable=False),
        sa.Column("before", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column("after", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column("details", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column("request_id", sa.String(length=64), nullable=True),
        sa.CheckConstraint(
            "own_case = (actor_id IS NOT NULL AND actor_id = ANY (participant_ids))",
            name=op.f("ck_audit_record_own_case_by_participants"),
        ),
        sa.CheckConstraint(
            "action ~ '^[a-z][a-z_]*(\\.[a-z][a-z_]*)+$'",
            name=op.f("ck_audit_record_action_format"),
        ),
        sa.CheckConstraint(
            "char_length(reason) BETWEEN 1 AND 1000",
            name=op.f("ck_audit_record_reason_length"),
        ),
        sa.ForeignKeyConstraint(
            ["actor_id"],
            ["identity_user.id"],
            name=op.f("fk_audit_record_actor_id_identity_user"),
            ondelete="RESTRICT",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_audit_record")),
    )
    op.create_index(
        op.f("ix_audit_record_action"), "audit_record", ["action"], unique=False
    )
    op.create_index(
        op.f("ix_audit_record_actor_id"), "audit_record", ["actor_id"], unique=False
    )
    op.create_index(
        "ix_audit_record_object",
        "audit_record",
        ["object_type", "object_id"],
        unique=False,
    )
    op.create_index(
        "ix_audit_record_occurred_at_id",
        "audit_record",
        ["occurred_at", "id"],
        unique=False,
    )
    op.create_index(
        "ix_audit_record_own_case",
        "audit_record",
        ["occurred_at"],
        unique=False,
        postgresql_where=sa.text("own_case"),
    )
    op.create_index(
        "ix_audit_record_participant_ids",
        "audit_record",
        ["participant_ids"],
        unique=False,
        postgresql_using="gin",
    )

    # Roles are shared by all databases of the server.
    op.execute(
        f"""
        DO $$
        BEGIN
            IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '{ROLE}') THEN
                CREATE ROLE {ROLE} NOLOGIN;
            END IF;
        END
        $$
        """
    )
    op.execute(f"REVOKE ALL ON audit_record FROM PUBLIC, {ROLE}")
    op.execute(f"GRANT SELECT, DELETE ON audit_record TO {ROLE}")
    op.execute(
        f"""
        CREATE FUNCTION audit_record_append_only() RETURNS trigger
        LANGUAGE plpgsql AS $$
        BEGIN
            IF TG_OP = 'DELETE' AND current_user = '{ROLE}' THEN
                RETURN OLD;
            END IF;
            RAISE EXCEPTION 'audit_record is append-only: % is not allowed', TG_OP
                USING ERRCODE = 'insufficient_privilege';
        END
        $$
        """
    )
    op.execute(
        "CREATE TRIGGER append_only BEFORE UPDATE OR DELETE ON audit_record"
        " FOR EACH ROW EXECUTE FUNCTION audit_record_append_only()"
    )
    op.execute(
        "CREATE TRIGGER no_truncate BEFORE TRUNCATE ON audit_record"
        " FOR EACH STATEMENT EXECUTE FUNCTION audit_record_append_only()"
    )
    # Fire also when replication mode would skip ordinary triggers.
    op.execute("ALTER TABLE audit_record ENABLE ALWAYS TRIGGER append_only")
    op.execute("ALTER TABLE audit_record ENABLE ALWAYS TRIGGER no_truncate")
    op.execute(
        """
        CREATE FUNCTION audit_purge_expired(retention interval) RETURNS bigint
        LANGUAGE plpgsql SECURITY DEFINER
        SET search_path = pg_catalog, pg_temp AS $$
        DECLARE
            deleted bigint;
        BEGIN
            IF retention IS NULL OR retention < interval '1096 days' THEN
                RAISE EXCEPTION 'audit retention must be at least 1096 days'
                    USING ERRCODE = 'invalid_parameter_value';
            END IF;
            DELETE FROM public.audit_record
            WHERE occurred_at < statement_timestamp() - retention;
            GET DIAGNOSTICS deleted = ROW_COUNT;
            RETURN deleted;
        END
        $$
        """
    )
    op.execute(f"ALTER FUNCTION audit_purge_expired(interval) OWNER TO {ROLE}")
    op.execute("REVOKE ALL ON FUNCTION audit_purge_expired(interval) FROM PUBLIC")
    op.execute(
        "GRANT EXECUTE ON FUNCTION audit_purge_expired(interval) TO CURRENT_USER"
    )


def downgrade() -> None:
    op.execute("DROP FUNCTION audit_purge_expired(interval)")
    op.drop_table("audit_record")
    op.execute("DROP FUNCTION audit_record_append_only()")
    # Other databases of the server (e.g. test copies) may still use it.
    op.execute(
        f"""
        DO $$
        BEGIN
            DROP ROLE IF EXISTS {ROLE};
        EXCEPTION WHEN dependent_objects_still_exist THEN
            NULL;
        END
        $$
        """
    )
