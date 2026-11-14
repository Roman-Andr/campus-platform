"""Multi-device inventory, revocation, and refresh races on PostgreSQL."""

import asyncio
from datetime import timedelta
from typing import Any
from uuid import UUID, uuid4

import jwt
import pytest
import time_machine
from fastapi import Request
from sqlalchemy import func, select, update

from campus.core import clock
from campus.core.outbox import OutboxMessage
from campus.modules.identity import (
    DocumentKind,
    RefreshToken,
    Session,
    publish_document,
)
from campus.modules.identity.sessions import revoke_sessions
from tests.test_identity import DEVICE, SECRET, Auth
from tests.test_identity import auth as auth  # noqa: PLC0414 - pytest fixture


def headers(tokens: dict[str, Any]) -> dict[str, str]:
    return {"Authorization": "Bearer " + tokens["access_token"]}


def sid(tokens: dict[str, Any]) -> str:
    return str(jwt.decode(tokens["access_token"], SECRET, algorithms=["HS256"])["sid"])


async def test_session_inventory_and_activity(auth: Auth) -> None:
    with time_machine.travel(clock.now(), tick=False) as travel:
        first = await auth.login(device_name="Phone")
        travel.shift(timedelta(seconds=10))
        second = await auth.login(device_id=str(uuid4()), device_name="Laptop")
        await auth.login(email="other@university.example", device_id=str(uuid4()))
        response = await auth.client.get("/api/v1/me/sessions", headers=headers(first))
        assert response.status_code == 200
        devices = response.json()
        assert [d["device_name"] for d in devices] == ["Laptop", "Phone"]
        assert [d["current"] for d in devices] == [False, True]
        assert all(d["platform"] == "android" for d in devices)
        before = devices[1]["last_active_at"]
        travel.shift(timedelta(seconds=10))
        await auth.post(
            "/token/refresh",
            {"refresh_token": first["refresh_token"], "device_id": DEVICE},
        )
        devices = (
            await auth.client.get("/api/v1/me/sessions", headers=headers(first))
        ).json()
        assert devices[1]["last_active_at"] > before
        assert devices[1]["signed_in_at"] == before
        await auth.client.delete(
            "/api/v1/me/sessions/" + sid(second),
            headers={**headers(first), "Idempotency-Key": str(uuid4())},
        )
        devices = (
            await auth.client.get("/api/v1/me/sessions", headers=headers(first))
        ).json()
        assert [d["id"] for d in devices] == [sid(first)]
        await auth.db.execute(update(RefreshToken).values(expires_at=clock.now()))
        await auth.db.commit()
        assert (
            await auth.client.get("/api/v1/me/sessions", headers=headers(first))
        ).json() == []


@pytest.mark.parametrize("all_devices", [False, True])
async def test_revoke_tokens_and_transactional_event(
    auth: Auth, all_devices: bool
) -> None:
    first = await auth.login()
    device_id = str(uuid4())
    second = await auth.login(device_id=device_id)
    other = await auth.login(email="other@university.example", device_id=str(uuid4()))
    path = "/api/v1/me/sessions" + ("" if all_devices else "/" + sid(second))
    key = str(uuid4())
    response = await auth.client.delete(
        path, headers={**headers(first), "Idempotency-Key": key}
    )
    assert response.status_code == 204
    for tokens, device in ((first, DEVICE), (second, device_id)):
        revoked = all_devices or tokens is second
        assert (
            await auth.client.get("/api/v1/private", headers=headers(tokens))
        ).status_code == (401 if revoked else 200)
        assert (
            await auth.post(
                "/token/refresh",
                {"refresh_token": tokens["refresh_token"], "device_id": device},
            )
        ).status_code == (401 if revoked else 200)
    assert (
        await auth.client.get("/api/v1/private", headers=headers(other))
    ).status_code == 200
    event = await auth.db.scalar(
        select(OutboxMessage).where(OutboxMessage.topic == "identity.sessions_revoked")
    )
    assert event is not None
    assert event.payload["user_id"] == first["user"]["id"]
    expected = {sid(first), sid(second)} if all_devices else {sid(second)}
    assert set(event.payload["session_ids"]) == expected
    for session_id in expected:
        assert await auth.redis.exists(f"auth:revoked:{session_id}")
        device_row = await auth.db.get(Session, UUID(session_id))
        assert device_row is not None
        assert device_row.revoked_at is not None
    if not all_devices:
        replay = await auth.client.delete(
            path, headers={**headers(first), "Idempotency-Key": key}
        )
        assert replay.status_code == 204
        assert replay.headers["Idempotent-Replayed"] == "true"
        assert (
            await auth.db.scalar(
                select(func.count())
                .select_from(OutboxMessage)
                .where(OutboxMessage.topic == "identity.sessions_revoked")
            )
            == 1
        )


