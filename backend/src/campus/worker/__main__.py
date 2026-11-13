"""Entry point of the worker process: ``campus-worker``.

A stub that waits for a stop signal; the real worker arrives with the
outbox and Taskiq (issue #29).
"""

import asyncio

import structlog

from campus.core.config import get_settings
from campus.core.observability import configure_observability
from campus.core.runtime import run_until_signal

logger = structlog.get_logger(__name__)


async def serve(stop: asyncio.Event) -> None:
    """Run until ``stop`` is set."""
    logger.info("worker_started")
    await stop.wait()
    logger.info("worker_stopped")


def main() -> None:
    """Start the worker process."""
    configure_observability(get_settings(), process="worker")
    asyncio.run(run_until_signal(serve))


if __name__ == "__main__":
    main()
