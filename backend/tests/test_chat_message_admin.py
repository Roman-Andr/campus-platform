"""Message editing, deletion, quotes, photos and complaint evidence."""

import asyncio
from datetime import timedelta
from typing import Any, ClassVar
from uuid import UUID, uuid4

import httpx2
import pytest
import time_machine
from sqlalchemy import select

import campus.modules.chat.api as chat_api
from campus.core import clock
from campus.core.db import create_session_factory
from campus.core.outbox import OutboxMessage, process_outbox
from campus.core.web import ProblemError
from campus.modules.chat import (
    MESSAGE_TOPIC,
    Chat,
    ChatMessage,
    ChatMessageHistory,
    ChatMessageSnapshot,
    ChatMessageVersion,
    edit_message,
    leave_chat,
    purge_message_versions,
    retention,
    snapshot_message,
    snapshot_photos,
)
from campus.modules.files import File
from tests.test_chat import (
    ROOT,
    Reference,
    account,
    bearer,
    chat_auth,
    create_chat,
    reference,
)
from tests.test_identity import Auth
from tests.test_profile import Account

__all__ = ["chat_auth", "reference"]


@pytest.fixture
async def sessions(engine: Any) -> Any:
    return create_session_factory(engine)


async def send(
    account: Account,
    chat_id: str,
    text: str,
    *,
    reply_to_id: UUID | None = None,
    photo_ids: list[UUID] | None = None,
) -> httpx2.Response:
    return await account.auth.client.post(
        f"{ROOT}/{chat_id}/messages",
        json={
            "client_id": str(uuid4()),
            "text": text,
            "reply_to_id": str(reply_to_id) if reply_to_id else None,
            "photo_ids": [str(photo_id) for photo_id in photo_ids or []],
        },
        headers={"Idempotency-Key": str(uuid4()), **bearer(account)},
    )


async def edit(
    account: Account, chat_id: str, message_id: UUID, text: str, key: str | None = None
) -> httpx2.Response:
    return await account.auth.client.patch(
        f"{ROOT}/{chat_id}/messages/{message_id}",
        json={"text": text},
        headers={"Idempotency-Key": key or str(uuid4()), **bearer(account)},
    )


async def remove(
    account: Account, chat_id: str, message_id: UUID, key: str | None = None
) -> httpx2.Response:
    return await account.auth.client.delete(
        f"{ROOT}/{chat_id}/messages/{message_id}",
        headers={"Idempotency-Key": key or str(uuid4()), **bearer(account)},
    )


async def history(account: Account, chat_id: str) -> httpx2.Response:
    return await account.auth.client.get(
        f"{ROOT}/{chat_id}/messages", headers=bearer(account)
    )


async def evidence(account: Account, chat_id: str, message_id: UUID) -> httpx2.Response:
    return await account.auth.client.get(
        f"{ROOT}/{chat_id}/messages/{message_id}/evidence", headers=bearer(account)
    )


async def photos(account: Account, chat_id: str, message_id: UUID) -> httpx2.Response:
    return await account.auth.client.get(
        f"{ROOT}/{chat_id}/messages/{message_id}/photos", headers=bearer(account)
    )


async def add_photo(
    auth: Auth, chat_id: UUID, owner_id: UUID, *, status: str = "ready"
) -> File:
    now = clock.now()
    file = File(
        owner_id=owner_id,
        chat_id=chat_id,
        purpose="chat_photo",
        key=f"photos/{uuid4()}",
        status=status,
        upload_expires_at=now + timedelta(hours=1),
        expires_at=now + timedelta(days=1),
    )
    auth.db.add(file)
    await auth.db.commit()
    return file


class FakeStorage:
    deleted: ClassVar[list[str]] = []

    def __init__(self, settings: Any) -> None:
        self.settings = settings

    def upload(self, key: str) -> dict[str, Any]:
        return {"url": f"https://upload.test/{key}", "fields": {"key": key}}

    def url(self, key: str) -> str:
        return f"https://signed.test/{key}"

    def delete(self, key: str) -> None:
        FakeStorage.deleted.append(key)


