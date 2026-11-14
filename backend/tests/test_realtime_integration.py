"""Realtime API and workers against a real Centrifugo server.

The unit tests replace the server API with a double and check the protocol
shape. These tests prove the other half: Centrifugo accepts the tokens we
issue, enforces the channel in a subscription token, and applies the forced
unsubscribe and disconnect commands the outbox delivers.
"""

import asyncio
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Any
from uuid import UUID, uuid4

import cent
import centrifuge  # type: ignore[import-untyped]
import pytest
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker

from campus.core.db import create_session_factory
from campus.core.outbox import add_message, process_outbox
from campus.modules.identity.session_events import SESSIONS_REVOKED
from tests.services import CentrifugoConfig, CentrifugoService
from tests.test_identity import Auth
from tests.test_identity import auth as auth  # noqa: PLC0414 - pytest fixture
from tests.test_realtime import grant, revoke, session_id, token_request


@pytest.fixture
def centrifugo_config(centrifugo_service: CentrifugoService) -> CentrifugoConfig:
    """Point the API under test at the real Centrifugo of this test session."""
    return CentrifugoConfig(
        token_secret=centrifugo_service.token_secret,
        api_url=centrifugo_service.api_url,
        api_key=centrifugo_service.api_key,
    )


@pytest.fixture
async def sessions(engine: AsyncEngine) -> async_sessionmaker[AsyncSession]:
    return create_session_factory(engine)


class ClientEvents(centrifuge.ClientEventHandler):  # type: ignore[misc]
    """Futures and a queue for the client events a test waits for."""

    def __init__(self) -> None:
        self.connected: asyncio.Future[Any] = asyncio.Future()
        self.disconnected: asyncio.Future[Any] = asyncio.Future()
        self.errors: list[Any] = []

    async def on_connected(self, context: Any) -> None:
        if not self.connected.done():
            self.connected.set_result(context)

    async def on_disconnected(self, context: Any) -> None:
        if not self.disconnected.done():
            self.disconnected.set_result(context)

    async def on_error(self, context: Any) -> None:
        self.errors.append(context)


class SubscriptionEvents(centrifuge.SubscriptionEventHandler):  # type: ignore[misc]
    """Futures and a queue for the subscription events a test waits for."""

    def __init__(self) -> None:
        self.subscribed: asyncio.Future[Any] = asyncio.Future()
        self.unsubscribed: asyncio.Future[Any] = asyncio.Future()
        self.publications: asyncio.Queue[Any] = asyncio.Queue()
        self.errors: list[Any] = []

    async def on_subscribed(self, context: Any) -> None:
        if not self.subscribed.done():
            self.subscribed.set_result(context)

    async def on_unsubscribed(self, context: Any) -> None:
        if not self.unsubscribed.done():
            self.unsubscribed.set_result(context)

    async def on_publication(self, context: Any) -> None:
        self.publications.put_nowait(context.pub.data)

    async def on_error(self, context: Any) -> None:
        self.errors.append(context)


async def issue(auth: Auth, tokens: dict[str, Any], path: str) -> dict[str, Any]:
    response = await token_request(auth, tokens, path)
    assert response.status_code == 200, response.text
    return dict(response.json())


@asynccontextmanager
async def connection(
    auth: Auth, tokens: dict[str, Any], service: CentrifugoService
) -> AsyncIterator[tuple[centrifuge.Client, ClientEvents]]:
    """A connected realtime client of the logged-in device."""
    token = (await issue(auth, tokens, "connection-token"))["token"]
    events = ClientEvents()
    client = centrifuge.Client(service.ws_url, events=events, token=token, timeout=5)
    await client.connect()
    await asyncio.wait_for(events.connected, 10)
    try:
        yield client, events
    finally:
        await client.disconnect()


async def subscribe(
    auth: Auth,
    tokens: dict[str, Any],
    client: centrifuge.Client,
    channel: str,
) -> tuple[centrifuge.Subscription, SubscriptionEvents]:
    response = await token_request(auth, tokens, "subscription-token", channel=channel)
    assert response.status_code == 200, response.text
    events = SubscriptionEvents()
    subscription = client.new_subscription(
        channel, events=events, token=response.json()["token"]
    )
    await subscription.subscribe()
    await asyncio.wait_for(events.subscribed, 10)
    return subscription, events


def api(service: CentrifugoService) -> cent.AsyncClient:
    return cent.AsyncClient(service.api_url, api_key=service.api_key)


async def drain(sessions: async_sessionmaker[AsyncSession], auth: Auth) -> None:
    while await process_outbox(sessions, auth.settings):
        pass


async def test_anonymous_client_cannot_connect(
    centrifugo_service: CentrifugoService,
) -> None:
    events = ClientEvents()
    client = centrifuge.Client(centrifugo_service.ws_url, events=events, timeout=2)
    await client.connect()
    try:
        with pytest.raises(TimeoutError):
            await asyncio.wait_for(events.connected, 3)
        assert client.state is not centrifuge.ClientState.CONNECTED
    finally:
        await client.disconnect()


