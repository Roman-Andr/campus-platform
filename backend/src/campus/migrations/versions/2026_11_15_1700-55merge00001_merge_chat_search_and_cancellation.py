"""merge chat search and listing cancellation

Revision ID: 55merge00001
Revises: 55a1b2c3d4e5, 82search00001
"""

from collections.abc import Sequence

revision: str = "55merge00001"
down_revision: str | Sequence[str] | None = ("55a1b2c3d4e5", "82search00001")
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
