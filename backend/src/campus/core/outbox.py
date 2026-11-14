"""Transactional outbox (specification, 4.3): side effects after commit.

A module writes a message with :func:`add_message` in the transaction that
changes its data, so the message exists if and only if the change is
committed. The worker polls the table (:func:`relay_outbox`) and runs the
handler of the message topic, registered with
``@outbox_handlers.register(topic)``, with retries (:mod:`campus.core.jobs`).

A topic names one action of one consumer, e.g. ``notifications.send``; an
event with several consumers is written as several messages, so that each
consumer is retried on its own. Messages are not ordered across retries.
"""

import asyncio
import contextlib
from typing import Any

import structlog
from sqlalchemy import Index, text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from campus.core import clock
from campus.core.config import Settings
from campus.core.jobs import (
    Handlers,
    Job,
    RetryPolicy,
    delete_finished_jobs,
    run_due_jobs,
)

logger = structlog.get_logger(__name__)

outbox_handlers = Handlers()


class OutboxMessage(Job):
    __tablename__ = "outbox_message"
    __table_args__ = (
        Index(
            "ix_outbox_message_pending",
            "available_at",
            postgresql_where=text("processed_at IS NULL AND failed_at IS NULL"),
        ),
    )


def add_message(session: AsyncSession, topic: str, payload: dict[str, Any]) -> None:
    """Add a message to the outbox in the current transaction of ``session``.

    ``payload`` must be JSON-serialisable.
    """
    session.add(OutboxMessage(topic=topic, payload=payload, available_at=clock.now()))


async def process_outbox(
    sessions: async_sessionmaker[AsyncSession], settings: Settings
) -> int:
    """Run the due outbox messages, at most one batch; return their number."""
    return await run_due_jobs(
        sessions,
        OutboxMessage,
        outbox_handlers,
        RetryPolicy.from_settings(settings),
        limit=settings.job_batch_size,
    )


async def relay_outbox(
    sessions: async_sessionmaker[AsyncSession],
    settings: Settings,
    stop: asyncio.Event,
) -> None:
    """Process the outbox until ``stop`` is set.

    A full batch is followed by the next one at once; otherwise the relay
    waits for the poll interval.
    """
    logger.info("outbox_relay_started")
    while not stop.is_set():
        try:
            attempted = await process_outbox(sessions, settings)
        except Exception:
            # E.g. the database is unavailable: keep polling until it is back.
            logger.exception("outbox_relay_error")
            attempted = 0
        if attempted < settings.job_batch_size:
            with contextlib.suppress(TimeoutError):
                await asyncio.wait_for(stop.wait(), settings.outbox_poll_interval)
    logger.info("outbox_relay_stopped")


async def delete_finished_messages(
    sessions: async_sessionmaker[AsyncSession], settings: Settings
) -> int:
    """Delete messages finished longer than the retention period ago."""
    return await delete_finished_jobs(
        sessions,
        OutboxMessage,
        retention=settings.outbox_retention,
    )