@pytest.fixture
def fake_storage(monkeypatch: pytest.MonkeyPatch) -> type[FakeStorage]:

    monkeypatch.setattr(chat_api, "Storage", FakeStorage)
    monkeypatch.setattr(retention, "Storage", FakeStorage)
    FakeStorage.deleted.clear()
    return FakeStorage


@pytest.fixture
async def couple(
    chat_auth: Auth, reference: Reference
) -> tuple[Account, Account, Account, str]:
    alice = await account(chat_auth, "alice@university.example", reference.places)
    bob = await account(chat_auth, "bob@university.example", reference.places)
    carol = await account(chat_auth, "carol@university.example", reference.places)
    chat = await create_chat(alice, bob)
    assert chat.status_code == 201, chat.text
    return alice, bob, carol, chat.json()["id"]


@pytest.mark.asyncio
async def test_quote_is_current_and_stays_inside_chat(
    couple: tuple[Account, Account, Account, str],
) -> None:
    alice, bob, carol, chat_id = couple
    first = await send(alice, chat_id, "the first visible text")
    assert first.status_code == 201, first.text
    message_id = UUID(first.json()["id"])

    reply = await send(bob, chat_id, "a reply", reply_to_id=message_id)
    assert reply.status_code == 201, reply.text
    assert reply.json()["reply_to"]["text"] == "the first visible text"
    assert reply.json()["reply_to_id"] == str(message_id)

    edited = await edit(alice, chat_id, message_id, "the edited visible text")
    assert edited.status_code == 200, edited.text
    assert edited.json()["version"] == 2
    page = await history(bob, chat_id)
    assert page.status_code == 200, page.text
    quote = next(row for row in page.json()["items"] if row["id"] == reply.json()["id"])
    assert quote["reply_to"]["text"] == "the edited visible text"

    other = await create_chat(alice, carol)
    assert other.status_code == 201, other.text
    foreign = await send(alice, other.json()["id"], "another chat")
    foreign_id = foreign.json()["id"]
    rejected = await send(bob, chat_id, "bad quote", reply_to_id=UUID(foreign_id))
    assert rejected.status_code == 404, rejected.text

    removed = await remove(alice, chat_id, message_id)
    assert removed.status_code == 204, removed.text
    rejected = await send(bob, chat_id, "deleted quote", reply_to_id=message_id)
    assert rejected.status_code == 404, rejected.text


