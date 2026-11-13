"""Structured JSON logging without personal data (specification, 5.2)."""

import logging
import re
import sys
from collections.abc import Mapping
from typing import Any

import structlog
from asgi_correlation_id import correlation_id
from structlog.tracebacks import ExceptionDictTransformer
from structlog.typing import EventDict, Processor, WrappedLogger

from campus.core.config import Settings

REDACTED = "[redacted]"

# Keys whose values are personal data or credentials. Compared
# case-insensitively after normalising "-" to "_".
SENSITIVE_KEYS = frozenset(
    {
        "access_token",
        "authorization",
        "client_ip",
        "code",
        "cookie",
        "email",
        "first_name",
        "full_name",
        "ip",
        "ip_address",
        "last_name",
        "otp",
        "password",
        "phone",
        "refresh_token",
        "secret",
        "set_cookie",
        "token",
    }
)

_EMAIL_RE = re.compile(r"[\w.+-]+@[\w-]+(?:\.[\w-]+)+")

# Loggers of libraries that would otherwise write plain-text records.
_LIBRARY_LOGGERS = ("uvicorn", "uvicorn.error")

# The uvicorn access log has the client address and query string; requests
# are logged by campus.api.access_log instead.
_DISABLED_LOGGERS = ("uvicorn.access",)

# HTTP clients log full request URLs at INFO; URLs of external APIs may hold
# credentials (e.g. a Telegram bot token) or personal data.
_QUIET_LOGGERS = ("httpx", "httpx2", "httpcore")


def redact(value: Any) -> Any:
    """Return ``value`` with personal data masked.

    Values under sensitive keys are replaced at any depth, e-mail addresses
    are masked in strings. Names and other free-form personal data cannot be
    detected in text, so they must be passed as structured fields.
    """
    if isinstance(value, str):
        return _EMAIL_RE.sub(REDACTED, value)
    if isinstance(value, Mapping):
        return {
            key: REDACTED if _is_sensitive(key) else redact(item)
            for key, item in value.items()
        }
    if isinstance(value, list):
        return [redact(item) for item in value]
    if isinstance(value, tuple):
        # Tuples stay tuples: structlog formats "%s" messages with them.
        return tuple(redact(item) for item in value)
    return value


def _is_sensitive(key: object) -> bool:
    return isinstance(key, str) and key.lower().replace("-", "_") in SENSITIVE_KEYS


def redact_personal_data(
    _logger: WrappedLogger, _method_name: str, event_dict: EventDict
) -> EventDict:
    """Structlog processor that masks personal data, see :func:`redact`."""
    redacted: EventDict = redact(event_dict)
    return redacted


def drop_color_message(
    _logger: WrappedLogger, _method_name: str, event_dict: EventDict
) -> EventDict:
    """Remove the ANSI-coloured duplicate of the message added by uvicorn."""
    event_dict.pop("color_message", None)
    return event_dict


def add_request_id(
    _logger: WrappedLogger, _method_name: str, event_dict: EventDict
) -> EventDict:
    """Attach the ID of the HTTP request being handled, if any."""
    request_id = correlation_id.get()
    if request_id is not None:
        event_dict.setdefault("request_id", request_id)
    return event_dict


def configure_logging(settings: Settings, *, process: str) -> None:
    """Route structlog and standard library logging to one stdout stream.

    ``process`` names the entry point (api, worker, scheduler) and is added
    to every record.
    """
    shared_processors: list[Processor] = [
        structlog.contextvars.merge_contextvars,
        structlog.stdlib.add_log_level,
        structlog.stdlib.add_logger_name,
        structlog.stdlib.ExtraAdder(),
        drop_color_message,
        structlog.processors.TimeStamper(fmt="iso", utc=True),
        add_request_id,
        # Records are redacted before they leave structlog, so the Sentry
        # logging integration, which reads them earlier than the formatter,
        # never sees personal data either.
        redact_personal_data,
    ]

    renderer: Processor
    if settings.log_format == "console":
        renderer = structlog.dev.ConsoleRenderer()
        exception_processors: list[Processor] = []
    else:
        renderer = structlog.processors.JSONRenderer()
        exception_processors = [
            # Local variables may hold personal data, so they are omitted.
            structlog.processors.ExceptionRenderer(
                ExceptionDictTransformer(show_locals=False)
            ),
        ]

    structlog.configure(
        processors=[
            structlog.stdlib.filter_by_level,
            *shared_processors,
            structlog.stdlib.PositionalArgumentsFormatter(),
            structlog.stdlib.ProcessorFormatter.wrap_for_formatter,
        ],
        logger_factory=structlog.stdlib.LoggerFactory(),
        wrapper_class=structlog.stdlib.BoundLogger,
        cache_logger_on_first_use=True,
    )

    formatter = structlog.stdlib.ProcessorFormatter(
        foreign_pre_chain=shared_processors,
        processors=[
            structlog.stdlib.ProcessorFormatter.remove_processors_meta,
            *exception_processors,
            redact_personal_data,
            renderer,
        ],
    )
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(formatter)

    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(settings.log_level)

    for name in _LIBRARY_LOGGERS:
        library_logger = logging.getLogger(name)
        library_logger.handlers = []
        library_logger.propagate = True
    for name in _DISABLED_LOGGERS:
        logging.getLogger(name).disabled = True
    for name in _QUIET_LOGGERS:
        logging.getLogger(name).setLevel(logging.WARNING)

    structlog.contextvars.clear_contextvars()
    structlog.contextvars.bind_contextvars(process=process)
