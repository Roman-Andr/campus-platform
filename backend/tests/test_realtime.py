"""Realtime tokens, channel ACL, forced unsubscribe and recovery."""

import asyncio
from datetime import datetime, timedelta
from typing import Any
from uuid import UUID, uuid4

import cent
import jwt
import pytest
import time_machine
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker

from campus.core import clock
from campus.core.config import Settings
from campus.core.db import create_session_factory
from campus.core.outbox import OutboxMessage, add_message, process_outbox
from campus.modules.identity import Session
from campus.modules.realtime import (
    can_access,
    chat_channel,
    grant_chat_access,
    parse_channel,
    personal_channel,
    revoke_chat_access,
)
from campus.modules.realtime.centrifugo import (
    CentrifugoNotConfiguredError,
    centrifugo_client,
)
from tests.test_identity import (
    CENTRIFUGO_SECRET,
    SECRET,
    Auth,
)
from tests.test_identity import auth as auth  # noqa: PLC0414 - pytest fixture


def headers(tokens: dict[str, Any]) -> dict[str, str]:
    return {"Authorization": "Bearer " + tokens["access_token"]}


def session_id(tokens: dict[str, Any]) -> str:
    return str(jwt.decode(tokens["access_token"], SECRET, algorithms=["HS256"])["sid"])


def claims(token: str) -> dict[str, Any]:
    return jwt.decode(
        token, CENTRIFUGO_SECRET, algorithms=["HS256"], options={"verify_exp": False}
    )


def token_request(auth: Auth, tokens: dict[str, Any], path: str, **body: Any) -> Any:
    return auth.client.post(
        "/api/v1/realtime/" + path,
        json=body or None,
        headers={**headers(tokens), "Idempotency-Key": str(uuid4())},
    )


class FakeCentrifugo:
    """In-process double of the Centrifugo server API."""

    def __init__(self) -> None:
        self.unsubscribed: list[tuple[str, str]] = []
        self.disconnected: list[str] = []
        self.unsubscribe_attempts = 0
        self.disconnect_attempts = 0
        self.history_calls: list[dict[str, Any]] = []
        self.history_result = cent.HistoryResult(
            publications=[
                cent.Publication(offset=2, data={"n": 2}),
                cent.Publication(offset=3, data={"n": 3}),
            ],
            epoch="epoch",
            offset=3,
        )
        self.history_error: Exception | None = None
        self.fail_unsubscribe = 0
        self.fail_disconnect = 0

    async def __aenter__(self) -> FakeCentrifugo:
        return self

    async def __aexit__(self, *_args: object) -> None:
        return None

    async def unsubscribe(self, *, channel: str, user: str) -> None:
        self.unsubscribe_attempts += 1
        if self.fail_unsubscribe:
            self.fail_unsubscribe -= 1
            raise ConnectionError("temporary Centrifugo failure")
        self.unsubscribed.append((channel, user))

    async def disconnect(self, *, user: str) -> None:
        self.disconnect_attempts += 1
        if self.fail_disconnect:
            self.fail_disconnect -= 1
            raise ConnectionError("temporary Centrifugo failure")
        self.disconnected.append(user)

    async def history(
        self,
        *,
        channel: str,
        limit: int = 0,
        since: cent.StreamPosition | None = None,
        reverse: bool = False,
    ) -> cent.HistoryResult:
        self.history_calls.append(
            {
                "channel": channel,
                "limit": limit,
                "since": since,
                "reverse": reverse,
            }
        )
        if self.history_error is not None:
            raise self.history_error
        if limit == 0:
            return cent.HistoryResult(
                publications=[],
                epoch=self.history_result.epoch,
                offset=self.history_result.offset,
            )
        return self.history_result


@pytest.fixture
def centrifugo(monkeypatch: pytest.MonkeyPatch) -> FakeCentrifugo:
    fake = FakeCentrifugo()
    monkeypatch.setattr(
        "campus.modules.realtime.api.centrifugo_client", lambda _settings: fake
    )
    monkeypatch.setattr(
        "campus.modules.realtime.consumers.centrifugo_client", lambda _settings: fake
    )
    return fake


