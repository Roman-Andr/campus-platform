"""Group chats of events and purchases on real PostgreSQL.

The server contract of #83: one group per listing, membership derived from
the accepted participation in the same transaction, immediate server-side
loss of history and sending, forced realtime unsubscribe, and no duplicate
chat or membership under a race. The tests use the real chat and listing
routers, the real Centrifugo token secret and a database owned by the test.
"""

import asyncio
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Any
from uuid import UUID, uuid4

import httpx2
import pytest
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker

from campus.core import clock
from campus.core.db import create_session_factory
from campus.core.outbox import OutboxMessage, process_outbox
from campus.modules.chat import (
    Chat,
    ChatMember,
    ChatMessage,
    sync_group_chat,
)
from campus.modules.chat.models import GROUP_CHATS
from campus.modules.listings import Interaction, InteractionStatus, Listing
from campus.modules.realtime import can_access, chat_channel
from campus.modules.realtime.models import ChannelGrant
from tests.test_chat import (
    add_category,
    add_places,
    bearer,
    chat_auth,
)
from tests.test_identity import Auth
from tests.test_profile import Account, Places, moscow_profile
from tests.test_realtime import FakeCentrifugo

__all__ = ["chat_auth"]

CHATS = "/api/v1/chats"
LISTINGS = "/api/v1/listings"
ME = "/api/v1/me"
REALTIME = "/api/v1/realtime"


def key() -> str:
    return str(uuid4())


def instant(value: datetime) -> str:
    return str(value.isoformat()).replace("+00:00", "Z")


@dataclass(frozen=True)
class Reference:
    places: Places
    category: UUID


@pytest.fixture
async def reference(chat_auth: Auth) -> Reference:
    places = await add_places(chat_auth.db)
    category = await add_category(chat_auth.db)
    await chat_auth.db.commit()
    return Reference(places, category)


@pytest.fixture
async def sessions(engine: AsyncEngine) -> async_sessionmaker[AsyncSession]:
    return create_session_factory(engine)


@pytest.fixture
def centrifugo(monkeypatch: pytest.MonkeyPatch) -> FakeCentrifugo:
    fake = FakeCentrifugo()
    monkeypatch.setattr(
        "campus.modules.realtime.consumers.centrifugo_client", lambda _settings: fake
    )
    return fake


async def account(auth: Auth, places: Places, email: str) -> Account:
    result = Account(auth, await auth.login(email=email))
    response = await result.put(moscow_profile(places))
    assert response.status_code == 200, response.text
    return result


async def request(
    account: Account,
    method: str,
    path: str = "",
    data: dict[str, Any] | None = None,
    key_value: str | None = None,
) -> httpx2.Response:
    return await account.auth.client.request(
        method,
        LISTINGS + path,
        json=data,
        headers={"Idempotency-Key": key_value or key(), **account.headers},
    )


async def publish_event(
    owner: Account, reference: Reference, **overrides: Any
) -> dict[str, Any]:
    response = await request(
        owner,
        "POST",
        "/events",
        {
            "category_id": str(reference.category),
            "title": "Campus concert",
            "description": "Meet in the hall",
            "starts_at": instant(clock.now() + timedelta(days=3)),
            "ends_at": instant(clock.now() + timedelta(days=3, hours=2)),
            "location": "Hall A",
            "capacity": 10,
            **overrides,
        },
    )
    assert response.status_code == 201, response.text
    return dict(response.json())


async def signup(
    account: Account,
    listing: dict[str, Any],
    *,
    queue: bool = False,
    key_value: str | None = None,
) -> httpx2.Response:
    return await request(
        account,
        "POST",
        f"/{listing['id']}/signup",
        {"join_queue": queue},
        key_value,
    )


async def cancel_interaction(
    account: Account,
    listing: dict[str, Any],
    interaction: dict[str, Any],
    **body: Any,
) -> httpx2.Response:
    return await request(
        account,
        "POST",
        f"/{listing['id']}/interactions/{interaction['id']}/transition",
        {"status": "cancelled", **body},
    )


