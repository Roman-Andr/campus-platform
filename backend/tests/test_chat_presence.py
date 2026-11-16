"""Ephemeral typing and open-chat state on PostgreSQL and Redis.

The server contract of #80: both indicators live in Redis with a configured
TTL and are never a chat message; every heartbeat rechecks membership, so a
removed participant cannot publish or read activity; a closed chat disappears
at once and a lost device expires; only active members see the state, and a
metadata-only outbox wakeup tells the chat channel to reload it.
"""

from datetime import datetime, timedelta
from typing import Any
from uuid import UUID, uuid4

import httpx2
import pytest
import time_machine
from redis.exceptions import RedisError
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from campus.core import clock
from campus.core.outbox import OutboxMessage, process_outbox
from campus.modules.chat import ChatMessage
from tests.test_chat import (
    account,
    bearer,
    chat_auth,
    create_chat,
    running_auth,
    send_message,
    sessions,
)
from tests.test_chat_groups import account as group_account
from tests.test_chat_groups import (
    cancel_interaction,
    group_of,
    publish_event,
    reference,
    signup,
)
from tests.test_identity import Auth
from tests.test_profile import Account

__all__ = ["chat_auth", "reference", "sessions"]

CHATS = "/api/v1/chats"


async def heartbeat(
    account_: Account,
    chat_id: str,
    *,
    typing: bool | None = None,
    open_: bool | None = None,
    key: str | None = None,
) -> httpx2.Response:
    body: dict[str, Any] = {}
    if typing is not None:
        body["typing"] = typing
    if open_ is not None:
        body["open"] = open_
    return await account_.auth.client.post(
        f"{CHATS}/{chat_id}/presence",
        json=body,
        headers={"Idempotency-Key": key or str(uuid4()), **bearer(account_)},
    )


async def close_presence(
    account_: Account, chat_id: str, *, key: str | None = None
) -> httpx2.Response:
    return await account_.auth.client.delete(
        f"{CHATS}/{chat_id}/presence",
        headers={"Idempotency-Key": key or str(uuid4()), **bearer(account_)},
    )


async def presence(account_: Account, chat_id: str) -> httpx2.Response:
    return await account_.auth.client.get(
        f"{CHATS}/{chat_id}/presence", headers=bearer(account_)
    )


async def items(account_: Account, chat_id: str) -> list[dict[str, Any]]:
    response = await presence(account_, chat_id)
    assert response.status_code == 200, response.text
    return list(response.json()["items"])


async def second_device(auth: Auth, account_: Account) -> Account:
    tokens = await auth.login(
        email=account_.tokens["user"]["email"], device_id=str(uuid4())
    )
    return Account(auth, tokens)


def user_id(account_: Account) -> str:
    return str(account_.tokens["user"]["id"])


