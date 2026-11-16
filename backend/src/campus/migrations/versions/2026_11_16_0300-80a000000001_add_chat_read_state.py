"""Add per-member chat read cursors and the unread source.

A member marks messages read through a message identifier of the same chat;
the stored cursor is that message's server sequence and only grows. The
unread count is derived from the cursor, so no second counter can drift.

Existing chats start with every active member's cursor at the chat's current
``last_sequence``: a deployment must not show a year of history as unread
after the upgrade. A member who joins later starts at zero and sees the
history of the group as unread until the client marks it.

Revision ID: 80a000000001
Revises: 83a000000001
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "80a000000001"
down_revision: str | Sequence[str] | None = "94a000000001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "chat_read_state",
        sa.Column("chat_id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("last_read_sequence", sa.BigInteger(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "last_read_sequence >= 0",
            name=op.f("ck_chat_read_state_last_read_sequence_non_negative"),
        ),
        sa.ForeignKeyConstraint(
            ["chat_id"],
            ["chat.id"],
            name=op.f("fk_chat_read_state_chat_id_chat"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["identity_user.id"],
            name=op.f("fk_chat_read_state_user_id_identity_user"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("chat_id", "user_id", name=op.f("pk_chat_read_state")),
    )
    op.create_index("ix_chat_read_state_user_id", "chat_read_state", ["user_id"])
    op.execute(
        """
        INSERT INTO chat_read_state
            (chat_id, user_id, last_read_sequence, updated_at)
        SELECT member.chat_id, member.user_id, chat.last_sequence, now()
        FROM chat_member member
        JOIN chat ON chat.id = member.chat_id
        WHERE member.left_at IS NULL
        ON CONFLICT (chat_id, user_id) DO NOTHING
        """
    )


def downgrade() -> None:
    op.drop_index("ix_chat_read_state_user_id", table_name="chat_read_state")
    op.drop_table("chat_read_state")