@pytest.mark.asyncio
async def test_edit_and_delete_rights_and_versions(  # noqa: PLR0915
    couple: tuple[Account, Account, Account, str], chat_auth: Auth
) -> None:
    alice, bob, carol, chat_id = couple
    sent = await send(alice, chat_id, "original searchable text")
    assert sent.status_code == 201, sent.text
    message_id = UUID(sent.json()["id"])

    denied = await edit(bob, chat_id, message_id, "stolen")
    assert denied.status_code == 404, denied.text
    denied = await remove(bob, chat_id, message_id)
    assert denied.status_code == 404, denied.text
    denied = await edit(carol, chat_id, message_id, "stolen")
    assert denied.status_code == 404, denied.text

    # A message of another chat is hidden even from its author: the path
    # chat and the message must belong together.
    other = await create_chat(alice, carol)
    assert other.status_code == 201, other.text
    foreign = await send(alice, other.json()["id"], "another chat")
    foreign_id = UUID(foreign.json()["id"])
    assert (await edit(alice, chat_id, foreign_id, "cross chat")).status_code == 404
    assert (await remove(alice, chat_id, foreign_id)).status_code == 404

    snapshot_early = await snapshot_message(
        chat_auth.db,
        complaint_id=uuid4(),
        message_id=message_id,
        settings=chat_auth.settings,
    )
    await chat_auth.db.commit()

    key = str(uuid4())
    edited = await edit(alice, chat_id, message_id, "edited searchable text", key=key)
    assert edited.status_code == 200, edited.text
    assert edited.json()["version"] == 2
    again = await edit(alice, chat_id, message_id, "edited searchable text", key=key)
    assert again.status_code == 200, again.text
    assert again.json()["version"] == 2
    assert again.headers["Idempotent-Replayed"] == "true"
    conflict = await edit(alice, chat_id, message_id, "different text", key=key)
    assert conflict.status_code == 422, conflict.text
    assert conflict.json()["type"].endswith("idempotency_key_reused")

    versions = list(
        await chat_auth.db.scalars(
            select(ChatMessageVersion).where(
                ChatMessageVersion.message_id == message_id
            )
        )
    )
    assert [row.text for row in versions] == ["original searchable text"]

    search = await alice.auth.client.get(
        f"{ROOT}/search", params={"q": "original searchable"}, headers=bearer(alice)
    )
    assert search.status_code == 200, search.text
    assert search.json()["items"] == []
    search = await alice.auth.client.get(
        f"{ROOT}/search", params={"q": "edited searchable"}, headers=bearer(alice)
    )
    assert search.status_code == 200, search.text
    assert len(search.json()["items"]) == 1

    delete_key = str(uuid4())
    deleted = await remove(alice, chat_id, message_id, key=delete_key)
    assert deleted.status_code == 204, deleted.text
    replayed = await remove(alice, chat_id, message_id, key=delete_key)
    assert replayed.status_code == 204
    assert replayed.headers["Idempotent-Replayed"] == "true"
    assert (await remove(alice, chat_id, message_id)).status_code == 204
    assert (await edit(alice, chat_id, message_id, "resurrect")).status_code == 409

    page = await history(bob, chat_id)
    assert page.status_code == 200, page.text
    assert page.json()["items"] == []
    search = await alice.auth.client.get(
        f"{ROOT}/search", params={"q": "edited searchable"}, headers=bearer(alice)
    )
    assert search.json()["items"] == []

    evidence_response = await evidence(alice, chat_id, message_id)
    assert evidence_response.status_code == 200, evidence_response.text
    body = evidence_response.json()
    assert body["current_text"] is None
    assert body["deleted_at"] is not None
    assert [row["kind"] for row in body["versions"]] == ["edit", "delete"]
    assert body["versions"][0]["text"] == "original searchable text"
    assert body["versions"][1]["text"] == "edited searchable text"
    assert (await evidence(carol, chat_id, message_id)).status_code == 404

    snapshot_late = await snapshot_message(
        chat_auth.db,
        complaint_id=uuid4(),
        message_id=message_id,
        settings=chat_auth.settings,
    )
    await chat_auth.db.commit()
    assert snapshot_early.text == "original searchable text"
    assert snapshot_early.version == 1
    assert snapshot_late.text == "edited searchable text"
    assert snapshot_late.version == 2


