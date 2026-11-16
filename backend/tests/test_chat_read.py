"""Read receipts and unread counters of personal and group chats on PostgreSQL.

The server contract of #80: only a member moves their own cursor, the cursor
grows to the maximum under parallel and delayed marks, the unread count is
derived and cannot go negative, and the committed position reaches every
device of the member through the outbox after the commit. A missed
publication is recovered by reading the chat, which is the authority.
"""

import asyncio
from typing import Any
from uuid import UUID, uuid4

import httpx2
import pytest
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from campus.core.outbox import OutboxMessage, process_outbox
from campus.modules.chat import ChatReadState, chat_read_states
from tests.test_chat import (
    account,
    bearer,
    chat_auth,
    create_chat,
    history,
    messages_of,
    send_message,
    sessions,
)
from tests.test_identity import Auth
from tests.test_profile import Account

__all__ = ["chat_auth", "sessions"]

CHATS = "/api/v1/chats"


async def mark_read(
    account_: Account,
    chat_id: str,
    through_id: str | UUID,
    *,
    key: str | None = None,
) -> httpx2.Response:
    return await account_.auth.client.post(
        f"{CHATS}/{chat_id}/read",
        json={"through_id": str(through_id)},
        headers={"Idempotency-Key": key or str(uuid4()), **bearer(account_)},
    )


async def chat_state(account_: Account, chat_id: str) -> dict[str, Any]:
    response = await account_.auth.client.get(
        f"{CHATS}/{chat_id}", headers=bearer(account_)
    )
    assert response.status_code == 200, response.text
    return dict(response.json()["read_state"])


async def listed_state(account_: Account, chat_id: str) -> dict[str, Any]:
    response = await account_.auth.client.get(CHATS, headers=bearer(account_))
    assert response.status_code == 200, response.text
    matches = [row for row in response.json()["items"] if row["id"] == chat_id]
    assert len(matches) == 1, response.text
    return dict(matches[0]["read_state"])


async def second_device(auth: Auth, account_: Account) -> Account:
    """Another device session of the same user."""
    tokens = await auth.login(
        email=account_.tokens["user"]["email"], device_id=str(uuid4())
    )
    return Account(auth, tokens)


async def test_read_receipt_is_member_scoped_and_counts_unread(
    chat_auth: Auth,
) -> None:
    alice = await account(chat_auth, "alice@university.example")
    bob = await account(chat_auth, "bob@university.example")
    carol = await account(chat_auth, "carol@university.example")
    mallory = await account(chat_auth, "mallory@university.example")
    chat_id = (await create_chat(alice, bob)).json()["id"]
    bob_carol_chat = (await create_chat(bob, carol)).json()["id"]

    sent = []
    for number in range(3):
        response = await send_message(alice, chat_id, f"message {number}")
        assert response.status_code == 201, response.text
        sent.append(response.json()["id"])

    # No cursor row yet: the whole history from another member is unread,
    # while the author sees none of their own messages as unread.
    assert await chat_state(bob, chat_id) == {
        "last_read_sequence": 0,
        "unread_count": 3,
    }
    assert await chat_state(alice, chat_id) == {
        "last_read_sequence": 0,
        "unread_count": 0,
    }
    assert await listed_state(bob, chat_id) == {
        "last_read_sequence": 0,
        "unread_count": 3,
    }

    marked = await mark_read(bob, chat_id, sent[1])
    assert marked.status_code == 200, marked.text
    assert marked.json() == {
        "chat_id": chat_id,
        "last_read_sequence": 2,
        "unread_count": 1,
    }
    assert await chat_state(bob, chat_id) == {
        "last_read_sequence": 2,
        "unread_count": 1,
    }
    # The cursor belongs to one member only.
    assert await chat_state(alice, chat_id) == {
        "last_read_sequence": 0,
        "unread_count": 0,
    }

    # Only a member reads or moves a cursor.
    outsider = await mark_read(mallory, chat_id, sent[0])
    assert outsider.status_code == 404
    assert outsider.headers["content-type"] == "application/problem+json"
    assert outsider.json()["code"] == "chat_not_found"
    assert (
        await mallory.auth.client.get(f"{CHATS}/{chat_id}", headers=bearer(mallory))
    ).status_code == 404
    # A member of two chats cannot move one cursor with the other's message.
    elsewhere = await send_message(carol, bob_carol_chat, "elsewhere")
    assert elsewhere.status_code == 201, elsewhere.text
    crossed = await mark_read(bob, chat_id, elsewhere.json()["id"])
    assert crossed.status_code == 404
    assert crossed.json()["code"] == "not_found"
    crossed_back = await mark_read(bob, bob_carol_chat, sent[0])
    assert crossed_back.status_code == 404
    assert crossed_back.json()["code"] == "not_found"
    nonexistent = await mark_read(bob, chat_id, uuid4())
    assert nonexistent.status_code == 404
    assert nonexistent.json()["code"] == "not_found"

    # A member who left loses the right to mark the chat immediately.
    assert (
        await bob.auth.client.delete(
            f"{CHATS}/{chat_id}/membership",
            headers={"Idempotency-Key": str(uuid4()), **bearer(bob)},
        )
    ).status_code == 204
    left = await mark_read(bob, chat_id, sent[2])
    assert left.status_code == 404
    assert left.json()["code"] == "chat_not_found"

    # Nothing above stored a message or moved another cursor.
    assert len(await messages_of(chat_auth.db, UUID(chat_id))) == 3
    assert len(await messages_of(chat_auth.db, UUID(bob_carol_chat))) == 1


