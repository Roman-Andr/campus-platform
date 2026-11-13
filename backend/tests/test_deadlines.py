"""Deadlines in the database, processed with controlled time (5.2)."""

import asyncio
from collections.abc import Iterator
from datetime import UTC, datetime, timedelta

import pytest
import time_machine
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker

from campus.core.config import Settings
from campus.core.db import create_session_factory
from campus.core.deadlines import (
    Deadline,
    cancel_deadline,
    deadline_handlers,
    delete_finished_deadlines,
    process_due_deadlines,
    schedule_deadline,
)
from campus.core.jobs import JobInfo

TOPIC = "test.expire"
START = datetime(2027, 3, 1, 12, 0, tzinfo=UTC)


class Recorder:
    def __init__(self) -> None:
        self.payloads: list[dict[str, object]] = []

    async def __call__(self, _session: AsyncSession, job: JobInfo) -> None:
        # Yield, so that concurrent runners interleave.
        await asyncio.sleep(0.005)
        self.payloads.append(job.payload)


@pytest.fixture
def handler() -> Iterator[Recorder]:
    recorder = Recorder()
    deadline_handlers.register(TOPIC)(recorder)
    yield recorder
    deadline_handlers.remove(TOPIC)


@pytest.fixture
def sessions(engine: AsyncEngine) -> async_sessionmaker[AsyncSession]:
    return create_session_factory(engine)


async def schedule(
    sessions: async_sessionmaker[AsyncSession],
    due_at: datetime,
    payload: dict[str, object],
    key: str | None = None,
) -> None:
    async with sessions() as session, session.begin():
        await schedule_deadline(session, TOPIC, due_at, payload, key=key)


async def pending_payloads(
    sessions: async_sessionmaker[AsyncSession],
) -> list[dict[str, object]]:
    async with sessions() as session:
        rows = await session.scalars(
            select(Deadline.payload)
            .where(Deadline.is_pending())
            .order_by(Deadline.available_at)
        )
        return list(rows)


async def test_deadline_is_processed_when_due_not_before(
    sessions: async_sessionmaker[AsyncSession], handler: Recorder
) -> None:
    with time_machine.travel(START, tick=False) as traveller:
        await schedule(sessions, START + timedelta(minutes=30), {"n": 1})

        traveller.shift(timedelta(minutes=29))
        assert await process_due_deadlines(sessions, Settings()) == 0

        traveller.shift(timedelta(minutes=1))
        assert await process_due_deadlines(sessions, Settings()) == 1

    assert handler.payloads == [{"n": 1}]
    assert await pending_payloads(sessions) == []


async def test_deadline_missed_during_downtime_is_processed_after_start(
    sessions: async_sessionmaker[AsyncSession], handler: Recorder
) -> None:
    with time_machine.travel(START, tick=False) as traveller:
        await schedule(sessions, START + timedelta(minutes=5), {"n": 1})
        await schedule(sessions, START + timedelta(hours=2), {"n": 2})
        await schedule(sessions, START + timedelta(days=2), {"n": 3})

        # The scheduler is down for a day: no run happens in between.
        traveller.shift(timedelta(days=1))
        assert await process_due_deadlines(sessions, Settings()) == 2

    assert handler.payloads == [{"n": 1}, {"n": 2}]
    assert await pending_payloads(sessions) == [{"n": 3}]


async def test_all_due_deadlines_are_processed_in_one_run(
    sessions: async_sessionmaker[AsyncSession], handler: Recorder
) -> None:
    with time_machine.travel(START, tick=False) as traveller:
        for n in range(7):
            await schedule(sessions, START, {"n": n})
        traveller.shift(timedelta(minutes=1))

        assert await process_due_deadlines(sessions, Settings(job_batch_size=3)) == 7

    assert len(handler.payloads) == 7


async def test_two_schedulers_do_not_process_a_deadline_twice(
    sessions: async_sessionmaker[AsyncSession], handler: Recorder
) -> None:
    settings = Settings(job_batch_size=2)
    with time_machine.travel(START, tick=False) as traveller:
        for n in range(30):
            await schedule(sessions, START, {"n": n})
        traveller.shift(timedelta(minutes=1))

        totals = await asyncio.gather(
            process_due_deadlines(sessions, settings),
            process_due_deadlines(sessions, settings),
        )

    assert sum(totals) == 30
    assert all(totals)  # both took part
    assert sorted(p["n"] for p in handler.payloads) == list(range(30))  # type: ignore[type-var]


async def test_deadline_with_key_is_moved(
    sessions: async_sessionmaker[AsyncSession], handler: Recorder
) -> None:
    with time_machine.travel(START, tick=False) as traveller:
        await schedule(sessions, START + timedelta(minutes=10), {"v": 1}, key="k")
        await schedule(sessions, START + timedelta(hours=1), {"v": 2}, key="k")

        traveller.shift(timedelta(minutes=30))
        assert await process_due_deadlines(sessions, Settings()) == 0
        traveller.shift(timedelta(minutes=30))
        assert await process_due_deadlines(sessions, Settings()) == 1

        # A processed deadline frees its key for a new one.
        await schedule(sessions, START + timedelta(hours=2), {"v": 3}, key="k")

    assert handler.payloads == [{"v": 2}]
    assert await pending_payloads(sessions) == [{"v": 3}]


async def test_cancelled_deadline_is_not_processed(
    sessions: async_sessionmaker[AsyncSession], handler: Recorder
) -> None:
    with time_machine.travel(START, tick=False) as traveller:
        await schedule(sessions, START + timedelta(minutes=10), {"v": 1}, key="k")
        async with sessions() as session, session.begin():
            assert await cancel_deadline(session, "k") is True
            assert await cancel_deadline(session, "k") is False

        traveller.shift(timedelta(hours=1))
        assert await process_due_deadlines(sessions, Settings()) == 0

    assert handler.payloads == []


async def test_finished_deadlines_are_deleted_after_retention(
    sessions: async_sessionmaker[AsyncSession], handler: Recorder
) -> None:
    settings = Settings(deadline_retention=timedelta(days=7))
    with time_machine.travel(START, tick=False) as traveller:
        await schedule(sessions, START, {"n": 1})
        await process_due_deadlines(sessions, settings)
        await schedule(sessions, START + timedelta(days=30), {"n": 2})

        traveller.shift(timedelta(days=7, seconds=1))
        assert await delete_finished_deadlines(sessions, settings) == 1

    assert handler.payloads == [{"n": 1}]
    assert await pending_payloads(sessions) == [{"n": 2}]