async def publish_purchase(
    owner: Account, reference: Reference, **overrides: Any
) -> dict[str, Any]:
    response = await request(
        owner,
        "POST",
        "/purchases",
        {
            "category_id": str(reference.category),
            "title": "A bag of rice",
            "description": "Bulk order",
            "price_per_unit": "12.50",
            "min_units": 2,
            "max_units": 20,
            "collection_deadline": instant(clock.now() + timedelta(days=3)),
            **overrides,
        },
    )
    assert response.status_code == 201, response.text
    return dict(response.json())


async def join_purchase(
    account: Account, listing: dict[str, Any], units: int = 1
) -> httpx2.Response:
    return await request(
        account,
        "POST",
        f"/{listing['id']}/shares",
        {"units": units},
    )


async def chats(account: Account, **params: Any) -> list[dict[str, Any]]:
    response = await account.auth.client.get(
        CHATS, params=params, headers=bearer(account)
    )
    assert response.status_code == 200, response.text
    return list(response.json()["items"])


async def group_of(account: Account, listing: dict[str, Any]) -> dict[str, Any]:
    items = await chats(account, kind=listing["kind"])
    matches = [item for item in items if item["listing_id"] == listing["id"]]
    assert len(matches) == 1, items
    return dict(matches[0])


async def members(account: Account, chat_id: str) -> httpx2.Response:
    return await account.auth.client.get(
        f"{CHATS}/{chat_id}/members", headers=bearer(account)
    )


async def history(account: Account, chat_id: str) -> httpx2.Response:
    return await account.auth.client.get(
        f"{CHATS}/{chat_id}/messages", headers=bearer(account)
    )


async def send(
    account: Account,
    chat_id: str,
    text: str,
    *,
    client_id: UUID | None = None,
    key_value: str | None = None,
) -> httpx2.Response:
    return await account.auth.client.post(
        f"{CHATS}/{chat_id}/messages",
        json={"client_id": str(client_id or uuid4()), "text": text},
        headers={"Idempotency-Key": key_value or key(), **bearer(account)},
    )


async def subscription_token(
    account: Account, channel: str, key_value: str | None = None
) -> httpx2.Response:
    return await account.auth.client.post(
        f"{REALTIME}/subscription-token",
        json={"channel": channel},
        headers={"Idempotency-Key": key_value or key(), **bearer(account)},
    )


async def block(account: Account, target: Account) -> httpx2.Response:
    return await account.auth.client.post(
        f"{ME}/blocks",
        json={"user_id": target.tokens["user"]["id"]},
        headers={"Idempotency-Key": key(), **bearer(account)},
    )


async def group_chats(db: AsyncSession) -> list[Chat]:
    return list(
        await db.scalars(
            select(Chat).where(Chat.kind.in_(GROUP_CHATS)).order_by(Chat.created_at)
        )
    )


async def member_of(
    db: AsyncSession, chat_id: UUID, user_id: UUID
) -> ChatMember | None:
    return await db.get(ChatMember, (chat_id, user_id))