async def test_personal_channel_roundtrip(
    auth: Auth, centrifugo_service: CentrifugoService
) -> None:
    tokens = await auth.login()
    user_id = tokens["user"]["id"]
    channel = f"user#{user_id}"

    async with connection(auth, tokens, centrifugo_service) as (client, _):
        _, events = await subscribe(auth, tokens, client, channel)
        async with api(centrifugo_service) as server:
            await server.publish(channel=channel, data={"hello": "campus"})
        assert await asyncio.wait_for(events.publications.get(), 10) == {
            "hello": "campus"
        }


async def test_chat_channel_roundtrip_for_a_member(
    auth: Auth, centrifugo_service: CentrifugoService
) -> None:
    tokens = await auth.login()
    user_id = UUID(tokens["user"]["id"])
    chat_id = uuid4()
    channel = await grant(auth, chat_id, user_id)

    async with connection(auth, tokens, centrifugo_service) as (client, _):
        _, events = await subscribe(auth, tokens, client, channel)
        async with api(centrifugo_service) as server:
            await server.publish(channel=channel, data={"message": 1})
        assert await asyncio.wait_for(events.publications.get(), 10) == {"message": 1}


async def test_subscription_token_does_not_open_another_channel(
    auth: Auth, centrifugo_service: CentrifugoService
) -> None:
    tokens = await auth.login()
    user_id = UUID(tokens["user"]["id"])
    first = uuid4()
    second = uuid4()
    allowed = await grant(auth, first, user_id)
    await grant(auth, second, user_id)

    async with connection(auth, tokens, centrifugo_service) as (client, events):
        await subscribe(auth, tokens, client, allowed)
        response = await token_request(
            auth, tokens, "subscription-token", channel=allowed
        )
        assert response.status_code == 200, response.text
        stolen = client.new_subscription(
            f"chat:{second}", token=response.json()["token"]
        )
        await stolen.subscribe()
        # Centrifugo rejects the mismatched token by disconnecting the client.
        disconnected = await asyncio.wait_for(events.disconnected, 10)
        assert disconnected.code == 3500


async def test_revoked_member_is_unsubscribed_by_the_outbox(
    auth: Auth,
    sessions: async_sessionmaker[AsyncSession],
    centrifugo_service: CentrifugoService,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    tokens = await auth.login()
    user_id = UUID(tokens["user"]["id"])
    chat_id = uuid4()
    channel = await grant(auth, chat_id, user_id)
    monkeypatch.setattr(
        "campus.modules.realtime.consumers.get_settings", lambda: auth.settings
    )

    async with connection(auth, tokens, centrifugo_service) as (client, _):
        _, events = await subscribe(auth, tokens, client, channel)
        assert await revoke(auth, chat_id, user_id)
        await drain(sessions, auth)
        unsubscribed = await asyncio.wait_for(events.unsubscribed, 10)
        assert unsubscribed.code == 2000
        async with api(centrifugo_service) as server:
            await server.publish(channel=channel, data={"message": 2})
        with pytest.raises(TimeoutError):
            await asyncio.wait_for(events.publications.get(), 1)


async def test_revoked_session_is_disconnected_by_the_outbox(
    auth: Auth,
    sessions: async_sessionmaker[AsyncSession],
    centrifugo_service: CentrifugoService,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    tokens = await auth.login()
    user_id = tokens["user"]["id"]
    monkeypatch.setattr(
        "campus.modules.realtime.consumers.get_settings", lambda: auth.settings
    )

    async with connection(auth, tokens, centrifugo_service) as (_, events):
        async with sessions() as session, session.begin():
            add_message(
                session,
                SESSIONS_REVOKED,
                {"user_id": user_id, "session_ids": [session_id(tokens)]},
            )
        await drain(sessions, auth)
        disconnected = await asyncio.wait_for(events.disconnected, 10)
        assert disconnected.code == 3503


async def test_recover_reads_real_history(
    auth: Auth, centrifugo_service: CentrifugoService
) -> None:
    tokens = await auth.login()
    user_id = UUID(tokens["user"]["id"])
    chat_id = uuid4()
    channel = await grant(auth, chat_id, user_id)

    async with api(centrifugo_service) as server:
        first = await server.publish(channel=channel, data={"n": 1})
        await server.publish(channel=channel, data={"n": 2})
        last = await server.publish(channel=channel, data={"n": 3})

    current = await token_request(auth, tokens, "recover", channel=channel)
    assert current.status_code == 200, current.text
    assert current.json()["offset"] == last.offset
    assert current.json()["epoch"] == last.epoch
    assert current.json()["publications"] == []

    response = await token_request(
        auth,
        tokens,
        "recover",
        channel=channel,
        since={"epoch": first.epoch, "offset": first.offset},
    )
    assert response.status_code == 200, response.text
    assert response.json()["publications"] == [
        {"offset": 2, "data": {"n": 2}},
        {"offset": 3, "data": {"n": 3}},
    ]
