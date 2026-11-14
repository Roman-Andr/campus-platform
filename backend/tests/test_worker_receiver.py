"""Restart of the worker receiver after a failure, without Redis."""

import asyncio
from typing import Any

import pytest
from pydantic import SecretStr

from campus.core.config import Settings
from campus.core.tasks import create_broker
from campus.worker import receiver as receiver_module
from campus.worker.receiver import receive_tasks


async def test_receiver_listens_again_after_failure(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    broker = create_broker(Settings(redis_url=SecretStr("redis://localhost:6379/0")))
    stop = asyncio.Event()
    calls: list[int] = []

    async def listen(_receiver: Any, finish_event: asyncio.Event) -> None:
        calls.append(len(calls))
        if len(calls) == 1:
            raise ConnectionError
        finish_event.set()

    monkeypatch.setattr(receiver_module, "RESTART_DELAY", 0.0)
    monkeypatch.setattr(receiver_module._TrackingReceiver, "listen", listen)

    await asyncio.wait_for(receive_tasks(broker, stop), timeout=5)

    assert calls == [0, 1]