async def test_first_signup_creates_one_group_and_members(
    chat_auth: Auth, reference: Reference
) -> None:
    owner = await account(chat_auth, reference.places, "owner@university.example")
    alice = await account(chat_auth, reference.places, "alice@university.example")
    bob = await account(chat_auth, reference.places, "bob@university.example")
    listing = await publish_event(owner, reference)

    assert await chats(owner) == []

    first = await signup(alice, listing)
    assert first.status_code == 200, first.text
    interaction = first.json()["interaction"]
    assert first.json()["result"] == "registered"

    alice_chat = await group_of(alice, listing)
    owner_chat = await group_of(owner, listing)
    assert alice_chat["id"] == owner_chat["id"]
    assert alice_chat["kind"] == "event"
    assert alice_chat["organizer_id"] == owner.tokens["user"]["id"]
    assert alice_chat["listing_title"] == "Campus concert"
    assert {person["id"] for person in alice_chat["participants"]} == {
        owner.tokens["user"]["id"],
        alice.tokens["user"]["id"],
    }

    composition = await members(owner, alice_chat["id"])
    assert composition.status_code == 200, composition.text
    assert [(item["is_organizer"], item["id"]) for item in composition.json()] == [
        (True, owner.tokens["user"]["id"]),
        (False, alice.tokens["user"]["id"]),
    ]

    # A repeated signup, with a new Idempotency-Key, returns the stored
    # interaction and must not create a second chat or membership.
    repeated = await signup(alice, listing)
    assert repeated.status_code == 200, repeated.text
    assert repeated.json()["interaction"]["id"] == interaction["id"]
    assert len(await group_chats(chat_auth.db)) == 1
    assert await chat_auth.db.scalar(select(func.count()).select_from(ChatMember)) == 2

    assert (await signup(bob, listing)).status_code == 200
    assert len(await group_chats(chat_auth.db)) == 1
    assert await chat_auth.db.scalar(select(func.count()).select_from(ChatMember)) == 3
    assert len((await members(owner, alice_chat["id"])).json()) == 3


async def test_parallel_first_signups_share_one_chat(
    chat_auth: Auth, reference: Reference
) -> None:
    owner = await account(chat_auth, reference.places, "owner@university.example")
    listing = await publish_event(owner, reference)
    people = [
        await account(
            chat_auth, reference.places, f"parallel{number}@university.example"
        )
        for number in range(8)
    ]
    replies = await asyncio.gather(*(signup(person, listing) for person in people))
    assert all(reply.status_code == 200 for reply in replies), [
        reply.text for reply in replies
    ]
    assert all(reply.json()["result"] == "registered" for reply in replies)

    groups = await group_chats(chat_auth.db)
    assert len(groups) == 1
    group_id = groups[0].id
    active = list(
        await chat_auth.db.scalars(
            select(ChatMember.user_id).where(
                ChatMember.chat_id == group_id,
                ChatMember.left_at.is_(None),
            )
        )
    )
    assert len(active) == 9
    for person in people:
        assert (await group_of(person, listing))["id"] == str(group_id)


@pytest.mark.parametrize("state", ["organizer", "accepted", "removed", "outsider"])
async def test_group_rights_matrix(
    chat_auth: Auth, reference: Reference, state: str
) -> None:
    owner = await account(chat_auth, reference.places, "owner@university.example")
    alice = await account(chat_auth, reference.places, "alice@university.example")
    outsider = await account(chat_auth, reference.places, "outsider@university.example")
    listing = await publish_event(owner, reference)
    interaction = (await signup(alice, listing)).json()["interaction"]
    chat_id = (await group_of(alice, listing))["id"]

    actor = {
        "organizer": owner,
        "accepted": alice,
        "removed": alice,
        "outsider": outsider,
    }[state]
    if state == "removed":
        cancelled = await cancel_interaction(actor, listing, interaction)
        assert cancelled.status_code == 200, cancelled.text

    expected = 200 if state in {"organizer", "accepted"} else 404
    assert (
        await actor.auth.client.get(f"{CHATS}/{chat_id}", headers=bearer(actor))
    ).status_code == expected
    assert (await history(actor, chat_id)).status_code == expected
    assert (await members(actor, chat_id)).status_code == expected
    sent = await send(actor, chat_id, f"a message from {state}")
    assert sent.status_code == (201 if expected == 200 else 404), sent.text

    token = await subscription_token(actor, f"chat:{chat_id}")
    assert token.status_code == (200 if expected == 200 else 403), token.text

    listed = await chats(actor, kind="event")
    assert (chat_id in {item["id"] for item in listed}) is (expected == 200)


