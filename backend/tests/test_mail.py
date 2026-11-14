"""Mail goes out through the outbox; Mailpit stands in for the SMTP server."""

import json
import urllib.request
from collections.abc import Iterator
from email import message_from_bytes
from email.message import EmailMessage
from typing import Any
from uuid import UUID

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker

from campus.core.config import Settings, get_settings
from campus.core.db import create_session_factory
from campus.core.jobs import JobInfo
from campus.core.mail import (
    MAIL_TOPIC,
    MailNotConfiguredError,
    build_message,
    queue_email,
    send_message,
)
from campus.core.outbox import OutboxMessage, process_outbox
from tests.services import Mailpit

JOB = JobInfo(
    id=UUID("01890a5d-ac96-774b-bcce-b302099a8057"),
    topic=MAIL_TOPIC,
    payload={"to": "a@example.org", "subject": "Hi", "text": "Plain", "html": None},
    attempt=1,
)


def request(mailpit: Mailpit, path: str, method: str = "GET") -> bytes:
    url = f"{mailpit.api_url}{path}"
    # A local test server over plain HTTP.
    http_request = urllib.request.Request(url, method=method)  # noqa: S310
    with urllib.request.urlopen(http_request, timeout=5) as response:  # noqa: S310
        body: bytes = response.read()
    return body


def api(mailpit: Mailpit, path: str) -> Any:
    return json.loads(request(mailpit, path))


@pytest.fixture
def smtp_environment(
    mailpit: Mailpit, monkeypatch: pytest.MonkeyPatch
) -> Iterator[None]:
    """Point the process settings at Mailpit and start with an empty box."""
    monkeypatch.setenv("CAMPUS_SMTP_HOST", mailpit.smtp_host)
    monkeypatch.setenv("CAMPUS_SMTP_PORT", str(mailpit.smtp_port))
    monkeypatch.setenv("CAMPUS_SMTP_SECURITY", "none")
    monkeypatch.setenv("CAMPUS_MAIL_FROM", "Campus <noreply@campus.test>")
    get_settings.cache_clear()
    request(mailpit, "/messages", method="DELETE")
    yield
    get_settings.cache_clear()


@pytest.fixture
def sessions(engine: AsyncEngine) -> async_sessionmaker[AsyncSession]:
    return create_session_factory(engine)


@pytest.mark.usefixtures("smtp_environment")
async def test_email_queued_through_outbox_is_delivered_to_mailpit(
    sessions: async_sessionmaker[AsyncSession], mailpit: Mailpit
) -> None:
    async with sessions() as session, session.begin():
        queue_email(
            session,
            to="student@university.example",
            subject="Код входа",
            text="Ваш код: 123456",
            html="<p>Ваш код: <b>123456</b></p>",
        )
    # Nothing is sent before the worker processes the outbox.
    assert api(mailpit, "/messages")["total"] == 0

    assert await process_outbox(sessions, Settings()) == 1

    [summary] = api(mailpit, "/messages")["messages"]
    assert summary["Subject"] == "Код входа"
    assert [to["Address"] for to in summary["To"]] == ["student@university.example"]
    assert summary["From"]["Address"] == "noreply@campus.test"
    message = api(mailpit, f"/message/{summary['ID']}")
    assert message["Text"].strip() == "Ваш код: 123456"
    assert "<b>123456</b>" in message["HTML"]
    async with sessions() as session:
        outbox = (await session.scalars(select(OutboxMessage))).one()
        outbox_id = outbox.id
        assert outbox.payload == {}
        assert outbox.processed_at is not None
    assert summary["MessageID"] == f"{outbox_id}@campus.test"


async def test_unreachable_server_leaves_the_letter_for_a_retry(
    sessions: async_sessionmaker[AsyncSession], monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("CAMPUS_SMTP_HOST", "127.0.0.1")
    monkeypatch.setenv("CAMPUS_SMTP_PORT", "9")  # discard port: refused
    monkeypatch.setenv("CAMPUS_SMTP_TIMEOUT", "2")
    async with sessions() as session, session.begin():
        queue_email(session, to="a@example.org", subject="Hi", text="Plain")

    await process_outbox(sessions, Settings())

    async with sessions() as session:
        message = (await session.scalars(select(OutboxMessage))).one()
    assert message.processed_at is None
    assert message.attempts == 1
    assert message.last_error is not None


def test_message_without_html_is_plain_text() -> None:
    message = build_message(Settings(), JOB)

    assert message["From"] == "Campus <noreply@campus.localhost>"
    assert message["To"] == "a@example.org"
    assert message["Message-ID"] == f"<{JOB.id}@campus.localhost>"
    assert message.get_content_type() == "text/plain"
    assert message_from_bytes(message.as_bytes())["Subject"] == "Hi"


async def test_sending_without_server_is_an_error() -> None:
    with pytest.raises(MailNotConfiguredError):
        await send_message(Settings(), EmailMessage())


@pytest.mark.parametrize(
    ("security", "use_tls", "start_tls"),
    [("none", False, False), ("starttls", False, True), ("tls", True, False)],
)
async def test_smtp_security_and_credentials_are_passed(
    monkeypatch: pytest.MonkeyPatch,
    security: str,
    use_tls: bool,
    start_tls: bool,
) -> None:
    calls: list[dict[str, Any]] = []

    async def fake_send(_message: EmailMessage, **kwargs: Any) -> None:
        calls.append(kwargs)

    monkeypatch.setattr("aiosmtplib.send", fake_send)
    settings = Settings.model_validate(
        {
            "smtp_host": "smtp.example.org",
            "smtp_security": security,
            "smtp_username": "campus",
            "smtp_password": "secret",
        }
    )

    await send_message(settings, EmailMessage())

    [kwargs] = calls
    assert kwargs["hostname"] == "smtp.example.org"
    assert kwargs["port"] == 587
    assert (kwargs["use_tls"], kwargs["start_tls"]) == (use_tls, start_tls)
    assert (kwargs["username"], kwargs["password"]) == ("campus", "secret")