@pytest.fixture
async def sessions(engine: AsyncEngine) -> async_sessionmaker[AsyncSession]:
    return create_session_factory(engine)


async def drain(sessions: async_sessionmaker[AsyncSession]) -> None:
    while await process_outbox(sessions, Settings()):
        pass


async def grant(auth: Auth, chat_id: UUID, user_id: UUID) -> str:
    channel = await grant_chat_access(auth.db, chat_id, user_id)
    await auth.db.commit()
    return channel


async def revoke(auth: Auth, chat_id: UUID, user_id: UUID) -> bool:
    revoked = await revoke_chat_access(auth.db, chat_id, user_id)
    await auth.db.commit()
    return revoked


async def test_personal_connection_and_subscription_tokens(auth: Auth) -> None:
    tokens = await auth.login()
    user_id = tokens["user"]["id"]

    response = await token_request(auth, tokens, "connection-token")
    assert response.status_code == 200, response.text
    connection = response.json()
    assert connection["expires_at"]
    payload = claims(connection["token"])
    assert payload["sub"] == user_id
    assert payload["sid"] == session_id(tokens)
    assert payload["exp"] > payload["iat"]

    response = await token_request(
        auth, tokens, "subscription-token", channel=f"user#{user_id}"
    )
    assert response.status_code == 200, response.text
    subscription = response.json()
    assert subscription["channel"] == f"user#{user_id}"
    assert claims(subscription["token"])["channel"] == f"user#{user_id}"

    other = str(uuid4())
    response = await token_request(
        auth, tokens, "subscription-token", channel=f"user#{other}"
    )
    assert response.status_code == 403
    assert response.json()["code"] == "realtime_channel_forbidden"

    response = await token_request(
        auth, tokens, "subscription-token", channel="chat:not-a-uuid"
    )
    assert response.status_code == 422
    assert response.json()["code"] == "realtime_channel_invalid"


async def test_tokens_require_authentication_and_idempotency(auth: Auth) -> None:
    response = await auth.client.post(
        "/api/v1/realtime/connection-token",
        headers={"Idempotency-Key": str(uuid4())},
    )
    assert response.status_code == 401

    tokens = await auth.login()
    response = await auth.client.post(
        "/api/v1/realtime/connection-token", headers=headers(tokens)
    )
    assert response.status_code == 400
    assert response.json()["code"] == "idempotency_key_missing"


async def test_token_issue_is_idempotent(auth: Auth) -> None:
    tokens = await auth.login()
    key = str(uuid4())
    path = "/api/v1/realtime/subscription-token"
    body = {"channel": f"user#{tokens['user']['id']}"}
    first = await auth.client.post(
        path, json=body, headers={**headers(tokens), "Idempotency-Key": key}
    )
    second = await auth.client.post(
        path, json=body, headers={**headers(tokens), "Idempotency-Key": key}
    )
    assert first.status_code == second.status_code == 200
    assert first.json() == second.json()
    assert second.headers["Idempotent-Replayed"] == "true"

    reused = await auth.client.post(
        path,
        json={"channel": f"user#{uuid4()}"},
        headers={**headers(tokens), "Idempotency-Key": key},
    )
    assert reused.status_code == 422
    assert reused.json()["code"] == "idempotency_key_reused"


async def test_idempotent_replay_rechecks_channel_access(auth: Auth) -> None:
    tokens = await auth.login()
    user_id = UUID(tokens["user"]["id"])
    chat_id = uuid4()
    await grant(auth, chat_id, user_id)
    key = str(uuid4())
    path = "/api/v1/realtime/subscription-token"
    body = {"channel": f"chat:{chat_id}"}

    first = await auth.client.post(
        path, json=body, headers={**headers(tokens), "Idempotency-Key": key}
    )
    assert first.status_code == 200, first.text

    assert await revoke(auth, chat_id, user_id)
    replay = await auth.client.post(
        path, json=body, headers={**headers(tokens), "Idempotency-Key": key}
    )
    assert replay.status_code == 403
    assert replay.json()["code"] == "realtime_channel_forbidden"