async def test_removal_loses_history_and_old_token_immediately(
    chat_auth: Auth, reference: Reference
) -> None:
    owner = await account(chat_auth, reference.places, "owner@university.example")
    alice = await account(chat_auth, reference.places, "alice@university.example")
    listing = await publish_event(owner, reference)
    interaction = (await signup(alice, listing)).json()["interaction"]
    chat_id = (await group_of(alice, listing))["id"]
    stale_key = key()
    assert (
        await subscription_token(alice, f"chat:{chat_id}", stale_key)
    ).status_code == 200
    stored = await send(alice, chat_id, "old secret", key_value=key())
    assert stored.status_code == 201, stored.text

    cancelled = await cancel_interaction(alice, listing, interaction)
    assert cancelled.status_code == 200, cancelled.text

    channel = chat_channel(UUID(chat_id)).name
    alice_id = UUID(alice.tokens["user"]["id"])
    assert await can_access(chat_auth.db, channel, alice_id) is False
    grant = await chat_auth.db.get(ChannelGrant, (channel, alice_id))
    assert grant is not None
    assert grant.revoked_at is not None

    # The stored token response is never served again, not even on a replay
    # of the same Idempotency-Key, and a fresh request is refused too.
    replay = await subscription_token(alice, channel, stale_key)
    assert replay.status_code == 403, replay.text
    assert replay.json()["code"] == "realtime_channel_forbidden"
    assert (await subscription_token(alice, channel)).status_code == 403
    recovery = await alice.auth.client.post(
        f"{REALTIME}/recover",
        json={"channel": channel},
        headers={"Idempotency-Key": key(), **bearer(alice)},
    )
    assert recovery.status_code == 403, recovery.text

    # History and editing are not reachable by direct identifiers either.
    assert (await history(alice, chat_id)).status_code == 404
    edited = await alice.auth.client.patch(
        f"{CHATS}/{chat_id}/messages/{stored.json()['id']}",
        json={"text": "changed"},
        headers={"Idempotency-Key": key(), **bearer(alice)},
    )
    assert edited.status_code == 404, edited.text
    search = await alice.auth.client.get(
        f"{CHATS}/search", params={"q": "secret"}, headers=bearer(alice)
    )
    assert search.status_code == 200
    assert search.json()["items"] == []

    member = await member_of(
        chat_auth.db, UUID(chat_id), UUID(alice.tokens["user"]["id"])
    )
    assert member is not None
    assert member.left_at is not None
    unsubscribe = list(
        await chat_auth.db.scalars(
            select(OutboxMessage).where(
                OutboxMessage.topic == "realtime.unsubscribe",
                OutboxMessage.payload["channel"].astext == channel,
            )
        )
    )
    assert len(unsubscribe) == 1

    # The organiser stays in the group and sees only the active composition.
    room = await group_of(owner, listing)
    assert {person["id"] for person in room["participants"]} == {
        owner.tokens["user"]["id"]
    }
    assert len((await members(owner, chat_id)).json()) == 1


async def test_reacceptance_restores_membership_and_history(
    chat_auth: Auth, reference: Reference
) -> None:
    owner = await account(chat_auth, reference.places, "owner@university.example")
    alice = await account(chat_auth, reference.places, "alice@university.example")
    listing = await publish_event(owner, reference)
    first = (await signup(alice, listing)).json()["interaction"]
    chat_id = (await group_of(alice, listing))["id"]
    assert (await send(alice, chat_id, "before leaving")).status_code == 201
    assert (await cancel_interaction(alice, listing, first)).status_code == 200
    assert (await history(alice, chat_id)).status_code == 404

    again = await signup(alice, listing)
    assert again.status_code == 200, again.text
    assert again.json()["result"] == "registered"
    assert again.json()["interaction"]["id"] != first["id"]
    assert (await group_of(alice, listing))["id"] == chat_id
    restored = await history(alice, chat_id)
    assert restored.status_code == 200, restored.text
    assert [item["text"] for item in restored.json()["items"]] == ["before leaving"]
    assert (await send(alice, chat_id, "after returning")).status_code == 201


