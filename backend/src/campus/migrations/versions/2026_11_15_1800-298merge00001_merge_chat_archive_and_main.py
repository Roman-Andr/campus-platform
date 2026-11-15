"""merge chat archive and current main

Revision ID: 298merge00001
Revises: 298a00000001, 55merge00001
"""

from collections.abc import Sequence

revision: str = "298merge00001"
down_revision: str | Sequence[str] | None = ("298a00000001", "55merge00001")
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
