"""add user profile

Revision ID: 8c8be0488993
Revises: 3c1e9a7f5b20
Create Date: 2026-11-14 09:08:40.080446+00:00
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "8c8be0488993"
down_revision: str | Sequence[str] | None = "3c1e9a7f5b20"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # Targets of the "row of this city" foreign keys below.
    op.create_unique_constraint(
        op.f("uq_university_dormitory_city_id_id"),
        "university_dormitory",
        ["city_id", "id"],
    )
    op.create_unique_constraint(
        op.f("uq_university_faculty_city_id_id"),
        "university_faculty",
        ["city_id", "id"],
    )
    op.add_column("identity_user", sa.Column("city_id", sa.Uuid(), nullable=True))
    op.add_column("identity_user", sa.Column("dormitory_id", sa.Uuid(), nullable=True))
    op.add_column("identity_user", sa.Column("faculty_id", sa.Uuid(), nullable=True))
    op.add_column(
        "identity_user", sa.Column("course", sa.SmallInteger(), nullable=True)
    )
    op.create_index(
        op.f("ix_identity_user_city_id"), "identity_user", ["city_id"], unique=False
    )
    op.create_index(
        op.f("ix_identity_user_dormitory_id"),
        "identity_user",
        ["dormitory_id"],
        unique=False,
    )
    op.create_index(
        op.f("ix_identity_user_faculty_id"),
        "identity_user",
        ["faculty_id"],
        unique=False,
    )
    op.create_foreign_key(
        op.f("fk_identity_user_city_id_university_city"),
        "identity_user",
        "university_city",
        ["city_id"],
        ["id"],
        ondelete="RESTRICT",
    )
    op.create_foreign_key(
        "fk_identity_user_dormitory_of_city",
        "identity_user",
        "university_dormitory",
        ["city_id", "dormitory_id"],
        ["city_id", "id"],
        ondelete="RESTRICT",
    )
    op.create_foreign_key(
        "fk_identity_user_faculty_of_city",
        "identity_user",
        "university_faculty",
        ["city_id", "faculty_id"],
        ["city_id", "id"],
        ondelete="RESTRICT",
    )
    op.create_check_constraint(
        op.f("ck_identity_user_profile_whole"),
        "identity_user",
        "(city_id IS NULL) = (faculty_id IS NULL)"
        " AND (city_id IS NOT NULL OR (dormitory_id IS NULL AND course IS NULL))",
    )
    op.create_check_constraint(
        op.f("ck_identity_user_course_positive"), "identity_user", "course >= 1"
    )


def downgrade() -> None:
    op.drop_constraint(
        op.f("ck_identity_user_course_positive"), "identity_user", type_="check"
    )
    op.drop_constraint(
        op.f("ck_identity_user_profile_whole"), "identity_user", type_="check"
    )
    op.drop_constraint(
        "fk_identity_user_faculty_of_city", "identity_user", type_="foreignkey"
    )
    op.drop_constraint(
        "fk_identity_user_dormitory_of_city", "identity_user", type_="foreignkey"
    )
    op.drop_constraint(
        op.f("fk_identity_user_city_id_university_city"),
        "identity_user",
        type_="foreignkey",
    )
    op.drop_index(op.f("ix_identity_user_faculty_id"), table_name="identity_user")
    op.drop_index(op.f("ix_identity_user_dormitory_id"), table_name="identity_user")
    op.drop_index(op.f("ix_identity_user_city_id"), table_name="identity_user")
    op.drop_column("identity_user", "course")
    op.drop_column("identity_user", "faculty_id")
    op.drop_column("identity_user", "dormitory_id")
    op.drop_column("identity_user", "city_id")
    op.drop_constraint(
        op.f("uq_university_faculty_city_id_id"), "university_faculty", type_="unique"
    )
    op.drop_constraint(
        op.f("uq_university_dormitory_city_id_id"),
        "university_dormitory",
        type_="unique",
    )
