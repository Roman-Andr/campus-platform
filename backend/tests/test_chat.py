"""Personal chats on PostgreSQL: rights, deduplication, order and delivery."""

import asyncio
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from contextvars import ContextVar
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID, uuid4

import httpx2
import pytest
import time_machine
from pydantic import SecretStr
from redis.asyncio import Redis
from sqlalchemy import delete, func, select, text, update
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker

from campus.api.app import create_app
from campus.core import clock
from campus.core.config import Settings
from campus.core.db import create_engine, create_session_factory
from campus.core.outbox import OutboxMessage, process_outbox
from campus.modules.chat import Chat, ChatMessage
from campus.modules.chat.service import create_personal_chat, post_message
from campus.modules.identity import (
    Role,
    RoleAssignment,
    User,
    seed_documents,
    serialize_contact_pair,
)
from campus.modules.listings import Category, Interaction
from campus.modules.university import (
    AccountType,
    City,
    Dormitory,
    EmailDomain,
    Faculty,
)
from tests.test_identity import SECRET, Auth
from tests.test_profile import Account, Places, moscow_profile
from tests.web_app import serve

__all__ = ["chat_auth", "limited_auth"]

ROOT = "/api/v1/chats"
REALTIME = "/api/v1/realtime"
LISTINGS = "/api/v1/listings"


@asynccontextmanager
async def running_auth(
    database_url: str,
    redis_url: str,
    token_secret: str,
    **overrides: Any,
) -> AsyncIterator[Auth]:
    """The API under test with the real routers and chosen chat settings."""
    settings = Settings(
        database_url=SecretStr(database_url),
        redis_url=SecretStr(redis_url),
        auth_secret_key=SecretStr(SECRET),
        centrifugo_token_hmac_secret=SecretStr(token_secret),
        centrifugo_api_url="http://centrifugo.test/api",
        centrifugo_api_key=SecretStr("testing-centrifugo-api-key"),
        **overrides,
    )
    engine = create_engine(settings)
    async with (
        create_session_factory(engine)() as db,
        Redis.from_url(redis_url) as redis,
    ):
        await redis.flushdb()
        db.add_all(
            [
                EmailDomain(
                    domain="university.example", account_type=AccountType.STUDENT
                ),
                EmailDomain(domain="staff.example", account_type=AccountType.EMPLOYEE),
            ]
        )
        await seed_documents(db)
        await db.commit()
        app = create_app(settings)
        async with serve(app) as client:
            yield Auth(client, db, settings, redis, app)
    await engine.dispose()


@pytest.fixture
async def chat_auth(
    database_url: str, redis_url: str, centrifugo_config: Any
) -> AsyncIterator[Auth]:
    async with running_auth(
        database_url, redis_url, centrifugo_config.token_secret
    ) as auth:
        yield auth


@pytest.fixture
async def limited_auth(
    database_url: str, redis_url: str, centrifugo_config: Any
) -> AsyncIterator[Auth]:
    """A small message limit, so boundary and concurrency checks stay cheap."""
    async with running_auth(
        database_url,
        redis_url,
        centrifugo_config.token_secret,
        chat_message_limit=3,
        chat_message_window=timedelta(minutes=1),
    ) as auth:
        yield auth


@pytest.fixture
async def sessions(engine: AsyncEngine) -> async_sessionmaker[AsyncSession]:
    return create_session_factory(engine)


@dataclass(frozen=True)
class Reference:
    """Reference data of two cities plus a listing category."""

    places: Places
    category: UUID


@pytest.fixture
async def reference(chat_auth: Auth) -> Reference:
    db = chat_auth.db
    places = await add_places(db)
    category = await add_category(db)
    await db.commit()
    return Reference(places, category)


