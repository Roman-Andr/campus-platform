import json
import logging
from typing import Any

import pytest
import structlog
from asgi_correlation_id import correlation_id

from campus.core.config import Settings
from campus.core.logging import REDACTED, configure_logging


def last_record(capsys: pytest.CaptureFixture[str]) -> dict[str, Any]:
    lines = capsys.readouterr().out.splitlines()
    record: dict[str, Any] = json.loads(lines[-1])
    return record


def test_records_are_json_with_context(
    settings: Settings, capsys: pytest.CaptureFixture[str]
) -> None:
    configure_logging(settings, process="worker")

    structlog.get_logger("campus.test").info("job_done", job="digest")

    record = last_record(capsys)
    assert record["event"] == "job_done"
    assert record["job"] == "digest"
    assert record["level"] == "info"
    assert record["logger"] == "campus.test"
    assert record["process"] == "worker"
    assert record["timestamp"].endswith("Z")


def test_records_below_configured_level_are_dropped(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.setenv("CAMPUS_LOG_LEVEL", "WARNING")
    configure_logging(Settings(), process="api")

    structlog.get_logger().info("noise")

    assert capsys.readouterr().out == ""


def test_personal_data_is_redacted(
    settings: Settings, capsys: pytest.CaptureFixture[str]
) -> None:
    configure_logging(settings, process="api")

    structlog.get_logger().info(
        "code sent to ivan.petrov@edu.example.org",
        email="ivan.petrov@edu.example.org",
        Authorization="Bearer token",
        user={"First-Name": "Ivan", "id": 7, "notes": ["mail me: a.b@example.org"]},
    )

    record = last_record(capsys)
    assert record["event"] == f"code sent to {REDACTED}"
    assert record["email"] == REDACTED
    assert record["Authorization"] == REDACTED
    assert record["user"] == {
        "First-Name": REDACTED,
        "id": 7,
        "notes": [f"mail me: {REDACTED}"],
    }


def test_standard_library_records_are_json_and_redacted(
    settings: Settings, capsys: pytest.CaptureFixture[str]
) -> None:
    configure_logging(settings, process="api")

    logging.getLogger("uvicorn.error").warning("bad login for %s", "x@example.org")

    record = last_record(capsys)
    assert record["event"] == f"bad login for {REDACTED}"
    assert record["logger"] == "uvicorn.error"
    assert record["level"] == "warning"


def test_positional_arguments_are_redacted(
    settings: Settings, capsys: pytest.CaptureFixture[str]
) -> None:
    configure_logging(settings, process="api")

    structlog.get_logger().info("invite %s to %s", "x@example.org", "chat")

    assert last_record(capsys)["event"] == f"invite {REDACTED} to chat"


def test_uvicorn_access_log_with_client_address_is_off(
    settings: Settings, capsys: pytest.CaptureFixture[str]
) -> None:
    configure_logging(settings, process="api")

    logging.getLogger("uvicorn.access").info("10.0.0.1:5000 - GET /")

    assert capsys.readouterr().out == ""


def test_uvicorn_color_message_is_dropped(
    settings: Settings, capsys: pytest.CaptureFixture[str]
) -> None:
    configure_logging(settings, process="api")

    logging.getLogger("uvicorn.error").info(
        "Started", extra={"color_message": "\x1b[36mStarted\x1b[0m"}
    )

    assert "color_message" not in last_record(capsys)


def test_http_client_request_urls_are_not_logged(
    settings: Settings, capsys: pytest.CaptureFixture[str]
) -> None:
    configure_logging(settings, process="worker")

    logging.getLogger("httpx2").info("HTTP Request: GET https://api.example.org/bot1")

    assert capsys.readouterr().out == ""


def test_exceptions_are_logged_without_local_variables(
    settings: Settings, capsys: pytest.CaptureFixture[str]
) -> None:
    configure_logging(settings, process="api")

    def fail(student_email: str) -> None:
        raise ValueError(len(student_email))

    try:
        fail("ivan.petrov@edu.example.org")
    except ValueError:
        structlog.get_logger().exception("failed")

    record = last_record(capsys)
    [error] = record["exception"]
    assert error["exc_type"] == "ValueError"
    assert error["frames"]
    assert "locals" not in error["frames"][-1]
    assert "ivan.petrov" not in json.dumps(record)


def test_request_id_is_attached(
    settings: Settings, capsys: pytest.CaptureFixture[str]
) -> None:
    configure_logging(settings, process="api")
    token = correlation_id.set("c" * 32)
    try:
        structlog.get_logger().info("handled")
    finally:
        correlation_id.reset(token)

    assert last_record(capsys)["request_id"] == "c" * 32


def test_console_format_is_human_readable(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.setenv("CAMPUS_LOG_FORMAT", "console")
    configure_logging(Settings(), process="api")

    structlog.get_logger().info("started", email="x@example.org")

    output = capsys.readouterr().out
    assert "started" in output
    assert "x@example.org" not in output
    with pytest.raises(json.JSONDecodeError):
        json.loads(output)
