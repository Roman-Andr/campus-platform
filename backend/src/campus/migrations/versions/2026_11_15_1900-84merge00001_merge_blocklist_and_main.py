"""merge blocklist and current main

Revision ID: 84merge00001
Revises: 84b10c000001, 59a000000001
"""

from collections.abc import Sequence

revision: str = "84merge00001"
down_revision: str | Sequence[str] | None = ("84b10c000001", "59a000000001")
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
