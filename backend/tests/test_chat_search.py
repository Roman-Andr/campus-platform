"""Search across a user's own dialogs, including archived message partitions."""

from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID, uuid4

import httpx2
import time_machine
from sqlalchemy import delete, text, update

from campus.core import clock
from campus.modules.chat.models import ChatMember, ChatMessage
from campus.modules.identity import Role, RoleAssignment
from tests.test_chat import (
    ROOT,
    account,
    bearer,
    chat_auth,
    create_chat,
    send_message,
)
from tests.test_profile import Account

__all__ = ["chat_auth"]

SEARCH = f"{ROOT}/search"


async def search(account: Account, q: str, **params: Any) -> httpx2.Response:
    return await account.auth.client.get(
        SEARCH,
        params={"q": q, **params},
        headers=bearer(account),
    )


async def results(account: Account, q: str, **params: Any) -> dict[str, Any]:
    response = await search(account, q, **params)
    assert response.status_code == 200, response.text
    body: dict[str, Any] = response.json()
    return body


async def test_search_finds_ru_en_only_in_own_dialogs(chat_auth: Any) -> None:
    alice = await account(chat_auth, "alice@university.example")
    bob = await account(chat_auth, "bob@university.example")
    mallory = await account(chat_auth, "mallory@university.example")
    chat = (await create_chat(alice, bob)).json()

    russian = await send_message(alice, chat["id"], "Отдам велосипед в общежитии")
    english = await send_message(bob, chat["id"], "Giving away a bike")
    assert russian.status_code == english.status_code == 201

    ru_items = (await results(alice, "велосипеды"))["items"]
    assert [item["message"]["id"] for item in ru_items] == [russian.json()["id"]]
    assert ru_items[0]["chat"]["id"] == chat["id"]
    assert {person["id"] for person in ru_items[0]["chat"]["participants"]} == {
        alice.tokens["user"]["id"],
        bob.tokens["user"]["id"],
    }
    assert "велосипед" in ru_items[0]["snippet"]

    en_items = (await results(bob, "bikes"))["items"]
    assert [item["message"]["id"] for item in en_items] == [english.json()["id"]]

    # A query in either language may combine both vectors.
    mixed = await send_message(alice, chat["id"], "Велосипед bike")
    assert mixed.status_code == 201
    mixed_items = (await results(alice, "велосипеды bikes"))["items"]
    assert mixed.json()["id"] in [item["message"]["id"] for item in mixed_items]

    long_text = "prefix " * 80 + "needle"
    long_sent = await send_message(alice, chat["id"], long_text)
    assert long_sent.status_code == 201
    long_item = (await results(alice, "needle"))["items"][0]
    assert "needle" in long_item["snippet"]
    assert len(long_item["snippet"]) <= 242

    # Outsiders and even administrators never see somebody else's messages.
    assert (await results(mallory, "велосипед"))["items"] == []
    mallory_id = UUID(mallory.tokens["user"]["id"])
    chat_auth.db.add(RoleAssignment(user_id=mallory_id, role=Role.ADMINISTRATOR))
    await chat_auth.db.commit()
    assert (await results(mallory, "велосипед"))["items"] == []


async def test_access_is_rechecked_for_opening_the_hit(chat_auth: Any) -> None:
    alice = await account(chat_auth, "alice@university.example")
    bob = await account(chat_auth, "bob@university.example")
    chat = (await create_chat(alice, bob)).json()
    sent = await send_message(alice, chat["id"], "a secret bicycle")
    assert sent.status_code == 201

    assert len((await results(bob, "bicycle"))["items"]) == 1
    await chat_auth.db.execute(
        delete(ChatMember).where(
            ChatMember.chat_id == UUID(chat["id"]),
            ChatMember.user_id == UUID(bob.tokens["user"]["id"]),
        )
    )
    await chat_auth.db.commit()

    assert (await results(bob, "bicycle"))["items"] == []
    # Opening the stored hit uses the same membership check as history.
    opened = await bob.auth.client.get(
        f"{ROOT}/{chat['id']}/messages", headers=bearer(bob)
    )
    assert opened.status_code == 404
    assert opened.json()["code"] == "chat_not_found"


