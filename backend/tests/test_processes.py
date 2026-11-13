"""The API, worker and scheduler processes, the latter two on real Redis."""

import asyncio
import os
import signal
from collections import defaultdict
from collections.abc import Iterator
from datetime import timedelta
from importlib import import_module
from types import ModuleType
from typing import Any

import pytest
import redis.asyncio
import uvicorn
from pydantic import SecretStr
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker

from campus.api import __main__ as api_main
from campus.api.app import create_app
from campus.core import clock
from campus.core.config import Settings
from campus.core.db import create_session_factory
from campus.core.deadlines import deadline_handlers, schedule_deadline
from campus.core.jobs import JobInfo
from campus.core.outbox import add_message, outbox_handlers
from campus.core.runtime import Service, run_until_signal
from campus.core.tasks import (
    CLEANUP_TASK,
    DEADLINES_TASK,
    RedisNotConfiguredError,
    create_broker,
)
from campus.scheduler import __main__ as scheduler_main
from campus.worker import __main__ as worker_main

TOPIC = "test.process"
# A schedule that never fires during a test: only the start-up run counts.
NEVER = "0 0 1 1 *"


def test_api_runs_uvicorn_with_configured_address(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    calls: list[dict[str, Any]] = []
    monkeypatch.setattr(uvicorn, "run", lambda _app, **kwargs: calls.append(kwargs))
    monkeypatch.setenv("CAMPUS_API_HOST", "0.0.0.0")  # noqa: S104
    monkeypatch.setenv("CAMPUS_API_PORT", "9000")

    api_main.main()

    [kwargs] = calls
    assert kwargs["host"] == "0.0.0.0"  # noqa: S104
    assert kwargs["port"] == 9000
    assert kwargs["factory"] is True
    assert kwargs["access_log"] is False
    assert kwargs["log_config"] is None


def test_api_factory_path_resolves_to_create_app() -> None:
    module = import_module("campus.api.app")

    assert module.create_app is create_app


@pytest.mark.parametrize("module", [worker_main, scheduler_main])
def test_process_main_runs_serve_until_signal(
    module: ModuleType, monkeypatch: pytest.MonkeyPatch
) -> None:
    services: list[Service] = []

    async def record(service: Service) -> None:
        services.append(service)

    monkeypatch.setattr(module, "run_until_signal", record)

    module.main()

    assert services == [module.serve]


@pytest.mark.parametrize("module", [worker_main, scheduler_main])
async def test_process_needs_redis(module: ModuleType) -> None:
    with pytest.raises(RedisNotConfiguredError):
        await module.serve(asyncio.Event())


def test_broker_has_periodic_tasks_on_configured_schedules() -> None:
    settings = Settings(
        redis_url=SecretStr("redis://localhost:6379/0"),
        deadlines_cron="*/5 * * * *",
        cleanup_cron="0 4 * * *",
    )

    broker = create_broker(settings)
    tasks = broker.get_all_tasks()

    assert tasks[DEADLINES_TASK].labels["schedule"][0]["cron"] == "*/5 * * * *"
    assert tasks[CLEANUP_TASK].labels["schedule"][0]["cron"] == "0 4 * * *"
    # Reconnects instead of failing while Redis is briefly unreachable.
    assert broker.connection_pool.connection_kwargs["retry"].get_retries() > 0  # type: ignore[attr-defined]


@pytest.fixture
async def services(
    redis_url: str, database_url: str, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Settings of the processes: the test database and an empty Redis."""
    client = redis.asyncio.from_url(redis_url)
    await client.flushdb()
    await client.aclose()
    monkeypatch.setenv("CAMPUS_REDIS_URL", redis_url)
    monkeypatch.setenv("CAMPUS_DATABASE_URL", database_url)
    monkeypatch.setenv("CAMPUS_OUTBOX_POLL_INTERVAL", "0.05")
    monkeypatch.setenv("CAMPUS_DEADLINES_CRON", NEVER)
    monkeypatch.setenv("CAMPUS_CLEANUP_CRON", NEVER)


@pytest.fixture
def sessions(engine: AsyncEngine) -> async_sessionmaker[AsyncSession]:
    return create_session_factory(engine)


class Handled:
    """Kinds of jobs run by the test handler of outbox messages and deadlines."""

    def __init__(self) -> None:
        self.kinds: list[str] = []
        self._events: defaultdict[str, asyncio.Event] = defaultdict(asyncio.Event)

    async def __call__(self, _session: AsyncSession, job: JobInfo) -> None:
        self.kinds.append(job.payload["kind"])
        self._events[job.payload["kind"]].set()

    async def wait(self, kind: str) -> None:
        await asyncio.wait_for(self._events[kind].wait(), timeout=10)


@pytest.fixture
def handled() -> Iterator[Handled]:
    handler = Handled()
    outbox_handlers.register(TOPIC)(handler)
    deadline_handlers.register(TOPIC)(handler)
    yield handler
    outbox_handlers.remove(TOPIC)
    deadline_handlers.remove(TOPIC)


def run(*services: Service) -> tuple[asyncio.Event, list[asyncio.Future[None]]]:
    stop = asyncio.Event()
    return stop, [asyncio.ensure_future(service(stop)) for service in services]


async def finish(stop: asyncio.Event, tasks: list[asyncio.Future[None]]) -> None:
    stop.set()
    await asyncio.wait_for(asyncio.gather(*tasks), timeout=10)


@pytest.mark.usefixtures("services")
async def test_worker_relays_the_outbox(
    sessions: async_sessionmaker[AsyncSession], handled: Handled
) -> None:
    stop, tasks = run(worker_main.serve)
    try:
        async with sessions() as session, session.begin():
            add_message(session, TOPIC, {"kind": "outbox"})

        await handled.wait("outbox")
    finally:
        await finish(stop, tasks)


@pytest.mark.usefixtures("services")
async def test_deadline_missed_while_scheduler_was_down_is_processed_on_start(
    sessions: async_sessionmaker[AsyncSession], handled: Handled
) -> None:
    # Due an hour ago: the scheduler was not running then.
    async with sessions() as session, session.begin():
        await schedule_deadline(
            session, TOPIC, clock.now() - timedelta(hours=1), {"kind": "deadline"}
        )
    stop, tasks = run(worker_main.serve)
    try:
        await asyncio.sleep(0.5)  # the worker alone does not process deadlines
        assert handled.kinds == []

        tasks.append(asyncio.ensure_future(scheduler_main.serve(stop)))

        await handled.wait("deadline")
        assert handled.kinds == ["deadline"]
    finally:
        await finish(stop, tasks)


@pytest.mark.usefixtures("services")
@pytest.mark.parametrize("module", [worker_main, scheduler_main])
async def test_process_stops_on_sigterm(
    module: ModuleType, capsys: pytest.CaptureFixture[str]
) -> None:
    asyncio.get_running_loop().call_later(0.5, os.kill, os.getpid(), signal.SIGTERM)

    await asyncio.wait_for(run_until_signal(module.serve), timeout=10)

    process = module.__name__.split(".")[1]
    assert f"{process}_stopped" in capsys.readouterr().out
