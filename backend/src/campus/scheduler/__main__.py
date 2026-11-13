"""Entry point of the scheduler process: ``campus-scheduler``.

A stub that waits for a stop signal; the real scheduler arrives with the
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
    logger.info("scheduler_started")
    await stop.wait()
    logger.info("scheduler_stopped")


def main() -> None:
    """Start the scheduler process."""
    configure_observability(get_settings(), process="scheduler")
    asyncio.run(run_until_signal(serve))


if __name__ == "__main__":
    main()