@pytest.mark.asyncio
async def test_hidden_revisions_are_erased_but_snapshot_survives(
    couple: tuple[Account, Account, Account, str],
    chat_auth: Auth,
    sessions: Any,
) -> None:
    alice, _, _, chat_id = couple
    sent = await send(alice, chat_id, "will disappear")
    message_id = UUID(sent.json()["id"])
    complaint_id = uuid4()
    snapshot = await snapshot_message(
        chat_auth.db,
        complaint_id=complaint_id,
        message_id=message_id,
        settings=chat_auth.settings,
    )
    await chat_auth.db.commit()
    assert (await remove(alice, chat_id, message_id)).status_code == 204

    stored = await chat_auth.db.scalar(
        select(ChatMessage).where(ChatMessage.id == message_id)
    )
    assert stored is not None
    assert stored.deleted_at is not None
    boundary = stored.deleted_at + chat_auth.settings.chat_message_version_retention

    with time_machine.travel(boundary - timedelta(seconds=1)):
        assert (await evidence(alice, chat_id, message_id)).status_code == 200
        within = await snapshot_message(
            chat_auth.db,
            complaint_id=uuid4(),
            message_id=message_id,
            settings=chat_auth.settings,
        )
        await chat_auth.db.commit()
        assert within.text == "will disappear"
        assert within.version == 1

    with time_machine.travel(boundary):
        # The boundary is enforced by the evidence contract, not only by the
        # cleanup job: a delayed worker must not leak an expired revision.
        assert (await evidence(alice, chat_id, message_id)).status_code == 404
        with pytest.raises(ProblemError) as error:
            await snapshot_message(
                chat_auth.db,
                complaint_id=uuid4(),
                message_id=message_id,
                settings=chat_auth.settings,
            )
        assert error.value.problem_type.code == "not_found"
        report = await purge_message_versions(sessions, chat_auth.settings)
        assert report["failed"] == 0
        assert report["versions"] == 1
        assert (await evidence(alice, chat_id, message_id)).status_code == 404
        assert await chat_auth.db.get(ChatMessageSnapshot, snapshot.id) is not None
        assert await chat_auth.db.get(ChatMessageSnapshot, within.id) is not None
        assert snapshot.text == "will disappear"

    # Repeating the capture of the stored complaint returns the same row.
    repeated = await snapshot_message(
        chat_auth.db,
        complaint_id=complaint_id,
        message_id=message_id,
        settings=chat_auth.settings,
    )
    assert repeated.id == snapshot.id


@pytest.mark.asyncio
async def test_snapshot_captures_selected_edited_revision(
    couple: tuple[Account, Account, Account, str],
    chat_auth: Auth,
    sessions: Any,
) -> None:
    alice, _, _, chat_id = couple
    sent = await send(alice, chat_id, "selected original")
    message_id = UUID(sent.json()["id"])
    edited = await edit(alice, chat_id, message_id, "selected current")
    assert edited.status_code == 200, edited.text

    complaint_id = uuid4()
    snapshot = await snapshot_message(
        chat_auth.db,
        complaint_id=complaint_id,
        message_id=message_id,
        version=1,
        settings=chat_auth.settings,
    )
    await chat_auth.db.commit()
    assert snapshot.text == "selected original"
    assert snapshot.version == 1
    assert (await remove(alice, chat_id, message_id)).status_code == 204

    with time_machine.travel(
        clock.now() + chat_auth.settings.chat_message_version_retention * 2
    ):
        # The expired revision is refused for a new complaint even before
        # the cleanup job removes its row.
        with pytest.raises(ProblemError) as error:
            await snapshot_message(
                chat_auth.db,
                complaint_id=uuid4(),
                message_id=message_id,
                version=1,
                settings=chat_auth.settings,
            )
        assert error.value.problem_type.code == "not_found"

        report = await purge_message_versions(sessions, chat_auth.settings)
        assert report["failed"] == 0
        assert report["versions"] == 2
        preserved = await chat_auth.db.scalar(
            select(ChatMessageSnapshot.text).where(
                ChatMessageSnapshot.id == snapshot.id
            )
        )
        assert preserved == "selected original"

        # The first capture is immutable and idempotent, even after purge.
        repeated = await snapshot_message(
            chat_auth.db,
            complaint_id=complaint_id,
            message_id=message_id,
            version=1,
            settings=chat_auth.settings,
        )
        assert repeated.id == snapshot.id
        assert repeated.text == "selected original"


