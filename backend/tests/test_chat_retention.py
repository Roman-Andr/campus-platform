"""Archive partitions and chat retention on PostgreSQL (specification, 5.3.2)."""

import asyncio
from datetime import datetime, timedelta
from uuid import UUID, uuid4

import httpx2
import pytest
import time_machine
from pydantic import SecretStr
from sqlalchemy import func, select, text
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker

from campus.core import clock
from campus.core.config import Settings
from campus.core.db import create_session_factory
from campus.core.storage import Storage
from campus.modules.chat import (
    Chat,
    ChatMember,
    ChatMessage,
    ChatMessageArchive,
    ChatMessageHistory,
    ChatMessageSnapshot,
    leave_chat,
    snapshot_message,
)
from campus.modules.chat.retention import (
    archive_messages,
    purge_empty_chats,
)
from campus.modules.chat.service import create_personal_chat, post_message
from campus.modules.files import File
from tests.test_chat import (
    ROOT,
    account,
    bearer,
    chat_auth,
    create_chat,
    history,
    send_message,
)
from tests.test_identity import Auth
from tests.test_profile import Account

__all__ = ["chat_auth"]

SEARCH = f"{ROOT}/search"


@pytest.fixture
async def sessions(chat_auth: Auth) -> async_sessionmaker[AsyncSession]:
    assert isinstance(chat_auth.db.bind, AsyncEngine)
    return create_session_factory(chat_auth.db.bind)


def leave_headers(account: Account, key: str | None = None) -> dict[str, str]:
    return {"Idempotency-Key": key or str(uuid4()), **bearer(account)}


async def leave(
    account: Account, chat_id: str, key: str | None = None
) -> httpx2.Response:
    return await account.auth.client.delete(
        f"{ROOT}/{chat_id}/membership",
        headers=leave_headers(account, key),
    )


async def chat_row(auth: Auth, chat_id: str) -> Chat | None:
    assert isinstance(auth.db.bind, AsyncEngine)
    async with create_session_factory(auth.db.bind)() as db:
        return await db.scalar(
            select(Chat)
            .where(Chat.id == UUID(chat_id))
            .execution_options(populate_existing=True)
        )


async def empty_since_of(auth: Auth, chat_id: str) -> datetime | None:
    chat = await chat_row(auth, chat_id)
    assert chat is not None
    return chat.empty_since


async def active_member_count(auth: Auth, chat_id: str) -> int:
    assert isinstance(auth.db.bind, AsyncEngine)
    async with create_session_factory(auth.db.bind)() as db:
        count = await db.scalar(
            select(func.count())
            .select_from(ChatMember)
            .where(
                ChatMember.chat_id == UUID(chat_id),
                ChatMember.left_at.is_(None),
            )
        )
    return count or 0


async def add_chat_file(auth: Auth, chat_id: str, owner_id: str) -> File:
    now = clock.now()
    file = File(
        owner_id=UUID(owner_id),
        chat_id=UUID(chat_id),
        purpose="chat_photo",
        key=f"photos/{uuid4()}",
        status="ready",
        size=10,
        upload_expires_at=now + timedelta(minutes=15),
        expires_at=now + timedelta(days=3650),
    )
    auth.db.add(file)
    await auth.db.commit()
    return file


def s3_settings(settings: Settings) -> Settings:
    return settings.model_copy(
        update={
            "s3_endpoint_url": "http://s3.test",
            "s3_bucket": "chat-retention",
            "s3_access_key": SecretStr("chat-retention-key"),
            "s3_secret_key": SecretStr("chat-retention-secret"),
        }
    )