@pytest.mark.parametrize("state", ["member", "former", "outsider"])
async def test_chat_channel_access_matrix(auth: Auth, state: str) -> None:
    tokens = await auth.login()
    user_id = UUID(tokens["user"]["id"])
    chat_id = uuid4()
    if state != "outsider":
        assert await grant(auth, chat_id, user_id) == f"chat:{chat_id}"
    if state == "former":
        assert await revoke(auth, chat_id, user_id)
        assert await can_access(auth.db, chat_channel(chat_id).name, user_id) is False
    assert await can_access(auth.db, chat_channel(chat_id).name, user_id) is (
        state == "member"
    )

    response = await token_request(
        auth, tokens, "subscription-token", channel=f"chat:{chat_id}"
    )
    if state == "member":
        assert response.status_code == 200, response.text
        assert claims(response.json()["token"])["channel"] == f"chat:{chat_id}"
    else:
        assert response.status_code == 403, response.text
        assert response.json()["code"] == "realtime_channel_forbidden"


async def test_revoked_session_never_gets_tokens(auth: Auth) -> None:
    tokens = await auth.login()
    key = str(uuid4())
    path = "/api/v1/realtime/connection-token"
    first = await auth.client.post(
        path, headers={**headers(tokens), "Idempotency-Key": key}
    )
    assert first.status_code == 200

    sid = UUID(session_id(tokens))
    device = await auth.db.get(Session, sid)
    assert device is not None
    device.revoked_at = clock.now()
    await auth.db.commit()
    # Remove the Redis marker: the database session row alone must deny access.
    await auth.redis.delete(f"auth:revoked:{sid}")

    # A repeat of the stored idempotent response is still refused.
    replay = await auth.client.post(
        path, headers={**headers(tokens), "Idempotency-Key": key}
    )
    assert replay.status_code == 401
    fresh = await token_request(auth, tokens, "connection-token")
    assert fresh.status_code == 401


async def test_missing_centrifugo_configuration_is_unavailable(auth: Auth) -> None:
    tokens = await auth.login()
    user_id = UUID(tokens["user"]["id"])
    chat_id = uuid4()
    channel = await grant(auth, chat_id, user_id)
    original = auth.app.state.settings
    try:
        auth.app.state.settings = original.model_copy(
            update={"centrifugo_token_hmac_secret": None}
        )
        for path, body in [
            ("connection-token", {}),
            ("subscription-token", {"channel": channel}),
        ]:
            response = await token_request(auth, tokens, path, **body)
            assert response.status_code == 503
            assert response.json()["code"] == "realtime_unavailable"

        auth.app.state.settings = original.model_copy(
            update={"centrifugo_api_url": None, "centrifugo_api_key": None}
        )
        response = await token_request(auth, tokens, "recover", channel=channel)
        assert response.status_code == 503
        assert response.json()["code"] == "realtime_unavailable"
    finally:
        auth.app.state.settings = original


async def test_token_expiry_and_refresh_recheck_membership(auth: Auth) -> None:
    tokens = await auth.login()
    user_id = UUID(tokens["user"]["id"])
    chat_id = uuid4()
    await grant(auth, chat_id, user_id)

    with time_machine.travel("2026-11-14T12:00:00Z", tick=False) as traveller:
        first = await token_request(
            auth, tokens, "subscription-token", channel=f"chat:{chat_id}"
        )
        assert first.status_code == 200
        first_payload = claims(first.json()["token"])
        assert first_payload["exp"] <= int(clock.now().timestamp()) + 300

        traveller.shift(timedelta(minutes=6))
        refreshed = await token_request(
            auth, tokens, "subscription-token", channel=f"chat:{chat_id}"
        )
        assert refreshed.status_code == 200
        refreshed_payload = claims(refreshed.json()["token"])
        assert refreshed_payload["exp"] > int(clock.now().timestamp())
        assert refreshed_payload["exp"] > first_payload["exp"]

        assert await revoke(auth, chat_id, user_id)
        denied = await token_request(
            auth, tokens, "subscription-token", channel=f"chat:{chat_id}"
        )
        assert denied.status_code == 403


