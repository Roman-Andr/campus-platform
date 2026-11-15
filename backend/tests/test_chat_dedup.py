"""Durable client UUID deduplication covers the whole message body (#356)."""

from datetime import timedelta
from typing import Any
from uuid import UUID, uuid4

import httpx2
import pytest
import time_machine
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker

from campus.core import clock
from campus.core.db import create_session_factory
from campus.core.outbox import OutboxMessage
from campus.modules.chat import (
    MESSAGE_TOPIC,
    Chat,
    ChatMessage,
    ChatMessageDedup,
    ChatMessageVersion,
)
from campus.modules.chat.retention import archive_messages
from campus.modules.chat.service import (
    body_fingerprint,
    content_hash,
    post_message,
)
from campus.modules.files import File
from tests.test_chat import ROOT, account, bearer, chat_auth, create_chat
from tests.test_identity import Auth
from tests.test_profile import Account

__all__ = ["chat_auth"]


@pytest.fixture
async def sessions(engine: AsyncEngine) -> async_sessionmaker[AsyncSession]:
    return create_session_factory(engine)


@pytest.fixture
async def couple(chat_auth: Auth) -> tuple[Account, Account, str]:
    alice = await account(chat_auth, "alice@university.example")
    bob = await account(chat_auth, "bob@university.example")
    chat = await create_chat(alice, bob)
    assert chat.status_code == 201, chat.text
    return alice, bob, chat.json()["id"]


async def send(  # noqa: PLR0913 - message fields
    account: Account,
    chat_id: str,
    text: str,
    *,
    client_id: UUID | None = None,
    key: str | None = None,
    reply_to_id: UUID | None = None,
    photo_ids: list[UUID] | None = None,
) -> httpx2.Response:
    return await account.auth.client.post(
        f"{ROOT}/{chat_id}/messages",
        json={
            "client_id": str(client_id or uuid4()),
            "text": text,
            "reply_to_id": str(reply_to_id) if reply_to_id else None,
            "photo_ids": [str(photo_id) for photo_id in photo_ids or []],
        },
        headers={"Idempotency-Key": key or str(uuid4()), **bearer(account)},
    )


async def edit(
    account: Account, chat_id: str, message_id: UUID, text: str
) -> httpx2.Response:
    return await account.auth.client.patch(
        f"{ROOT}/{chat_id}/messages/{message_id}",
        json={"text": text},
        headers={"Idempotency-Key": str(uuid4()), **bearer(account)},
    )


async def remove(account: Account, chat_id: str, message_id: UUID) -> httpx2.Response:
    return await account.auth.client.delete(
        f"{ROOT}/{chat_id}/messages/{message_id}",
        headers={"Idempotency-Key": str(uuid4()), **bearer(account)},
    )


async def add_photo(auth: Auth, chat_id: UUID, owner_id: UUID) -> File:
    now = clock.now()
    file = File(
        owner_id=owner_id,
        chat_id=chat_id,
        purpose="chat_photo",
        key=f"photos/{uuid4()}",
        status="ready",
        size=10,
        upload_expires_at=now + timedelta(hours=1),
        expires_at=now + timedelta(days=1),
    )
    auth.db.add(file)
    await auth.db.commit()
    return file


async def relogin(auth: Auth, email: str) -> Account:
    return Account(auth, await auth.login(email=email))


async def set_fingerprint(
    db: AsyncSession,
    chat_id: UUID,
    client_id: UUID,
    fingerprint: str | None,
) -> ChatMessageDedup:
    dedup = await db.scalar(
        select(ChatMessageDedup).where(
            ChatMessageDedup.chat_id == chat_id,
            ChatMessageDedup.client_id == client_id,
        )
    )
    assert dedup is not None
    dedup.content_fingerprint = fingerprint
    await db.commit()
    return dedup


async def message_count(db: AsyncSession, chat_id: UUID) -> int:
    count = await db.scalar(
        select(func.count())
        .select_from(ChatMessage)
        .where(ChatMessage.chat_id == chat_id)
    )
    assert count is not None
    return count


async def outbox_count(db: AsyncSession) -> int:
    count = await db.scalar(
        select(func.count())
        .select_from(OutboxMessage)
        .where(OutboxMessage.topic == MESSAGE_TOPIC)
    )
    assert count is not None
    return count


