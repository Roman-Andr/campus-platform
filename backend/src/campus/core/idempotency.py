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

A stored response may carry credentials (tokens issued by sign-in and
refresh), so it is sealed with AES-256-GCM before it is written: status,
headers and body are encrypted together with the first key of a
:class:`ResponseKeyring`, the scope and key are its associated data, so a
sealed response cannot be moved to another row. Any key of the keyring
opens a response, which allows rotation: a new key is put first and an old
one is removed once the responses it sealed have expired.
"""

import base64
import hashlib
import json
import secrets
from collections.abc import Sequence
from dataclasses import dataclass
from datetime import datetime, timedelta
from uuid import UUID

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from sqlalchemy import LargeBinary, String, delete, select, update
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import Mapped, mapped_column

from campus.core.db import Base

ANONYMOUS_SCOPE = "anonymous"


class IdempotencyKey(Base):
    """A claimed key; the response is empty until it is stored."""

    __tablename__ = "idempotency_key"

    # Whose key it is: the user id; "anonymous" for requests without a user.
    scope: Mapped[str] = mapped_column(String(64), primary_key=True)
    key: Mapped[UUID] = mapped_column(primary_key=True)
    # SHA-256 of the method, path with query string and body.
    fingerprint: Mapped[bytes] = mapped_column(LargeBinary(32))
    # Status, headers and body sealed by ResponseKeyring.seal.
    response: Mapped[bytes | None] = mapped_column(LargeBinary)
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


class MissingEncryptionKeysError(RuntimeError):
    """The API cannot start: stored responses need an encryption key."""

    def __init__(self) -> None:
        super().__init__(
            "CAMPUS_IDEMPOTENCY_ENCRYPTION_KEYS is not set: the API encrypts"
            " stored idempotent responses with it. Generate a key with"
            " `openssl rand -base64 32` (see .env.example)."
        )


class ResponseUnreadableError(Exception):
    """A stored response cannot be opened: its key left the keyring."""


_KEY_ID_SIZE = 8
_NONCE_SIZE = 12


class ResponseKeyring:
    """AES-256-GCM keys of stored responses; the first one seals.

    A sealed response is ``key id (8 bytes) | nonce (12) | ciphertext``;
    the key id is a prefix of the key's SHA-256, so keys need no names.
    """

    def __init__(self, keys: Sequence[bytes]) -> None:
        if not keys:
            raise MissingEncryptionKeysError
        self._sealing = self._key_id(keys[0])
        self._keys = {self._key_id(key): AESGCM(key) for key in keys}

    @staticmethod
    def _key_id(key: bytes) -> bytes:
        return hashlib.sha256(key).digest()[:_KEY_ID_SIZE]

    @staticmethod
    def _associated_data(scope: str, key: UUID) -> bytes:
        return scope.encode() + b"\0" + key.bytes

    def seal(self, scope: str, key: UUID, response: StoredResponse) -> bytes:
        plaintext = json.dumps(
            {
                "status": response.status_code,
                "headers": [[name, value] for name, value in response.headers],
                "body": base64.b64encode(response.body).decode(),
            },
            separators=(",", ":"),
        ).encode()
        nonce = secrets.token_bytes(_NONCE_SIZE)
        ciphertext = self._keys[self._sealing].encrypt(
            nonce, plaintext, self._associated_data(scope, key)
        )
        return self._sealing + nonce + ciphertext

    def open(self, scope: str, key: UUID, sealed: bytes) -> StoredResponse:
        key_id = sealed[:_KEY_ID_SIZE]
        nonce = sealed[_KEY_ID_SIZE : _KEY_ID_SIZE + _NONCE_SIZE]
        cipher = self._keys.get(key_id)
        if cipher is None:
            raise ResponseUnreadableError
        try:
            plaintext = cipher.decrypt(
                nonce,
                sealed[_KEY_ID_SIZE + _NONCE_SIZE :],
                self._associated_data(scope, key),
            )
        except InvalidTag:
            raise ResponseUnreadableError from None
        data = json.loads(plaintext)
        return StoredResponse(
            status_code=data["status"],
            body=base64.b64decode(data["body"]),
            headers=[(name, value) for name, value in data["headers"]],
        )


# A claim retries when the conflicting key disappears in between (expired
# and deleted, or rolled back); a few rounds settle any race.
_CLAIM_ATTEMPTS = 3


async def claim_idempotency_key(  # noqa: PLR0913 - the parts of a key
    session: AsyncSession,
    *,
    keyring: ResponseKeyring,
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
                    IdempotencyKey.response,
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
        assert existing.response is not None  # noqa: S101
        return keyring.open(scope, key, existing.response)
    msg = "idempotency key could not be claimed"
    raise RuntimeError(msg)


async def store_response(
    session: AsyncSession,
    *,
    keyring: ResponseKeyring,
    scope: str,
    key: UUID,
    response: StoredResponse,
) -> None:
    """Seal and store the response of the request that claimed ``key``."""
    await session.execute(
        update(IdempotencyKey)
        .where(IdempotencyKey.scope == scope, IdempotencyKey.key == key)
        .values(response=keyring.seal(scope, key, response))
    )


async def delete_expired_idempotency_keys(session: AsyncSession, now: datetime) -> int:
    """Delete keys that expired by ``now``; return how many were deleted."""
    result = await session.execute(
        delete(IdempotencyKey).where(IdempotencyKey.expires_at <= now)
    )
    return int(getattr(result, "rowcount", 0))
