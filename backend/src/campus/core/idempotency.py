"""Stored ``Idempotency-Key`` values and responses (specification, 4.3, 4.6).

A mutating request claims its key in its own transaction, before the
operation runs, and stores its response in the same transaction, so the key
is committed together with the operation or not at all:

- the first request inserts the key and runs;
- a concurrent repeat blocks on the key's primary key until the first one
  commits, then gets the stored response (or, if the first one rolled back,
  claims the key itself and runs);
- a later repeat with the same request gets the stored response;
- a repeat with a different request is rejected;
- an expired key is deleted and claimed anew.

Expired keys are deleted by :func:`delete_expired_idempotency_keys`.
"""

from collections.abc import Sequence
from dataclasses import dataclass
from datetime import datetime, timedelta
from uuid import UUID

from sqlalchemy import LargeBinary, SmallInteger, String, delete, select, update
from sqlalchemy.dialects.postgresql import JSONB, insert
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import Mapped, mapped_column

from campus.core.db import Base

ANONYMOUS_SCOPE = "anonymous"


class IdempotencyKey(Base):
    """A claimed key; the response columns are empty until it is stored."""

    __tablename__ = "idempotency_key"

    # Whose key it is: the user id; "anonymous" for requests without a user.
    scope: Mapped[str] = mapped_column(String(64), primary_key=True)
    key: Mapped[UUID] = mapped_column(primary_key=True)
    # SHA-256 of the method, path with query string and body.
    fingerprint: Mapped[bytes] = mapped_column(LargeBinary(32))
    status_code: Mapped[int | None] = mapped_column(SmallInteger)
    response_body: Mapped[bytes | None] = mapped_column(LargeBinary)
    response_headers: Mapped[list[list[str]] | None] = mapped_column(JSONB)
    created_at: Mapped[datetime]
    expires_at: Mapped[datetime] = mapped_column(index=True)


@dataclass(frozen=True, slots=True)
class StoredResponse:
    """The response stored for a key, to be returned to repeats."""

    status_code: int
    body: bytes
    headers: Sequence[tuple[str, str]]


class IdempotencyKeyReusedError(Exception):
    """The key was already used for a different request."""


# A claim retries when the conflicting key disappears in between (expired
# and deleted, or rolled back); a few rounds settle any race.
_CLAIM_ATTEMPTS = 3


async def claim_idempotency_key(  # noqa: PLR0913 - the parts of a key
    session: AsyncSession,
    *,
    scope: str,
    key: UUID,
    fingerprint: bytes,
    now: datetime,
    ttl: timedelta,
) -> StoredResponse | None:
    """Claim ``key`` for this request, or return the response stored for it.

    ``None`` means the key is claimed by the current transaction and the
    request should run, then call :func:`store_response`.
    """
    for _ in range(_CLAIM_ATTEMPTS):
        claimed = await session.scalar(
            insert(IdempotencyKey)
            .values(
                scope=scope,
                key=key,
                fingerprint=fingerprint,
                created_at=now,
                expires_at=now + ttl,
            )
            .on_conflict_do_nothing()
            .returning(IdempotencyKey.key)
        )
        if claimed is not None:
            return None

        existing = (
            await session.execute(
                select(
                    IdempotencyKey.fingerprint,
                    IdempotencyKey.status_code,
                    IdempotencyKey.response_body,
                    IdempotencyKey.response_headers,
                    IdempotencyKey.expires_at,
                ).where(IdempotencyKey.scope == scope, IdempotencyKey.key == key)
            )
        ).one_or_none()
        if existing is None:
            continue
        if existing.expires_at <= now:
            await session.execute(
                delete(IdempotencyKey).where(
                    IdempotencyKey.scope == scope,
                    IdempotencyKey.key == key,
                    IdempotencyKey.expires_at <= now,
                )
            )
            continue
        if existing.fingerprint != fingerprint:
            raise IdempotencyKeyReusedError
        # Committed keys always have a response: it is stored in the same
        # transaction that claims the key.
        assert existing.status_code is not None  # noqa: S101
        assert existing.response_body is not None  # noqa: S101
        return StoredResponse(
            status_code=existing.status_code,
            body=existing.response_body,
            headers=[(name, value) for name, value in existing.response_headers or []],
        )
    msg = "idempotency key could not be claimed"
    raise RuntimeError(msg)


async def store_response(
    session: AsyncSession, *, scope: str, key: UUID, response: StoredResponse
) -> None:
    """Store the response of the request that claimed ``key``."""
    await session.execute(
        update(IdempotencyKey)
        .where(IdempotencyKey.scope == scope, IdempotencyKey.key == key)
        .values(
            status_code=response.status_code,
            response_body=response.body,
            response_headers=[[name, value] for name, value in response.headers],
        )
    )


async def delete_expired_idempotency_keys(session: AsyncSession, now: datetime) -> int:
    """Delete keys that expired by ``now``; return how many were deleted."""
    result = await session.execute(
        delete(IdempotencyKey).where(IdempotencyKey.expires_at <= now)
    )
    return int(getattr(result, "rowcount", 0))