@pytest.mark.asyncio
async def test_full_body_replay_after_ttl_has_one_effect(
    couple: tuple[Account, Account, str], chat_auth: Auth
) -> None:
    alice, _, chat_id = couple
    quote = await send(alice, chat_id, "quoted")
    assert quote.status_code == 201, quote.text
    quote_id = UUID(quote.json()["id"])
    owner = UUID(alice.tokens["user"]["id"])
    first_photo = await add_photo(chat_auth, UUID(chat_id), owner)
    second_photo = await add_photo(chat_auth, UUID(chat_id), owner)
    client_id = uuid4()
    photo_ids = [second_photo.id, first_photo.id]

    first = await send(
        alice,
        chat_id,
        "full body",
        client_id=client_id,
        key=str(uuid4()),
        reply_to_id=quote_id,
        photo_ids=photo_ids,
    )
    assert first.status_code == 201, first.text
    message_id = UUID(first.json()["id"])
    chat_auth.db.expire_all()
    assert await message_count(chat_auth.db, UUID(chat_id)) == 2
    assert await outbox_count(chat_auth.db) == 2
    sequence = await chat_auth.db.scalar(
        select(Chat.last_sequence).where(Chat.id == UUID(chat_id))
    )
    dedup = await chat_auth.db.scalar(
        select(ChatMessageDedup).where(
            ChatMessageDedup.chat_id == UUID(chat_id),
            ChatMessageDedup.client_id == client_id,
        )
    )
    assert dedup is not None
    assert dedup.content_fingerprint == body_fingerprint(
        content_hash("full body"), quote_id, photo_ids
    )

    with time_machine.travel(clock.now() + timedelta(hours=25), tick=False):
        future = await relogin(chat_auth, "alice@university.example")
        replay = await send(
            future,
            chat_id,
            "full body",
            client_id=client_id,
            key=str(uuid4()),
            reply_to_id=quote_id,
            photo_ids=photo_ids,
        )
        assert replay.status_code == 200, replay.text
        assert replay.json() == first.json()

    chat_auth.db.expire_all()
    assert await message_count(chat_auth.db, UUID(chat_id)) == 2
    assert await outbox_count(chat_auth.db) == 2
    assert (
        await chat_auth.db.scalar(
            select(Chat.last_sequence).where(Chat.id == UUID(chat_id))
        )
        == sequence
        == 2
    )
    versions = await chat_auth.db.scalar(
        select(func.count())
        .select_from(ChatMessageVersion)
        .where(ChatMessageVersion.message_id == message_id)
    )
    assert versions == 0