async def test_archived_edit_and_delete(chat_auth: Any) -> None:
    alice = await account(chat_auth, "alice@university.example")
    bob = await account(chat_auth, "bob@university.example")
    chat = (await create_chat(alice, bob)).json()
    sent = await send_message(alice, chat["id"], "Старый велосипед")
    assert sent.status_code == 201
    message_id = UUID(sent.json()["id"])

    assert [
        item["message"]["id"] for item in (await results(alice, "велосипед"))["items"]
    ] == [sent.json()["id"]]
    # Editing the current text updates the generated vector immediately.
    await chat_auth.db.execute(
        update(ChatMessage)
        .where(ChatMessage.id == message_id)
        .values(text="Новый учебник")
    )
    await chat_auth.db.commit()
    assert (await results(alice, "велосипед"))["items"] == []
    assert [
        item["message"]["text"] for item in (await results(alice, "учебник"))["items"]
    ] == ["Новый учебник"]

    # A message deleted by #81 is hidden by the partial-index predicate.
    await chat_auth.db.execute(
        update(ChatMessage)
        .where(ChatMessage.id == message_id)
        .values(deleted_at=clock.now())
    )
    await chat_auth.db.commit()
    assert (await results(alice, "учебник"))["items"] == []
    history = await alice.auth.client.get(
        f"{ROOT}/{chat['id']}/messages", headers=bearer(alice)
    )
    assert history.json()["items"] == []
    preview = await alice.auth.client.get(f"{ROOT}/{chat['id']}", headers=bearer(alice))
    assert preview.json()["last_message"] is None

    # An old, separately created partition is searched by the same parent index.
    await chat_auth.db.execute(
        text(
            "CREATE TABLE chat_message_2024_01 PARTITION OF chat_message "
            "FOR VALUES FROM ('2024-01-01') TO ('2024-02-01')"
        )
    )
    archived = ChatMessage(
        chat_id=UUID(chat["id"]),
        sender_id=UUID(alice.tokens["user"]["id"]),
        client_id=uuid4(),
        sequence=99,
        text="Archived bicycle from last year",
        created_at=datetime(2024, 6, 1, 12, tzinfo=UTC),
    )
    chat_auth.db.add(archived)
    await chat_auth.db.commit()
    archived_items = (await results(alice, "bicycle"))["items"]
    assert [item["message"]["text"] for item in archived_items] == [
        "Archived bicycle from last year"
    ]


async def test_equal_relevance_pagination_and_validation(chat_auth: Any) -> None:
    alice = await account(chat_auth, "alice@university.example")
    bob = await account(chat_auth, "bob@university.example")
    chat = (await create_chat(alice, bob)).json()
    expected: list[str] = []
    with time_machine.travel(clock.now(), tick=False) as traveller:
        for _ in range(5):
            sent = await send_message(alice, chat["id"], "ranked bike")
            assert sent.status_code == 201
            expected.insert(0, sent.json()["id"])
            traveller.shift(timedelta(seconds=1))

    first = await results(alice, "bike", size=2)
    assert [item["message"]["id"] for item in first["items"]] == expected[:2]
    cursor = first["next_page"]
    assert cursor is not None

    # A cursor is bound to the normalized query and the caller.
    changed = await search(alice, "desk", cursor=cursor, size=2)
    assert changed.status_code == 400
    assert changed.json()["code"] == "invalid_cursor"

    seen = [item["message"]["id"] for item in first["items"]]
    while cursor is not None:
        page = await results(alice, "bike", cursor=cursor, size=2)
        seen += [item["message"]["id"] for item in page["items"]]
        cursor = page["next_page"]
    assert seen == expected
    assert len(seen) == len(set(seen))

    assert (await results(alice, ""))["items"] == []
    assert (await results(alice, "   "))["items"] == []
    assert (await results(alice, "!!!"))["items"] == []
    too_long = await search(alice, "x" * 501)
    assert too_long.status_code == 422
    assert too_long.json()["code"] == "chat_search_invalid"
    too_big = await search(alice, "bike", size=101)
    assert too_big.status_code == 422


async def test_partition_gin_index_is_used(chat_auth: Any) -> None:
    alice = await account(chat_auth, "alice@university.example")
    bob = await account(chat_auth, "bob@university.example")
    chat = (await create_chat(alice, bob)).json()
    assert (await send_message(alice, chat["id"], "indexed bicycle")).status_code == 201

    await chat_auth.db.execute(text("SET LOCAL enable_seqscan = off"))
    plan = "\n".join(
        await chat_auth.db.scalars(
            text(
                "EXPLAIN SELECT id FROM chat_message "
                "WHERE deleted_at IS NULL AND search_vector @@ "
                "(plainto_tsquery('russian', 'bicycle') || "
                "plainto_tsquery('english', 'bicycle'))"
            )
        )
    )
    assert "Bitmap Index Scan" in plan
    assert "search_vector" in plan or "ix_chat_message_search" in plan
    indexes = await chat_auth.db.scalars(
        text(
            "SELECT indexname FROM pg_indexes "
            "WHERE tablename LIKE 'chat_message_%' "
            "AND indexdef LIKE '%USING gin%'"
        )
    )
    # The parent index is created on every existing and later partition.
    assert len(list(indexes)) >= 27
