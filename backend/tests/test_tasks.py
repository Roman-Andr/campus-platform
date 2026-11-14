"""Periodic tasks run by the worker, on the in-memory Taskiq broker."""

from collections.abc import AsyncIterator
from datetime import UTC, datetime, timedelta
from unittest.mock import AsyncMock
from uuid import uuid4

import pytest
import time_machine
from pydantic import SecretStr
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from taskiq import AsyncBroker, InMemoryBroker

from campus.core.config import Settings
from campus.core.deadlines import Deadline, deadline_handlers, schedule_deadline
from campus.core.idempotency import (
    IdempotencyKey,
    ResponseKeyring,
    claim_idempotency_key,
)
from campus.core.jobs import Handlers, JobInfo
from campus.core.outbox import (
    OutboxMessage,
    add_message,
    outbox_handlers,
    process_outbox,
)
from campus.core.tasks import (
    CLEANUP_TASK,
    DEADLINES_TASK,
    configure_broker,
    kick,
    register_cleanup,
    worker_resources,
)
from campus.modules.identity import SignInCode

START = datetime(2027, 3, 1, 12, 0, tzinfo=UTC)
TOPIC = "test.task"


async def noop(_session: AsyncSession, _job: JobInfo) -> None:
    pass


@pytest.fixture
async def broker(database_url: str) -> AsyncIterator[InMemoryBroker]:
    """A started worker broker with the application tasks."""
    broker = InMemoryBroker()
    configure_broker(broker, Settings(database_url=SecretStr(database_url)))
    broker.is_worker_process = True
    await broker.startup()
    outbox_handlers.register(TOPIC)(noop)
    deadline_handlers.register(TOPIC)(noop)
    yield broker
    outbox_handlers.remove(TOPIC)
    deadline_handlers.remove(TOPIC)
    await broker.shutdown()


async def count(broker: AsyncBroker, model: type) -> int:
    async with worker_resources(broker).sessions() as session:
        return await session.scalar(select(func.count()).select_from(model)) or 0


async def test_deadline_task_processes_due_deadlines(broker: InMemoryBroker) -> None:
    sessions = worker_resources(broker).sessions
    with time_machine.travel(START, tick=False) as traveller:
        async with sessions() as session, session.begin():
            await schedule_deadline(session, TOPIC, START, {})
        traveller.shift(timedelta(minutes=1))

        await kick(broker, DEADLINES_TASK)
        await broker.wait_all()

    async with sessions() as session:
        deadline = (await session.scalars(select(Deadline))).one()
    assert deadline.processed_at is not None


async def test_cleanup_task_deletes_expired_records(broker: InMemoryBroker) -> None:
    sessions = worker_resources(broker).sessions
    settings = worker_resources(broker).settings
    with time_machine.travel(START, tick=False) as traveller:
        async with sessions() as session, session.begin():
            add_message(session, TOPIC, {})
            session.add(
                SignInCode(
                    email="expired@university.example",
                    code_hash="0" * 64,
                    expires_at=START,
                )
            )
            await schedule_deadline(session, TOPIC, START, {})
            for ttl in (timedelta(days=1), timedelta(days=30)):
                await claim_idempotency_key(
                    session,
                    keyring=ResponseKeyring([bytes(32)]),
                    scope="anonymous",
                    key=uuid4(),
                    fingerprint=bytes(32),
                    now=START,
                    ttl=ttl,
                )
        await kick(broker, DEADLINES_TASK)
        await broker.wait_all()
        await process_outbox(sessions, settings)
        traveller.shift(timedelta(days=8))

        await kick(broker, CLEANUP_TASK)
        await broker.wait_all()

    assert await count(broker, OutboxMessage) == 0
    assert await count(broker, Deadline) == 0
    assert await count(broker, IdempotencyKey) == 1  # the unexpired one
    assert await count(broker, SignInCode) == 0  # a registered module cleanup


def test_cleanup_has_one_name() -> None:
    with pytest.raises(ValueError, match="already registered"):
        register_cleanup("identity")(AsyncMock())


def test_topic_has_one_handler() -> None:
    handlers = Handlers()
    handlers.register("a")(noop)

    with pytest.raises(ValueError, match="already registered"):
        handlers.register("a")(noop)
