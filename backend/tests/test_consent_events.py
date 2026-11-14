"""Consent dispatch, replay and current-state delivery on PostgreSQL."""

import asyncio
from collections.abc import Iterator
from datetime import timedelta
from uuid import UUID, uuid4

import pytest
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker

from campus.core import clock
from campus.core.config import Settings
from campus.core.db import create_session_factory
from campus.core.jobs import JobInfo
from campus.core.outbox import OutboxMessage, outbox_handlers, process_outbox
from campus.core.web import Principal
from campus.modules.identity import (
    ConsentChange,
    DocumentKind,
    User,
    consent_consumers,
    publish_document,
    replay_consent_events,
)
from campus.modules.identity.consent_events import CONSENT_CHANGED, ConsentDispatch
from campus.modules.identity.consents import (
    consent_changed,
    lock_consent_state,
    record_decision,
)
from tests.models import Note


@pytest.fixture
def consumers() -> Iterator[list[str]]:
    names: list[str] = []
    yield names
    for name in names:
        consent_consumers.remove(name)


@pytest.fixture
async def sessions(engine: AsyncEngine) -> async_sessionmaker[AsyncSession]:
    return create_session_factory(engine)


async def event(sessions: async_sessionmaker[AsyncSession]) -> UUID:
    async with sessions() as session, session.begin():
        consent_changed(session, uuid4(), uuid4(), allowed=True)
        await session.flush()
        return (await session.scalars(select(OutboxMessage))).one().id


async def drain(sessions: async_sessionmaker[AsyncSession]) -> None:
    while await process_outbox(sessions, Settings()):
        pass


async def test_worker_accepts_event_without_consumers(
    sessions: async_sessionmaker[AsyncSession],
) -> None:
    event_id = await event(sessions)
    await drain(sessions)
    async with sessions() as session:
        message = await session.get(OutboxMessage, event_id)
        assert message is not None
        assert message.processed_at is not None
        assert message.last_error is None


async def test_independent_retries_and_transactional_effects(
    sessions: async_sessionmaker[AsyncSession], consumers: list[str]
) -> None:
    calls: list[ConsentChange] = []
    failures = 1

    @consent_consumers.register("fcm")
    async def fcm(session: AsyncSession, change: ConsentChange) -> None:
        nonlocal failures
        calls.append(change)
        session.add(Note(title="fcm"))
        await session.flush()
        if failures:
            failures -= 1
            raise ConnectionError("offline")

    @consent_consumers.register("telegram")
    async def telegram(session: AsyncSession, change: ConsentChange) -> None:
        assert change.allowed is False
        session.add(Note(title="telegram"))

    consumers.extend(["fcm", "telegram"])
    await event(sessions)
    await drain(sessions)
    async with sessions() as session, session.begin():
        assert list(await session.scalars(select(Note.title))) == ["telegram"]
        failed = (
            await session.scalars(
                select(OutboxMessage).where(OutboxMessage.last_error.is_not(None))
            )
        ).one()
        failed.available_at = clock.now() - timedelta(seconds=1)
    await drain(sessions)
    assert len(calls) == 2
    assert calls[0].delivery_id == calls[1].delivery_id
    async with sessions() as session:
        assert sorted(await session.scalars(select(Note.title))) == ["fcm", "telegram"]


@pytest.mark.parametrize("legacy_failed", [False, True])
async def test_late_consumer_replay_is_durable_and_concurrent(
    sessions: async_sessionmaker[AsyncSession],
    consumers: list[str],
    legacy_failed: bool,
) -> None:
    event_id = await event(sessions)
    await drain(sessions)
    if legacy_failed:
        async with sessions() as session, session.begin():
            message = await session.get(OutboxMessage, event_id)
            assert message is not None
            message.processed_at = None
            message.failed_at = clock.now()
            message.last_error = "UnknownTopicError: no handler"
            message.attempts = 5

    @consent_consumers.register("ai")
    async def ai(session: AsyncSession, change: ConsentChange) -> None:
        assert change.allowed is False
        session.add(Note(title="ai"))

    consumers.append("ai")

    async def replay() -> None:
        async with sessions() as session, session.begin():
            assert await replay_consent_events(session) == 1

    await asyncio.gather(replay(), replay())
    await drain(sessions)
    # Outbox retention removes deliveries, but never deduplication receipts.
    async with sessions() as session, session.begin():
        await session.execute(
            delete(OutboxMessage).where(OutboxMessage.topic != CONSENT_CHANGED)
        )
    await replay()
    await drain(sessions)
    async with sessions() as session:
        assert list(await session.scalars(select(Note.title))) == ["ai"]
        assert len(list(await session.scalars(select(ConsentDispatch)))) == 1
        message = await session.get(OutboxMessage, event_id)
        assert message is not None
        assert message.processed_at is not None
        assert message.failed_at is None