@pytest.mark.parametrize(("status", "kept"), [("completed", True), ("no_show", False)])
async def test_projection_keeps_completed_participation_and_drops_no_show(
    chat_auth: Auth,
    reference: Reference,
    sessions: async_sessionmaker[AsyncSession],
    status: str,
    kept: bool,
) -> None:
    owner = await account(chat_auth, reference.places, "owner@university.example")
    alice = await account(chat_auth, reference.places, "alice@university.example")
    listing = await publish_event(owner, reference)
    interaction = (await signup(alice, listing)).json()["interaction"]
    chat_id = UUID((await group_of(alice, listing))["id"])
    alice_id = UUID(alice.tokens["user"]["id"])

    # A completed participation is not a leave; a no-show ends it.
    async with sessions() as db, db.begin():
        stored_interaction = await db.get(Interaction, UUID(interaction["id"]))
        stored_listing = await db.get(Listing, UUID(listing["id"]))
        assert stored_interaction is not None
        assert stored_listing is not None
        stored_interaction.status = status
        await db.flush()
        await sync_group_chat(db, stored_listing)
        member = await member_of(db, chat_id, alice_id)
        assert member is not None
        assert (member.left_at is None) is kept
        assert await can_access(db, f"chat:{chat_id}", alice_id) is kept


async def test_late_projection_cannot_return_removed_participant(
    chat_auth: Auth, reference: Reference, sessions: async_sessionmaker[AsyncSession]
) -> None:
    owner = await account(chat_auth, reference.places, "owner@university.example")
    alice = await account(chat_auth, reference.places, "alice@university.example")
    listing = await publish_event(owner, reference)
    interaction = (await signup(alice, listing)).json()["interaction"]
    chat_id = UUID((await group_of(alice, listing))["id"])
    # A repeated projection of the same state changes nothing.
    async with sessions() as db, db.begin():
        stored = await db.get(Listing, UUID(listing["id"]))
        assert stored is not None
        await sync_group_chat(db, stored)
        await sync_group_chat(db, stored)
    assert len(await group_chats(chat_auth.db)) == 1
    assert (
        await chat_auth.db.scalar(
            select(func.count())
            .select_from(ChatMember)
            .where(ChatMember.chat_id == chat_id)
        )
        == 2
    )
    assert (await cancel_interaction(alice, listing, interaction)).status_code == 200

    # A delayed projector run re-reads the domain and must converge to the
    # current state instead of replaying the old acceptance.
    async with sessions() as db, db.begin():
        stored = await db.get(Listing, UUID(listing["id"]))
        assert stored is not None
        projected = await sync_group_chat(db, stored)
        assert projected is not None
        assert projected.id == chat_id
    async with sessions() as db:
        member = await member_of(db, chat_id, UUID(alice.tokens["user"]["id"]))
        assert member is not None
        assert member.left_at is not None

    # A rollback of a composition change leaves the chat untouched and the
    # current membership active.
    async with sessions() as db:
        stored = await db.get(Listing, UUID(listing["id"]))
        assert stored is not None
        db.add(
            Interaction(
                listing_id=stored.id,
                participant_id=UUID(alice.tokens["user"]["id"]),
                slot=None,
                status=InteractionStatus.ACCEPTED,
                meeting=None,
                options=[],
            )
        )
        await db.flush()
        await sync_group_chat(db, stored)
        await db.rollback()
    async with sessions() as db:
        member = await member_of(db, chat_id, UUID(alice.tokens["user"]["id"]))
        assert member is not None
        assert member.left_at is not None
        assert (
            await can_access(
                db, chat_channel(chat_id).name, UUID(alice.tokens["user"]["id"])
            )
            is False
        )