async def test_revoke_queues_one_delivery_and_retries(
    auth: Auth,
    sessions: async_sessionmaker[AsyncSession],
    centrifugo: FakeCentrifugo,
) -> None:
    tokens = await auth.login()
    user_id = UUID(tokens["user"]["id"])
    chat_id = uuid4()
    channel = await grant(auth, chat_id, user_id)

    with time_machine.travel("2026-11-14T12:00:00Z", tick=False) as traveller:
        assert await revoke(auth, chat_id, user_id) is True
        assert await revoke(auth, chat_id, user_id) is False
        messages = list(
            await auth.db.scalars(
                select(OutboxMessage).where(
                    OutboxMessage.topic == "realtime.unsubscribe"
                )
            )
        )
        assert len(messages) == 1
        assert messages[0].payload == {"channel": channel, "user_id": str(user_id)}

        centrifugo.fail_unsubscribe = 1
        await drain(sessions)
        assert centrifugo.unsubscribe_attempts == 1
        assert centrifugo.unsubscribed == []
        retry = (
            await auth.db.scalars(
                select(OutboxMessage).where(
                    OutboxMessage.topic == "realtime.unsubscribe"
                )
            )
        ).one()
        await auth.db.refresh(retry)
        traveller.move_to(retry.available_at)
        await drain(sessions)

    assert centrifugo.unsubscribe_attempts == 2
    assert centrifugo.unsubscribed == [(channel, str(user_id))]


async def test_concurrent_revokes_queue_one_unsubscribe(
    auth: Auth, engine: AsyncEngine
) -> None:
    tokens = await auth.login()
    user_id = UUID(tokens["user"]["id"])
    chat_id = uuid4()
    await grant(auth, chat_id, user_id)
    sessions = create_session_factory(engine)

    async def revoke_once() -> bool:
        async with sessions() as session, session.begin():
            return await revoke_chat_access(session, chat_id, user_id)

    results = await asyncio.gather(revoke_once(), revoke_once())
    assert sorted(results) == [False, True]
    messages = list(
        await auth.db.scalars(
            select(OutboxMessage).where(OutboxMessage.topic == "realtime.unsubscribe")
        )
    )
    assert len(messages) == 1


async def test_stale_unsubscribe_does_not_remove_fresh_access(
    auth: Auth,
    sessions: async_sessionmaker[AsyncSession],
    centrifugo: FakeCentrifugo,
) -> None:
    tokens = await auth.login()
    user_id = UUID(tokens["user"]["id"])
    chat_id = uuid4()
    await grant(auth, chat_id, user_id)
    assert await revoke(auth, chat_id, user_id)

    # The user was granted access again before the queued command was delivered.
    await grant(auth, chat_id, user_id)
    await drain(sessions)

    assert centrifugo.unsubscribe_attempts == 0
    assert await can_access(auth.db, chat_channel(chat_id).name, user_id) is True


async def test_session_revocation_disconnects_user(
    auth: Auth,
    sessions: async_sessionmaker[AsyncSession],
    centrifugo: FakeCentrifugo,
) -> None:
    tokens = await auth.login()
    user_id = tokens["user"]["id"]
    revoked_session = str(uuid4())

    with time_machine.travel("2026-11-14T12:00:00Z", tick=False) as traveller:
        async with sessions() as session, session.begin():
            add_message(
                session,
                "identity.sessions_revoked",
                {"user_id": user_id, "session_ids": [revoked_session]},
            )
        centrifugo.fail_disconnect = 1
        await drain(sessions)
        assert centrifugo.disconnect_attempts == 1
        assert centrifugo.disconnected == []

        retry = (
            await auth.db.scalars(
                select(OutboxMessage).where(
                    OutboxMessage.topic == "identity.session.realtime_connections"
                )
            )
        ).one()
        await auth.db.refresh(retry)
        traveller.move_to(retry.available_at)
        await drain(sessions)

    assert centrifugo.disconnect_attempts == 2
    assert centrifugo.disconnected == [user_id]


