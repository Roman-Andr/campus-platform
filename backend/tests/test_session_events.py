"""Session event dispatch and replay on PostgreSQL with controlled time."""

import asyncio
import subprocess
import sys
from collections.abc import Iterator
from datetime import timedelta
from uuid import UUID, uuid4

import pytest
import time_machine
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker

from campus.core import clock
from campus.core.config import Settings
from campus.core.db import create_session_factory
from campus.core.jobs import JobInfo
from campus.core.outbox import (
    OutboxMessage,
    add_message,
    delete_finished_messages,
    outbox_handlers,
    process_outbox,
)
from campus.modules.identity import (
    SessionsRevoked,
    replay_session_events,
    session_consumers,
)
from campus.modules.identity.session_events import SESSIONS_REVOKED, SessionDispatch
from tests.models import Note


@pytest.fixture(autouse=True)
def only_test_consumers() -> Iterator[None]:
    """Hide consumers of imported modules: each test owns the registry."""
    with session_consumers.suspend():
        yield


@pytest.fixture
def consumers() -> Iterator[list[str]]:
    names: list[str] = []
    yield names
    for name in names:
        session_consumers.remove(name)


@pytest.fixture
async def sessions(engine: AsyncEngine) -> async_sessionmaker[AsyncSession]:
    return create_session_factory(engine)


async def event(sessions: async_sessionmaker[AsyncSession]) -> OutboxMessage:
    async with sessions() as session, session.begin():
        add_message(
            session,
            SESSIONS_REVOKED,
            {"user_id": str(uuid4()), "session_ids": [str(uuid4()), str(uuid4())]},
        )
        await session.flush()
        return (await session.scalars(select(OutboxMessage))).one()


async def drain(sessions: async_sessionmaker[AsyncSession]) -> None:
    while await process_outbox(sessions, Settings()):
        pass


async def replay(sessions: async_sessionmaker[AsyncSession]) -> None:
    async with sessions() as session, session.begin():
        assert await replay_session_events(session) == 1


async def test_worker_accepts_zero_consumers(
    sessions: async_sessionmaker[AsyncSession],
) -> None:
    with time_machine.travel("2026-11-14T12:00:00Z", tick=False):
        source = await event(sessions)
        await drain(sessions)
        async with sessions() as session:
            job = await session.get(OutboxMessage, source.id)
            assert job is not None
            assert job.processed_at == clock.now()
            assert job.failed_at is None
            assert job.last_error is None
            assert job.attempts == 1


async def test_independent_failures_and_external_idempotency(
    sessions: async_sessionmaker[AsyncSession], consumers: list[str]
) -> None:
    seen: list[SessionsRevoked] = []
    provider_keys: set[UUID] = set()

    @session_consumers.register("devices")
    async def devices(session: AsyncSession, change: SessionsRevoked) -> None:
        seen.append(change)
        provider_keys.add(change.delivery_id)
        session.add(Note(title="devices"))
        await session.flush()
        if len(seen) == 1:
            raise ConnectionError("acknowledgement lost")

    @session_consumers.register("realtime")
    async def realtime(session: AsyncSession, change: SessionsRevoked) -> None:
        assert change.user_id == UUID(source.payload["user_id"])
        assert change.session_ids == tuple(map(UUID, source.payload["session_ids"]))
        session.add(Note(title="realtime"))

    consumers.extend(["devices", "realtime"])
    with time_machine.travel("2026-11-14T12:00:00Z", tick=False) as traveller:
        source = await event(sessions)
        await drain(sessions)
        async with sessions() as session:
            assert list(await session.scalars(select(Note.title))) == ["realtime"]
            retry = (
                await session.scalars(
                    select(OutboxMessage).where(OutboxMessage.last_error.is_not(None))
                )
            ).one()
            assert retry.failed_at is None
            retry_at = retry.available_at
        await replay(sessions)
        await drain(sessions)
        assert len(seen) == 1
        traveller.move_to(retry_at)
        await drain(sessions)
        assert len(seen) == 2
        assert seen[0] == seen[1]
        assert seen[0].user_id == UUID(source.payload["user_id"])
        assert seen[0].session_ids == tuple(map(UUID, source.payload["session_ids"]))
        assert len(provider_keys) == 1
        async with sessions() as session:
            assert sorted(await session.scalars(select(Note.title))) == [
                "devices",
                "realtime",
            ]


