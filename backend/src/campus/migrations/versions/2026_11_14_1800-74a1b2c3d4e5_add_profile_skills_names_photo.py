"""Add skill tags, profile skills, name history and the profile photo.

Revision ID: 74a1b2c3d4e5
Revises: 248e00000001
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "74a1b2c3d4e5"
down_revision: str | Sequence[str] | None = "56feed000001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _entity_columns() -> list[sa.Column[object]]:
    return [
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    ]


def upgrade() -> None:
    op.create_table(
        "identity_skill_tag",
        *_entity_columns(),
        sa.Column("name_ru", sa.String(200), nullable=False),
        sa.Column("name_en", sa.String(200), nullable=False),
        sa.Column("code", sa.String(64), nullable=False),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_identity_skill_tag")),
        sa.UniqueConstraint("code", name=op.f("uq_identity_skill_tag_code")),
        sa.CheckConstraint(
            "code ~ '^[a-z0-9]+(-[a-z0-9]+)*$'",
            name=op.f("ck_identity_skill_tag_code_format"),
        ),
    )
    op.create_table(
        "identity_user_skill",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("kind", sa.String(8), nullable=False),
        sa.Column("tag_id", sa.Uuid(), nullable=False),
        sa.PrimaryKeyConstraint(
            "user_id", "kind", "tag_id", name=op.f("pk_identity_user_skill")
        ),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["identity_user.id"],
            name=op.f("fk_identity_user_skill_user_id_identity_user"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["tag_id"],
            ["identity_skill_tag.id"],
            name=op.f("fk_identity_user_skill_tag_id_identity_skill_tag"),
            ondelete="RESTRICT",
        ),
        sa.CheckConstraint(
            "kind IN ('can', 'wants')", name=op.f("ck_identity_user_skill_kind")
        ),
    )
    op.create_index(
        op.f("ix_identity_user_skill_tag_id"), "identity_user_skill", ["tag_id"]
    )
    op.create_table(
        "identity_name_change",
        *_entity_columns(),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("old_first_name", sa.String(100), nullable=False),
        sa.Column("old_last_name", sa.String(100), nullable=False),
        sa.Column("new_first_name", sa.String(100), nullable=False),
        sa.Column("new_last_name", sa.String(100), nullable=False),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_identity_name_change")),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["identity_user.id"],
            name=op.f("fk_identity_name_change_user_id_identity_user"),
        ),
    )
    op.create_index(
        op.f("ix_identity_name_change_user"),
        "identity_name_change",
        ["user_id", "created_at"],
    )
    # The name history is append-only, whoever writes to the database.
    op.execute(
        """
        CREATE FUNCTION identity_name_change_immutable() RETURNS trigger
        LANGUAGE plpgsql AS $$
        BEGIN
            RAISE EXCEPTION 'identity_name_change is append-only'
                USING ERRCODE = 'restrict_violation';
        END
        $$
        """
    )
    op.execute(
        "CREATE TRIGGER identity_name_change_immutable"
        " BEFORE UPDATE OR DELETE ON identity_name_change"
        " FOR EACH ROW EXECUTE FUNCTION identity_name_change_immutable()"
    )
    op.execute(
        "CREATE TRIGGER identity_name_change_no_truncate"
        " BEFORE TRUNCATE ON identity_name_change"
        " FOR EACH STATEMENT EXECUTE FUNCTION identity_name_change_immutable()"
    )
    op.add_column("file", sa.Column("profile_user_id", sa.Uuid()))
    op.create_foreign_key(
        op.f("fk_file_profile_user_id_identity_user"),
        "file",
        "identity_user",
        ["profile_user_id"],
        ["id"],
    )
    op.create_unique_constraint(
        op.f("uq_file_profile_user_id"), "file", ["profile_user_id"]
    )
    op.create_check_constraint(
        op.f("ck_file_single_owner"),
        "file",
        "listing_id IS NULL OR profile_user_id IS NULL",
    )


def downgrade() -> None:
    op.drop_constraint(op.f("ck_file_single_owner"), "file", type_="check")
    op.drop_constraint(op.f("uq_file_profile_user_id"), "file", type_="unique")
    op.drop_constraint(
        op.f("fk_file_profile_user_id_identity_user"), "file", type_="foreignkey"
    )
    op.drop_column("file", "profile_user_id")
    op.drop_table("identity_name_change")
    op.execute("DROP FUNCTION identity_name_change_immutable()")
    op.drop_table("identity_user_skill")
    op.drop_table("identity_skill_tag")
