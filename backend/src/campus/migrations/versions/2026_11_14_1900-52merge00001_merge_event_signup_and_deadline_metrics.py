"""merge event signup and deadline metrics

Revision ID: 52merge00001
Revises: 52event00001, 106a00000001
Create Date: 2026-11-14 19:00:38.971932+00:00
"""

from collections.abc import Sequence

revision: str = "52merge00001"
down_revision: str | Sequence[str] | None = ("52event00001", "50c1d2e3f4a5")
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
