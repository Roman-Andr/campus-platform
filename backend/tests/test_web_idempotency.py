"""Idempotency-Key: repeats, concurrent repeats, reuse, rollback, expiry,
encryption of stored responses and rotation of their keys."""

import asyncio
import base64
import secrets
import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

import httpx2
import pytest
import time_machine
from pydantic import SecretStr, ValidationError
from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from campus.core.config import Settings
from campus.core.idempotency import (
    IdempotencyKey,
    ResponseKeyring,
    ResponseUnreadableError,
    StoredResponse,
    delete_expired_idempotency_keys,
)
from tests.conftest import web_settings
from tests.models import Note
from tests.web_app import ENCRYPTION_KEY, NOTES_URL, create_test_app, serve

NOTE = {"title": "Lecture notes", "body": "Chapter 1"}


def key_header(key: uuid.UUID | str | None = None) -> dict[str, str]:
    return {"Idempotency-Key": str(key or uuid.uuid4())}


async def count(session: AsyncSession, model: type) -> int:
    session.expire_all()
    return await session.scalar(select(func.count()).select_from(model)) or 0


async def test_repeat_returns_the_same_response(
    api: httpx2.AsyncClient, session: AsyncSession
) -> None:
    headers = key_header()

    first = await api.post(NOTES_URL, json=NOTE, headers=headers)
    second = await api.post(NOTES_URL, json=NOTE, headers=headers)

    assert first.status_code == second.status_code == 201
    assert first.content == second.content
    assert first.headers["content-type"] == second.headers["content-type"]
    assert "Idempotent-Replayed" not in first.headers
    assert second.headers["Idempotent-Replayed"] == "true"
    assert first.headers["X-Request-ID"] != second.headers["X-Request-ID"]
    assert await count(session, Note) == 1


async def test_concurrent_repeats_create_one_object(
    api: httpx2.AsyncClient, session: AsyncSession
) -> None:
    headers = key_header()

    # The first request holds its transaction open for a while; the others
    # wait for it on the key and then get its response.
    responses = await asyncio.gather(
        *(
            api.post(NOTES_URL, json=NOTE, headers=headers, params={"delay": 0.3})
            for _ in range(5)
        )
    )

    assert {response.status_code for response in responses} == {201}
    assert len({response.content for response in responses}) == 1
    replayed = [r for r in responses if "Idempotent-Replayed" in r.headers]
    assert len(replayed) == 4
    assert await count(session, Note) == 1
    assert await count(session, IdempotencyKey) == 1


async def test_different_keys_create_different_objects(
    api: httpx2.AsyncClient, session: AsyncSession
) -> None:
    for _ in range(2):
        response = await api.post(NOTES_URL, json=NOTE, headers=key_header())
        assert response.status_code == 201

    assert await count(session, Note) == 2


@pytest.mark.parametrize(
    "change",
    [
        {"json": {**NOTE, "title": "Other"}},
        {"json": NOTE, "params": {"delay": 0}},
    ],
)
async def test_same_key_with_other_request_is_rejected(
    api: httpx2.AsyncClient, session: AsyncSession, change: dict[str, Any]
) -> None:
    headers = key_header()
    await api.post(NOTES_URL, json=NOTE, headers=headers)

    response = await api.post(NOTES_URL, headers=headers, **change)

    assert response.status_code == 422
    assert response.json()["code"] == "idempotency_key_reused"
    assert await count(session, Note) == 1


async def test_same_key_on_another_path_is_rejected(api: httpx2.AsyncClient) -> None:
    headers = key_header()
    created = await api.post(NOTES_URL, json=NOTE, headers=headers)

    response = await api.delete(f"{NOTES_URL}/{created.json()['id']}", headers=headers)

    assert response.status_code == 422
    assert response.json()["code"] == "idempotency_key_reused"


@pytest.mark.parametrize("outcome", ["problem", "conflict_response", "crash"])
async def test_failed_request_rolls_back_with_its_key(
    api: httpx2.AsyncClient, session: AsyncSession, outcome: str
) -> None:
    headers = key_header()
    params = {"outcome": outcome}

    first = await api.post(NOTES_URL, json=NOTE, headers=headers, params=params)
    second = await api.post(NOTES_URL, json=NOTE, headers=headers, params=params)

    assert first.status_code == second.status_code
    assert first.status_code in {409, 500}
    assert "Idempotent-Replayed" not in second.headers
    assert await count(session, Note) == 0
    assert await count(session, IdempotencyKey) == 0


