"""FCM token registration and Android push delivery on PostgreSQL."""

import asyncio
import json
from typing import Any
from uuid import UUID, uuid4

import httpx2
import jwt
import pytest
import time_machine
from pydantic import SecretStr
from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncEngine

from campus.core import clock
from campus.core.config import Settings
from campus.core.db import create_session_factory
from campus.core.outbox import OutboxMessage, add_message, process_outbox
from campus.modules.identity import Session, SessionsRevoked
from campus.modules.notifications import (
    Notification,
    PushToken,
    notify,
)
from campus.modules.notifications import (
    fcm as fcm_module,
)
from campus.modules.notifications.fcm import (
    FcmNotConfiguredError,
    FcmPermanentError,
    FcmTemporaryError,
    FcmTokenInvalidError,
)
from tests.test_identity import Auth
from tests.test_listings import auth, borrower, owner, places
from tests.test_profile import Account

__all__ = ["auth", "borrower", "owner", "places"]

ROOT = "/api/v1/notifications/push-token"
GENERIC_RU = "У вас новое уведомление."  # noqa: RUF001 - expected Russian


async def put_token(account: Account, token: str, key: str | None = None) -> Any:
    return await account.auth.client.put(
        ROOT,
        json={"token": token},
        headers={"Idempotency-Key": key or str(uuid4()), **account.headers},
    )


async def delete_token(account: Account, key: str | None = None) -> Any:
    return await account.auth.client.delete(
        ROOT,
        headers={"Idempotency-Key": key or str(uuid4()), **account.headers},
    )


async def token_rows(auth: Auth) -> list[PushToken]:
    await auth.db.rollback()
    return list((await auth.db.scalars(select(PushToken))).all())


async def token_count(auth: Auth) -> int:
    await auth.db.rollback()
    return int(await auth.db.scalar(select(func.count()).select_from(PushToken)) or 0)


async def notification_count(auth: Auth) -> int:
    await auth.db.rollback()
    return int(
        await auth.db.scalar(select(func.count()).select_from(Notification)) or 0
    )


async def session_id(auth: Auth, account: Account) -> UUID:
    await auth.db.rollback()
    value = await auth.db.scalar(
        select(Session.id).where(Session.user_id == UUID(account.tokens["user"]["id"]))
    )
    assert value is not None
    return value


async def set_consent(auth: Auth, account: Account, accepted: bool) -> None:
    documents = (await auth.client.get("/api/v1/documents")).json()
    document = next(
        item for item in documents if item["kind"] == "cross_border_transfer"
    )
    response = await auth.client.put(
        "/api/v1/me/consents/cross-border",
        json={"document_id": document["id"], "accepted": accepted},
        headers={"Idempotency-Key": str(uuid4()), **account.headers},
    )
    assert response.status_code == 204, response.text


async def enqueue(
    auth: Auth, account: Account, message: str = "There is an update."
) -> None:
    notify(
        auth.db,
        {UUID(account.tokens["user"]["id"])},
        "status.changed",
        {},
        message=message,
    )
    await auth.db.commit()


async def drain(engine: AsyncEngine, auth: Auth) -> None:
    sessions = create_session_factory(engine)
    for _ in range(20):
        if not await process_outbox(sessions, auth.settings):
            break


async def feed(account: Account) -> Any:
    response = await account.auth.client.get(
        "/api/v1/notifications", headers=account.headers
    )
    assert response.status_code == 200, response.text
    return response.json()


class FakeFcm:
    """A transport that records messages and raises queued errors."""

    def __init__(self) -> None:
        self.calls: list[tuple[str, dict[str, Any]]] = []
        self.failures: list[Exception] = []

    async def __call__(
        self, _settings: Settings, token: str, message: dict[str, Any]
    ) -> None:
        self.calls.append((token, message))
        if self.failures:
            raise self.failures.pop(0)


@pytest.fixture(autouse=True)
def daytime_delivery(monkeypatch: pytest.MonkeyPatch) -> None:
    """Keep quiet hours out of push tests; #87 has its own boundary tests."""
    settings = Settings().model_copy(update={"notification_quiet_hours_enabled": False})
    monkeypatch.setattr(
        "campus.modules.notifications.preferences.get_settings", lambda: settings
    )