@pytest.mark.asyncio
async def test_altered_quote_photos_or_order_conflicts(
    couple: tuple[Account, Account, str], chat_auth: Auth
) -> None:
    alice, _, chat_id = couple
    quote_a = await send(alice, chat_id, "quote a")
    quote_b = await send(alice, chat_id, "quote b")
    assert quote_a.status_code == quote_b.status_code == 201
    quote_a_id = UUID(quote_a.json()["id"])
    quote_b_id = UUID(quote_b.json()["id"])
    owner = UUID(alice.tokens["user"]["id"])
    photos = [await add_photo(chat_auth, UUID(chat_id), owner) for _ in range(3)]
    photo_ids = [photo.id for photo in photos]
    client_id = uuid4()
    first = await send(
        alice,
        chat_id,
        "full body",
        client_id=client_id,
        key=str(uuid4()),
        reply_to_id=quote_a_id,
        photo_ids=[photo_ids[0], photo_ids[1]],
    )
    assert first.status_code == 201, first.text
    message_id = UUID(first.json()["id"])
    before_messages = await message_count(chat_auth.db, UUID(chat_id))
    before_outbox = await outbox_count(chat_auth.db)
    before_sequence = await chat_auth.db.scalar(
        select(Chat.last_sequence).where(Chat.id == UUID(chat_id))
    )

    alterations: list[tuple[str, dict[str, Any]]] = [
        (
            "quote",
            {"reply_to_id": quote_b_id, "photo_ids": [photo_ids[0], photo_ids[1]]},
        ),
        ("photo set", {"reply_to_id": quote_a_id, "photo_ids": [photo_ids[0]]}),
        (
            "photo order",
            {"reply_to_id": quote_a_id, "photo_ids": [photo_ids[1], photo_ids[0]]},
        ),
        (
            "text",
            {"reply_to_id": quote_a_id, "photo_ids": [photo_ids[0], photo_ids[1]]},
        ),
    ]
    for label, alteration in alterations:
        text = "other body" if label == "text" else "full body"
        response = await send(
            alice,
            chat_id,
            text,
            client_id=client_id,
            key=str(uuid4()),
            **alteration,
        )
        assert response.status_code == 409, (label, response.text)
        assert response.json()["code"] == "chat_message_conflict"
        assert response.headers["content-type"] == "application/problem+json"

    chat_auth.db.expire_all()
    stored = await chat_auth.db.scalar(
        select(ChatMessage).where(ChatMessage.id == message_id)
    )
    assert stored is not None
    assert stored.text == "full body"
    assert stored.reply_to_id == quote_a_id
    stored_photos = list(
        await chat_auth.db.scalars(
            select(File)
            .where(File.message_id == message_id)
            .order_by(File.message_position, File.id)
        )
    )
    assert [file.id for file in stored_photos] == [photo_ids[0], photo_ids[1]]
    assert await message_count(chat_auth.db, UUID(chat_id)) == before_messages
    assert await outbox_count(chat_auth.db) == before_outbox
    assert (
        await chat_auth.db.scalar(
            select(Chat.last_sequence).where(Chat.id == UUID(chat_id))
        )
        == before_sequence
    )

    with time_machine.travel(clock.now() + timedelta(hours=25), tick=False):
        future = await relogin(chat_auth, "alice@university.example")
        conflict = await send(
            future,
            chat_id,
            "full body",
            client_id=client_id,
            key=str(uuid4()),
            reply_to_id=quote_a_id,
            photo_ids=[photo_ids[1], photo_ids[0]],
        )
        assert conflict.status_code == 409, conflict.text
        replay = await send(
            future,
            chat_id,
            "full body",
            client_id=client_id,
            key=str(uuid4()),
            reply_to_id=quote_a_id,
            photo_ids=[photo_ids[0], photo_ids[1]],
        )
        assert replay.status_code == 200, replay.text
        assert replay.json()["id"] == str(message_id)


@pytest.mark.asyncio
async def test_edit_does_not_change_the_original_body(
    couple: tuple[Account, Account, str], chat_auth: Auth
) -> None:
    alice, _, chat_id = couple
    quote = await send(alice, chat_id, "quoted")
    quote_id = UUID(quote.json()["id"])
    owner = UUID(alice.tokens["user"]["id"])
    first_photo = await add_photo(chat_auth, UUID(chat_id), owner)
    second_photo = await add_photo(chat_auth, UUID(chat_id), owner)
    client_id = uuid4()
    photo_ids = [second_photo.id, first_photo.id]
    first = await send(
        alice,
        chat_id,
        "original body",
        client_id=client_id,
        key=str(uuid4()),
        reply_to_id=quote_id,
        photo_ids=photo_ids,
    )
    assert first.status_code == 201, first.text
    message_id = UUID(first.json()["id"])

    edited = await edit(alice, chat_id, message_id, "edited body")
    assert edited.status_code == 200, edited.text

    replay = await send(
        alice,
        chat_id,
        "original body",
        client_id=client_id,
        key=str(uuid4()),
        reply_to_id=quote_id,
        photo_ids=photo_ids,
    )
    assert replay.status_code == 200, replay.text
    assert replay.json()["id"] == str(message_id)
    changed = await send(
        alice,
        chat_id,
        "original body",
        client_id=client_id,
        key=str(uuid4()),
        reply_to_id=quote_id,
        photo_ids=[photo_ids[1], photo_ids[0]],
    )
    assert changed.status_code == 409, changed.text
    edited_text = await send(
        alice,
        chat_id,
        "edited body",
        client_id=client_id,
        key=str(uuid4()),
        reply_to_id=quote_id,
        photo_ids=photo_ids,
    )
    assert edited_text.status_code == 409, edited_text.text
    versions = await chat_auth.db.scalar(
        select(func.count())
        .select_from(ChatMessageVersion)
        .where(ChatMessageVersion.message_id == message_id)
    )
    assert versions == 1