@pytest.mark.parametrize("invalidate", ["revoke", "publish"])
async def test_old_grant_never_overrides_current_permission(
    sessions: async_sessionmaker[AsyncSession], consumers: list[str], invalidate: str
) -> None:
    seen: list[bool] = []

    @consent_consumers.register("fcm")
    async def fcm(_session: AsyncSession, change: ConsentChange) -> None:
        seen.append(change.allowed)

    consumers.append("fcm")
    async with sessions() as session, session.begin():
        user = User(
            email="consent@example.test",
            first_name="A",
            last_name="B",
            account_type="student",
        )
        session.add(user)
        document = await publish_document(
            session, DocumentKind.CROSS_BORDER, text_ru="RU", text_en="EN"
        )
        await session.flush()
        principal = Principal(user_id=user.id, session_id=uuid4())
        await record_decision(session, principal, document, accepted=True)
    # Deliver one grant successfully first, then delay/replay the old grant.
    await drain(sessions)
    assert seen == [True]
    if invalidate == "revoke":
        async with sessions() as session, session.begin():
            await lock_consent_state(session, principal.user_id)
            await record_decision(session, principal, document, accepted=False)
    else:
        async with sessions() as session, session.begin():
            await publish_document(
                session, DocumentKind.CROSS_BORDER, text_ru="RU2", text_en="EN2"
            )
    async with sessions() as session, session.begin():
        consent_changed(session, principal.user_id, document.id, allowed=True)
    await drain(sessions)
    assert seen[1:] == [False, False]


async def test_dispatch_rollback_leaves_no_receipt_or_delivery(
    sessions: async_sessionmaker[AsyncSession], consumers: list[str]
) -> None:
    @consent_consumers.register("fcm")
    async def fcm(_session: AsyncSession, _change: ConsentChange) -> None:
        pass

    consumers.append("fcm")
    event_id = await event(sessions)
    async with sessions() as session:
        await outbox_handlers.get(CONSENT_CHANGED)(
            session, JobInfo(event_id, CONSENT_CHANGED, {"user_id": str(uuid4())}, 1)
        )
        await session.flush()
        await session.rollback()
    async with sessions() as session:
        assert list(await session.scalars(select(ConsentDispatch))) == []
        assert len(list(await session.scalars(select(OutboxMessage)))) == 1
    await drain(sessions)
    async with sessions() as session:
        assert len(list(await session.scalars(select(ConsentDispatch)))) == 1


async def test_new_consumer_receives_history_without_repeating_existing_one(
    sessions: async_sessionmaker[AsyncSession], consumers: list[str]
) -> None:
    @consent_consumers.register("fcm")
    async def fcm(session: AsyncSession, _change: ConsentChange) -> None:
        session.add(Note(title="fcm"))

    consumers.append("fcm")
    await event(sessions)
    await drain(sessions)

    @consent_consumers.register("ai")
    async def ai(session: AsyncSession, _change: ConsentChange) -> None:
        session.add(Note(title="ai"))

    consumers.append("ai")
    async with sessions() as session, session.begin():
        await replay_consent_events(session)
    await drain(sessions)
    async with sessions() as session:
        assert sorted(await session.scalars(select(Note.title))) == ["ai", "fcm"]


async def test_external_effect_uses_stable_id_after_lost_acknowledgement(
    sessions: async_sessionmaker[AsyncSession], consumers: list[str]
) -> None:
    provider_keys: set[UUID] = set()
    calls: list[UUID] = []

    @consent_consumers.register("fcm")
    async def fcm(_session: AsyncSession, change: ConsentChange) -> None:
        calls.append(change.delivery_id)
        # A provider persists the idempotency key outside our transaction.
        provider_keys.add(change.delivery_id)
        if len(calls) == 1:
            raise ConnectionError("acknowledgement lost after external effect")

    consumers.append("fcm")
    await event(sessions)
    await drain(sessions)
    async with sessions() as session, session.begin():
        job = (
            await session.scalars(
                select(OutboxMessage).where(
                    OutboxMessage.topic == "identity.consent.fcm"
                )
            )
        ).one()
        job.available_at = clock.now() - timedelta(seconds=1)
    await drain(sessions)
    assert len(calls) == 2
    assert len(provider_keys) == 1


async def test_transfer_waits_for_concurrent_revocation(
    sessions: async_sessionmaker[AsyncSession], consumers: list[str]
) -> None:
    seen: list[bool] = []

    @consent_consumers.register("fcm")
    async def fcm(_session: AsyncSession, change: ConsentChange) -> None:
        seen.append(change.allowed)

    consumers.append("fcm")
    async with sessions() as session, session.begin():
        user = User(
            email="race@example.test",
            first_name="A",
            last_name="B",
            account_type="student",
        )
        session.add(user)
        document = await publish_document(
            session, DocumentKind.CROSS_BORDER, text_ru="RU", text_en="EN"
        )
        await session.flush()
        principal = Principal(user_id=user.id, session_id=uuid4())
        await record_decision(session, principal, document, accepted=True)
    # Dispatch without delivering yet.
    await process_outbox(sessions, Settings(job_batch_size=1))
    async with sessions() as session, session.begin():
        await lock_consent_state(session, principal.user_id)
        await record_decision(session, principal, document, accepted=False)
        started = asyncio.Event()

        async def deliver() -> None:
            started.set()
            await drain(sessions)

        delivery = asyncio.create_task(deliver())
        await started.wait()
        # The delivery cannot observe the previous grant while this
        # transaction holds the revocation lock.
        assert seen == []
    await asyncio.wait_for(delivery, timeout=10)
    assert seen == [False, False]


def test_consumer_registration_rejects_invalid_or_duplicate_names(
    consumers: list[str],
) -> None:
    with pytest.raises(ValueError, match="lowercase"):
        consent_consumers.register("invalid.name")

    async def callback(_session: AsyncSession, _change: ConsentChange) -> None:
        pass

    consent_consumers.register("fcm")(callback)
    consumers.append("fcm")
    with pytest.raises(ValueError, match="already registered"):
        consent_consumers.register("fcm")(callback)