@pytest.mark.asyncio
async def test_photo_attachment_access_and_cleanup(
    couple: tuple[Account, Account, Account, str],
    chat_auth: Auth,
    sessions: Any,
    fake_storage: Any,
) -> None:
    alice, bob, carol, chat_id = couple
    file = await add_photo(chat_auth, UUID(chat_id), UUID(alice.tokens["user"]["id"]))
    file_id = file.id
    file_key = file.key
    sent = await send(
        alice,
        chat_id,
        "with a photo",
        photo_ids=[file.id],
    )
    assert sent.status_code == 201, sent.text
    message_id = UUID(sent.json()["id"])
    assert sent.json()["photo_ids"] == [str(file.id)]

    own = await photos(alice, chat_id, message_id)
    assert own.status_code == 200, own.text
    assert own.headers["cache-control"] == "private, no-store"
    assert own.json()["items"][0]["url"].endswith(f"/{file.key}/photo")
    # Only the processed object is exposed; the original source stays private.
    assert "/source" not in own.json()["items"][0]["url"]
    assert (await photos(bob, chat_id, message_id)).status_code == 200
    assert (await photos(carol, chat_id, message_id)).status_code == 404

    # A member of another chat cannot read this photo through its message id.
    other = await create_chat(alice, carol)
    assert other.status_code == 201, other.text
    other_chat_id = other.json()["id"]
    other_photo = await add_photo(
        chat_auth, UUID(other_chat_id), UUID(alice.tokens["user"]["id"])
    )
    other_sent = await send(
        alice, other_chat_id, "another chat photo", photo_ids=[other_photo.id]
    )
    assert other_sent.status_code == 201, other_sent.text
    assert (
        await photos(bob, other_chat_id, UUID(other_sent.json()["id"]))
    ).status_code == 404

    foreign_file = await add_photo(
        chat_auth, UUID(chat_id), UUID(bob.tokens["user"]["id"])
    )
    rejected = await send(alice, chat_id, "not mine", photo_ids=[foreign_file.id])
    assert rejected.status_code == 422, rejected.text
    processed = await add_photo(
        chat_auth, UUID(chat_id), UUID(alice.tokens["user"]["id"]), status="processing"
    )
    rejected = await send(alice, chat_id, "not ready", photo_ids=[processed.id])
    assert rejected.status_code == 422, rejected.text

    assert (await remove(alice, chat_id, message_id)).status_code == 204
    assert (await photos(bob, chat_id, message_id)).status_code == 404
    evidence_response = await evidence(bob, chat_id, message_id)
    assert evidence_response.status_code == 200, evidence_response.text
    assert evidence_response.headers["cache-control"] == "private, no-store"
    assert evidence_response.json()["photos"][0]["id"] == str(file.id)

    # A member who left gets no new links. Links already handed out stay
    # valid until their own `photo_read_ttl`: they cannot be revoked.
    assert await leave_chat(chat_auth.db, UUID(chat_id), UUID(bob.tokens["user"]["id"]))
    await chat_auth.db.commit()
    assert (await photos(bob, chat_id, message_id)).status_code == 404

    with time_machine.travel(clock.now() + timedelta(days=31)):
        report = await purge_message_versions(sessions, chat_auth.settings)
    assert report["failed"] == 0
    assert report["files"] >= 1
    assert report["protected"] == 0
    assert (await evidence(bob, chat_id, message_id)).status_code == 404
    chat_auth.db.expire_all()
    assert await chat_auth.db.get(File, file_id) is None
    deleted = list(fake_storage.deleted)
    assert f"{file_key}/source" in deleted
    assert f"{file_key}/photo" in deleted
    assert f"{file_key}/preview" in deleted