async def test_key_may_be_reused_after_a_failed_attempt(
    api: httpx2.AsyncClient, session: AsyncSession
) -> None:
    headers = key_header()
    await api.post(NOTES_URL, json=NOTE, headers=headers, params={"outcome": "crash"})

    response = await api.post(NOTES_URL, json=NOTE, headers=headers)

    assert response.status_code == 201
    assert await count(session, Note) == 1


async def test_empty_response_is_replayed(api: httpx2.AsyncClient) -> None:
    created = await api.post(NOTES_URL, json=NOTE, headers=key_header())
    headers = key_header()
    url = f"{NOTES_URL}/{created.json()['id']}"

    first = await api.delete(url, headers=headers)
    second = await api.delete(url, headers=headers)

    assert first.status_code == second.status_code == 204
    assert second.content == b""
    assert second.headers["Idempotent-Replayed"] == "true"


@pytest.mark.parametrize(
    ("value", "code"),
    [(None, "idempotency_key_missing"), ("not-a-uuid", "idempotency_key_invalid")],
)
async def test_mutating_request_needs_a_uuid_key(
    api: httpx2.AsyncClient, session: AsyncSession, value: str | None, code: str
) -> None:
    headers = {} if value is None else {"Idempotency-Key": value}

    response = await api.post(NOTES_URL, json=NOTE, headers=headers)

    assert response.status_code == 400
    assert response.json()["code"] == code
    assert await count(session, Note) == 0


async def test_mutating_request_without_database_fails(
    api_without_database: httpx2.AsyncClient,
) -> None:
    response = await api_without_database.post(
        NOTES_URL, json=NOTE, headers=key_header()
    )

    assert response.status_code == 500
    assert response.json()["code"] == "internal_error"


async def test_key_expires_after_ttl(
    api: httpx2.AsyncClient, session: AsyncSession
) -> None:
    headers = key_header()
    start = datetime(2027, 3, 1, 12, 0, tzinfo=UTC)
    with time_machine.travel(start, tick=False) as traveller:
        await api.post(NOTES_URL, json=NOTE, headers=headers)

        traveller.shift(timedelta(hours=24) - timedelta(seconds=1))
        within = await api.post(NOTES_URL, json=NOTE, headers=headers)
        traveller.shift(timedelta(seconds=1))
        # Expired: the key is free again, even for a different request.
        after = await api.post(
            NOTES_URL, json={**NOTE, "title": "Other"}, headers=headers
        )

    assert within.headers["Idempotent-Replayed"] == "true"
    assert after.status_code == 201
    assert "Idempotent-Replayed" not in after.headers
    assert await count(session, Note) == 2
    assert await count(session, IdempotencyKey) == 1


async def test_expired_keys_are_deleted(
    api: httpx2.AsyncClient, session: AsyncSession
) -> None:
    start = datetime(2027, 3, 1, 12, 0, tzinfo=UTC)
    with time_machine.travel(start, tick=False) as traveller:
        await api.post(NOTES_URL, json=NOTE, headers=key_header())
        traveller.shift(timedelta(hours=12))
        await api.post(NOTES_URL, json=NOTE, headers=key_header())

    deleted = await delete_expired_idempotency_keys(
        session, start + timedelta(hours=24)
    )
    await session.commit()

    assert deleted == 1
    assert await count(session, IdempotencyKey) == 1
    assert await count(session, Note) == 2


def new_key() -> str:
    return base64.b64encode(secrets.token_bytes(32)).decode()


def keyring_settings(database_url: str, *keys: str) -> Settings:
    return web_settings(database_url).model_copy(
        update={"idempotency_encryption_keys": [SecretStr(key) for key in keys]}
    )


async def test_stored_response_is_encrypted(
    api: httpx2.AsyncClient, session: AsyncSession
) -> None:
    response = await api.post(NOTES_URL, json=NOTE, headers=key_header())

    stored = await session.scalar(select(IdempotencyKey.response))
    assert stored is not None
    for plaintext in (b"Lecture notes", b"Chapter 1", b"application/json"):
        assert plaintext not in stored
    assert response.json()["id"].encode() not in stored


