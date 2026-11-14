"""Taskiq receiver of the worker with a graceful stop.

``taskiq.api.run_receiver_task`` stops only by cancellation, which leaves
the tasks already running behind: they keep using the database after the
worker has shut its resources down. :func:`receive_tasks` stops fetching
when the stop event is set and waits for the running tasks; cancelling it
cancels them and waits until they are finished.
"""

import asyncio
import contextlib
from concurrent.futures import ThreadPoolExecutor
from typing import Any

import structlog
from taskiq import AckableMessage, AsyncBroker
from taskiq.receiver import Receiver

logger = structlog.get_logger(__name__)

# Most tasks run at once by one worker process.
MAX_RUNNING_TASKS = 100
# Seconds before listening again after the receiver failed (e.g. Redis is
# unreachable longer than the reconnection attempts of the broker).
RESTART_DELAY = 1.0


class _TrackingReceiver(Receiver):
    """Receiver that keeps its running tasks in ``running``."""

    def __init__(
        self, *args: Any, running: set[asyncio.Task[Any]], **kwargs: Any
    ) -> None:
        super().__init__(*args, **kwargs)
        self._running = running

    async def callback(
        self, message: bytes | AckableMessage, raise_err: bool = False
    ) -> None:
        # The receiver runs every callback in a task of its own.
        task = asyncio.current_task()
        assert task is not None  # noqa: S101 - always inside a task
        self._running.add(task)
        try:
            await super().callback(message, raise_err=raise_err)
        finally:
            self._running.discard(task)


async def receive_tasks(broker: AsyncBroker, stop: asyncio.Event) -> None:
    """Run queued tasks until ``stop`` is set, then wait for running ones.

    Cancelling cancels the running tasks and returns once they finished, so
    nothing of the receiver outlives it.
    """
    running: set[asyncio.Task[Any]] = set()
    with ThreadPoolExecutor() as executor:
        try:
            while not stop.is_set():
                receiver = _TrackingReceiver(
                    broker,
                    executor,
                    running=running,
                    max_async_tasks=MAX_RUNNING_TASKS,
                    run_startup=False,
                )
                try:
                    await receiver.listen(stop)
                except Exception:
                    logger.exception("task_receiver_error")
                    with contextlib.suppress(TimeoutError):
                        await asyncio.wait_for(stop.wait(), RESTART_DELAY)
            # Tasks of a failed receiver are not awaited by a later one.
            if running:
                await asyncio.wait(set(running))
        finally:
            await _cancel(running)


async def _cancel(tasks: set[asyncio.Task[Any]]) -> None:
    """Cancel ``tasks`` and wait until they are finished."""
    pending = set(tasks)
    if not pending:
        return
    logger.warning("running_tasks_cancelled", count=len(pending))
    for task in pending:
        task.cancel()
    await asyncio.gather(*pending, return_exceptions=True)