@pytest.mark.parametrize("state", ["processed", "unknown", "other", "pending"])
async def test_late_consumers_concurrent_replay_and_retention(
    sessions: async_sessionmaker[AsyncSession], consumers: list[str], state: str
) -> None:
    with time_machine.travel("2026-11-14T12:00:00Z", tick=False) as traveller:
        source = await event(sessions)
        await drain(sessions)
        async with sessions() as session, session.begin():
            job = await session.get(OutboxMessage, source.id)
            assert job is not None
            if state != "processed":
                job.processed_at = None
            if state in {"unknown", "other"}:
                job.failed_at = clock.now()
                job.attempts = 5
                job.last_error = (
                    "UnknownTopicError: no handler"
                    if state == "unknown"
                    else "ValueError: broken event"
                )
            if state == "pending":
                job.available_at = clock.now() + timedelta(days=30)

        @session_consumers.register("devices")
        async def devices(session: AsyncSession, _change: SessionsRevoked) -> None:
            session.add(Note(title="devices"))

        consumers.append("devices")
        await asyncio.gather(replay(sessions), replay(sessions))
        await drain(sessions)
        async with sessions() as session:
            job = await session.get(OutboxMessage, source.id)
            assert job is not None
            if state == "other":
                assert job.failed_at is not None
                assert job.last_error == "ValueError: broken event"
            elif state != "pending":
                assert job.processed_at is not None
                assert job.failed_at is None
                assert job.last_error is None

        # Retain the source while completed delivery jobs age past retention.
        # A pruned source event cannot be replayed.
        async with sessions() as session, session.begin():
            job = await session.get(OutboxMessage, source.id)
            assert job is not None
            job.processed_at = None
            job.failed_at = None
            job.available_at = clock.now() + timedelta(days=30)
        traveller.shift(Settings().outbox_retention + timedelta(seconds=1))
        assert await delete_finished_messages(sessions, Settings()) == 1

        @session_consumers.register("realtime")
        async def realtime(session: AsyncSession, _change: SessionsRevoked) -> None:
            session.add(Note(title="realtime"))

        consumers.append("realtime")
        await asyncio.gather(replay(sessions), replay(sessions))
        await drain(sessions)
        await replay(sessions)
        await drain(sessions)
        async with sessions() as session:
            assert sorted(await session.scalars(select(Note.title))) == [
                "devices",
                "realtime",
            ]
            assert len(list(await session.scalars(select(SessionDispatch)))) == 2


async def test_dispatch_rollback_is_atomic(
    sessions: async_sessionmaker[AsyncSession], consumers: list[str]
) -> None:
    @session_consumers.register("devices")
    async def devices(_session: AsyncSession, _change: SessionsRevoked) -> None:
        pass

    consumers.append("devices")
    source = await event(sessions)
    async with sessions() as session:
        await outbox_handlers.get(SESSIONS_REVOKED)(
            session, JobInfo(source.id, source.topic, source.payload, 1)
        )
        await session.flush()
        await session.rollback()
    async with sessions() as session:
        assert list(await session.scalars(select(SessionDispatch))) == []
        assert len(list(await session.scalars(select(OutboxMessage)))) == 1
    await drain(sessions)
    async with sessions() as session:
        assert len(list(await session.scalars(select(SessionDispatch)))) == 1


def test_ordinary_module_import_registers_handlers() -> None:
    result = subprocess.run(
        [
            sys.executable,
            "-c",
            """
from campus import modules
from campus.core.outbox import outbox_handlers
modules.import_all()
assert callable(outbox_handlers.get('identity.sessions_revoked'))
assert callable(outbox_handlers.get('identity.cross_border_consent_changed'))
assert callable(outbox_handlers.get('identity.session.realtime_connections'))
assert callable(outbox_handlers.get('realtime.unsubscribe'))
""",
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr


def test_consumer_registration(consumers: list[str]) -> None:
    with pytest.raises(ValueError, match="lowercase"):
        session_consumers.register("invalid.name")

    async def callback(_session: AsyncSession, _change: SessionsRevoked) -> None:
        pass

    session_consumers.register("devices")(callback)
    consumers.append("devices")
    with pytest.raises(ValueError, match="already registered"):
        session_consumers.register("devices")(callback)


async def test_replay_keeps_exhausted_delivery_failed(
    sessions: async_sessionmaker[AsyncSession], consumers: list[str]
) -> None:
    calls = 0

    @session_consumers.register("devices")
    async def devices(_session: AsyncSession, _change: SessionsRevoked) -> None:
        nonlocal calls
        calls += 1
        raise ConnectionError("offline")

    consumers.append("devices")
    with time_machine.travel("2026-11-14T12:00:00Z", tick=False):
        await event(sessions)
        settings = Settings(job_max_attempts=1)
        while await process_outbox(sessions, settings):
            pass
        await replay(sessions)
        await drain(sessions)
        assert calls == 1
        async with sessions() as session:
            delivery = (
                await session.scalars(
                    select(OutboxMessage).where(
                        OutboxMessage.topic == "identity.session.devices"
                    )
                )
            ).one()
            assert delivery.failed_at == clock.now()
            assert delivery.attempts == 1
            assert delivery.last_error == "ConnectionError: offline"
