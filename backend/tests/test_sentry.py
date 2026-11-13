import json
from collections.abc import Iterator

import pytest
import sentry_sdk
from sentry_sdk.types import Breadcrumb, Event

from campus import __version__
from campus.core.config import Settings
from campus.core.logging import REDACTED
from campus.core.sentry import configure_sentry, redact_breadcrumb, redact_event

DSN = "https://public@errors.example.invalid/1"


@pytest.fixture(autouse=True)
def disable_sentry() -> Iterator[None]:
    yield
    sentry_sdk.init()


def test_sentry_stays_off_without_dsn(settings: Settings) -> None:
    assert configure_sentry(settings, process="api") is False
    assert not sentry_sdk.get_client().is_active()


def test_sentry_is_enabled_by_dsn_without_personal_data(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("CAMPUS_SENTRY_DSN", DSN)
    monkeypatch.setenv("CAMPUS_ENVIRONMENT", "staging")

    assert configure_sentry(Settings(), process="worker") is True

    client = sentry_sdk.get_client()
    assert client.is_active()
    assert client.options["dsn"] == DSN
    assert client.options["environment"] == "staging"
    assert client.options["release"] == f"campus@{__version__}"
    collection = client.options["data_collection"]
    assert collection["user_info"] is False
    assert collection["stack_frame_variables"] is False
    assert collection["http_bodies"] == []
    assert collection["http_headers"]["request"]["mode"] == "off"
    assert collection["cookies"]["mode"] == "off"
    assert collection["url_query_params"]["mode"] == "off"
    assert sentry_sdk.get_isolation_scope()._tags["process"] == "worker"


def test_sentry_release_comes_from_settings(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("CAMPUS_SENTRY_DSN", DSN)
    monkeypatch.setenv("CAMPUS_RELEASE", "abc123")

    configure_sentry(Settings(), process="api")

    assert sentry_sdk.get_client().options["release"] == "abc123"


def test_events_are_sent_without_personal_data(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    sent: list[Event] = []
    monkeypatch.setenv("CAMPUS_SENTRY_DSN", DSN)
    configure_sentry(Settings(), process="api")
    monkeypatch.setattr(
        sentry_sdk.get_client().transport,
        "capture_envelope",
        lambda envelope: sent.extend(
            item.get_event() for item in envelope.items if item.get_event()
        ),
    )

    def fail(student_email: str) -> None:
        raise ValueError(student_email)

    email = "@".join(("ivan.petrov", "edu.example.org"))
    try:
        fail(email)
    except ValueError as error:
        sentry_sdk.capture_exception(error)
    sentry_sdk.flush()

    [event] = sent
    assert email not in json.dumps(event, default=str)
    [exception] = event["exception"]["values"]
    assert exception["value"] == REDACTED
    assert all("vars" not in frame for frame in exception["stacktrace"]["frames"])


def test_event_hook_redacts_messages_and_extra_data() -> None:
    event: Event = {
        "logentry": {"message": "login %s", "params": ["a@example.org"]},
        "extra": {"email": "a@example.org", "attempt": 2},
        "exception": {"values": [{"type": "KeyError"}]},
    }

    redacted = redact_event(event, {})

    assert redacted["logentry"] == {"message": "login %s", "params": [REDACTED]}
    assert redacted["extra"] == {"email": REDACTED, "attempt": 2}


def test_breadcrumb_hook_redacts_messages_and_data() -> None:
    crumb: Breadcrumb = {
        "message": "sent to a@example.org",
        "data": {"phone": "+70000000000"},
        "category": "log",
    }

    assert redact_breadcrumb(crumb, {}) == {
        "message": f"sent to {REDACTED}",
        "data": {"phone": REDACTED},
        "category": "log",
    }
    assert redact_breadcrumb({"category": "http"}, {}) == {"category": "http"}