async def test_parallel_send_and_cancel_do_not_leak_after_leaving(
    chat_auth: Auth, reference: Reference
) -> None:
    owner = await account(chat_auth, reference.places, "owner@university.example")
    alice = await account(chat_auth, reference.places, "alice@university.example")
    listing = await publish_event(owner, reference)
    interaction = (await signup(alice, listing)).json()["interaction"]
    chat_id = (await group_of(alice, listing))["id"]

    sent, cancelled = await asyncio.gather(
        send(alice, chat_id, "racing"),
        cancel_interaction(alice, listing, interaction),
    )
    assert cancelled.status_code == 200, cancelled.text
    assert sent.status_code in (201, 404), sent.text
    if sent.status_code == 201:
        stored = await chat_auth.db.scalar(
            select(ChatMember).where(
                ChatMember.chat_id == UUID(chat_id),
                ChatMember.user_id == UUID(alice.tokens["user"]["id"]),
            )
        )
        assert stored is not None
        assert stored.left_at is not None
    after = await send(alice, chat_id, "after leaving")
    assert after.status_code == 404, after.text
    room = await group_of(owner, listing)
    assert {person["id"] for person in room["participants"]} == {
        owner.tokens["user"]["id"]
    }


async def test_group_message_is_independent_of_personal_block(
    chat_auth: Auth, reference: Reference
) -> None:
    owner = await account(chat_auth, reference.places, "owner@university.example")
    alice = await account(chat_auth, reference.places, "alice@university.example")
    listing = await publish_event(owner, reference)
    await signup(alice, listing)
    chat_id = (await group_of(owner, listing))["id"]
    assert (await block(alice, owner)).status_code == 201

    assert (await send(alice, chat_id, "the group still works")).status_code == 201
    assert (await send(owner, chat_id, "and still answers")).status_code == 201
    assert (await history(alice, chat_id)).status_code == 200
    assert len((await history(alice, chat_id)).json()["items"]) == 2

    # A personal dialog is still refused; the group did not open one.
    personal = await alice.auth.client.post(
        CHATS,
        json={"recipient_id": owner.tokens["user"]["id"]},
        headers={"Idempotency-Key": key(), **bearer(alice)},
    )
    assert personal.status_code == 403, personal.text


async def test_group_message_idempotency(chat_auth: Auth, reference: Reference) -> None:
    owner = await account(chat_auth, reference.places, "owner@university.example")
    alice = await account(chat_auth, reference.places, "alice@university.example")
    listing = await publish_event(owner, reference)
    await signup(alice, listing)
    chat_id = (await group_of(alice, listing))["id"]
    idem = key()
    client_id = uuid4()
    first = await send(alice, chat_id, "same body", client_id=client_id, key_value=idem)
    assert first.status_code == 201, first.text
    replay = await send(
        alice, chat_id, "same body", client_id=client_id, key_value=idem
    )
    assert replay.status_code == 201, replay.text
    assert replay.headers["Idempotent-Replayed"] == "true"
    assert replay.json()["id"] == first.json()["id"]

    reused = await send(
        alice, chat_id, "different body", client_id=client_id, key_value=idem
    )
    assert reused.status_code == 422, reused.text
    assert reused.json()["code"] == "idempotency_key_reused"

    conflict = await send(
        alice, chat_id, "different body", client_id=client_id, key_value=key()
    )
    assert conflict.status_code == 409, conflict.text
    assert conflict.json()["code"] == "chat_message_conflict"
    assert (
        await chat_auth.db.scalar(
            select(func.count())
            .select_from(ChatMessage)
            .where(ChatMessage.chat_id == UUID(chat_id))
        )
        == 1
    )


