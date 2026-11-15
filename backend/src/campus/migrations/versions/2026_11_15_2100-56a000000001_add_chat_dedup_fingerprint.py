"""Add a full-body fingerprint to durable chat message deduplication.

A repeat of a client UUID must carry the same text, quote and ordered
photos, including with a new ``Idempotency-Key`` and after the message was
edited, deleted or archived. The old ``content_hash`` covers only the text.
The new ``content_fingerprint`` covers the whole durable body:

    SHA-256(content_hash | reply_to_id or "-" | ordered photo UUIDs)

The text enters through its stored SHA-256, so the fingerprint can be
backfilled even when the original plaintext is already hidden by an edit or
delete. ``reply_to_id`` and the attached photo rows never change after
creation, so the backfill is reached through ``chat_message_history`` (active
and archived messages) and ``file`` positions.

A deleted legacy message may already have had its photo rows purged. Its
attachment metadata is then unknowable, so the row keeps its old
``content_hash`` and gets a NULL fingerprint: the service fails closed on
such a replay instead of accepting a body that might have lost attachments.
No row and no hash is rewritten or discarded. The legacy rows of the real
stage database predate #81, so they carry no quote or photo data and are
backfilled as text-only bodies.

Revision ID: 56a000000001
Revises: 71a000000001
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "56a000000001"
down_revision: str | Sequence[str] | None = "71a000000001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_FINGERPRINT_SQL = r"""
UPDATE chat_message_dedup AS dedup
SET content_fingerprint =
    'v1:' || translate(
        encode(
            sha256(
                convert_to(
                    dedup.content_hash || '|' ||
                    COALESCE(message.reply_to_id::text, '-') || '|' ||
                    COALESCE(
                        (
                            SELECT string_agg(
                                file.id::text, ','
                                ORDER BY file.message_position, file.id
                            )
                            FROM file
                            WHERE file.message_id = dedup.message_id
                        ),
                        ''
                    ),
                    'UTF8'
                )
            ),
            'base64'
        ),
        E'+/=\n',
        '-_'
    )
FROM chat_message_history AS message
WHERE message.id = dedup.message_id
  AND message.created_at = dedup.message_created_at
  AND message.deleted_at IS NULL
"""


def upgrade() -> None:
    op.add_column(
        "chat_message_dedup",
        sa.Column("content_fingerprint", sa.String(64), nullable=True),
    )
    op.execute(_FINGERPRINT_SQL)


def downgrade() -> None:
    op.drop_column("chat_message_dedup", "content_fingerprint")