async def test_typing_and_open_chat_are_ephemeral_member_only_state(
    chat_auth: Auth,
) -> None:
    alice = await account(chat_auth, "alice@university.example")
    bob = await account(chat_auth, "bob@university.example")
    carol = await account(chat_auth, "carol@university.example")
    chat_id = (await create_chat(alice, bob)).json()["id"]

    start = clock.now()
    started = await heartbeat(alice, chat_id, typing=True, open_=True)
    assert started.status_code == 200, started.text
    state = started.json()
    assert state["chat_id"] == chat_id
    assert state["typing"] is True
    assert state["open"] is True
    assert state["typing_expires_at"] is not None
    assert state["open_expires_at"] is not None
    assert state["heartbeat_interval_seconds"] == 15
    typing_expiry = datetime.fromisoformat(
        state["typing_expires_at"].replace("Z", "+00:00")
    )
    assert abs((typing_expiry - clock.now()).total_seconds() - 5) < 2

    # Another member sees the activity; the caller does not repeat their own.
    assert await items(bob, chat_id) == [
        {"user_id": user_id(alice), "typing": True, "open": True}
    ]
    assert await items(alice, chat_id) == []

    # An outsider sees neither the activity nor the chat.
    denied = await presence(carol, chat_id)
    assert denied.status_code == 404
    assert denied.headers["content-type"] == "application/problem+json"
    assert denied.json()["code"] == "chat_not_found"
    assert (await heartbeat(carol, chat_id, typing=True)).status_code == 404
    assert (await close_presence(carol, chat_id)).status_code == 404

    # Typing disappears after its TTL without a message in the history; the
    # open flag lives longer and then disappears too when the device is lost.
    with time_machine.travel(start + timedelta(seconds=6), tick=False):
        assert await items(bob, chat_id) == [
            {"user_id": user_id(alice), "typing": False, "open": True}
        ]
    with time_machine.travel(start + timedelta(seconds=61), tick=False):
        assert await items(bob, chat_id) == []

    # A fresh heartbeat keeps the typing indicator, while the open flag of
    # the lost device stays expired.
    with time_machine.travel(start + timedelta(seconds=62), tick=False):
        again = await heartbeat(alice, chat_id, typing=True)
        assert again.status_code == 200, again.text
    with time_machine.travel(start + timedelta(seconds=65), tick=False):
        assert await items(bob, chat_id) == [
            {"user_id": user_id(alice), "typing": True, "open": False}
        ]

    # Presence is not history: no message, no outbox text and no archive row.
    stored = list(
        await chat_auth.db.scalars(
            select(ChatMessage).where(ChatMessage.chat_id == UUID(chat_id))
        )
    )
    assert stored == []
    outbox = list(
        await chat_auth.db.scalars(
            select(OutboxMessage).where(
                OutboxMessage.payload["chat_id"].astext == chat_id,
                OutboxMessage.topic == "chat.presence",
            )
        )
    )
    assert outbox
    assert all("text" not in row.payload for row in outbox)


async def test_closing_a_chat_removes_only_that_device(chat_auth: Auth) -> None:
    alice = await account(chat_auth, "alice@university.example")
    bob = await account(chat_auth, "bob@university.example")
    chat_id = (await create_chat(alice, bob)).json()["id"]
    phone = await second_device(chat_auth, alice)

    assert (await heartbeat(alice, chat_id, typing=True, open_=True)).status_code == 200
    assert (await heartbeat(phone, chat_id, open_=True)).status_code == 200
    assert await items(bob, chat_id) == [
        {"user_id": user_id(alice), "typing": True, "open": True}
    ]

    # Closing on one device keeps the flag of the other open device.
    assert (await close_presence(alice, chat_id)).status_code == 204
    assert await items(bob, chat_id) == [
        {"user_id": user_id(alice), "typing": False, "open": True}
    ]
    assert (await close_presence(phone, chat_id)).status_code == 204
    assert await items(bob, chat_id) == []
    # Closing twice is harmless.
    assert (await close_presence(phone, chat_id)).status_code == 204

    # Stopping typing keeps the open flag of the same device.
    assert (await heartbeat(alice, chat_id, typing=True, open_=True)).status_code == 200
    stopped = await heartbeat(alice, chat_id, typing=False)
    assert stopped.status_code == 200, stopped.text
    assert stopped.json()["typing"] is False
    assert stopped.json()["open"] is True
    assert await items(bob, chat_id) == [
        {"user_id": user_id(alice), "typing": False, "open": True}
    ]

    # A heartbeat with open=false is the same close, and also stops typing.
    assert (await heartbeat(alice, chat_id, typing=True, open_=True)).status_code == 200
    closed = await heartbeat(alice, chat_id, open_=False, key=str(uuid4()))
    assert closed.status_code == 200, closed.text
    assert closed.json()["typing"] is False
    assert closed.json()["open"] is False
    assert await items(bob, chat_id) == []
    # A heartbeat without any flag is refused instead of silently doing nothing.
    empty = await heartbeat(alice, chat_id)
    assert empty.status_code == 422
    assert empty.json()["code"] == "validation_failed"


