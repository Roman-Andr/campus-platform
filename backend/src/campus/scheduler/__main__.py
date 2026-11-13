"""Entry point of the scheduler process: ``campus-scheduler``.

Sends the periodic tasks to the queue on their cron schedules (Taskiq
scheduler); the worker runs them. On start it sends the deadline task at
once, so deadlines missed while the scheduler was down are processed
without waiting for the next minute.
"""

import asyncio
import contextlib

import structlog
from taskiq import TaskiqScheduler
from taskiq.api import run_scheduler_task
from taskiq.schedule_sources import LabelScheduleSource

from campus.core.config import get_settings
from campus.core.observability import configure_observability
from campus.core.runtime import run_until_signal
from campus.core.tasks import DEADLINES_TASK, create_broker, kick

logger = structlog.get_logger(__name__)


async def serve(stop: asyncio.Event) -> None:
    """Send scheduled tasks until ``stop`` is set."""
    broker = create_broker(get_settings())
    scheduler = TaskiqScheduler(broker, sources=[LabelScheduleSource(broker)])
    await broker.startup()
    logger.info("scheduler_started")
    try:
        await kick(broker, DEADLINES_TASK)
        loop = asyncio.create_task(run_scheduler_task(scheduler), name="scheduler")
        await stop.wait()
        loop.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await loop
    finally:
        await broker.shutdown()
        logger.info("scheduler_stopped")


def main() -> None:
    """Start the scheduler process."""
    configure_observability(get_settings(), process="scheduler")
    asyncio.run(run_until_signal(serve))


if __name__ == "__main__":
    main()
