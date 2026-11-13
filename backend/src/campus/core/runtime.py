"""Lifecycle helpers for long-running processes."""

import asyncio
import signal
from collections.abc import Awaitable, Callable

type Service = Callable[[asyncio.Event], Awaitable[None]]


async def run_until_signal(service: Service) -> None:
    """Run ``service`` until SIGINT or SIGTERM sets its stop event."""
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    signals = (signal.SIGINT, signal.SIGTERM)
    for sig in signals:
        loop.add_signal_handler(sig, stop.set)
    try:
        await service(stop)
    finally:
        for sig in signals:
            loop.remove_signal_handler(sig)