async def test_archive_keeps_id_sequence_history_and_replay(
    chat_auth: Auth, sessions: async_sessionmaker[AsyncSession]
) -> None:
    alice = await account(chat_auth, "alice@university.example")
    bob = await account(chat_auth, "bob@university.example")
    chat_id = (await create_chat(alice, bob)).json()["id"]
    chat_uuid = UUID(chat_id)
    now = clock.now()

    with time_machine.travel(now - timedelta(days=400), tick=False):
        old, created = await post_message(
            chat_auth.db,
            chat_id=chat_uuid,
            sender_id=UUID(alice.tokens["user"]["id"]),
            client_id=uuid4(),
            text="archived hello",
            settings=chat_auth.settings,
        )
        assert created
        await chat_auth.db.commit()
        old_id, old_client, old_sequence = old.id, old.client_id, old.sequence
        old_year = old.created_at.year

    with time_machine.travel(now - timedelta(days=10), tick=False):
        fresh, _ = await post_message(
            chat_auth.db,
            chat_id=chat_uuid,
            sender_id=UUID(bob.tokens["user"]["id"]),
            client_id=uuid4(),
            text="recent hello",
            settings=chat_auth.settings,
        )
        await chat_auth.db.commit()
        fresh_id = fresh.id

    report = await archive_messages(sessions, chat_auth.settings)
    assert report["archived"] == 1
    assert report["failed"] == 0

    chat_auth.db.expire_all()
    hot = await chat_auth.db.scalar(select(ChatMessage).where(ChatMessage.id == old_id))
    archived = await chat_auth.db.scalar(
        select(ChatMessageArchive).where(ChatMessageArchive.id == old_id)
    )
    history_row = await chat_auth.db.scalar(
        select(ChatMessageHistory).where(ChatMessageHistory.id == old_id)
    )
    assert hot is None
    assert archived is not None
    assert history_row is not None
    assert archived.sequence == old_sequence == 1
    assert archived.client_id == old_client
    assert history_row.text == "archived hello"
    partition = await chat_auth.db.scalar(
        text(
            "SELECT tableoid::regclass::text FROM chat_message_archive WHERE id = :id"
        ),
        {"id": old_id},
    )
    assert partition == f"chat_message_archive_{old_year}"

    page = await history(bob, chat_id, ascending=True, size=100)
    assert page.status_code == 200, page.text
    items = page.json()["items"]
    assert [item["id"] for item in items] == [str(old_id), str(fresh_id)]
    assert [item["sequence"] for item in items] == [1, 2]

    found = await bob.auth.client.get(
        SEARCH,
        params={"q": "archived"},
        headers=bearer(bob),
    )
    assert found.status_code == 200, found.text
    assert [item["message"]["id"] for item in found.json()["items"]] == [str(old_id)]

    replay = await send_message(
        alice, chat_id, "archived hello", old_client, str(uuid4())
    )
    assert replay.status_code == 200, replay.text
    assert replay.json()["id"] == str(old_id)
    await chat_auth.db.rollback()


async def test_concurrent_archive_send_and_history_do_not_lose_rows(
    chat_auth: Auth, sessions: async_sessionmaker[AsyncSession]
) -> None:
    alice = await account(chat_auth, "alice@university.example")
    bob = await account(chat_auth, "bob@university.example")
    chat_id = (await create_chat(alice, bob)).json()["id"]
    chat_uuid = UUID(chat_id)
    alice_id = UUID(alice.tokens["user"]["id"])
    now = clock.now()

    with time_machine.travel(now - timedelta(days=400), tick=False):
        for number in range(30):
            await post_message(
                chat_auth.db,
                chat_id=chat_uuid,
                sender_id=alice_id,
                client_id=uuid4(),
                text=f"old {number}",
                settings=chat_auth.settings,
            )
        await chat_auth.db.commit()

    with time_machine.travel(now - timedelta(days=10), tick=False):
        recent = await send_message(alice, chat_id, "recent")
        assert recent.status_code == 201, recent.text
        page_during = history(bob, chat_id)
        # Two archive jobs and the history read race for the same rows.
        first, second, during = await asyncio.gather(
            archive_messages(sessions, chat_auth.settings),
            archive_messages(sessions, chat_auth.settings),
            page_during,
        )
        sent = await send_message(alice, chat_id, "sent during archive")
    assert first["failed"] == second["failed"] == 0
    assert during.status_code == 200, during.text
    assert sent.status_code == 201, sent.text

    page = await history(bob, chat_id, size=100, ascending=True)
    assert page.status_code == 200, page.text
    items = page.json()["items"]
    assert len(items) == 32
    assert len({item["id"] for item in items}) == 32
    assert [item["sequence"] for item in items] == list(range(1, 33))

    chat_auth.db.expire_all()
    hot = await chat_auth.db.scalar(select(func.count()).select_from(ChatMessage))
    archived = await chat_auth.db.scalar(
        select(func.count()).select_from(ChatMessageArchive)
    )
    assert hot == 2
    assert archived == 30
    await chat_auth.db.rollback()


