"""Append-only audit of moderator and administrator actions (5.1.1, module 8).

Every administrative module records its successful actions with
:func:`record_action` in the same session as the action itself: the
request transaction commits both or neither, and an idempotent replay
returns the stored response without running the endpoint, so a repeated
``Idempotency-Key`` adds no second record.

A moderator's view of conversation content (messages attached to a
complaint, the chat of a disputed interaction) is recorded with
:func:`record_conversation_access` *before* the content is loaded. The
record is flushed immediately, so a failed write raises before anything is
read, and a GET request transaction commits the record before the response
is sent.

"Own case" is derived on the server: ``own_case`` is true exactly when the
actor is among ``participant_ids``, which the caller loads from the case
itself. A database check enforces the same rule, so no caller can pass a
different flag.

Records are immutable: database triggers reject UPDATE, DELETE and TRUNCATE
for every role except ``campus_audit_retention``. Only the
``audit_purge_expired`` function runs as that role (SECURITY DEFINER), and
it deletes nothing younger than the legal minimum of three years, whatever
retention the caller passes; see the migration that creates the table.

Tokens, one-time codes, TOTP secrets and full message texts are never
written: :func:`record_action` rejects payload keys that name them and
long strings, so an accidental dump of a request or a message fails loudly
instead of leaking into the journal.
"""

from collections.abc import Iterable, Mapping
from datetime import datetime, timedelta
from typing import Any
from uuid import UUID

from asgi_correlation_id import correlation_id
from pydantic_core import to_jsonable_python
from sqlalchemy import (
    CheckConstraint,
    ForeignKey,
    Index,
    String,
    Uuid,
    func,
    text,
)
from sqlalchemy.dialects.postgresql import ARRAY, JSONB
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import Mapped, mapped_column

from campus.core import clock
from campus.core.db import Base

# Role that alone may delete records; created by the migration.
RETENTION_ROLE = "campus_audit_retention"
# Action codes: dotted lowercase words, e.g. "moderation.complaint.resolve".
ACTION_PATTERN = r"^[a-z][a-z_]*(\.[a-z][a-z_]*)+$"
CONVERSATION_ACCESS = "moderation.conversation.view"
REASON_MAX_LENGTH = 1000
# Longest string value in before/after/details: identifiers, statuses and
# short labels fit; message texts and documents do not.
VALUE_MAX_LENGTH = 200
# Key fragments that name secrets or content; matched case-insensitively.
_SECRET_KEY_PARTS = ("token", "secret", "password", "totp", "otp", "recovery_code")
_CONTENT_KEYS = frozenset({"text", "body", "content", "message", "messages", "code"})


class AuditRecord(Base):
    """One action of a moderator or administrator; never changed."""

    __tablename__ = "audit_record"
    __table_args__ = (
        CheckConstraint(
            "own_case = (actor_id IS NOT NULL AND actor_id = ANY (participant_ids))",
            name="own_case_by_participants",
        ),
        CheckConstraint(f"action ~ '{ACTION_PATTERN}'", name="action_format"),
        CheckConstraint(
            f"char_length(reason) BETWEEN 1 AND {REASON_MAX_LENGTH}",
            name="reason_length",
        ),
        Index("ix_audit_record_occurred_at_id", "occurred_at", "id"),
        Index("ix_audit_record_object", "object_type", "object_id"),
        Index(
            "ix_audit_record_participant_ids",
            "participant_ids",
            postgresql_using="gin",
        ),
        Index(
            "ix_audit_record_own_case",
            "occurred_at",
            postgresql_where=text("own_case"),
        ),
    )

    id: Mapped[UUID] = mapped_column(primary_key=True, server_default=func.uuidv7())
    occurred_at: Mapped[datetime] = mapped_column(default=clock.now)
    # Empty for actions of the deployment team (command line, migrations).
    actor_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("identity_user.id", ondelete="RESTRICT"), index=True
    )
    action: Mapped[str] = mapped_column(String(100), index=True)
    object_type: Mapped[str] = mapped_column(String(64))
    object_id: Mapped[UUID | None]
    # The ground of the action: a complaint, a dispute, a presented document.
    reason: Mapped[str | None] = mapped_column(String(REASON_MAX_LENGTH))
    # Users the case is about, loaded by the caller from the case itself.
    participant_ids: Mapped[list[UUID]] = mapped_column(
        ARRAY(Uuid), server_default=text("'{}'")
    )
    own_case: Mapped[bool]
    before: Mapped[dict[str, Any] | None] = mapped_column(JSONB)
    after: Mapped[dict[str, Any] | None] = mapped_column(JSONB)
    details: Mapped[dict[str, Any] | None] = mapped_column(JSONB)
    request_id: Mapped[str | None] = mapped_column(String(64))