async def test_response_cannot_be_moved_to_another_key(
    api: httpx2.AsyncClient, session: AsyncSession
) -> None:
    first, second = uuid.uuid4(), uuid.uuid4()
    await api.post(NOTES_URL, json=NOTE, headers=key_header(first))
    await api.post(NOTES_URL, json=NOTE, headers=key_header(second))
    stored = await session.scalar(
        select(IdempotencyKey.response).where(IdempotencyKey.key == first)
    )
    await session.execute(
        update(IdempotencyKey)
        .where(IdempotencyKey.key == second)
        .values(response=stored)
    )
    await session.commit()

    # The ciphertext is bound to its scope and key: it fails to open, and
    # the operation is not run again.
    response = await api.post(NOTES_URL, json=NOTE, headers=key_header(second))

    assert response.status_code == 500
    assert await count(session, Note) == 2


async def test_keys_rotate_without_losing_responses(
    database_url: str, session: AsyncSession
) -> None:
    old, new = ENCRYPTION_KEY, new_key()
    headers = key_header()
    async with serve(create_test_app(keyring_settings(database_url, old))) as api:
        first = await api.post(NOTES_URL, json=NOTE, headers=headers)

    # The new key is put first: it seals new responses, the old one still
    # opens responses sealed before the rotation.
    async with serve(create_test_app(keyring_settings(database_url, new, old))) as api:
        replayed = await api.post(NOTES_URL, json=NOTE, headers=headers)
        other = key_header()
        await api.post(NOTES_URL, json=NOTE, headers=other)
    assert replayed.content == first.content
    assert replayed.headers["Idempotent-Replayed"] == "true"

    # Once the old responses expired, the old key is removed.
    async with serve(create_test_app(keyring_settings(database_url, new))) as api:
        assert (await api.post(NOTES_URL, json=NOTE, headers=other)).status_code == 201
        assert (await api.post(NOTES_URL, json=NOTE, headers=headers)).status_code == (
            500
        )
    assert await count(session, Note) == 2


async def test_mutating_request_without_keys_fails(
    database_url: str, session: AsyncSession
) -> None:
    async with serve(create_test_app(keyring_settings(database_url))) as api:
        response = await api.post(NOTES_URL, json=NOTE, headers=key_header())
        listed = await api.get(NOTES_URL)

    assert response.status_code == 500
    assert listed.status_code == 200
    assert await count(session, Note) == 0
    assert await count(session, IdempotencyKey) == 0


def test_keyring_round_trip_and_tampering() -> None:
    keyring = ResponseKeyring([secrets.token_bytes(32)])
    key = uuid.uuid4()
    response = StoredResponse(201, b"\x00\xffbody", [("set-cookie", "a=b")])

    sealed = keyring.seal("anonymous", key, response)

    assert keyring.open("anonymous", key, sealed) == StoredResponse(
        201, b"\x00\xffbody", [("set-cookie", "a=b")]
    )
    assert sealed != keyring.seal("anonymous", key, response)
    tampered = sealed[:-1] + bytes([sealed[-1] ^ 1])
    for scope, value in (("anonymous", tampered), ("user", sealed)):
        with pytest.raises(ResponseUnreadableError):
            keyring.open(scope, key, value)
    with pytest.raises(RuntimeError, match="IDEMPOTENCY_ENCRYPTION_KEYS"):
        ResponseKeyring([])


@pytest.mark.parametrize(
    "keys",
    [
        ["not base64!"],
        [base64.b64encode(b"short").decode()],
        [ENCRYPTION_KEY, ENCRYPTION_KEY],
    ],
)
def test_invalid_encryption_keys(keys: list[str]) -> None:
    with pytest.raises(ValidationError):
        Settings(idempotency_encryption_keys=[SecretStr(key) for key in keys])


def test_encryption_keys_from_environment(monkeypatch: pytest.MonkeyPatch) -> None:
    new, old = new_key(), new_key()
    monkeypatch.setenv("CAMPUS_IDEMPOTENCY_ENCRYPTION_KEYS", f"{new}, {old}")

    keys = Settings().idempotency_encryption_keys

    assert [value.get_secret_value() for value in keys] == [new, old]
    assert new not in repr(Settings())