async def add_places(db: AsyncSession) -> Places:
    moscow = City(
        code="moscow", name_ru="Москва", name_en="Moscow", timezone="Europe/Moscow"
    )
    perm = City(
        code="perm", name_ru="Пермь", name_en="Perm", timezone="Asia/Yekaterinburg"
    )
    db.add_all([moscow, perm])
    await db.flush()
    dubki = Dormitory(city_id=moscow.id, code="dubki", name_ru="Дубки", name_en="Dubki")
    economics = Faculty(
        city_id=moscow.id, code="economics", name_ru="Экономика", name_en="Economics"
    )
    perm_dormitory = Dormitory(
        city_id=perm.id, code="perm-1", name_ru="Общежитие 1", name_en="Dormitory 1"
    )
    perm_faculty = Faculty(city_id=perm.id, code="law", name_ru="Право", name_en="Law")
    db.add_all([dubki, economics, perm_dormitory, perm_faculty])
    await db.flush()
    return Places(
        moscow=moscow.id,
        dubki=dubki.id,
        economics=economics.id,
        perm=perm.id,
        perm_dormitory=perm_dormitory.id,
        perm_faculty=perm_faculty.id,
    )


async def add_category(db: AsyncSession) -> UUID:
    category = Category(code="things", name_ru="Вещи", name_en="Things")
    db.add(category)
    await db.flush()
    return category.id


async def account(
    auth: Auth,
    email: str,
    places: Places | None = None,
    *,
    staff: bool = False,
    **profile: Any,
) -> Account:
    result = Account(auth, await auth.login(email=email))
    if places is not None:
        response = await result.put(
            moscow_profile(places, course=None if staff else 2, **profile)
        )
        assert response.status_code == 200, response.text
    return result


def bearer(account: Account) -> dict[str, str]:
    return account.headers


async def create_chat(
    account: Account,
    recipient: Account | str,
    key: str | None = None,
    **body: Any,
) -> httpx2.Response:
    recipient_id = (
        recipient if isinstance(recipient, str) else recipient.tokens["user"]["id"]
    )
    return await account.auth.client.post(
        ROOT,
        json={"recipient_id": recipient_id, **body},
        headers={"Idempotency-Key": key or str(uuid4()), **bearer(account)},
    )


async def send_message(
    account: Account,
    chat_id: str,
    message: str,
    client_id: UUID | None = None,
    key: str | None = None,
) -> httpx2.Response:
    return await account.auth.client.post(
        f"{ROOT}/{chat_id}/messages",
        json={"client_id": str(client_id or uuid4()), "text": message},
        headers={"Idempotency-Key": key or str(uuid4()), **bearer(account)},
    )


async def history(account: Account, chat_id: str, **params: Any) -> httpx2.Response:
    return await account.auth.client.get(
        f"{ROOT}/{chat_id}/messages", params=params, headers=bearer(account)
    )


async def subscription_token(account: Account, channel: str) -> httpx2.Response:
    return await account.auth.client.post(
        f"{REALTIME}/subscription-token",
        json={"channel": channel},
        headers={"Idempotency-Key": str(uuid4()), **bearer(account)},
    )


async def publish_listing(account: Account, reference: Reference) -> dict[str, Any]:
    response = await account.auth.client.post(
        f"{LISTINGS}/giveaways",
        json={
            "category_id": str(reference.category),
            "title": "A desk",
            "description": "Collect on campus",
            "visibility": "city",
            "audience": "community",
        },
        headers={"Idempotency-Key": str(uuid4()), **bearer(account)},
    )
    assert response.status_code == 201, response.text
    result: dict[str, Any] = response.json()
    return result


async def messages_of(session: AsyncSession, chat_id: UUID) -> list[ChatMessage]:
    return list(
        await session.scalars(
            select(ChatMessage)
            .where(ChatMessage.chat_id == chat_id)
            .order_by(ChatMessage.sequence)
        )
    )