async def test_session_authorization_and_idempotency_header(auth: Auth) -> None:
    first = await auth.login()
    other = await auth.login(email="other@university.example", device_id=str(uuid4()))
    for session_id in (sid(other), str(uuid4())):
        response = await auth.client.delete(
            "/api/v1/me/sessions/" + session_id,
            headers={**headers(first), "Idempotency-Key": str(uuid4())},
        )
        assert response.status_code == 404
    assert (
        await auth.client.delete("/api/v1/me/sessions", headers=headers(first))
    ).status_code == 400
    assert (await auth.client.get("/api/v1/me/sessions")).status_code == 401
    assert (
        await auth.client.delete(
            "/api/v1/me/sessions", headers={"Idempotency-Key": str(uuid4())}
        )
    ).status_code == 401
    assert (
        await auth.client.get("/api/v1/private", headers=headers(other))
    ).status_code == 200


@pytest.mark.parametrize("all_devices", [False, True])
async def test_parallel_revoke_and_refresh(auth: Auth, all_devices: bool) -> None:
    first = await auth.login()
    device_id = str(uuid4())
    target = await auth.login(device_id=device_id)
    path = "/api/v1/me/sessions" + ("" if all_devices else "/" + sid(target))
    revoked, refreshed = await asyncio.gather(
        auth.client.delete(
            path, headers={**headers(first), "Idempotency-Key": str(uuid4())}
        ),
        auth.post(
            "/token/refresh",
            {"refresh_token": target["refresh_token"], "device_id": device_id},
        ),
    )
    assert revoked.status_code == 204
    assert refreshed.status_code in (200, 401)
    for tokens in [
        target,
        *([refreshed.json()] if refreshed.status_code == 200 else []),
    ]:
        assert (
            await auth.client.get("/api/v1/private", headers=headers(tokens))
        ).status_code == 401
        assert (
            await auth.post(
                "/token/refresh",
                {"refresh_token": tokens["refresh_token"], "device_id": device_id},
            )
        ).status_code == 401


async def test_outbox_and_revocation_roll_back_together(auth: Auth) -> None:
    tokens = await auth.login()
    device = await auth.db.scalar(
        select(Session).where(Session.id == UUID(sid(tokens))).with_for_update()
    )
    assert device is not None
    request = Request({"type": "http", "app": auth.app})
    await revoke_sessions(request, auth.db, [device])
    await auth.db.flush()
    assert (
        await auth.db.scalar(
            select(OutboxMessage).where(
                OutboxMessage.topic == "identity.sessions_revoked"
            )
        )
        is not None
    )
    await auth.db.rollback()
    device = await auth.db.get(Session, UUID(sid(tokens)))
    assert device is not None
    assert device.revoked_at is None
    assert (
        await auth.db.scalar(
            select(OutboxMessage).where(
                OutboxMessage.topic == "identity.sessions_revoked"
            )
        )
        is None
    )


async def test_pending_consents_do_not_block_session_management(auth: Auth) -> None:
    first = await auth.login()
    second = await auth.login(device_id=str(uuid4()))
    await publish_document(
        auth.db, DocumentKind.RULES, text_ru="Новые правила", text_en="New rules"
    )
    await auth.db.commit()
    assert (
        await auth.client.get("/api/v1/private", headers=headers(first))
    ).status_code == 403
    assert (
        await auth.client.get("/api/v1/me/sessions", headers=headers(first))
    ).status_code == 200
    assert (
        await auth.client.delete(
            "/api/v1/me/sessions/" + sid(second),
            headers={**headers(first), "Idempotency-Key": str(uuid4())},
        )
    ).status_code == 204
    assert (
        await auth.client.delete(
            "/api/v1/me/sessions",
            headers={**headers(first), "Idempotency-Key": str(uuid4())},
        )
    ).status_code == 204
