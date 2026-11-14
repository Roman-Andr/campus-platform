"""Entry point of the worker process: ``campus-worker``.

Runs two loops until a stop signal: the outbox relay, which polls the
outbox table, and the Taskiq receiver, which runs tasks from Redis (the
periodic tasks of the scheduler and tasks of the modules).

On the signal both loops stop taking new work and finish the running one
within ``CAMPUS_WORKER_SHUTDOWN_TIMEOUT``; what is still running then is
cancelled (its transaction rolls back and the job is retried later). The
database and Redis are closed only after that.
"""

import asyncio
import contextlib

import structlog

import campus.core.mail  # noqa: F401 - registers the mail handler
from campus import modules
from campus.core.config import get_settings
from campus.core.observability import configure_observability
from campus.core.outbox import relay_outbox
from campus.core.runtime import run_until_signal
from campus.core.tasks import create_broker, worker_resources
from campus.worker.receiver import receive_tasks

logger = structlog.get_logger(__name__)


async def serve(stop: asyncio.Event) -> None:
    """Relay the outbox and run queued tasks until ``stop`` is set."""
    modules.import_all()
    settings = get_settings()
    broker = create_broker(settings)
    broker.is_worker_process = True
    await broker.startup()
    logger.info("worker_started")
    try:
        resources = worker_resources(broker)
        loops = [
            asyncio.create_task(receive_tasks(broker, stop), name="receiver"),
            asyncio.create_task(
                relay_outbox(resources.sessions, settings, stop), name="outbox"
            ),
        ]
        await stop.wait()
        _, overdue = await asyncio.wait(
            loops, timeout=settings.worker_shutdown_timeout.total_seconds()
        )
        for loop in overdue:
            loop.cancel()
        for loop in loops:
            with contextlib.suppress(asyncio.CancelledError):
                await loop
    finally:
        await broker.shutdown()
        logger.info("worker_stopped")


def main() -> None:
    """Start the worker process."""
    configure_observability(get_settings(), process="worker")
    asyncio.run(run_until_signal(serve))


if __name__ == "__main__":
    main()