async def test_members_read_and_subscribe_others_do_not(chat_auth: Auth) -> None:
    alice = await account(chat_auth, "alice@university.example")
    bob = await account(chat_auth, "bob@university.example")
    mallory = await account(chat_auth, "mallory@university.example")

    response = await create_chat(alice, bob)
    assert response.status_code == 201, response.text
    chat = response.json()
    assert chat["kind"] == "personal"
    assert {p["id"] for p in chat["participants"]} == {
        alice.tokens["user"]["id"],
        bob.tokens["user"]["id"],
    }
    # The same pair maps to the same chat.
    assert (await create_chat(alice, bob)).status_code == 200

    assert (
        await bob.auth.client.get(f"{ROOT}/{chat['id']}", headers=bearer(bob))
    ).status_code == 200
    page = await history(bob, chat["id"])
    assert page.status_code == 200
    assert page.json()["items"] == []

    for member in (alice, bob):
        token = await subscription_token(member, f"chat:{chat['id']}")
        assert token.status_code == 200, token.text
        assert token.json()["channel"] == f"chat:{chat['id']}"

    assert (
        await mallory.auth.client.get(f"{ROOT}/{chat['id']}", headers=bearer(mallory))
    ).status_code == 404
    assert (await history(mallory, chat["id"])).status_code == 404
    assert (await send_message(mallory, chat["id"], "hello")).status_code == 404
    denied = await subscription_token(mallory, f"chat:{chat['id']}")
    assert denied.status_code == 403
    assert denied.json()["code"] == "realtime_channel_forbidden"

    # An administrative role gives no access to somebody else's messages.
    user_id = UUID(mallory.tokens["user"]["id"])
    chat_auth.db.add(RoleAssignment(user_id=user_id, role=Role.ADMINISTRATOR))
    await chat_auth.db.commit()
    assert (
        await mallory.auth.client.get(f"{ROOT}/{chat['id']}", headers=bearer(mallory))
    ).status_code == 404
    assert (
        await mallory.auth.client.get(
            f"{ROOT}/{chat['id']}/messages", headers=bearer(mallory)
        )
    ).status_code == 404


async def test_creation_rules_and_alumni(chat_auth: Auth) -> None:
    alice = await account(chat_auth, "alice@university.example")
    bob = await account(chat_auth, "bob@university.example")
    staff = await account(chat_auth, "staff@staff.example", staff=True)

    assert (await create_chat(staff, bob)).status_code == 201
    chat = (await create_chat(alice, bob)).json()

    user_id = UUID(bob.tokens["user"]["id"])
    await chat_auth.db.execute(
        update(User).where(User.id == user_id).values(account_type="alumni")
    )
    await chat_auth.db.commit()

    denied = await create_chat(bob, alice)
    assert denied.status_code == 403
    assert denied.json()["code"] == "chat_forbidden"
    # An existing chat stays writable for an alumnus.
    assert (await send_message(bob, chat["id"], "still here")).status_code == 201

    self_chat = await create_chat(alice, alice)
    assert self_chat.status_code == 422
    assert self_chat.json()["code"] == "chat_self"

    unknown = await create_chat(alice, str(uuid4()))
    assert unknown.status_code == 404


async def test_listing_and_interaction_links(
    chat_auth: Auth, reference: Reference
) -> None:
    alice = await account(chat_auth, "alice@university.example", reference.places)
    bob = await account(chat_auth, "bob@university.example", reference.places)
    perm = await account(
        chat_auth,
        "perm@university.example",
        reference.places,
        city_id=str(reference.places.perm),
        dormitory_id=str(reference.places.perm_dormitory),
        faculty_id=str(reference.places.perm_faculty),
    )
    listing = await publish_listing(alice, reference)

    linked = await create_chat(bob, alice, listing_id=listing["id"])
    assert linked.status_code == 201, linked.text
    assert linked.json()["listing_id"] == listing["id"]
    # The link never becomes a copy of the listing text.
    assert "title" not in linked.json()

    # A user outside the listing area cannot attach it to a chat.
    response = await create_chat(perm, alice, listing_id=listing["id"])
    assert response.status_code == 404
    assert response.json()["code"] == "not_found"

    interaction = Interaction(
        listing_id=UUID(listing["id"]),
        participant_id=UUID(bob.tokens["user"]["id"]),
        slot=1,
        status="accepted",
    )
    chat_auth.db.add(interaction)
    await chat_auth.db.commit()
    interaction_id = str(interaction.id)
    by_interaction = await create_chat(
        bob,
        alice,
        listing_id=listing["id"],
        interaction_id=interaction_id,
    )
    assert by_interaction.status_code == 201, by_interaction.text
    assert by_interaction.json()["interaction_id"] == interaction_id
    assert by_interaction.json()["listing_id"] == listing["id"]

    # A third user is not a party of the interaction.
    stranger = await account(chat_auth, "stranger@university.example")
    denied = await create_chat(stranger, alice, interaction_id=interaction_id)
    assert denied.status_code == 404