@pytest.mark.asyncio
async def test_snapshot_photos_survive_message_and_chat_cleanup(  # noqa: PLR0915
    couple: tuple[Account, Account, Account, str],
    chat_auth: Auth,
    sessions: Any,
    fake_storage: Any,
) -> None:
    alice, bob, _, chat_id = couple
    alice_id = UUID(alice.tokens["user"]["id"])
    bob_id = UUID(bob.tokens["user"]["id"])

    gone_file = await add_photo(chat_auth, UUID(chat_id), alice_id)
    sent = await send(alice, chat_id, "photo will disappear", photo_ids=[gone_file.id])
    gone_id = UUID(sent.json()["id"])
    assert (await remove(alice, chat_id, gone_id)).status_code == 204
    gone_snapshot = await snapshot_message(
        chat_auth.db,
        complaint_id=uuid4(),
        message_id=gone_id,
        settings=chat_auth.settings,
    )

    kept_file = await add_photo(chat_auth, UUID(chat_id), alice_id)
    sent = await send(alice, chat_id, "visible with photo", photo_ids=[kept_file.id])
    kept_id = UUID(sent.json()["id"])
    kept_snapshot = await snapshot_message(
        chat_auth.db,
        complaint_id=uuid4(),
        message_id=kept_id,
        settings=chat_auth.settings,
    )
    await chat_auth.db.commit()

    assert gone_snapshot.text == "photo will disappear"
    assert gone_snapshot.version == 1
    assert kept_snapshot.text == "visible with photo"
    assert [
        row.key for row in await snapshot_photos(chat_auth.db, gone_snapshot.id)
    ] == [gone_file.key]
    assert [
        row.key for row in await snapshot_photos(chat_auth.db, kept_snapshot.id)
    ] == [kept_file.key]

    with time_machine.travel(clock.now() + timedelta(days=30, seconds=1)):
        report = await purge_message_versions(sessions, chat_auth.settings)
    assert report["failed"] == 0
    assert report["files"] >= 1
    assert report["protected"] >= 1
    chat_auth.db.expire_all()
    assert await chat_auth.db.get(File, gone_file.id) is None
    assert [
        row.key for row in await snapshot_photos(chat_auth.db, gone_snapshot.id)
    ] == [gone_file.key]
    deleted = list(fake_storage.deleted)
    assert f"{gone_file.key}/source" in deleted
    assert f"{gone_file.key}/photo" not in deleted
    assert f"{gone_file.key}/preview" not in deleted

    # Deleting the empty chat removes the visible message and its file row
    # too, while the complaint attachment keeps the processed objects.
    assert await leave_chat(chat_auth.db, UUID(chat_id), alice_id)
    assert await leave_chat(chat_auth.db, UUID(chat_id), bob_id)
    await chat_auth.db.commit()
    chat = await chat_auth.db.scalar(
        select(Chat)
        .where(Chat.id == UUID(chat_id))
        .execution_options(populate_existing=True)
    )
    assert chat is not None
    assert chat.empty_since is not None
    with time_machine.travel(
        chat.empty_since + chat_auth.settings.chat_retention + timedelta(seconds=1)
    ):
        purge = await retention.purge_empty_chats(sessions, chat_auth.settings)
    assert purge["failed"] == 0
    assert purge["chats"] == 1
    chat_auth.db.expire_all()
    assert await chat_auth.db.get(Chat, UUID(chat_id)) is None
    assert await chat_auth.db.get(File, kept_file.id) is None
    assert (
        await chat_auth.db.scalar(select(ChatMessage).where(ChatMessage.id == gone_id))
        is None
    )
    assert await chat_auth.db.get(ChatMessageSnapshot, gone_snapshot.id) is not None
    assert await chat_auth.db.get(ChatMessageSnapshot, kept_snapshot.id) is not None
    assert [
        row.key for row in await snapshot_photos(chat_auth.db, gone_snapshot.id)
    ] == [gone_file.key]
    assert [
        row.key for row in await snapshot_photos(chat_auth.db, kept_snapshot.id)
    ] == [kept_file.key]
    deleted = list(fake_storage.deleted)
    for photo in (gone_file, kept_file):
        assert f"{photo.key}/source" in deleted
        assert f"{photo.key}/photo" not in deleted
        assert f"{photo.key}/preview" not in deleted


