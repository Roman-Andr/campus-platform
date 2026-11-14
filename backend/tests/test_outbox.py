"""Transactional outbox on a real database (specification, 4.3, 5.2)."""

import asyncio
from collections.abc import Iterator
from datetime import UTC, datetime, timedelta

import pytest
import time_machine
from sqlalchemy import func, select
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
    relay_outbox,
)
from tests.models import Note

TOPIC = "test.note"
START = datetime(2027, 3, 1, 12, 0, tzinfo=UTC)


class Recorder:
    """A handler that writes a note and fails the first ``failures`` times."""

    def __init__(self) -> None:
        self.calls: list[JobInfo] = []
        self.failures = 0
        self.called = asyncio.Event()

    async def __call__(self, session: AsyncSession, job: JobInfo) -> None:
        self.calls.append(job)
        self.called.set()
        session.add(Note(title=job.payload["title"]))
        await session.flush()
        if self.failures:
            self.failures -= 1
            msg = "temporary failure"
            raise ConnectionError(msg)


@pytest.fixture
def handler() -> Iterator[Recorder]:
    recorder = Recorder()
    outbox_handlers.register(TOPIC)(recorder)
    yield recorder
    outbox_handlers.remove(TOPIC)


@pytest.fixture
def sessions(engine: AsyncEngine) -> async_sessionmaker[AsyncSession]:
    return create_session_factory(engine)


@pytest.fixture
def settings() -> Settings:
    return Settings(
        job_max_attempts=3,
        job_retry_base_delay=timedelta(seconds=60),
        job_retry_max_delay=timedelta(seconds=600),
    )


async def count(sessions: async_sessionmaker[AsyncSession], model: type) -> int:
    async with sessions() as session:
        return await session.scalar(select(func.count()).select_from(model)) or 0


async def only_message(sessions: async_sessionmaker[AsyncSession]) -> OutboxMessage:
    async with sessions() as session:
        return (await session.scalars(select(OutboxMessage))).one()


async def add_note_with_message(
    sessions: async_sessionmaker[AsyncSession], *, commit: bool
) -> None:
    async with sessions() as session:
        session.add(Note(title="changed"))
        add_message(session, TOPIC, {"title": "side effect"})
        if commit:
            await session.commit()
        else:
            await session.rollback()


async def test_rolled_back_transaction_leaves_no_message(
    sessions: async_sessionmaker[AsyncSession], settings: Settings, handler: Recorder
) -> None:
    await add_note_with_message(sessions, commit=False)

    assert await count(sessions, OutboxMessage) == 0
    assert await process_outbox(sessions, settings) == 0
    assert handler.calls == []


async def test_handler_runs_after_commit(
    sessions: async_sessionmaker[AsyncSession], settings: Settings, handler: Recorder
) -> None:
    await add_note_with_message(sessions, commit=True)

    assert await process_outbox(sessions, settings) == 1

    [call] = handler.calls
    assert (call.topic, call.payload, call.attempt) == (
        TOPIC,
        {"title": "side effect"},
        1,
    )
    message = await only_message(sessions)
    assert message.processed_at is not None
    assert message.attempts == 1
    assert await count(sessions, Note) == 2  # the change and the side effect


async def test_processed_message_is_not_run_again(
    sessions: async_sessionmaker[AsyncSession], settings: Settings, handler: Recorder
) -> None:
    await add_note_with_message(sessions, commit=True)

    await process_outbox(sessions, settings)
    assert await process_outbox(sessions, settings) == 0

    assert len(handler.calls) == 1


async def test_failed_attempt_is_retried_without_double_side_effect(
    sessions: async_sessionmaker[AsyncSession], settings: Settings, handler: Recorder
) -> None:
    handler.failures = 1
    with time_machine.travel(START, tick=False) as traveller:
        await add_note_with_message(sessions, commit=True)

        assert await process_outbox(sessions, settings) == 1
        message = await only_message(sessions)
        assert message.processed_at is None
        assert message.attempts == 1
        assert message.last_error == "ConnectionError: temporary failure"
        assert message.available_at == START + timedelta(seconds=60)
        # The note written by the failed attempt was rolled back.
        assert await count(sessions, Note) == 1

        # Not retried before the backoff delay.
        traveller.shift(timedelta(seconds=59))
        assert await process_outbox(sessions, settings) == 0

        traveller.shift(timedelta(seconds=1))
        assert await process_outbox(sessions, settings) == 1

    message = await only_message(sessions)
    assert message.processed_at is not None
    assert message.attempts == 2
    assert message.last_error is None
    assert [call.attempt for call in handler.calls] == [1, 2]
    assert len({call.id for call in handler.calls}) == 1
    assert await count(sessions, Note) == 2  # one side effect, not two