async def test_presence_heartbeat_is_idempotent(chat_auth: Auth) -> None:
    alice = await account(chat_auth, "alice@university.example")
    bob = await account(chat_auth, "bob@university.example")
    chat_id = (await create_chat(alice, bob)).json()["id"]

    key = str(uuid4())
    original = await heartbeat(alice, chat_id, typing=True, open_=True, key=key)
    assert original.status_code == 200, original.text
    replay = await heartbeat(alice, chat_id, typing=True, open_=True, key=key)
    assert replay.status_code == 200
    assert replay.headers["Idempotent-Replayed"] == "true"
    assert replay.json() == original.json()
    reused = await heartbeat(alice, chat_id, typing=False, open_=True, key=key)
    assert reused.status_code == 422
    assert reused.headers["content-type"] == "application/problem+json"
    assert reused.json()["code"] == "idempotency_key_reused"


async def test_removed_group_participant_loses_activity_immediately(
    chat_auth: Auth, reference: Any
) -> None:
    owner = await group_account(chat_auth, reference.places, "owner@university.example")
    bob = await group_account(chat_auth, reference.places, "bob@university.example")
    listing = await publish_event(owner, reference)
    interaction = (await signup(bob, listing)).json()["interaction"]
    chat_id = (await group_of(bob, listing))["id"]

    assert (await heartbeat(bob, chat_id, typing=True, open_=True)).status_code == 200
    assert await items(owner, chat_id) == [
        {"user_id": user_id(bob), "typing": True, "open": True}
    ]

    cancelled = await cancel_interaction(bob, listing, interaction)
    assert cancelled.status_code == 200, cancelled.text

    # The removed participant cannot publish or read the ephemeral state.
    assert (await heartbeat(bob, chat_id, typing=True)).status_code == 404
    assert (await close_presence(bob, chat_id)).status_code == 404
    assert (await presence(bob, chat_id)).status_code == 404
    # The active member no longer sees the removed one, without waiting for TTL.
    assert await items(owner, chat_id) == []

    # The organiser and the participant who is still in the group are visible.
    carol = await group_account(chat_auth, reference.places, "carol@university.example")
    assert (await signup(carol, listing)).status_code == 200
    assert (await heartbeat(carol, chat_id, open_=True)).status_code == 200
    assert await items(owner, chat_id) == [
        {"user_id": user_id(carol), "typing": False, "open": True}
    ]
    assert await items(carol, chat_id) == []