@pytest.mark.asyncio
async def test_photo_order_follows_the_client(
    couple: tuple[Account, Account, Account, str], chat_auth: Auth
) -> None:
    alice, _, _, chat_id = couple
    owner = UUID(alice.tokens["user"]["id"])
    first = await add_photo(chat_auth, UUID(chat_id), owner)
    second = await add_photo(chat_auth, UUID(chat_id), owner)
    sent = await send(alice, chat_id, "ordered photos", photo_ids=[second.id, first.id])
    assert sent.status_code == 201, sent.text
    assert sent.json()["photo_ids"] == [str(second.id), str(first.id)]

    chat_auth.db.expire_all()
    rows = list(
        await chat_auth.db.scalars(
            select(File)
            .where(File.id.in_([first.id, second.id]))
            .order_by(File.message_position)
        )
    )
    assert [row.id for row in rows] == [second.id, first.id]


@pytest.mark.asyncio
async def test_chat_photo_upload_is_chat_scoped(
    couple: tuple[Account, Account, Account, str], chat_auth: Auth, fake_storage: Any
) -> None:
    alice, bob, carol, chat_id = couple
    assert fake_storage is FakeStorage
    response = await alice.auth.client.post(
        f"{ROOT}/{chat_id}/photo-uploads",
        headers={"Idempotency-Key": str(uuid4()), **bearer(alice)},
    )
    assert response.status_code == 201, response.text
    body = response.json()
    file_id = UUID(body["file"]["id"])
    file = await chat_auth.db.get(File, file_id)
    assert file is not None
    assert file.chat_id == UUID(chat_id)
    assert file.purpose == "chat_photo"

    denied = await bob.auth.client.post(
        f"{ROOT}/{chat_id}/photo-uploads/{file_id}/complete",
        headers={"Idempotency-Key": str(uuid4()), **bearer(bob)},
    )
    assert denied.status_code == 404, denied.text
    completed = await alice.auth.client.post(
        f"{ROOT}/{chat_id}/photo-uploads/{file_id}/complete",
        headers={"Idempotency-Key": str(uuid4()), **bearer(alice)},
    )
    assert completed.status_code == 202, completed.text
    assert completed.json()["status"] == "processing"
    assert (
        await carol.auth.client.post(
            f"{ROOT}/{chat_id}/photo-uploads",
            headers={"Idempotency-Key": str(uuid4()), **bearer(carol)},
        )
    ).status_code == 404


@pytest.mark.asyncio
async def test_concurrent_edit_and_delete_keep_a_deleted_message_deleted(
    couple: tuple[Account, Account, Account, str], chat_auth: Auth
) -> None:
    alice, _, _, chat_id = couple
    sent = await send(alice, chat_id, "race original")
    message_id = UUID(sent.json()["id"])

    async def edit_call() -> httpx2.Response:
        return await edit(alice, chat_id, message_id, "race edited")

    async def delete_call() -> httpx2.Response:
        return await remove(alice, chat_id, message_id)

    edited, deleted = await asyncio.gather(edit_call(), delete_call())
    assert edited.status_code in {200, 409}, edited.text
    assert deleted.status_code == 204, deleted.text
    assert (await edit(alice, chat_id, message_id, "resurrect")).status_code == 409
    assert (await remove(alice, chat_id, message_id)).status_code == 204
    page = await history(alice, chat_id)
    assert page.json()["items"] == []
    rows = list(
        await chat_auth.db.scalars(
            select(ChatMessageVersion).where(
                ChatMessageVersion.message_id == message_id
            )
        )
    )
    assert any(row.kind == "delete" for row in rows)
    if edited.status_code == 200:
        assert {row.kind for row in rows} == {"edit", "delete"}
    stored = await chat_auth.db.scalar(
        select(ChatMessage).where(ChatMessage.id == message_id)
    )
    assert stored is not None
    assert stored.deleted_at is not None
    assert stored.text == " "


