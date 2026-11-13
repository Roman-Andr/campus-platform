"""Add university reference data

Revision ID: dc8a2482d824
Revises: 5f2ca402e1bc
Create Date: 2026-11-13 23:55:08.375829+00:00
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "dc8a2482d824"
down_revision: str | Sequence[str] | None = "5f2ca402e1bc"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # Campus cities, their dormitories and faculties, e-mail domains
    # (specification, 4.5, module 11).
    op.create_table(
        "university_city",
        sa.Column("code", sa.String(length=64), nullable=False),
        sa.Column("timezone", sa.String(length=64), nullable=False),
        sa.Column("name_ru", sa.String(length=200), nullable=False),
        sa.Column("name_en", sa.String(length=200), nullable=False),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "code ~ '^[a-z0-9]+(-[a-z0-9]+)*$'",
            name=op.f("ck_university_city_code_format"),
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_university_city")),
        sa.UniqueConstraint("code", name=op.f("uq_university_city_code")),
    )
    op.create_table(
        "university_email_domain",
        sa.Column("domain", sa.String(length=253), nullable=False),
        sa.Column(
            "account_type",
            sa.Enum(
                "student",
                "employee",
                name="account_type",
                native_enum=False,
                create_constraint=True,
                length=16,
            ),
            nullable=False,
        ),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "domain ~ '^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z][a-z0-9-]*[a-z0-9]$'",
            name=op.f("ck_university_email_domain_domain_format"),
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_university_email_domain")),
        sa.UniqueConstraint("domain", name=op.f("uq_university_email_domain_domain")),
    )
    op.create_table(
        "university_dormitory",
        sa.Column("city_id", sa.Uuid(), nullable=False),
        sa.Column("code", sa.String(length=64), nullable=False),
        sa.Column("name_ru", sa.String(length=200), nullable=False),
        sa.Column("name_en", sa.String(length=200), nullable=False),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "code ~ '^[a-z0-9]+(-[a-z0-9]+)*$'",
            name=op.f("ck_university_dormitory_code_format"),
        ),
        sa.ForeignKeyConstraint(
            ["city_id"],
            ["university_city.id"],
            name=op.f("fk_university_dormitory_city_id_university_city"),
            ondelete="RESTRICT",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_university_dormitory")),
        sa.UniqueConstraint(
            "city_id", "code", name=op.f("uq_university_dormitory_city_id_code")
        ),
    )
    op.create_table(
        "university_faculty",
        sa.Column("city_id", sa.Uuid(), nullable=False),
        sa.Column("code", sa.String(length=64), nullable=False),
        sa.Column("name_ru", sa.String(length=200), nullable=False),
        sa.Column("name_en", sa.String(length=200), nullable=False),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "code ~ '^[a-z0-9]+(-[a-z0-9]+)*$'",
            name=op.f("ck_university_faculty_code_format"),
        ),
        sa.ForeignKeyConstraint(
            ["city_id"],
            ["university_city.id"],
            name=op.f("fk_university_faculty_city_id_university_city"),
            ondelete="RESTRICT",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_university_faculty")),
        sa.UniqueConstraint(
            "city_id", "code", name=op.f("uq_university_faculty_city_id_code")
        ),
    )


def downgrade() -> None:
    op.drop_table("university_faculty")
    op.drop_table("university_dormitory")
    op.drop_table("university_email_domain")
    op.drop_table("university_city")