@pytest.fixture
def fcm(monkeypatch: pytest.MonkeyPatch) -> FakeFcm:
    fake = FakeFcm()
    monkeypatch.setattr("campus.modules.notifications.fcm.send_message", fake)
    return fake


class FakeResponse:
    """A minimal HTTP response for the FCM client."""

    def __init__(
        self,
        status_code: int,
        body: dict[str, Any] | None = None,
        *,
        invalid_json: bool = False,
    ) -> None:
        self.status_code = status_code
        self.body = body or {}
        self.invalid_json = invalid_json

    def json(self) -> dict[str, Any]:
        if self.invalid_json:
            raise ValueError("not JSON")
        return self.body


class FakeHttp:
    """An async HTTP client that returns one prepared answer."""

    def __init__(
        self, response: FakeResponse | None = None, error: Exception | None = None
    ) -> None:
        self.response = response
        self.error = error
        self.requests: list[dict[str, Any]] = []

    async def __aenter__(self) -> FakeHttp:
        return self

    async def __aexit__(self, *_args: object) -> None:
        return None

    async def post(self, url: str, **kwargs: Any) -> FakeResponse:
        self.requests.append({"url": url, **kwargs})
        if self.error is not None:
            raise self.error
        assert self.response is not None
        return self.response


def fake_http(
    monkeypatch: pytest.MonkeyPatch,
    response: FakeResponse | None = None,
    error: Exception | None = None,
) -> FakeHttp:
    client = FakeHttp(response, error)
    monkeypatch.setattr(httpx2, "AsyncClient", lambda **_kwargs: client)
    return client


@pytest.fixture
def fcm_settings() -> Settings:
    return Settings(
        fcm_project_id="project",
        fcm_client_email="service@example.com",
        fcm_private_key=SecretStr("line1\\nline2"),
    )


async def test_registration_is_idempotent_and_owner_only(
    auth: Auth, owner: Account, borrower: Account
) -> None:
    key = str(uuid4())
    assert (await put_token(owner, "token-a", key)).status_code == 204
    assert await token_count(auth) == 1

    replay = await put_token(owner, "token-a", key)
    assert replay.status_code == 204
    assert replay.headers["Idempotent-Replayed"] == "true"
    assert await token_count(auth) == 1

    # Same body with a new key is still one binding.
    assert (await put_token(owner, "token-a")).status_code == 204
    assert await token_count(auth) == 1

    # A rotated token replaces the previous token of the session.
    assert (await put_token(owner, "token-b")).status_code == 204
    assert {row.token for row in await token_rows(auth)} == {"token-b"}

    # Another account cannot remove it, because it only owns its own session.
    assert (await delete_token(borrower)).status_code == 204
    assert {row.token for row in await token_rows(auth)} == {"token-b"}

    assert (await delete_token(owner)).status_code == 204
    assert await token_count(auth) == 0

    missing = await owner.auth.client.put(
        ROOT, json={"token": "token-c"}, headers=owner.headers
    )
    assert missing.status_code == 400
    assert missing.json()["code"] == "idempotency_key_missing"

    empty = await put_token(owner, "")
    assert empty.status_code == 422
    assert empty.json()["code"] == "validation_failed"

    anonymous = await owner.auth.client.put(
        ROOT,
        json={"token": "token-c"},
        headers={"Idempotency-Key": str(uuid4())},
    )
    assert anonymous.status_code == 401


async def test_same_key_with_another_body_is_rejected(
    auth: Auth, owner: Account
) -> None:
    key = str(uuid4())
    assert (await put_token(owner, "token-a", key)).status_code == 204

    reused = await put_token(owner, "token-b", key)
    assert reused.status_code == 422
    assert reused.json()["code"] == "idempotency_key_reused"
    assert {row.token for row in await token_rows(auth)} == {"token-a"}