@pytest.mark.asyncio
async def test_direct_service_double_edit_is_serialized(
    couple: tuple[Account, Account, Account, str], chat_auth: Auth, sessions: Any
) -> None:
    alice, _, _, chat_id = couple
    sent = await send(alice, chat_id, "direct original")
    message_id = UUID(sent.json()["id"])
    settings = chat_auth.settings

    async def one(text: str) -> bool:
        async with sessions() as db, db.begin():
            _, changed = await edit_message(
                db,
                chat_id=UUID(chat_id),
                message_id=message_id,
                editor_id=UUID(alice.tokens["user"]["id"]),
                text=text,
                settings=settings,
            )
            return changed

    results = await asyncio.gather(one("direct one"), one("direct two"))
    assert sorted(results) == [True, True]
    rows = list(
        await chat_auth.db.scalars(
            select(ChatMessageVersion).where(
                ChatMessageVersion.message_id == message_id
            )
        )
    )
    assert len(rows) == 2
    current = await chat_auth.db.scalar(
        select(ChatMessageHistory).where(ChatMessageHistory.id == message_id)
    )
    assert current is not None
    assert current.version == 3
    assert current.text in {"direct one", "direct two"}


@pytest.mark.asyncio
async def test_chat_change_events_are_metadata_only(
    couple: tuple[Account, Account, Account, str],
    chat_auth: Auth,
    sessions: Any,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    alice, _, _, chat_id = couple
    sent = await send(alice, chat_id, "event original")
    message_id = UUID(sent.json()["id"])
    assert (await edit(alice, chat_id, message_id, "event edited")).status_code == 200
    assert (await remove(alice, chat_id, message_id)).status_code == 204

    rows = list(
        await chat_auth.db.scalars(
            select(OutboxMessage)
            .where(OutboxMessage.topic == MESSAGE_TOPIC)
            .order_by(OutboxMessage.available_at, OutboxMessage.id)
        )
    )
    payloads = [row.payload for row in rows]
    assert [payload["action"] for payload in payloads] == [
        "created",
        "edited",
        "deleted",
    ]
    assert all("text" not in payload for payload in payloads)
    assert "event original" not in repr(payloads)
    assert "event edited" not in repr(payloads)

    calls: list[tuple[str, dict[str, Any], UUID]] = []

    async def fake_publish(
        channel: str, data: dict[str, Any], delivery_id: UUID
    ) -> None:
        calls.append((channel, data, delivery_id))

    monkeypatch.setattr("campus.modules.chat.consumers.publish_channel", fake_publish)
    await process_outbox(sessions, chat_auth.settings)
    chat_calls = [call for call in calls if call[0] == f"chat:{chat_id}"]
    assert [call[1]["action"] for call in chat_calls] == [
        "created",
        "edited",
        "deleted",
    ]
    assert all("text" not in call[1] for call in chat_calls)
    assert "event original" not in repr(chat_calls)
    assert "event edited" not in repr(chat_calls)


@pytest.mark.asyncio
async def test_legacy_outbox_text_is_removed_before_publication(
    chat_auth: Auth,
    sessions: Any,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    chat_id = uuid4()
    legacy = OutboxMessage(
        topic=MESSAGE_TOPIC,
        payload={
            "action": "created",
            "chat_id": str(chat_id),
            "message_id": str(uuid4()),
            "sequence": 1,
            "text": "legacy secret",
        },
        available_at=clock.now(),
    )
    chat_auth.db.add(legacy)
    await chat_auth.db.commit()

    calls: list[tuple[str, dict[str, Any], UUID]] = []

    async def fake_publish(
        channel: str, data: dict[str, Any], delivery_id: UUID
    ) -> None:
        calls.append((channel, data, delivery_id))

    monkeypatch.setattr("campus.modules.chat.consumers.publish_channel", fake_publish)
    assert await process_outbox(sessions, chat_auth.settings) == 1
    published = [call for call in calls if call[0] == f"chat:{chat_id}"]
    assert len(published) == 1
    assert "text" not in published[0][1]

    chat_auth.db.expire_all()
    stored = await chat_auth.db.get(OutboxMessage, legacy.id)
    assert stored is not None
    assert "text" not in stored.payload
