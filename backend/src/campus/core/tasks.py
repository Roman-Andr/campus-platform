"""Task queue: Taskiq with a Redis Streams broker (specification, 5.5.2).

The scheduler sends periodic tasks to Redis on their cron schedules; the
worker receives and runs them. Periodic tasks only start database-driven
work (:mod:`campus.core.deadlines`, retention cleanup), so a lost or
duplicated run is harmless: the next one catches up, and concurrent runs
share the work through ``FOR UPDATE SKIP LOCKED``.

Modules declare their own tasks with :data:`task` (Taskiq shared tasks);
they are sent through the broker made by :func:`create_broker`. Modules add
retention rules of their own tables to the cleanup task with
:func:`register_cleanup`.
"""

from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from typing import Annotated

import structlog
from redis.asyncio.retry import Retry
from redis.backoff import ExponentialWithJitterBackoff
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker
from taskiq import (
    AsyncBroker,
    Context,
    TaskiqDepends,
    TaskiqEvents,
    TaskiqState,
    async_shared_broker,
)
from taskiq.kicker import AsyncKicker
from taskiq_redis import RedisStreamBroker

from campus.core import clock
from campus.core.config import Settings
from campus.core.db import create_engine, create_session_factory
from campus.core.deadlines import delete_finished_deadlines, process_due_deadlines
from campus.core.idempotency import delete_expired_idempotency_keys
from campus.core.metrics import Metrics, TaskMetricsMiddleware
from campus.core.outbox import delete_finished_messages
from campus.core.queue_names import CONSUMER_GROUP, QUEUE_NAME

logger = structlog.get_logger(__name__)

task = async_shared_broker.task

DEADLINES_TASK = "campus.deadlines.process_due"
CLEANUP_TASK = "campus.cleanup.delete_expired"

# Approximate number of entries kept in the stream; delivered entries stay
# in a Redis stream until trimmed.
STREAM_MAXLEN = 10_000
# Seconds; frees the lock of a worker that died while claiming stale tasks.
AUTOCLAIM_LOCK_TIMEOUT = 10.0
# Reconnection to Redis on connection errors and timeouts: at start-up the
# network of a container may lag behind, and Redis may restart. Backoff
# with jitter, capped at 10 s, for about a minute in total.
REDIS_RETRIES = 8
REDIS_BACKOFF_CAP = 10.0


type Cleanup = Callable[
    [async_sessionmaker[AsyncSession], Settings], Awaitable[dict[str, int]]
]
"""Deletes expired records of a module; returns deleted counts by kind."""

_cleanups: dict[str, Cleanup] = {}


def register_cleanup(name: str) -> Callable[[Cleanup], Cleanup]:
    """Decorator: run the decorated coroutine in the cleanup task.

    A cleanup must be idempotent: a repeated or concurrent run deletes
    nothing more. Modules register cleanups when imported, so the worker
    imports all modules first. Counts are logged as ``<name>_<kind>``.
    """

    def decorator(cleanup: Cleanup) -> Cleanup:
        if name in _cleanups:
            msg = f"a cleanup {name!r} is already registered"
            raise ValueError(msg)
        _cleanups[name] = cleanup
        return cleanup

    return decorator


class RedisNotConfiguredError(RuntimeError):
    """CAMPUS_REDIS_URL is required but not set."""

    def __init__(self) -> None:
        super().__init__("CAMPUS_REDIS_URL is not set")


@dataclass(frozen=True)
class WorkerResources:
    """What tasks use in the worker process; kept in the broker state."""

    settings: Settings
    engine: AsyncEngine
    sessions: async_sessionmaker[AsyncSession]


def create_broker(settings: Settings, metrics: Metrics | None = None) -> AsyncBroker:
    """Create the Redis broker with the tasks of the application."""
    if settings.redis_url is None:
        raise RedisNotConfiguredError
    broker = RedisStreamBroker(
        settings.redis_url.get_secret_value(),
        queue_name=QUEUE_NAME,
        consumer_group_name=CONSUMER_GROUP,
        maxlen=STREAM_MAXLEN,
        unacknowledged_lock_timeout=AUTOCLAIM_LOCK_TIMEOUT,
        retry=Retry(ExponentialWithJitterBackoff(cap=REDIS_BACKOFF_CAP), REDIS_RETRIES),
    )
    if metrics is not None:
        broker.add_middlewares(TaskMetricsMiddleware(metrics))
    configure_broker(broker, settings)
    return broker


def configure_broker(broker: AsyncBroker, settings: Settings) -> None:
    """Register the periodic tasks and worker resources on ``broker``."""
    async_shared_broker.default_broker(broker)

    async def start_worker(state: TaskiqState) -> None:
        engine = create_engine(settings)
        state.resources = WorkerResources(
            settings=settings, engine=engine, sessions=create_session_factory(engine)
        )

    async def stop_worker(state: TaskiqState) -> None:
        resources: WorkerResources = state.resources
        await resources.engine.dispose()

    broker.add_event_handler(TaskiqEvents.WORKER_STARTUP, start_worker)
    broker.add_event_handler(TaskiqEvents.WORKER_SHUTDOWN, stop_worker)
    broker.register_task(
        _process_due_deadlines,
        DEADLINES_TASK,
        schedule=[{"cron": settings.deadlines_cron, "schedule_id": "deadlines"}],
    )
    broker.register_task(
        _delete_expired,
        CLEANUP_TASK,
        schedule=[{"cron": settings.cleanup_cron, "schedule_id": "cleanup"}],
    )


def worker_resources(broker: AsyncBroker) -> WorkerResources:
    """Resources of a started worker broker."""
    resources: WorkerResources = broker.state.resources
    return resources


async def kick(broker: AsyncBroker, task_name: str) -> None:
    """Send a task without arguments by name."""
    await AsyncKicker(task_name, broker, {}).kiq()


async def _process_due_deadlines(
    context: Annotated[Context, TaskiqDepends()],
) -> int:
    resources: WorkerResources = context.state.resources
    processed = await process_due_deadlines(resources.sessions, resources.settings)
    if processed:
        logger.info("deadlines_processed", count=processed)
    return processed


async def _delete_expired(context: Annotated[Context, TaskiqDepends()]) -> None:
    resources: WorkerResources = context.state.resources
    sessions, settings = resources.sessions, resources.settings
    async with sessions() as session, session.begin():
        idempotency_keys = await delete_expired_idempotency_keys(session, clock.now())
    counts = {
        "outbox_messages": await delete_finished_messages(sessions, settings),
        "deadlines": await delete_finished_deadlines(sessions, settings),
        "idempotency_keys": idempotency_keys,
    }
    for name, cleanup in _cleanups.items():
        for kind, deleted in (await cleanup(sessions, settings)).items():
            counts[f"{name}_{kind}"] = deleted
    logger.info("expired_records_deleted", **counts)