async def test_message_fails_after_last_attempt(
    sessions: async_sessionmaker[AsyncSession], settings: Settings, handler: Recorder
) -> None:
    handler.failures = 10
    with time_machine.travel(START, tick=False) as traveller:
        await add_note_with_message(sessions, commit=True)
        for _ in range(settings.job_max_attempts):
            assert await process_outbox(sessions, settings) == 1
            traveller.shift(timedelta(hours=1))

        assert await process_outbox(sessions, settings) == 0

    message = await only_message(sessions)
    assert message.failed_at is not None
    assert message.processed_at is None
    assert message.attempts == 3


async def test_backoff_doubles_up_to_the_limit(
    sessions: async_sessionmaker[AsyncSession], handler: Recorder
) -> None:
    settings = Settings(
        job_max_attempts=10,
        job_retry_base_delay=timedelta(seconds=60),
        job_retry_max_delay=timedelta(seconds=200),
    )
    handler.failures = 10
    delays = []
    with time_machine.travel(START, tick=False) as traveller:
        await add_note_with_message(sessions, commit=True)
        for _ in range(4):
            await process_outbox(sessions, settings)
            message = await only_message(sessions)
            delays.append(message.available_at - clock.now())
            traveller.move_to(message.available_at)

    assert [delay.total_seconds() for delay in delays] == [60, 120, 200, 200]


async def test_message_with_unknown_topic_is_retried(
    sessions: async_sessionmaker[AsyncSession], settings: Settings
) -> None:
    async with sessions() as session, session.begin():
        add_message(session, "test.nobody", {})

    await process_outbox(sessions, settings)

    message = await only_message(sessions)
    assert message.processed_at is None
    assert message.last_error == "UnknownTopicError: no handler for topic 'test.nobody'"


async def test_concurrent_runners_process_each_message_once(
    sessions: async_sessionmaker[AsyncSession], handler: Recorder
) -> None:
    settings = Settings(job_batch_size=5)
    async with sessions() as session, session.begin():
        for number in range(20):
            add_message(session, TOPIC, {"title": f"note {number}"})

    async def drain() -> int:
        total = 0
        while attempted := await process_outbox(sessions, settings):
            total += attempted
        return total

    totals = await asyncio.gather(*(drain() for _ in range(4)))

    assert sum(totals) == 20
    titles = sorted(call.payload["title"] for call in handler.calls)
    assert titles == sorted(f"note {number}" for number in range(20))


async def test_relay_processes_messages_until_stopped(
    sessions: async_sessionmaker[AsyncSession], handler: Recorder
) -> None:
    settings = Settings(outbox_poll_interval=0.01)
    stop = asyncio.Event()
    relay = asyncio.create_task(relay_outbox(sessions, settings, stop))

    await add_note_with_message(sessions, commit=True)
    await asyncio.wait_for(handler.called.wait(), timeout=5)
    stop.set()
    await asyncio.wait_for(relay, timeout=5)

    assert (await only_message(sessions)).processed_at is not None


async def test_relay_survives_database_errors(
    sessions: async_sessionmaker[AsyncSession],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    settings = Settings(outbox_poll_interval=0.01)
    calls = 0

    async def broken(*_args: object) -> int:
        nonlocal calls
        calls += 1
        if calls >= 3:
            stop.set()
        msg = "database is down"
        raise OSError(msg)

    monkeypatch.setattr("campus.core.outbox.process_outbox", broken)
    stop = asyncio.Event()

    await asyncio.wait_for(relay_outbox(sessions, settings, stop), timeout=5)

    assert calls == 3


async def test_finished_messages_are_deleted_after_retention(
    sessions: async_sessionmaker[AsyncSession], handler: Recorder
) -> None:
    settings = Settings(outbox_retention=timedelta(days=7), job_max_attempts=1)
    with time_machine.travel(START, tick=False) as traveller:
        async with sessions() as session, session.begin():
            add_message(session, TOPIC, {"title": "processed"})
            add_message(session, "test.nobody", {})  # fails at once
        await process_outbox(sessions, settings)
        traveller.shift(timedelta(days=1))
        async with sessions() as session, session.begin():
            add_message(session, TOPIC, {"title": "recent"})
        await process_outbox(sessions, settings)
        async with sessions() as session, session.begin():
            add_message(session, TOPIC, {"title": "pending"})

        traveller.shift(timedelta(days=7))
        assert await delete_finished_messages(sessions, settings) == 2

    async with sessions() as session:
        left = await session.scalars(
            select(OutboxMessage.payload["title"].astext).order_by(OutboxMessage.id)
        )
        assert list(left) == ["recent", "pending"]
    assert len(handler.calls) == 2