async def test_idempotency_and_client_uuid_dedup(chat_auth: Auth) -> None:
    alice = await account(chat_auth, "alice@university.example")
    bob = await account(chat_auth, "bob@university.example")
    chat_id = (await create_chat(alice, bob)).json()["id"]
    client_id = uuid4()
    key = str(uuid4())

    first = await send_message(alice, chat_id, "hello", client_id, key)
    assert first.status_code == 201, first.text
    message = first.json()
    assert message["sequence"] == 1
    assert message["client_id"] == str(client_id)

    replay = await send_message(alice, chat_id, "hello", client_id, key)
    assert replay.status_code == 201
    assert replay.headers["Idempotent-Replayed"] == "true"
    assert replay.json() == message

    # After the idempotency key is gone the client UUID still deduplicates.
    again = await send_message(alice, chat_id, "hello", client_id)
    assert again.status_code == 200
    assert again.json()["id"] == message["id"]

    reused = await send_message(alice, chat_id, "different", uuid4(), key)
    assert reused.status_code == 422
    assert reused.json()["code"] == "idempotency_key_reused"

    # Even after the Idempotency-Key retention the client UUID still wins.
    with time_machine.travel(clock.now() + timedelta(hours=25), tick=False):
        future = Account(
            chat_auth, await chat_auth.login(email="alice@university.example")
        )
        late = await send_message(future, chat_id, "hello", client_id)
        assert late.status_code == 200
        assert late.json()["id"] == message["id"]

        conflict = await send_message(future, chat_id, "other text", client_id)
        assert conflict.status_code == 409
        assert conflict.json()["code"] == "chat_message_conflict"
        assert conflict.headers["content-type"] == "application/problem+json"

    session = chat_auth.db
    session.expire_all()
    count = await session.scalar(
        select(func.count())
        .select_from(ChatMessage)
        .where(ChatMessage.chat_id == UUID(chat_id))
    )
    assert count == 1
    assert (await history(bob, chat_id)).json()["items"][0]["id"] == message["id"]


async def test_history_pagination_by_sequence(chat_auth: Auth) -> None:
    alice = await account(chat_auth, "alice@university.example")
    bob = await account(chat_auth, "bob@university.example")
    chat_id = (await create_chat(alice, bob)).json()["id"]
    for number in range(5):
        response = await send_message(alice, chat_id, f"message {number}")
        assert response.status_code == 201, response.text
        assert response.json()["sequence"] == number + 1

    seen: list[int] = []
    cursor: str | None = None
    while True:
        page = await history(bob, chat_id, size=2, cursor=cursor)
        assert page.status_code == 200, page.text
        body = page.json()
        seen += [item["sequence"] for item in body["items"]]
        cursor = body["next_page"]
        if cursor is None:
            break
    assert seen == [5, 4, 3, 2, 1]

    # New messages do not shift the pages already read: the cursor is a
    # sequence, not an offset, and gaps recover with ascending=true.
    assert (await send_message(bob, chat_id, "six")).json()["sequence"] == 6
    missed = await history(bob, chat_id, ascending=True, after_sequence=4)
    assert [item["sequence"] for item in missed.json()["items"]] == [5, 6]
    assert (await history(alice, chat_id, size=1, cursor=cursor)).status_code == 200


async def test_parallel_sends_get_unique_increasing_sequences(
    chat_auth: Auth,
) -> None:
    alice = await account(chat_auth, "alice@university.example")
    bob = await account(chat_auth, "bob@university.example")
    chat_id = (await create_chat(alice, bob)).json()["id"]

    responses = await asyncio.gather(
        *(
            send_message(alice if index % 2 else bob, chat_id, f"parallel {index}")
            for index in range(10)
        )
    )
    assert [response.status_code for response in responses] == [201] * 10

    session = chat_auth.db
    session.expire_all()
    stored = await messages_of(session, UUID(chat_id))
    assert [message.sequence for message in stored] == list(range(1, 11))
    assert len({message.text for message in stored}) == 10

    page = await history(alice, chat_id, size=100, ascending=True)
    assert [item["sequence"] for item in page.json()["items"]] == list(range(1, 11))