async def test_concurrent_registration_keeps_one_token(
    auth: Auth, owner: Account
) -> None:
    responses = await asyncio.gather(
        put_token(owner, "token-a"), put_token(owner, "token-b")
    )
    assert [response.status_code for response in responses] == [204, 204]

    rows = await token_rows(auth)
    assert len(rows) == 1
    assert rows[0].token in {"token-a", "token-b"}
    assert rows[0].session_id == await session_id(auth, owner)


async def test_token_moves_to_the_current_account(
    auth: Auth, owner: Account, borrower: Account
) -> None:
    assert (await put_token(owner, "shared-token")).status_code == 204
    assert (await put_token(borrower, "shared-token")).status_code == 204

    rows = await token_rows(auth)
    assert len(rows) == 1
    assert rows[0].token == "shared-token"  # noqa: S105 - test token
    assert rows[0].user_id == UUID(borrower.tokens["user"]["id"])
    assert rows[0].session_id == await session_id(auth, borrower)


async def test_revoked_session_cannot_register_or_replay(
    auth: Auth, owner: Account, engine: AsyncEngine
) -> None:
    key = str(uuid4())
    assert (await put_token(owner, "token-a", key)).status_code == 204
    identifier = await session_id(auth, owner)

    revoked = await owner.auth.client.delete(
        f"/api/v1/me/sessions/{identifier}",
        headers={"Idempotency-Key": str(uuid4()), **owner.headers},
    )
    assert revoked.status_code == 204

    # The dependency runs on a replay too: the stored 204 is not returned to
    # a session revoked after the original request.
    replay = await put_token(owner, "token-a", key)
    assert replay.status_code == 401
    assert (await delete_token(owner)).status_code == 401

    await drain(engine, auth)
    assert await token_count(auth) == 0


async def test_revoked_session_is_skipped_before_tokens_are_pruned(
    auth: Auth, owner: Account, engine: AsyncEngine, fcm: FakeFcm
) -> None:
    assert (await put_token(owner, "token-a")).status_code == 204
    identifier = await session_id(auth, owner)
    await auth.db.execute(
        update(Session).where(Session.id == identifier).values(revoked_at=clock.now())
    )
    await auth.db.commit()

    await enqueue(auth, owner)
    await drain(engine, auth)

    assert fcm.calls == []
    assert await notification_count(auth) == 1


async def test_push_text_requires_live_consent(
    auth: Auth, owner: Account, engine: AsyncEngine, fcm: FakeFcm
) -> None:
    assert (await put_token(owner, "token-a")).status_code == 204
    await set_consent(auth, owner, True)
    await drain(engine, auth)
    message = "Anna wants to join your listing."
    await enqueue(auth, owner, message)
    await drain(engine, auth)

    assert len(fcm.calls) == 1
    allowed = fcm.calls[0][1]
    assert allowed["notification"]["body"] == message
    assert allowed["data"]["type"] == "status.changed"
    assert allowed["data"]["notification_id"]
    assert allowed["data"]["delivery_id"]

    await set_consent(auth, owner, False)
    await drain(engine, auth)
    # A late "allowed" event cannot restore text after the revocation.
    async with create_session_factory(engine)() as session, session.begin():
        add_message(
            session,
            "identity.cross_border_consent_changed",
            {
                "user_id": str(UUID(owner.tokens["user"]["id"])),
                "document_id": str(uuid4()),
                "allowed": True,
            },
        )
    await drain(engine, auth)
    await enqueue(auth, owner, message)
    await drain(engine, auth)

    assert len(fcm.calls) == 2
    sanitized = fcm.calls[1][1]
    assert sanitized["notification"]["body"] == GENERIC_RU
    assert set(sanitized["data"]) == {
        "notification_id",
        "sequence",
        "delivery_id",
    }
    assert "Anna" not in json.dumps(sanitized, ensure_ascii=False)
    assert len((await feed(owner))["items"]) == 2


