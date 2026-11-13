import json
from typing import Any

import pytest
from fastapi.testclient import TestClient

from campus.api.app import create_app
from campus.core.config import Settings


def records(output: str) -> list[dict[str, Any]]:
    return [json.loads(line) for line in output.splitlines() if line]


def access_records(output: str) -> list[dict[str, Any]]:
    return [r for r in records(output) if r["event"] == "http_request"]


# The app is built inside each test: logging writes to the sys.stdout that
# is current at configuration time, and capsys replaces it per test phase.


def test_request_is_logged_without_query_or_client_data(
    settings: Settings, capsys: pytest.CaptureFixture[str]
) -> None:
    with TestClient(create_app(settings)) as client:
        client.get(
            "/api/v1/health?email=student@example.org",
            headers={"X-Request-ID": "b" * 32, "Authorization": "Bearer secret"},
        )

    output = capsys.readouterr().out
    [record] = access_records(output)
    assert record["method"] == "GET"
    assert record["path"] == "/api/v1/health"
    assert record["status_code"] == 200
    assert record["request_id"] == "b" * 32
    assert record["process"] == "api"
    assert isinstance(record["duration_ms"], float)
    for leaked in ("student@example.org", "secret", "testclient"):
        assert leaked not in output


def test_failed_request_is_logged_as_server_error(
    settings: Settings, capsys: pytest.CaptureFixture[str]
) -> None:
    app = create_app(settings)

    @app.get("/boom")
    async def boom() -> None:
        raise RuntimeError

    with TestClient(app, raise_server_exceptions=False) as test_client:
        assert test_client.get("/boom").status_code == 500

    [record] = access_records(capsys.readouterr().out)
    assert record["status_code"] == 500