class AuditPayloadError(ValueError):
    """A record would carry a secret or content; a programming error."""


def _check_value(path: str, value: Any) -> None:
    if isinstance(value, Mapping):
        for key, item in value.items():
            name = str(key).lower()
            if name in _CONTENT_KEYS or any(p in name for p in _SECRET_KEY_PARTS):
                msg = f"audit payload must not contain {path}.{key}"
                raise AuditPayloadError(msg)
            _check_value(f"{path}.{key}", item)
    elif isinstance(value, list):
        for index, item in enumerate(value):
            _check_value(f"{path}[{index}]", item)
    elif isinstance(value, str) and len(value) > VALUE_MAX_LENGTH:
        msg = f"audit payload value {path} is longer than {VALUE_MAX_LENGTH}"
        raise AuditPayloadError(msg)


def _payload(name: str, value: Mapping[str, Any] | None) -> dict[str, Any] | None:
    if value is None:
        return None
    payload: dict[str, Any] = to_jsonable_python(dict(value))
    _check_value(name, payload)
    return payload


async def record_action(  # noqa: PLR0913 - the fields of a record
    session: AsyncSession,
    *,
    actor_id: UUID | None,
    action: str,
    object_type: str,
    object_id: UUID | None = None,
    reason: str | None = None,
    participant_ids: Iterable[UUID] = (),
    before: Mapping[str, Any] | None = None,
    after: Mapping[str, Any] | None = None,
    details: Mapping[str, Any] | None = None,
) -> AuditRecord:
    """Add a record in the caller's transaction and flush it.

    ``participant_ids`` must come from the case loaded on the server (its
    complainant, defendant, interaction participants), never from the
    client: the own-case mark is computed from it. ``before`` and ``after``
    hold the changed fields only; IDs, statuses and short labels, never
    secrets or texts (:class:`AuditPayloadError`).
    """
    participants = list(dict.fromkeys(participant_ids))
    record = AuditRecord(
        actor_id=actor_id,
        action=action,
        object_type=object_type,
        object_id=object_id,
        reason=reason,
        participant_ids=participants,
        own_case=actor_id is not None and actor_id in participants,
        before=_payload("before", before),
        after=_payload("after", after),
        details=_payload("details", details),
        request_id=correlation_id.get(),
    )
    session.add(record)
    await session.flush()
    return record


async def record_conversation_access(  # noqa: PLR0913 - the fields of an access
    session: AsyncSession,
    *,
    actor_id: UUID,
    object_type: str,
    object_id: UUID,
    reason: str,
    participant_ids: Iterable[UUID],
    first_message_id: UUID | None,
    last_message_id: UUID | None,
    message_count: int,
) -> AuditRecord:
    """Record a moderator's view of messages before loading them.

    ``object_type`` is the case whose content is opened (a complaint with
    attached messages, a dispute with its chat), ``reason`` its ground and
    the message IDs the viewed range. Load the content only after this
    returns: a failed write raises here, so nothing is read unrecorded.
    """
    if not reason.strip():
        msg = "a conversation access needs a reason"
        raise AuditPayloadError(msg)
    return await record_action(
        session,
        actor_id=actor_id,
        action=CONVERSATION_ACCESS,
        object_type=object_type,
        object_id=object_id,
        reason=reason,
        participant_ids=participant_ids,
        details={
            "first_message_id": first_message_id,
            "last_message_id": last_message_id,
            "message_count": message_count,
        },
    )


async def purge_expired_records(session: AsyncSession, retention: timedelta) -> int:
    """Delete records older than ``retention`` through the purge function.

    The function runs as the retention role; it refuses a retention below
    the legal minimum, and the database clock decides what is expired.
    """
    deleted = await session.scalar(
        text("SELECT audit_purge_expired(:retention)"), {"retention": retention}
    )
    return int(deleted or 0)
