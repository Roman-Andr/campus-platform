"""Durable background jobs stored in the database (specification, 4.3, 5.2).

The outbox (:mod:`campus.core.outbox`) and deadlines
(:mod:`campus.core.deadlines`) share this machinery: a job is a row with a
topic and a JSON payload that becomes due at ``available_at``. A runner
claims one due row at a time with ``FOR UPDATE SKIP LOCKED``, so any number
of concurrent runners never run the same job twice, and runs the handler of
the topic in the same transaction as the mark of completion: database side
effects of a handler happen exactly once. A failed attempt is rolled back
and retried with exponential backoff; after the last attempt the job is
marked failed.
"""

from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Any
from uuid import UUID

import structlog
from sqlalchemy import ColumnElement, String, Text, and_, delete, or_, select
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker
from sqlalchemy.orm import Mapped, mapped_column

from campus.core import clock
from campus.core.config import Settings
from campus.core.db import Entity

logger = structlog.get_logger(__name__)

# Longest error text kept on a job row.
_ERROR_LIMIT = 2000


class Job(Entity):
    """Columns shared by job tables; pending means not processed, not failed."""

    __abstract__ = True

    topic: Mapped[str] = mapped_column(String(100))
    payload: Mapped[dict[str, Any]] = mapped_column(JSONB)
    # The job is not run before this time: the deadline or the next retry.
    available_at: Mapped[datetime]
    attempts: Mapped[int] = mapped_column(default=0)
    last_error: Mapped[str | None] = mapped_column(Text)
    processed_at: Mapped[datetime | None]
    failed_at: Mapped[datetime | None]

    @classmethod
    def is_pending(cls) -> ColumnElement[bool]:
        return and_(cls.processed_at.is_(None), cls.failed_at.is_(None))


@dataclass(frozen=True)
class JobInfo:
    """What a handler learns about the job it runs.

    ``id`` is stable across attempts: use it to make an external side effect
    idempotent, e.g. as a message identifier.
    """

    id: UUID
    topic: str
    payload: dict[str, Any]
    attempt: int


type Handler = Callable[[AsyncSession, JobInfo], Awaitable[None]]


class UnknownTopicError(LookupError):
    """No handler is registered for the topic of a job."""

    def __init__(self, topic: str) -> None:
        super().__init__(f"no handler for topic {topic!r}")


class Handlers:
    """Handlers of a job table by topic: one handler per topic.

    Modules register handlers when imported, so every process that runs
    jobs imports all modules first.
    """

    def __init__(self) -> None:
        self._handlers: dict[str, Handler] = {}

    def register(self, topic: str) -> Callable[[Handler], Handler]:
        """Decorator: run the decorated coroutine for jobs of ``topic``."""

        def decorator(handler: Handler) -> Handler:
            if topic in self._handlers:
                msg = f"a handler for topic {topic!r} is already registered"
                raise ValueError(msg)
            self._handlers[topic] = handler
            return handler

        return decorator

    def remove(self, topic: str) -> None:
        """Forget the handler of ``topic`` (for tests)."""
        del self._handlers[topic]

    def get(self, topic: str) -> Handler:
        try:
            return self._handlers[topic]
        except KeyError:
            raise UnknownTopicError(topic) from None


@dataclass(frozen=True)
class RetryPolicy:
    """How many times a job is attempted and how long to wait in between."""

    max_attempts: int
    base_delay: timedelta
    max_delay: timedelta

    @classmethod
    def from_settings(cls, settings: Settings) -> RetryPolicy:
        return cls(
            max_attempts=settings.job_max_attempts,
            base_delay=settings.job_retry_base_delay,
            max_delay=settings.job_retry_max_delay,
        )

    def delay(self, attempts: int) -> timedelta:
        """Wait before the next attempt after ``attempts`` failed ones."""
        return min(self.base_delay * (1 << (attempts - 1)), self.max_delay)


async def run_due_jobs(
    sessions: async_sessionmaker[AsyncSession],
    model: type[Job],
    handlers: Handlers,
    policy: RetryPolicy,
    *,
    limit: int,
) -> int:
    """Run up to ``limit`` due jobs, each in its own transaction.

    Returns the number of jobs attempted; fewer than ``limit`` means no
    due job is left (or the rest are locked by other runners).
    """
    attempted = 0
    while attempted < limit:
        async with sessions() as session, session.begin():
            job = await session.scalar(
                select(model)
                .where(model.is_pending(), model.available_at <= clock.now())
                .order_by(model.available_at, model.id)
                .limit(1)
                .with_for_update(skip_locked=True)
            )
            if job is None:
                break
            await _attempt(session, job, handlers, policy)
        attempted += 1
    return attempted


async def _attempt(
    session: AsyncSession, job: Job, handlers: Handlers, policy: RetryPolicy
) -> None:
    job.attempts += 1
    info = JobInfo(
        id=job.id, topic=job.topic, payload=job.payload, attempt=job.attempts
    )
    log = logger.bind(table=job.__tablename__, job_id=str(job.id), topic=job.topic)
    try:
        handler = handlers.get(job.topic)
        # A failed handler leaves no trace: its changes roll back to here.
        async with session.begin_nested():
            await handler(session, info)
    except Exception as error:  # any failure is retried
        now = clock.now()
        job.last_error = f"{type(error).__name__}: {error}"[:_ERROR_LIMIT]
        if job.attempts >= policy.max_attempts:
            job.failed_at = now
            log.error("job_failed", attempts=job.attempts, exc_info=error)
        else:
            job.available_at = now + policy.delay(job.attempts)
            log.warning(
                "job_attempt_failed",
                attempts=job.attempts,
                retry_at=job.available_at.isoformat(),
                error=type(error).__name__,
            )
    else:
        job.processed_at = clock.now()
        job.last_error = None
        log.debug("job_processed", attempts=job.attempts)


async def delete_finished_jobs(
    sessions: async_sessionmaker[AsyncSession],
    model: type[Job],
    *,
    retention: timedelta,
) -> int:
    """Delete jobs processed or failed more than ``retention`` ago."""
    cutoff = clock.now() - retention
    async with sessions() as session, session.begin():
        result = await session.execute(
            delete(model).where(
                or_(model.processed_at < cutoff, model.failed_at < cutoff)
            )
        )
    deleted: int = result.rowcount  # type: ignore[attr-defined]
    return deleted