@pytest.mark.asyncio
async def test_delete_does_not_change_the_original_body(
    couple: tuple[Account, Account, str], chat_auth: Auth
) -> None:
    alice, _, chat_id = couple
    quote = await send(alice, chat_id, "quoted")
    quote_id = UUID(quote.json()["id"])
    owner = UUID(alice.tokens["user"]["id"])
    first_photo = await add_photo(chat_auth, UUID(chat_id), owner)
    second_photo = await add_photo(chat_auth, UUID(chat_id), owner)
    client_id = uuid4()
    photo_ids = [second_photo.id, first_photo.id]
    first = await send(
        alice,
        chat_id,
        "original body",
        client_id=client_id,
        key=str(uuid4()),
        reply_to_id=quote_id,
        photo_ids=photo_ids,
    )
    assert first.status_code == 201, first.text
    message_id = UUID(first.json()["id"])
    deleted = await remove(alice, chat_id, message_id)
    assert deleted.status_code == 204, deleted.text

    replay = await send(
        alice,
        chat_id,
        "original body",
        client_id=client_id,
        key=str(uuid4()),
        reply_to_id=quote_id,
        photo_ids=photo_ids,
    )
    assert replay.status_code == 200, replay.text
    assert replay.json()["id"] == str(message_id)
    changed = await send(
        alice,
        chat_id,
        "original body",
        client_id=client_id,
        key=str(uuid4()),
        reply_to_id=quote_id,
        photo_ids=[photo_ids[1], photo_ids[0]],
    )
    assert changed.status_code == 409, changed.text


@pytest.mark.asyncio
async def test_archive_does_not_change_the_original_body(
    couple: tuple[Account, Account, str],
    chat_auth: Auth,
    sessions: async_sessionmaker[AsyncSession],
) -> None:
    alice, _, chat_id = couple
    owner = UUID(alice.tokens["user"]["id"])
    first_photo = await add_photo(chat_auth, UUID(chat_id), owner)
    second_photo = await add_photo(chat_auth, UUID(chat_id), owner)
    photo_ids = [second_photo.id, first_photo.id]
    client_id = uuid4()
    chat_uuid = UUID(chat_id)
    sender_id = owner

    with time_machine.travel(clock.now() - timedelta(days=400), tick=False):
        quote, _ = await post_message(
            chat_auth.db,
            chat_id=chat_uuid,
            sender_id=sender_id,
            client_id=uuid4(),
            text="old quote",
            settings=chat_auth.settings,
        )
        body, created = await post_message(
            chat_auth.db,
            chat_id=chat_uuid,
            sender_id=sender_id,
            client_id=client_id,
            text="old body",
            settings=chat_auth.settings,
            reply_to_id=quote.id,
            photo_ids=photo_ids,
        )
        assert created
        await chat_auth.db.commit()
        body_id, quote_id = body.id, quote.id

    chat_auth.db.expire_all()
    report = await archive_messages(sessions, chat_auth.settings)
    assert report["failed"] == 0
    assert report["archived"] == 2

    replay = await send(
        alice,
        chat_id,
        "old body",
        client_id=client_id,
        key=str(uuid4()),
        reply_to_id=quote_id,
        photo_ids=photo_ids,
    )
    assert replay.status_code == 200, replay.text
    assert replay.json()["id"] == str(body_id)
    changed = await send(
        alice,
        chat_id,
        "old body",
        client_id=client_id,
        key=str(uuid4()),
        reply_to_id=quote_id,
        photo_ids=[photo_ids[1], photo_ids[0]],
    )
    assert changed.status_code == 409, changed.text