async def test_outbox_publishes_metadata_and_unsubscribes_removed_member(
    chat_auth: Auth,
    reference: Reference,
    sessions: async_sessionmaker[AsyncSession],
    centrifugo: FakeCentrifugo,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    owner = await account(chat_auth, reference.places, "owner@university.example")
    alice = await account(chat_auth, reference.places, "alice@university.example")
    listing = await publish_event(owner, reference)
    interaction = (await signup(alice, listing)).json()["interaction"]
    chat_id = (await group_of(alice, listing))["id"]

    calls: list[tuple[str, dict[str, Any]]] = []

    async def fake_publish(
        channel: str, data: dict[str, Any], _delivery_id: UUID
    ) -> None:
        calls.append((channel, data))

    monkeypatch.setattr("campus.modules.chat.consumers.publish_channel", fake_publish)
    assert (await send(owner, chat_id, "metadata only")).status_code == 201
    await chat_auth.db.execute(
        delete(OutboxMessage).where(OutboxMessage.topic != "chat.message")
    )
    await chat_auth.db.commit()
    assert await process_outbox(sessions, chat_auth.settings) == 1
    assert calls
    assert calls[0][0] == f"chat:{chat_id}"
    assert "text" not in calls[0][1]
    assert calls[0][1]["action"] == "created"

    assert (await cancel_interaction(alice, listing, interaction)).status_code == 200
    await process_outbox(sessions, chat_auth.settings)
    assert (f"chat:{chat_id}", alice.tokens["user"]["id"]) in centrifugo.unsubscribed
    assert (
        await can_access(
            chat_auth.db,
            chat_channel(UUID(chat_id)).name,
            UUID(alice.tokens["user"]["id"]),
        )
        is False
    )


async def test_purchase_group_follows_shares(
    chat_auth: Auth, reference: Reference
) -> None:
    owner = await account(chat_auth, reference.places, "owner@university.example")
    alice = await account(chat_auth, reference.places, "alice@university.example")
    bob = await account(chat_auth, reference.places, "bob@university.example")
    listing = await publish_purchase(owner, reference)
    assert (await join_purchase(alice, listing, 2)).status_code == 201
    assert (await join_purchase(bob, listing, 1)).status_code == 201

    room = await group_of(owner, listing)
    assert room["kind"] == "purchase"
    assert {person["id"] for person in room["participants"]} == {
        owner.tokens["user"]["id"],
        alice.tokens["user"]["id"],
        bob.tokens["user"]["id"],
    }
    assert (await join_purchase(bob, listing, 1)).status_code == 409

    left = await request(alice, "DELETE", f"/{listing['id']}/shares/me")
    assert left.status_code == 204, left.text
    assert (await history(alice, room["id"])).status_code == 404
    remaining = await members(owner, room["id"])
    assert {item["id"] for item in remaining.json()} == {
        owner.tokens["user"]["id"],
        bob.tokens["user"]["id"],
    }

    rejoined = await join_purchase(alice, listing, 2)
    assert rejoined.status_code == 201, rejoined.text
    assert (await group_of(alice, listing))["id"] == room["id"]
    assert (await history(alice, room["id"])).status_code == 200

    cancelled = await request(
        owner, "POST", f"/{listing['id']}/cancel", {"reason": "no supplier"}
    )
    assert cancelled.status_code == 200, cancelled.text
    for person in (alice, bob):
        assert (await history(person, room["id"])).status_code == 404
    # The organiser is always a member of the group of the listing.
    assert (await history(owner, room["id"])).status_code == 200


async def test_group_chat_leave_endpoint_is_managed_by_the_domain(
    chat_auth: Auth, reference: Reference
) -> None:
    owner = await account(chat_auth, reference.places, "owner@university.example")
    alice = await account(chat_auth, reference.places, "alice@university.example")
    listing = await publish_event(owner, reference)
    await signup(alice, listing)
    chat_id = (await group_of(alice, listing))["id"]

    response = await alice.auth.client.delete(
        f"{CHATS}/{chat_id}/membership",
        headers={"Idempotency-Key": key(), **bearer(alice)},
    )
    assert response.status_code == 409, response.text
    assert response.json()["code"] == "chat_group_managed"
    assert (await history(alice, chat_id)).status_code == 200