async def test_delayed_and_parallel_marks_converge_on_the_maximum(
    chat_auth: Auth,
) -> None:
    alice = await account(chat_auth, "alice@university.example")
    bob = await account(chat_auth, "bob@university.example")
    chat_id = (await create_chat(alice, bob)).json()["id"]
    messages = []
    for number in range(5):
        response = await send_message(alice, chat_id, f"message {number}")
        assert response.status_code == 201, response.text
        messages.append(response.json()["id"])

    first = await second_device(chat_auth, bob)
    second = await second_device(chat_auth, bob)
    advanced = await mark_read(second, chat_id, messages[3])
    assert advanced.status_code == 200, advanced.text
    assert advanced.json()["last_read_sequence"] == 4
    assert advanced.json()["unread_count"] == 1

    # The delayed mark of the second device does not move the cursor back.
    delayed = await mark_read(first, chat_id, messages[1])
    assert delayed.status_code == 200, delayed.text
    assert delayed.json() == {
        "chat_id": chat_id,
        "last_read_sequence": 4,
        "unread_count": 1,
    }

    # Parallel marks take the maximum; no answer is negative.
    responses = await asyncio.gather(
        mark_read(first, chat_id, messages[4]),
        mark_read(second, chat_id, messages[2]),
        mark_read(first, chat_id, messages[0]),
    )
    assert [response.status_code for response in responses] == [200, 200, 200]
    cursors = [response.json()["last_read_sequence"] for response in responses]
    assert max(cursors) == 5
    assert all(cursor >= 4 for cursor in cursors)
    assert all(response.json()["unread_count"] >= 0 for response in responses)
    final = {"last_read_sequence": 5, "unread_count": 0}
    assert await chat_state(bob, chat_id) == final
    # Both devices converged on the same server state.
    assert await chat_state(first, chat_id) == final
    assert await chat_state(second, chat_id) == final

    stored = await chat_auth.db.scalar(
        select(ChatReadState).where(
            ChatReadState.chat_id == UUID(chat_id),
            ChatReadState.user_id == UUID(bob.tokens["user"]["id"]),
        )
    )
    assert stored is not None
    assert stored.last_read_sequence == 5


