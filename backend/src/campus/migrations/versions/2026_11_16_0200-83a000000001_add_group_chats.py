"""Add group chats of events and purchases.

A group chat belongs to one listing and has no member pair: the organiser of
the listing and every participant with an accepted interaction are its
members. The partial unique index on the listing keeps one chat per event or
purchase; the pair of the personal chat stays NULL and is excluded from it.
The chat kind is re-checked together with the member columns, so a group row
and a personal row cannot be mixed up by a direct write.

Existing accepted participations receive their chat and realtime grants in
the same migration: a deployed event with already registered participants
must not wait for the next signup to open its group.

Revision ID: 83a000000001
Revises: 63a000000001
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "83a000000001"
down_revision: str | Sequence[str] | None = "63a000000001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.alter_column("chat", "user_low_id", existing_type=sa.Uuid(), nullable=True)
    op.alter_column("chat", "user_high_id", existing_type=sa.Uuid(), nullable=True)
    op.drop_constraint(op.f("ck_chat_kind"), "chat", type_="check")
    op.drop_constraint(op.f("ck_chat_distinct_members"), "chat", type_="check")
    op.create_check_constraint(
        op.f("ck_chat_kind"),
        "chat",
        "kind IN ('personal','event','purchase')",
    )
    op.create_check_constraint(
        op.f("ck_chat_members_by_kind"),
        "chat",
        "(kind = 'personal' AND user_low_id IS NOT NULL "
        "AND user_high_id IS NOT NULL AND user_low_id <> user_high_id) OR "
        "(kind IN ('event','purchase') AND user_low_id IS NULL "
        "AND user_high_id IS NULL)",
    )
    op.create_check_constraint(
        op.f("ck_chat_group_listing"),
        "chat",
        "(kind IN ('event','purchase') AND listing_id IS NOT NULL "
        "AND interaction_id IS NULL) OR kind = 'personal'",
    )
    op.create_index(
        "uq_chat_listing_group",
        "chat",
        ["listing_id"],
        unique=True,
        postgresql_where=sa.text("kind IN ('event','purchase')"),
    )
    # A group chat is created by the first accepted participation; existing
    # deployments get one chat per listing that already has such a
    # participation, plus the organiser and the accepted participants.
    op.execute(
        """
        INSERT INTO chat
            (id, kind, user_low_id, user_high_id, listing_id, interaction_id,
             last_sequence, empty_since, created_at, updated_at)
        SELECT uuidv7(), listing.kind, NULL, NULL, listing.id, NULL, 0, NULL,
               now(), now()
        FROM listing
        WHERE listing.kind IN ('event', 'purchase')
          AND EXISTS (
              SELECT 1 FROM listing_interaction interaction
              WHERE interaction.listing_id = listing.id
                AND interaction.status IN ('accepted', 'completed')
          )
        """
    )
    op.execute(
        """
        INSERT INTO chat_member (chat_id, user_id, joined_at, left_at)
        SELECT chat.id, listing.author_id, now(), NULL
        FROM chat
        JOIN listing ON listing.id = chat.listing_id
        WHERE chat.kind IN ('event', 'purchase')
        ON CONFLICT (chat_id, user_id) DO NOTHING
        """
    )
    op.execute(
        """
        INSERT INTO chat_member (chat_id, user_id, joined_at, left_at)
        SELECT chat.id, interaction.participant_id, now(), NULL
        FROM chat
        JOIN listing_interaction interaction
          ON interaction.listing_id = chat.listing_id
         AND interaction.status IN ('accepted', 'completed')
        WHERE chat.kind IN ('event', 'purchase')
        ON CONFLICT (chat_id, user_id) DO NOTHING
        """
    )
    op.execute(
        """
        INSERT INTO realtime_channel_grant (channel, user_id, created_at, revoked_at)
        SELECT 'chat:' || member.chat_id::text, member.user_id, now(), NULL
        FROM chat_member member
        JOIN chat ON chat.id = member.chat_id
        WHERE chat.kind IN ('event', 'purchase')
          AND member.left_at IS NULL
        ON CONFLICT (channel, user_id) DO UPDATE SET revoked_at = NULL
        """
    )


def downgrade() -> None:
    op.execute(
        """
        DELETE FROM realtime_channel_grant
        USING chat
        WHERE realtime_channel_grant.channel = 'chat:' || chat.id::text
          AND chat.kind IN ('event', 'purchase')
        """
    )
    op.execute("DELETE FROM chat WHERE kind IN ('event', 'purchase')")
    op.drop_index("uq_chat_listing_group", table_name="chat")
    op.drop_constraint(op.f("ck_chat_group_listing"), "chat", type_="check")
    op.drop_constraint(op.f("ck_chat_members_by_kind"), "chat", type_="check")
    op.drop_constraint(op.f("ck_chat_kind"), "chat", type_="check")
    op.create_check_constraint(op.f("ck_chat_kind"), "chat", "kind IN ('personal')")
    op.create_check_constraint(
        op.f("ck_chat_distinct_members"),
        "chat",
        "user_low_id <> user_high_id",
    )
    op.alter_column("chat", "user_low_id", existing_type=sa.Uuid(), nullable=False)
    op.alter_column("chat", "user_high_id", existing_type=sa.Uuid(), nullable=False)
