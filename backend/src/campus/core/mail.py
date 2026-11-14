"""Outgoing mail through the outbox: SMTP, Mailpit in development.

:func:`queue_email` writes the letter to the outbox in the caller's
transaction; the worker sends it over SMTP with retries. The Message-ID is
derived from the outbox message, so a letter resent after a lost
acknowledgement keeps its identifier.
"""

from email.message import EmailMessage
from email.utils import format_datetime, parseaddr

import aiosmtplib
from sqlalchemy import update
from sqlalchemy.ext.asyncio import AsyncSession

from campus.core import clock
from campus.core.config import Settings, get_settings
from campus.core.jobs import JobInfo
from campus.core.outbox import OutboxMessage, add_message, outbox_handlers

MAIL_TOPIC = "core.mail.send"


class MailNotConfiguredError(RuntimeError):
    """CAMPUS_SMTP_HOST is required to send mail but not set."""

    def __init__(self) -> None:
        super().__init__("CAMPUS_SMTP_HOST is not set")


def queue_email(
    session: AsyncSession,
    *,
    to: str,
    subject: str,
    text: str,
    html: str | None = None,
) -> None:
    """Queue a letter, sent after the transaction of ``session`` commits."""
    add_message(
        session,
        MAIL_TOPIC,
        {"to": to, "subject": subject, "text": text, "html": html},
    )


def build_message(settings: Settings, job: JobInfo) -> EmailMessage:
    """Build the letter of an outbox message written by :func:`queue_email`."""
    payload = job.payload
    message = EmailMessage()
    message["From"] = settings.mail_from
    message["To"] = payload["to"]
    message["Subject"] = payload["subject"]
    message["Date"] = format_datetime(clock.now(), usegmt=True)
    _, sender = parseaddr(settings.mail_from)
    domain = sender.rpartition("@")[2] or "localhost"
    message["Message-ID"] = f"<{job.id}@{domain}>"
    message.set_content(payload["text"])
    if payload.get("html"):
        message.add_alternative(payload["html"], subtype="html")
    return message


async def send_message(settings: Settings, message: EmailMessage) -> None:
    """Send ``message`` through the configured SMTP server."""
    if settings.smtp_host is None:
        raise MailNotConfiguredError
    password = settings.smtp_password
    await aiosmtplib.send(
        message,
        hostname=settings.smtp_host,
        port=settings.smtp_port,
        username=settings.smtp_username,
        password=password.get_secret_value() if password else None,
        use_tls=settings.smtp_security == "tls",
        start_tls=settings.smtp_security == "starttls",
        timeout=settings.smtp_timeout,
    )


@outbox_handlers.register(MAIL_TOPIC)
async def _send_queued_email(_session: AsyncSession, job: JobInfo) -> None:
    settings = get_settings()
    await send_message(settings, build_message(settings, job))
    await _session.execute(
        update(OutboxMessage).where(OutboxMessage.id == job.id).values(payload={})
    )