async def test_temporary_error_is_retried_with_the_same_delivery_id(
    auth: Auth, owner: Account, engine: AsyncEngine, fcm: FakeFcm
) -> None:
    assert (await put_token(owner, "token-a")).status_code == 204
    fcm.failures.append(FcmTemporaryError("provider unavailable"))
    await enqueue(auth, owner)
    await drain(engine, auth)

    assert len(fcm.calls) == 1
    assert await token_count(auth) == 1
    assert await notification_count(auth) == 1
    delivery_id = fcm.calls[0][1]["data"]["delivery_id"]

    await auth.db.rollback()
    job = await auth.db.scalar(
        select(OutboxMessage).where(
            OutboxMessage.topic == "notifications.channel.fcm",
            OutboxMessage.processed_at.is_(None),
        )
    )
    assert job is not None
    assert job.attempts == 1
    with time_machine.travel(job.available_at, tick=False):
        await drain(engine, auth)

    assert len(fcm.calls) == 2
    assert fcm.calls[1][1]["data"]["delivery_id"] == delivery_id
    assert await notification_count(auth) == 1


async def test_invalid_token_is_forgotten_and_feed_survives(
    auth: Auth, owner: Account, engine: AsyncEngine, fcm: FakeFcm
) -> None:
    assert (await put_token(owner, "token-a")).status_code == 204
    fcm.failures.append(FcmTokenInvalidError())
    await enqueue(auth, owner)
    await drain(engine, auth)

    assert await token_count(auth) == 0
    assert await notification_count(auth) == 1
    await auth.db.rollback()
    job = await auth.db.scalar(
        select(OutboxMessage).where(OutboxMessage.topic == "notifications.channel.fcm")
    )
    assert job is not None
    assert job.processed_at is not None


async def test_permanent_error_keeps_token_and_does_not_retry(
    auth: Auth, owner: Account, engine: AsyncEngine, fcm: FakeFcm
) -> None:
    assert (await put_token(owner, "token-a")).status_code == 204
    fcm.failures.append(FcmPermanentError("bad payload"))
    await enqueue(auth, owner)
    await drain(engine, auth)

    assert await token_count(auth) == 1
    assert await notification_count(auth) == 1
    await auth.db.rollback()
    job = await auth.db.scalar(
        select(OutboxMessage).where(OutboxMessage.topic == "notifications.channel.fcm")
    )
    assert job is not None
    assert job.processed_at is not None


async def test_consent_change_reaches_the_fcm_consumer(
    auth: Auth, owner: Account, engine: AsyncEngine
) -> None:
    await set_consent(auth, owner, True)
    await drain(engine, auth)

    await auth.db.rollback()
    job = await auth.db.scalar(
        select(OutboxMessage).where(OutboxMessage.topic == "identity.consent.fcm")
    )
    assert job is not None
    assert job.processed_at is not None


@pytest.mark.parametrize(
    ("status", "body", "expected"),
    [
        (200, {}, None),
        (
            404,
            {"error": {"details": [{"errorCode": "UNREGISTERED"}]}},
            FcmTokenInvalidError,
        ),
        (
            400,
            {"error": {"message": "The registration token is invalid"}},
            FcmTokenInvalidError,
        ),
        (400, {"error": {"message": "Invalid payload"}}, FcmPermanentError),
        (429, {}, FcmTemporaryError),
        (500, {}, FcmTemporaryError),
        (401, {}, FcmPermanentError),
    ],
)
async def test_send_message_classifies_provider_answers(
    monkeypatch: pytest.MonkeyPatch,
    fcm_settings: Settings,
    status: int,
    body: dict[str, Any],
    expected: type[Exception] | None,
) -> None:
    fake_http(monkeypatch, FakeResponse(status, body))

    async def access(*_args: object, **_kwargs: object) -> str:
        return "access"

    monkeypatch.setattr(fcm_module, "_access_token", access)
    if expected is None:
        await fcm_module.send_message(fcm_settings, "token", {"data": {}})
    else:
        with pytest.raises(expected):
            await fcm_module.send_message(fcm_settings, "token", {"data": {}})


