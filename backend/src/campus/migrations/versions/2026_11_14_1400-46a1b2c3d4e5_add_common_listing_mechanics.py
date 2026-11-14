"""Add common listing mechanics and localized categories.

Revision ID: 46a1b2c3d4e5
Revises: b87769795a67
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "46a1b2c3d4e5"
down_revision: str | Sequence[str] | None = "b87769795a67"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

CATEGORIES = (
    ("books", "Книги и учебные материалы", "Books and study materials"),
    ("electronics", "Электроника", "Electronics"),
    ("clothing", "Одежда", "Clothing"),
    ("household", "Для дома", "Household"),
    ("other", "Другое", "Other"),
)


def upgrade() -> None:
    op.create_table(
        "listing_category",
        sa.Column("code", sa.String(64), nullable=False),
        sa.Column("name_ru", sa.String(200), nullable=False),
        sa.Column("name_en", sa.String(200), nullable=False),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_listing_category")),
        sa.UniqueConstraint("code", name=op.f("uq_listing_category_code")),
    )
    for code, ru, en in CATEGORIES:
        op.execute(
            sa.text(
                "INSERT INTO listing_category "
                "(code, name_ru, name_en, created_at, updated_at) "
                "VALUES (:code, :ru, :en, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)"
            ).bindparams(code=code, ru=ru, en=en)
        )
    op.add_column("listing", sa.Column("category_id", sa.Uuid(), nullable=True))
    op.create_foreign_key(
        op.f("fk_listing_category_id_listing_category"),
        "listing",
        "listing_category",
        ["category_id"],
        ["id"],
    )
    op.execute(
        "UPDATE listing SET category_id = "
        "(SELECT id FROM listing_category WHERE code = 'other')"
    )
    op.add_column("listing", sa.Column("hidden_reason", sa.Text(), nullable=True))
    op.alter_column("listing", "expires_at", nullable=True)
    op.drop_constraint(op.f("ck_listing_status"), "listing", type_="check")
    op.create_check_constraint(
        op.f("ck_listing_status"),
        "listing",
        "status IN ('draft','active','busy','completed',"
        "'cancelled','expired','hidden')",
    )
    op.drop_constraint(
        op.f("ck_listing_interaction_status"), "listing_interaction", type_="check"
    )
    op.create_check_constraint(
        op.f("ck_listing_interaction_status"),
        "listing_interaction",
        "status IN ('pending','accepted','rejected','cancelled','completed','no_show')",
    )
    op.add_column(
        "listing_interaction", sa.Column("stage", sa.String(32), nullable=True)
    )
    op.add_column(
        "listing_interaction",
        sa.Column("response_due_at", sa.DateTime(timezone=True), nullable=True),
    )
    # Preserve old requests and start processing their original response deadline.
    op.execute(
        "UPDATE listing_interaction "
        "SET response_due_at = created_at + interval '24 hours' "
        "WHERE status = 'pending'"
    )
    op.execute("""INSERT INTO deadline
        (id, topic, payload, available_at, attempts, created_at, updated_at, key)
        SELECT uuidv7(), 'listing.author_response',
            jsonb_build_object('listing_id', listing_id::text,
                               'interaction_id', id::text),
            response_due_at, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP,
            'interaction:' || id::text
        FROM listing_interaction WHERE status = 'pending'""")
    op.create_index(
        "ix_listing_event_quota", "listing_event", ["actor_id", "action", "created_at"]
    )
    op.add_column("listing_event", sa.Column("reason", sa.Text(), nullable=True))
    op.add_column("listing_event", sa.Column("stage", sa.String(32), nullable=True))
    for column in ("via_assistant", "offline_qr"):
        op.add_column(
            "listing_event",
            sa.Column(column, sa.Boolean(), server_default=sa.false(), nullable=False),
        )
        op.alter_column("listing_event", column, server_default=None)


def downgrade() -> None:
    # New states cannot be represented by the old schema; refuse lossy downgrades.
    op.execute("DELETE FROM deadline WHERE topic = 'listing.author_response'")
    op.drop_index("ix_listing_event_quota", table_name="listing_event")
    for column in ("offline_qr", "via_assistant", "stage", "reason"):
        op.drop_column("listing_event", column)
    for column in ("response_due_at", "stage"):
        op.drop_column("listing_interaction", column)
    op.drop_constraint(
        op.f("ck_listing_interaction_status"), "listing_interaction", type_="check"
    )
    op.create_check_constraint(
        op.f("ck_listing_interaction_status"),
        "listing_interaction",
        "status IN ('pending','accepted','rejected','cancelled')",
    )
    op.drop_constraint(op.f("ck_listing_status"), "listing", type_="check")
    op.create_check_constraint(
        op.f("ck_listing_status"),
        "listing",
        "status IN ('active','busy','cancelled','expired')",
    )
    op.alter_column("listing", "expires_at", nullable=False)
    op.drop_column("listing", "hidden_reason")
    op.drop_constraint(
        op.f("fk_listing_category_id_listing_category"), "listing", type_="foreignkey"
    )
    op.drop_column("listing", "category_id")
    op.drop_table("listing_category")