async def test_presence_wakeup_goes_to_the_chat_channel_only(
    chat_auth: Auth,
    sessions: async_sessionmaker[AsyncSession],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    alice = await account(chat_auth, "alice@university.example")
    bob = await account(chat_auth, "bob@university.example")
    carol = await account(chat_auth, "carol@university.example")
    chat_id = (await create_chat(alice, bob)).json()["id"]
    await chat_auth.db.execute(delete(OutboxMessage))
    await chat_auth.db.commit()
    published: list[tuple[str, dict[str, Any], UUID]] = []

    async def fake_publish(
        channel: str, data: dict[str, Any], delivery_id: UUID
    ) -> None:
        published.append((channel, data, delivery_id))

    monkeypatch.setattr("campus.modules.chat.consumers.publish_channel", fake_publish)

    assert (await heartbeat(alice, chat_id, typing=True, open_=True)).status_code == 200
    assert await process_outbox(sessions, chat_auth.settings) == 1
    assert len(published) == 1
    channel, payload, delivery_id = published[0]
    assert channel == f"chat:{chat_id}"
    assert payload["user_id"] == user_id(alice)
    assert payload["typing"] is True
    assert payload["open"] is True
    assert payload["chat_id"] == chat_id
    assert payload["occurred_at"]
    assert delivery_id

    assert (await close_presence(alice, chat_id)).status_code == 204
    assert await process_outbox(sessions, chat_auth.settings) == 1
    channel, payload, _ = published[1]
    assert channel == f"chat:{chat_id}"
    assert payload["typing"] is False
    assert payload["open"] is False

    # A refused heartbeat publishes nothing: membership is checked first.
    assert (await heartbeat(carol, chat_id, typing=True)).status_code == 404
    assert await process_outbox(sessions, chat_auth.settings) == 0


async def test_ttl_and_heartbeat_come_from_configuration(
    database_url: str, redis_url: str, centrifugo_config: Any
) -> None:
    async with running_auth(
        database_url,
        redis_url,
        centrifugo_config.token_secret,
        chat_typing_ttl=timedelta(seconds=2),
        chat_presence_ttl=timedelta(seconds=10),
        chat_presence_heartbeat=timedelta(seconds=3),
    ) as auth:
        alice = await account(auth, "alice@university.example")
        bob = await account(auth, "bob@university.example")
        chat_id = (await create_chat(alice, bob)).json()["id"]
        start = clock.now()
        started = await heartbeat(alice, chat_id, typing=True, open_=True)
        assert started.status_code == 200, started.text
        assert started.json()["heartbeat_interval_seconds"] == 3
        typing_expiry = datetime.fromisoformat(
            started.json()["typing_expires_at"].replace("Z", "+00:00")
        )
        assert abs((typing_expiry - start).total_seconds() - 2) < 1

        with time_machine.travel(start + timedelta(seconds=3), tick=False):
            assert await items(bob, chat_id) == [
                {"user_id": user_id(alice), "typing": False, "open": True}
            ]
        with time_machine.travel(start + timedelta(seconds=11), tick=False):
            assert await items(bob, chat_id) == []


async def test_presence_reports_redis_failure_as_a_problem(
    chat_auth: Auth,
) -> None:
    alice = await account(chat_auth, "alice@university.example")
    bob = await account(chat_auth, "bob@university.example")
    chat_id = (await create_chat(alice, bob)).json()["id"]

    class BrokenRedis:
        async def aclose(self) -> None:
            return None

        async def exists(self, *_args: Any, **_kwargs: Any) -> int:
            return 0

        async def _fail(self, *_args: Any, **_kwargs: Any) -> Any:
            raise RedisError("redis is down")

        hgetall = _fail
        hmget = _fail
        hset = _fail
        hdel = _fail
        expire = _fail

    original = getattr(chat_auth.app.state, "auth_redis", None)
    chat_auth.app.state.auth_redis = BrokenRedis()
    try:
        listed = await presence(alice, chat_id)
        assert listed.status_code == 503, listed.text
        assert listed.headers["content-type"] == "application/problem+json"
        assert listed.json()["code"] == "chat_presence_unavailable"
        beat = await heartbeat(alice, chat_id, typing=True)
        assert beat.status_code == 503
        assert beat.json()["code"] == "chat_presence_unavailable"
        closed = await close_presence(alice, chat_id)
        assert closed.status_code == 503
    finally:
        if original is None:
            del chat_auth.app.state.auth_redis
        else:
            chat_auth.app.state.auth_redis = original


async def test_presence_is_not_a_message_and_send_stays_unchanged(
    chat_auth: Auth,
) -> None:
    alice = await account(chat_auth, "alice@university.example")
    bob = await account(chat_auth, "bob@university.example")
    chat_id = (await create_chat(alice, bob)).json()["id"]
    before = await presence(bob, chat_id)
    assert before.status_code == 200
    assert before.json()["items"] == []

    # A heartbeat while the other member sends does not change the sequence
    # or the message count: the indicators never enter the history.
    assert (await heartbeat(alice, chat_id, typing=True)).status_code == 200
    stored = await send_message(alice, chat_id, "after typing")
    assert stored.status_code == 201, stored.text
    assert stored.json()["sequence"] == 1
    messages = await chat_auth.db.scalars(
        select(ChatMessage).where(ChatMessage.chat_id == UUID(chat_id))
    )
    assert [message.sequence for message in messages] == [1]