async def test_concurrent_creation_returns_one_chat(chat_auth: Auth) -> None:
    alice = await account(chat_auth, "alice@university.example")
    bob = await account(chat_auth, "bob@university.example")

    responses = await asyncio.gather(create_chat(alice, bob), create_chat(bob, alice))
    assert sorted(response.status_code for response in responses) == [200, 201], [
        response.text for response in responses
    ]
    assert len({response.json()["id"] for response in responses}) == 1

    session = chat_auth.db
    session.expire_all()
    count = await session.scalar(
        select(func.count())
        .select_from(Chat)
        .where(
            Chat.user_low_id.in_(
                [UUID(alice.tokens["user"]["id"]), UUID(bob.tokens["user"]["id"])]
            )
        )
    )
    assert count == 1


async def test_concurrent_create_and_send_take_pair_lock_before_chat(
    sessions: async_sessionmaker[AsyncSession],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Create and send share the lock order: pair lock, then chat row lock."""
    async with sessions() as setup:
        alice, bob = await local_users(setup)
        chat, _ = await create_personal_chat(
            setup, creator_id=alice.id, recipient_id=bob.id
        )
        await setup.commit()
        alice_id, bob_id, chat_id = alice.id, bob.id, chat.id

    create_started = asyncio.Event()
    send_at_pair = asyncio.Event()
    create_has_pair = asyncio.Event()
    marker: ContextVar[str | None] = ContextVar("lock-test", default=None)
    original = serialize_contact_pair

    async def coordinated(session: AsyncSession, first: UUID, second: UUID) -> None:
        owner = marker.get()
        if owner == "create":
            create_started.set()
            await send_at_pair.wait()
            await original(session, first, second)
            create_has_pair.set()
            return
        if owner == "send":
            send_at_pair.set()
            await create_has_pair.wait()
        await original(session, first, second)

    monkeypatch.setattr(
        "campus.modules.chat.service.serialize_contact_pair", coordinated
    )

    async def create_call() -> bool:
        marker.set("create")
        async with sessions() as session:
            _, created = await create_personal_chat(
                session, creator_id=alice_id, recipient_id=bob_id
            )
            await session.commit()
            return created

    async def send_call() -> bool:
        marker.set("send")
        async with sessions() as session:
            _, created = await post_message(
                session,
                chat_id=chat_id,
                sender_id=bob_id,
                client_id=uuid4(),
                text="racing",
                settings=default_chat_settings(),
            )
            await session.commit()
            return created

    create_task = asyncio.create_task(create_call())
    await asyncio.wait_for(create_started.wait(), timeout=5)
    send_task = asyncio.create_task(send_call())
    created, sent = await asyncio.wait_for(
        asyncio.gather(create_task, send_task), timeout=10
    )
    assert created is False
    assert sent is True

    async with sessions() as check:
        stored = await check.scalar(
            select(ChatMessage).where(
                ChatMessage.chat_id == chat_id, ChatMessage.text == "racing"
            )
        )
    assert stored is not None


async def test_concurrent_same_client_uuid_is_stored_once(chat_auth: Auth) -> None:
    alice = await account(chat_auth, "alice@university.example")
    bob = await account(chat_auth, "bob@university.example")
    chat_id = (await create_chat(alice, bob)).json()["id"]
    client_id = uuid4()

    responses = await asyncio.gather(
        send_message(alice, chat_id, "once", client_id),
        send_message(alice, chat_id, "once", client_id),
    )
    assert sorted(response.status_code for response in responses) == [200, 201]
    assert len({response.json()["id"] for response in responses}) == 1

    session = chat_auth.db
    session.expire_all()
    stored = await messages_of(session, UUID(chat_id))
    assert [message.sequence for message in stored] == [1]


async def test_dialogue_list(chat_auth: Auth) -> None:
    alice = await account(chat_auth, "alice@university.example")
    bob = await account(chat_auth, "bob@university.example")
    carol = await account(chat_auth, "carol@university.example")
    first = (await create_chat(alice, bob)).json()["id"]
    second = (await create_chat(alice, carol)).json()["id"]
    assert (await send_message(alice, first, "to bob")).status_code == 201
    assert (await send_message(carol, second, "to carol")).status_code == 201

    first_page = await alice.auth.client.get(
        ROOT, params={"size": 1}, headers=bearer(alice)
    )
    assert first_page.status_code == 200, first_page.text
    body = first_page.json()
    assert len(body["items"]) == 1
    assert body["items"][0]["last_message"]["text"] == "to carol"
    assert body["next_page"] is not None
    second_page = await alice.auth.client.get(
        ROOT, params={"size": 1, "cursor": body["next_page"]}, headers=bearer(alice)
    )
    ids = {
        body["items"][0]["id"],
        *[item["id"] for item in second_page.json()["items"]],
    }
    assert ids == {first, second}

    bob_view = await bob.auth.client.get(ROOT, headers=bearer(bob))
    assert [item["id"] for item in bob_view.json()["items"]] == [first]
    assert len(bob_view.json()["items"][0]["participants"]) == 2


async def test_message_length_and_rate_limit(limited_auth: Auth) -> None:
    alice = await account(limited_auth, "alice@university.example")
    bob = await account(limited_auth, "bob@university.example")
    carol = await account(limited_auth, "carol@university.example")
    chat_id = (await create_chat(alice, bob)).json()["id"]

    empty = await send_message(alice, chat_id, "   ")
    assert empty.status_code == 422
    assert empty.json()["code"] == "chat_message_invalid"
    long = await send_message(alice, chat_id, "x" * 4001)
    assert long.status_code == 422

    for number in range(3):
        accepted = await send_message(alice, chat_id, f"ok {number}")
        assert accepted.status_code == 201, accepted.text
    refused = await send_message(alice, chat_id, "too many")
    assert refused.status_code == 429
    assert refused.json()["code"] == "chat_rate_limited"
    assert int(refused.headers["Retry-After"]) >= 1
    # The limit is per user, not per chat or per account pair.
    assert (await send_message(bob, chat_id, "bob is fine")).status_code == 201

    with time_machine.travel(clock.now() + timedelta(seconds=61), tick=False):
        assert (await send_message(alice, chat_id, "new minute")).status_code == 201

    # The same user's parallel requests respect the limit too.
    chat_with_carol = (await create_chat(alice, carol)).json()["id"]
    with time_machine.travel(clock.now() + timedelta(seconds=122), tick=False):
        responses = await asyncio.gather(
            *(
                send_message(alice, chat_with_carol, f"parallel {index}")
                for index in range(6)
            )
        )
    codes = sorted(response.status_code for response in responses)
    assert codes == [201, 201, 201, 429, 429, 429]


async def test_rollback_does_not_publish(session: AsyncSession) -> None:
    alice, bob = await local_users(session)
    chat, created = await create_personal_chat(
        session, creator_id=alice.id, recipient_id=bob.id
    )
    assert created
    message, created_message = await post_message(
        session,
        chat_id=chat.id,
        sender_id=alice.id,
        client_id=uuid4(),
        text="in a transaction",
        settings=default_chat_settings(),
    )
    assert created_message
    assert await session.scalar(select(func.count()).select_from(ChatMessage)) == 1
    assert await session.scalar(select(func.count()).select_from(OutboxMessage)) == 1
    await session.rollback()
    assert await session.scalar(select(func.count()).select_from(ChatMessage)) == 0
    assert await session.scalar(select(func.count()).select_from(OutboxMessage)) == 0
    assert message.sequence == 1


async def test_outbox_publishes_stored_message(
    session: AsyncSession,
    sessions: async_sessionmaker[AsyncSession],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    alice, bob = await local_users(session)
    chat, _ = await create_personal_chat(
        session, creator_id=alice.id, recipient_id=bob.id
    )
    message, _ = await post_message(
        session,
        chat_id=chat.id,
        sender_id=alice.id,
        client_id=uuid4(),
        text="publish me",
        settings=default_chat_settings(),
    )
    await session.commit()

    calls: list[tuple[str, dict[str, Any], UUID]] = []

    async def fake_publish(
        channel: str, data: dict[str, Any], delivery_id: UUID
    ) -> None:
        calls.append((channel, data, delivery_id))

    monkeypatch.setattr("campus.modules.chat.consumers.publish_channel", fake_publish)
    assert await process_outbox(sessions, default_chat_settings()) == 1
    assert len(calls) == 1
    channel, payload, delivery_id = calls[0]
    assert channel == f"chat:{chat.id}"
    assert payload["message_id"] == str(message.id)
    assert payload["sequence"] == 1
    assert payload["text"] == "publish me"
    assert delivery_id


async def test_realtime_failure_keeps_message(
    chat_auth: Auth,
    sessions: async_sessionmaker[AsyncSession],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    alice = await account(chat_auth, "alice@university.example")
    bob = await account(chat_auth, "bob@university.example")
    chat_id = (await create_chat(alice, bob)).json()["id"]

    async def broken(_channel: str, _data: dict[str, Any], _delivery_id: UUID) -> None:
        raise ConnectionError("realtime is down")

    monkeypatch.setattr("campus.modules.chat.consumers.publish_channel", broken)
    # Sign-in codes also write the outbox; keep only this message's job.
    await chat_auth.db.execute(delete(OutboxMessage))
    await chat_auth.db.commit()
    sent = await send_message(alice, chat_id, "saved anyway")
    assert sent.status_code == 201, sent.text

    # The failed publication stays in the outbox for a retry.
    assert await process_outbox(sessions, chat_auth.settings) == 1
    outbox = await chat_auth.db.scalar(select(OutboxMessage))
    assert outbox is not None
    assert outbox.processed_at is None
    assert outbox.failed_at is None
    assert outbox.attempts == 1

    # The stored message is not lost: the API returns it for the recovery.
    recovered = await history(bob, chat_id)
    assert recovered.status_code == 200
    assert [item["text"] for item in recovered.json()["items"]] == ["saved anyway"]


async def test_messages_are_partitioned_by_creation_time(
    session: AsyncSession, sessions: async_sessionmaker[AsyncSession]
) -> None:
    alice, bob = await local_users(session)
    chat, _ = await create_personal_chat(
        session, creator_id=alice.id, recipient_id=bob.id
    )
    await session.commit()
    with time_machine.travel(datetime(2027, 3, 15, 12, tzinfo=UTC), tick=False):
        message, created = await post_message(
            session,
            chat_id=chat.id,
            sender_id=alice.id,
            client_id=uuid4(),
            text="march",
            settings=default_chat_settings(),
        )
        assert created
    await session.commit()

    async with sessions() as other:
        partition = await other.scalar(
            text(
                "SELECT tableoid::regclass::text FROM chat_message"
                " WHERE id = :message_id"
            ),
            {"message_id": message.id},
        )
    assert partition == "chat_message_2027_03"

    # Rows outside the prepared months still land in the default partition.
    async with sessions() as other:
        other.add(
            ChatMessage(
                chat_id=chat.id,
                sender_id=alice.id,
                client_id=uuid4(),
                sequence=99,
                text="far future",
                created_at=datetime(2035, 1, 1, tzinfo=UTC),
            )
        )
        await other.commit()
        default_partition = await other.scalar(
            text(
                "SELECT tableoid::regclass::text FROM chat_message WHERE sequence = 99"
            )
        )
    assert default_partition == "chat_message_default"


def default_chat_settings() -> Settings:
    return Settings(
        database_url=None,
        idempotency_encryption_keys=[],
    )


async def local_users(session: AsyncSession) -> tuple[User, User]:
    """Two persisted accounts, independent of the HTTP sign-in tests."""
    first = User(
        email="rollback-a@university.example",
        first_name="A",
        last_name="One",
        account_type="student",
    )
    second = User(
        email="rollback-b@university.example",
        first_name="B",
        last_name="Two",
        account_type="student",
    )
    session.add_all([first, second])
    await session.flush()
    return first, second