async def test_send_message_without_credentials_is_permanent(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    client = fake_http(monkeypatch)
    with pytest.raises(FcmNotConfiguredError):
        await fcm_module.send_message(Settings(_env_file=None), "token", {"data": {}})
    assert client.requests == []


async def test_send_message_handles_malformed_error_body(
    monkeypatch: pytest.MonkeyPatch, fcm_settings: Settings
) -> None:
    fake_http(monkeypatch, FakeResponse(500, invalid_json=True))

    async def access(*_args: object, **_kwargs: object) -> str:
        return "access"

    monkeypatch.setattr(fcm_module, "_access_token", access)
    with pytest.raises(FcmTemporaryError):
        await fcm_module.send_message(fcm_settings, "token", {"data": {}})


async def test_send_message_wraps_network_errors(
    monkeypatch: pytest.MonkeyPatch, fcm_settings: Settings
) -> None:
    fake_http(monkeypatch, error=httpx2.HTTPError("offline"))

    async def access(*_args: object, **_kwargs: object) -> str:
        return "access"

    monkeypatch.setattr(fcm_module, "_access_token", access)
    with pytest.raises(FcmTemporaryError):
        await fcm_module.send_message(fcm_settings, "token", {"data": {}})


async def test_access_token_comes_from_the_oauth_endpoint(
    monkeypatch: pytest.MonkeyPatch, fcm_settings: Settings
) -> None:
    client = fake_http(monkeypatch, FakeResponse(200, {"access_token": "abc"}))
    monkeypatch.setattr(jwt, "encode", lambda *_args, **_kwargs: "assertion")

    token = await fcm_module._access_token(fcm_settings, "service@example.com", "key")

    assert token == "abc"  # noqa: S105 - test access token
    assert client.requests[0]["url"] == fcm_module.OAUTH_ENDPOINT
    assert client.requests[0]["data"]["assertion"] == "assertion"


@pytest.mark.parametrize(
    ("status", "body", "expected"),
    [
        (500, {}, FcmTemporaryError),
        (400, {}, FcmPermanentError),
        (200, {}, FcmPermanentError),
    ],
)
async def test_access_token_classifies_answers(
    monkeypatch: pytest.MonkeyPatch,
    fcm_settings: Settings,
    status: int,
    body: dict[str, Any],
    expected: type[Exception],
) -> None:
    fake_http(monkeypatch, FakeResponse(status, body))
    monkeypatch.setattr(jwt, "encode", lambda *_args, **_kwargs: "assertion")

    with pytest.raises(expected):
        await fcm_module._access_token(fcm_settings, "service@example.com", "key")


async def test_access_token_wraps_network_errors(
    monkeypatch: pytest.MonkeyPatch, fcm_settings: Settings
) -> None:
    fake_http(monkeypatch, error=httpx2.HTTPError("offline"))
    monkeypatch.setattr(jwt, "encode", lambda *_args, **_kwargs: "assertion")

    with pytest.raises(FcmTemporaryError):
        await fcm_module._access_token(fcm_settings, "service@example.com", "key")


async def test_access_token_rejects_non_json(
    monkeypatch: pytest.MonkeyPatch, fcm_settings: Settings
) -> None:
    fake_http(monkeypatch, FakeResponse(200, invalid_json=True))
    monkeypatch.setattr(jwt, "encode", lambda *_args, **_kwargs: "assertion")

    with pytest.raises(FcmPermanentError):
        await fcm_module._access_token(fcm_settings, "service@example.com", "key")


def test_credentials_require_all_parts() -> None:
    with pytest.raises(FcmNotConfiguredError):
        fcm_module._credentials(Settings(_env_file=None))

    settings = Settings(
        fcm_project_id="project",
        fcm_client_email="service@example.com",
        fcm_private_key=SecretStr("line1\\nline2"),
    )
    assert fcm_module._credentials(settings) == (
        "project",
        "service@example.com",
        "line1\nline2",
    )


async def test_empty_session_event_deletes_no_tokens(auth: Auth) -> None:
    await fcm_module._forget_revoked_tokens(
        auth.db, SessionsRevoked(uuid4(), uuid4(), ())
    )

    assert await token_count(auth) == 0


async def test_access_token_rejects_malformed_private_key(
    fcm_settings: Settings,
) -> None:
    with pytest.raises(FcmPermanentError):
        await fcm_module._access_token(
            fcm_settings, "service@example.com", "not a private key"
        )
