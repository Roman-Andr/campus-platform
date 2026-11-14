"""Entry point of the worker process: ``campus-worker``.

Runs two loops until a stop signal: the outbox relay, which polls the
outbox table, and the Taskiq receiver, which runs tasks from Redis (the
periodic tasks of the scheduler and tasks of the modules).
"""

import asyncio
import contextlib

import structlog
from taskiq.api import run_receiver_task

import campus.core.mail  # noqa: F401 - registers the mail handler
from campus import modules
from campus.core.config import get_settings
from campus.core.observability import configure_observability
from campus.core.outbox import relay_outbox
from campus.core.runtime import run_until_signal
from campus.core.tasks import create_broker, worker_resources

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
            asyncio.create_task(run_receiver_task(broker), name="receiver"),
            asyncio.create_task(
                relay_outbox(resources.sessions, settings, stop), name="outbox"
            ),
        ]
        await stop.wait()
        for loop in loops:
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