async def test_recover_returns_publications_and_position(
    auth: Auth, centrifugo: FakeCentrifugo
) -> None:
    tokens = await auth.login()
    user_id = UUID(tokens["user"]["id"])
    chat_id = uuid4()
    await grant(auth, chat_id, user_id)
    channel = f"chat:{chat_id}"

    position = await token_request(auth, tokens, "recover", channel=channel)
    assert position.status_code == 200, position.text
    assert position.json()["offset"] == 3
    assert position.json()["epoch"] == "epoch"
    assert position.json()["publications"] == []
    assert centrifugo.history_calls[-1] == {
        "channel": channel,
        "limit": 0,
        "since": None,
        "reverse": False,
    }

    response = await token_request(
        auth,
        tokens,
        "recover",
        channel=channel,
        since={"epoch": "epoch", "offset": 1},
    )
    assert response.status_code == 200, response.text
    assert response.json()["publications"] == [
        {"offset": 2, "data": {"n": 2}},
        {"offset": 3, "data": {"n": 3}},
    ]
    assert isinstance(centrifugo.history_calls[-1]["since"], cent.StreamPosition)
    assert centrifugo.history_calls[-1]["limit"] == 100


async def test_recover_signals_lost_history_and_unavailable_server(
    auth: Auth, centrifugo: FakeCentrifugo
) -> None:
    tokens = await auth.login()
    user_id = UUID(tokens["user"]["id"])
    chat_id = uuid4()
    await grant(auth, chat_id, user_id)
    channel = f"chat:{chat_id}"

    centrifugo.history_error = cent.UnrecoverablePositionError(112, "lost")
    response = await token_request(
        auth,
        tokens,
        "recover",
        channel=channel,
        since={"epoch": "old", "offset": 1},
    )
    assert response.status_code == 409
    assert response.json()["code"] == "realtime_history_lost"

    centrifugo.history_error = cent.ApiError(100, "internal")
    response = await token_request(auth, tokens, "recover", channel=channel)
    assert response.status_code == 503
    assert response.json()["code"] == "realtime_unavailable"


async def test_recover_checks_channel_access_before_history(
    auth: Auth, centrifugo: FakeCentrifugo
) -> None:
    tokens = await auth.login()
    response = await token_request(auth, tokens, "recover", channel=f"chat:{uuid4()}")
    assert response.status_code == 403
    assert centrifugo.history_calls == []


@pytest.mark.parametrize(
    "name",
    [
        "user#not-a-uuid",
        "user#urn:uuid:" + str(uuid4()),
        "chat:" + str(uuid4()).upper(),
        "chat:" + str(uuid4()) + "x",
        "room:" + str(uuid4()),
        "x" * 256,
    ],
)
def test_invalid_channels_are_rejected(name: str) -> None:
    with pytest.raises(ValueError, match="channel"):
        parse_channel(name)


def test_channel_names_are_canonical() -> None:
    user_id = uuid4()
    chat_id = uuid4()

    assert personal_channel(user_id).name == f"user#{user_id}"
    assert chat_channel(chat_id).name == f"chat:{chat_id}"
    assert parse_channel(f"chat:{chat_id}").target_id == chat_id


async def test_centrifugo_client_requires_configuration() -> None:
    with pytest.raises(CentrifugoNotConfiguredError):
        async with centrifugo_client(Settings()):
            pass


async def test_connection_token_expires_at_follows_configuration(auth: Auth) -> None:
    tokens = await auth.login()
    with time_machine.travel("2026-11-14T12:00:00Z", tick=False):
        response = await token_request(auth, tokens, "connection-token")
        assert response.status_code == 200
        expires_at = datetime.fromisoformat(response.json()["expires_at"])
        assert expires_at == clock.now() + auth.settings.centrifugo_connection_token_ttl
