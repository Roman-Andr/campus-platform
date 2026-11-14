"""Add informational publications and feed pin deadlines."""

import sqlalchemy as sa
from alembic import op

revision = "56feed000001"
down_revision = "248e00000001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "publication",
        sa.Column("listing_id", sa.Uuid(), nullable=False),
        sa.ForeignKeyConstraint(
            ["listing_id"],
            ["listing.id"],
            name=op.f("fk_publication_listing_id_listing"),
        ),
        sa.PrimaryKeyConstraint("listing_id", name=op.f("pk_publication")),
    )
    op.add_column("listing", sa.Column("pinned_until", sa.DateTime(timezone=True)))
    op.add_column("listing", sa.Column("author_dormitory_id", sa.Uuid()))
    op.create_foreign_key(
        op.f("fk_listing_author_dormitory_id_university_dormitory"),
        "listing",
        "university_dormitory",
        ["author_dormitory_id"],
        ["id"],
    )
    op.execute(
        "UPDATE listing SET author_dormitory_id = u.dormitory_id "
        "FROM identity_user u WHERE u.id = listing.author_id"
    )
    op.drop_constraint("ck_listing_visibility", "listing")
    op.drop_constraint("ck_listing_scope", "listing")
    op.create_check_constraint(
        "visibility",
        "listing",
        "visibility IN ('city','faculty','dormitory','university')",
    )
    op.create_check_constraint(
        "scope",
        "listing",
        "(visibility IN ('city','university') AND dormitory_id IS NULL "
        "AND faculty_id IS NULL) OR "
        "(visibility = 'faculty' AND faculty_id IS NOT NULL "
        "AND dormitory_id IS NULL) OR "
        "(visibility = 'dormitory' AND dormitory_id IS NOT NULL "
        "AND faculty_id IS NULL)",
    )


def downgrade() -> None:
    op.drop_table("publication")
    # A university publication has no equivalent in the old visibility enum.
    op.execute("UPDATE listing SET visibility = 'city' WHERE visibility = 'university'")
    op.drop_constraint("ck_listing_scope", "listing")
    op.drop_constraint("ck_listing_visibility", "listing")
    op.create_check_constraint(
        "visibility", "listing", "visibility IN ('city','faculty','dormitory')"
    )
    op.create_check_constraint(
        "scope",
        "listing",
        "(visibility = 'city' AND dormitory_id IS NULL "
        "AND faculty_id IS NULL) OR "
        "(visibility = 'faculty' AND faculty_id IS NOT NULL "
        "AND dormitory_id IS NULL) OR "
        "(visibility = 'dormitory' AND dormitory_id IS NOT NULL "
        "AND faculty_id IS NULL)",
    )
    op.drop_column("listing", "pinned_until")
    op.drop_column("listing", "author_dormitory_id")