async def test_read_receipt_idempotency(chat_auth: Auth) -> None:
    alice = await account(chat_auth, "alice@university.example")
    bob = await account(chat_auth, "bob@university.example")
    chat_id = (await create_chat(alice, bob)).json()["id"]
    first = await send_message(alice, chat_id, "one")
    second = await send_message(alice, chat_id, "two")

    key = str(uuid4())
    original = await mark_read(bob, chat_id, first.json()["id"], key=key)
    assert original.status_code == 200, original.text
    replay = await mark_read(bob, chat_id, first.json()["id"], key=key)
    assert replay.status_code == 200
    assert replay.headers["Idempotent-Replayed"] == "true"
    assert replay.json() == original.json()

    # The same key with another body is a conflict, not a second effect.
    reused = await mark_read(bob, chat_id, second.json()["id"], key=key)
    assert reused.status_code == 422
    assert reused.headers["content-type"] == "application/problem+json"
    assert reused.json()["code"] == "idempotency_key_reused"
    assert (await chat_state(bob, chat_id))["last_read_sequence"] == 1


async def test_read_event_reaches_all_devices_after_commit(
    chat_auth: Auth,
    sessions: async_sessionmaker[AsyncSession],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    alice = await account(chat_auth, "alice@university.example")
    bob = await account(chat_auth, "bob@university.example")
    chat_id = (await create_chat(alice, bob)).json()["id"]
    message = await send_message(alice, chat_id, "read me")
    assert message.status_code == 201, message.text

    # Sign-in and message jobs are not the subject: only the read event stays.
    await chat_auth.db.execute(delete(OutboxMessage))
    await chat_auth.db.commit()
    published: list[tuple[UUID, dict[str, Any], UUID]] = []

    async def fake_publish_personal(
        user_id: UUID, data: dict[str, Any], delivery_id: UUID
    ) -> None:
        published.append((user_id, data, delivery_id))

    monkeypatch.setattr(
        "campus.modules.chat.consumers.publish_personal", fake_publish_personal
    )
    marked = await mark_read(bob, chat_id, message.json()["id"])
    assert marked.status_code == 200, marked.text
    assert await process_outbox(sessions, chat_auth.settings) == 1

    assert len(published) == 1
    user_id, payload, delivery_id = published[0]
    assert user_id == UUID(bob.tokens["user"]["id"])
    assert payload["chat_id"] == chat_id
    assert payload["last_read_sequence"] == 1
    assert payload["unread_count"] == 0
    assert payload["user_id"] == str(user_id)
    assert "text" not in payload
    assert delivery_id

    # The publication is a wakeup: the state itself is recovered from the API
    # by every device, which sees the same after a cold start.
    expected = {"last_read_sequence": 1, "unread_count": 0}
    assert await chat_state(bob, chat_id) == expected
    device = await second_device(chat_auth, bob)
    assert await chat_state(device, chat_id) == expected


async def test_unread_ignores_deleted_messages_and_survives_reconnect(
    chat_auth: Auth,
) -> None:
    alice = await account(chat_auth, "alice@university.example")
    bob = await account(chat_auth, "bob@university.example")
    chat_id = (await create_chat(alice, bob)).json()["id"]
    first = await send_message(alice, chat_id, "one")
    await send_message(alice, chat_id, "two")

    assert await chat_state(bob, chat_id) == {
        "last_read_sequence": 0,
        "unread_count": 2,
    }
    # A deleted message is not unread; the visible one still is.
    deleted = await alice.auth.client.delete(
        f"{CHATS}/{chat_id}/messages/{first.json()['id']}",
        headers={"Idempotency-Key": str(uuid4()), **bearer(alice)},
    )
    assert deleted.status_code == 204
    assert await chat_state(bob, chat_id) == {
        "last_read_sequence": 0,
        "unread_count": 1,
    }
    # A cold start of another device reads the same derived count.
    device = await second_device(chat_auth, bob)
    assert await listed_state(device, chat_id) == {
        "last_read_sequence": 0,
        "unread_count": 1,
    }
    history_page = await history(bob, chat_id)
    assert history_page.status_code == 200
    assert [item["text"] for item in history_page.json()["items"]] == ["two"]


async def test_read_state_of_an_empty_page_is_empty(chat_auth: Auth) -> None:
    assert await chat_read_states(chat_auth.db, chat_ids=[], user_id=uuid4()) == {}
