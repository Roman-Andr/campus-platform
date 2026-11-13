import asyncio
import json
import os
import signal
from importlib import import_module
from typing import Any

import pytest
import uvicorn

from campus.api import __main__ as api_main
from campus.api.app import create_app
from campus.core.runtime import Service, run_until_signal

STUB_PROCESSES = ["campus.worker.__main__", "campus.scheduler.__main__"]


def test_api_runs_uvicorn_with_configured_address(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    calls: list[dict[str, Any]] = []
    monkeypatch.setattr(uvicorn, "run", lambda _app, **kwargs: calls.append(kwargs))
    monkeypatch.setenv("CAMPUS_API_HOST", "0.0.0.0")  # noqa: S104
    monkeypatch.setenv("CAMPUS_API_PORT", "9000")

    api_main.main()

    [kwargs] = calls
    assert kwargs["host"] == "0.0.0.0"  # noqa: S104
    assert kwargs["port"] == 9000
    assert kwargs["factory"] is True
    assert kwargs["access_log"] is False
    assert kwargs["log_config"] is None


def test_api_factory_path_resolves_to_create_app() -> None:
    module = import_module("campus.api.app")

    assert module.create_app is create_app


@pytest.mark.parametrize("module_name", STUB_PROCESSES)
async def test_stub_process_stops_on_sigterm(module_name: str) -> None:
    serve = import_module(module_name).serve
    asyncio.get_running_loop().call_later(0.05, os.kill, os.getpid(), signal.SIGTERM)

    await asyncio.wait_for(run_until_signal(serve), timeout=5)


@pytest.mark.parametrize("module_name", STUB_PROCESSES)
def test_stub_process_logs_start_and_stop(
    module_name: str,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    module = import_module(module_name)

    async def stopped_at_once(service: Service) -> None:
        stop = asyncio.Event()
        stop.set()
        await service(stop)

    monkeypatch.setattr(module, "run_until_signal", stopped_at_once)

    module.main()

    process = module_name.split(".")[1]
    events = [json.loads(line) for line in capsys.readouterr().out.splitlines()]
    assert [(e["process"], e["event"]) for e in events] == [
        (process, f"{process}_started"),
        (process, f"{process}_stopped"),
    ]