async def test_retention_starts_after_last_member_and_rejoin_cancels(  # noqa: PLR0915
    chat_auth: Auth,
    sessions: async_sessionmaker[AsyncSession],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    alice = await account(chat_auth, "alice@university.example")
    bob = await account(chat_auth, "bob@university.example")

    def delete(self: Storage, object_key: str) -> None:
        del self, object_key

    monkeypatch.setattr(Storage, "delete", delete)
    created = await create_chat(alice, bob)
    assert created.status_code == 201, created.text
    chat_id = created.json()["id"]
    file = await add_chat_file(chat_auth, chat_id, alice.tokens["user"]["id"])
    message_response = await send_message(alice, chat_id, "keep evidence")
    assert message_response.status_code == 201, message_response.text
    message_id = UUID(message_response.json()["id"])
    complaint_id = uuid4()
    snapshot = await snapshot_message(
        chat_auth.db, complaint_id=complaint_id, message_id=message_id
    )
    await chat_auth.db.commit()
    snapshot_text = snapshot.text

    started = clock.now()
    first = await leave(alice, chat_id)
    assert first.status_code == 204
    assert await empty_since_of(chat_auth, chat_id) is None
    assert await active_member_count(chat_auth, chat_id) == 1

    with time_machine.travel(started + timedelta(days=800), tick=False):
        assert (await purge_empty_chats(sessions, s3_settings(chat_auth.settings)))[
            "chats"
        ] == 0

    second = await leave(bob, chat_id)
    assert second.status_code == 204
    empty_since = await empty_since_of(chat_auth, chat_id)
    assert empty_since is not None
    assert await active_member_count(chat_auth, chat_id) == 0

    retention = chat_auth.settings.chat_retention
    with time_machine.travel(empty_since + retention - timedelta(seconds=1)):
        assert (await purge_empty_chats(sessions, s3_settings(chat_auth.settings)))[
            "chats"
        ] == 0
    assert await chat_row(chat_auth, chat_id) is not None

    alice_id = UUID(alice.tokens["user"]["id"])
    bob_id = UUID(bob.tokens["user"]["id"])
    rejoin_at = empty_since + retention - timedelta(seconds=1)
    with time_machine.travel(rejoin_at, tick=False):
        # The bearer token is older than its lifetime in this controlled
        # clock; the service call exercises the same membership transition.
        await create_personal_chat(
            chat_auth.db,
            creator_id=alice_id,
            recipient_id=bob_id,
        )
        await chat_auth.db.commit()
        assert await empty_since_of(chat_auth, chat_id) is None
        assert await active_member_count(chat_auth, chat_id) == 1
        assert (await purge_empty_chats(sessions, s3_settings(chat_auth.settings)))[
            "chats"
        ] == 0
        assert await chat_row(chat_auth, chat_id) is not None
        # Leave again at the rejoin instant; its own clock starts now.
        assert await leave_chat(chat_auth.db, UUID(chat_id), alice_id)
        await chat_auth.db.commit()
        second_empty = await empty_since_of(chat_auth, chat_id)
        assert second_empty is not None

    # Check the exact boundary and the full cleanup.
    with time_machine.travel(second_empty + retention, tick=False):
        report = await purge_empty_chats(sessions, s3_settings(chat_auth.settings))
    assert report["failed"] == 0
    assert report["chats"] == 1, report
    assert report["files"] == 1, report
    assert await chat_row(chat_auth, chat_id) is None
    survived = await chat_auth.db.scalar(
        select(ChatMessageSnapshot).where(ChatMessageSnapshot.id == snapshot.id)
    )
    assert survived is not None
    assert survived.text == snapshot_text
    assert (await chat_auth.db.scalar(select(File).where(File.id == file.id))) is None
    await chat_auth.db.rollback()


async def test_s3_failure_rolls_back_and_missing_object_is_retryable(
    chat_auth: Auth,
    sessions: async_sessionmaker[AsyncSession],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    alice = await account(chat_auth, "alice@university.example")
    bob = await account(chat_auth, "bob@university.example")
    chat_id = (await create_chat(alice, bob)).json()["id"]
    file = await add_chat_file(chat_auth, chat_id, alice.tokens["user"]["id"])
    key = file.key
    assert (await leave(alice, chat_id)).status_code == 204
    assert (await leave(bob, chat_id)).status_code == 204
    empty_since = await empty_since_of(chat_auth, chat_id)
    assert empty_since is not None

    deleted: list[str] = []
    calls = 0

    def delete(self: Storage, object_key: str) -> None:
        nonlocal calls
        del self
        calls += 1
        deleted.append(object_key)
        if calls == 2:
            # The source object is already gone, the photo call fails: the
            # retry must tolerate the missing object and finish the batch.
            raise RuntimeError("S3 unavailable")

    monkeypatch.setattr(Storage, "delete", delete)
    retention = chat_auth.settings.chat_retention
    with time_machine.travel(empty_since + retention + timedelta(seconds=1)):
        failed = await purge_empty_chats(sessions, s3_settings(chat_auth.settings))
        assert failed["failed"] == 1
        assert failed["chats"] == 0
        assert await chat_row(chat_auth, chat_id) is not None

        retried = await purge_empty_chats(sessions, s3_settings(chat_auth.settings))
    assert retried["failed"] == 0, retried
    assert retried["chats"] == 1, retried
    assert deleted == [
        key + "/source",
        key + "/photo",
        key + "/source",
        key + "/photo",
        key + "/preview",
    ]
    await chat_auth.db.rollback()


async def test_leave_rights_list_and_idempotent_replay(chat_auth: Auth) -> None:
    alice = await account(chat_auth, "alice@university.example")
    bob = await account(chat_auth, "bob@university.example")
    stranger = await account(chat_auth, "stranger@university.example")
    chat_id = (await create_chat(alice, bob)).json()["id"]
    assert (await history(alice, chat_id)).status_code == 200
    assert (await history(stranger, chat_id)).status_code == 404

    denied = await leave(stranger, chat_id)
    assert denied.status_code == 404
    assert denied.headers["content-type"] == "application/problem+json"

    key = str(uuid4())
    first = await leave(alice, chat_id, key)
    assert first.status_code == 204
    replay = await leave(alice, chat_id, key)
    assert replay.status_code == 204
    assert replay.headers["Idempotent-Replayed"] == "true"

    assert (await history(alice, chat_id)).status_code == 404
    assert (await send_message(alice, chat_id, "after leaving")).status_code == 404
    chats = await alice.auth.client.get(ROOT, headers=bearer(alice))
    assert chats.status_code == 200
    assert all(item["id"] != chat_id for item in chats.json()["items"])
    assert (await history(bob, chat_id)).status_code == 200
    assert (await send_message(bob, chat_id, "still a member")).status_code == 201
    assert (await active_member_count(chat_auth, chat_id)) == 1

    rejoined = await create_chat(alice, bob)
    assert rejoined.status_code == 200, rejoined.text
    assert await active_member_count(chat_auth, chat_id) == 2
    assert await empty_since_of(chat_auth, chat_id) is None
    assert (await history(alice, chat_id)).status_code == 200
    chats = await alice.auth.client.get(ROOT, headers=bearer(alice))
    assert all(item["id"] == chat_id for item in chats.json()["items"])


async def test_snapshot_survives_cleanup_and_active_chat_photo_survives(
    chat_auth: Auth,
    sessions: async_sessionmaker[AsyncSession],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    alice = await account(chat_auth, "alice@university.example")
    bob = await account(chat_auth, "bob@university.example")
    stranger = await account(chat_auth, "stranger@university.example")
    empty_id = (await create_chat(alice, bob)).json()["id"]
    active_id = (await create_chat(bob, stranger)).json()["id"]
    empty_file = await add_chat_file(chat_auth, empty_id, alice.tokens["user"]["id"])
    active_file = await add_chat_file(chat_auth, active_id, bob.tokens["user"]["id"])
    sent = await send_message(alice, empty_id, "complaint evidence")
    message_id = UUID(sent.json()["id"])
    complaint_id = uuid4()
    snapshot = await snapshot_message(
        chat_auth.db, complaint_id=complaint_id, message_id=message_id
    )
    await chat_auth.db.commit()
    duplicate = await snapshot_message(
        chat_auth.db, complaint_id=complaint_id, message_id=message_id
    )
    await chat_auth.db.commit()
    assert duplicate.id == snapshot.id

    assert (await leave(alice, empty_id)).status_code == 204
    assert (await leave(bob, empty_id)).status_code == 204
    empty_since = await empty_since_of(chat_auth, empty_id)
    assert empty_since is not None

    def delete(self: Storage, object_key: str) -> None:
        del self, object_key

    monkeypatch.setattr(Storage, "delete", delete)
    retention = chat_auth.settings.chat_retention
    with time_machine.travel(empty_since + retention + timedelta(seconds=1)):
        report = await purge_empty_chats(sessions, s3_settings(chat_auth.settings))
    assert report["chats"] == 1, report
    assert await chat_row(chat_auth, empty_id) is None
    assert (
        await chat_auth.db.scalar(
            select(ChatMessageSnapshot).where(ChatMessageSnapshot.id == snapshot.id)
        )
    ) is not None
    assert (
        await chat_auth.db.scalar(select(File).where(File.id == empty_file.id))
    ) is None
    assert (
        await chat_auth.db.scalar(select(File).where(File.id == active_file.id))
    ) is not None
    assert await chat_row(chat_auth, active_id) is not None
    await chat_auth.db.rollback()