@pytest.mark.asyncio
async def test_text_only_backfilled_row_stays_strict(
    couple: tuple[Account, Account, str], chat_auth: Auth
) -> None:
    alice, _, chat_id = couple
    quote = await send(alice, chat_id, "quoted")
    quote_id = UUID(quote.json()["id"])
    owner = UUID(alice.tokens["user"]["id"])
    photo = await add_photo(chat_auth, UUID(chat_id), owner)
    client_id = uuid4()
    first = await send(
        alice, chat_id, "legacy text", client_id=client_id, key=str(uuid4())
    )
    assert first.status_code == 201, first.text
    message_id = UUID(first.json()["id"])
    await set_fingerprint(
        chat_auth.db,
        UUID(chat_id),
        client_id,
        body_fingerprint(content_hash("legacy text"), None, []),
    )

    replay = await send(
        alice, chat_id, "legacy text", client_id=client_id, key=str(uuid4())
    )
    assert replay.status_code == 200, replay.text
    assert replay.json()["id"] == str(message_id)
    changed_text = await send(
        alice, chat_id, "legacy text changed", client_id=client_id, key=str(uuid4())
    )
    assert changed_text.status_code == 409, changed_text.text
    gained_quote = await send(
        alice,
        chat_id,
        "legacy text",
        client_id=client_id,
        key=str(uuid4()),
        reply_to_id=quote_id,
    )
    assert gained_quote.status_code == 409, gained_quote.text
    gained_photo = await send(
        alice,
        chat_id,
        "legacy text",
        client_id=client_id,
        key=str(uuid4()),
        photo_ids=[photo.id],
    )
    assert gained_photo.status_code == 409, gained_photo.text


@pytest.mark.asyncio
async def test_backfilled_metadata_row_replays_only_the_exact_body(
    couple: tuple[Account, Account, str], chat_auth: Auth
) -> None:
    alice, _, chat_id = couple
    quote = await send(alice, chat_id, "quoted")
    quote_id = UUID(quote.json()["id"])
    owner = UUID(alice.tokens["user"]["id"])
    first_photo = await add_photo(chat_auth, UUID(chat_id), owner)
    second_photo = await add_photo(chat_auth, UUID(chat_id), owner)
    client_id = uuid4()
    photo_ids = [second_photo.id, first_photo.id]
    first = await send(
        alice,
        chat_id,
        "legacy rich body",
        client_id=client_id,
        key=str(uuid4()),
        reply_to_id=quote_id,
        photo_ids=photo_ids,
    )
    assert first.status_code == 201, first.text
    message_id = UUID(first.json()["id"])
    await set_fingerprint(
        chat_auth.db,
        UUID(chat_id),
        client_id,
        body_fingerprint(content_hash("legacy rich body"), quote_id, photo_ids),
    )

    replay = await send(
        alice,
        chat_id,
        "legacy rich body",
        client_id=client_id,
        key=str(uuid4()),
        reply_to_id=quote_id,
        photo_ids=photo_ids,
    )
    assert replay.status_code == 200, replay.text
    assert replay.json()["id"] == str(message_id)
    changed_order = await send(
        alice,
        chat_id,
        "legacy rich body",
        client_id=client_id,
        key=str(uuid4()),
        reply_to_id=quote_id,
        photo_ids=[first_photo.id, second_photo.id],
    )
    assert changed_order.status_code == 409, changed_order.text
    omitted_photo = await send(
        alice,
        chat_id,
        "legacy rich body",
        client_id=client_id,
        key=str(uuid4()),
        reply_to_id=quote_id,
        photo_ids=[second_photo.id],
    )
    assert omitted_photo.status_code == 409, omitted_photo.text


@pytest.mark.asyncio
async def test_unverifiable_legacy_row_fails_closed(
    couple: tuple[Account, Account, str], chat_auth: Auth
) -> None:
    alice, _, chat_id = couple
    client_id = uuid4()
    first = await send(alice, chat_id, "lost metadata", client_id=client_id)
    assert first.status_code == 201, first.text
    message_id = UUID(first.json()["id"])
    dedup = await set_fingerprint(chat_auth.db, UUID(chat_id), client_id, None)

    replay = await send(
        alice, chat_id, "lost metadata", client_id=client_id, key=str(uuid4())
    )
    assert replay.status_code == 409, replay.text
    assert replay.json()["code"] == "chat_message_conflict"
    assert dedup.content_hash == content_hash("lost metadata")
    assert await message_count(chat_auth.db, UUID(chat_id)) == 1
    stored = await chat_auth.db.scalar(
        select(ChatMessage).where(ChatMessage.id == message_id)
    )
    assert stored is not None
    assert stored.text == "lost metadata"
