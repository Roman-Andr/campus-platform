"""Error reporting via Sentry SDK (GlitchTip-compatible)."""

from typing import TYPE_CHECKING, Any

import sentry_sdk

from campus import __version__
from campus.core.config import Settings
from campus.core.logging import redact

if TYPE_CHECKING:
    from sentry_sdk.types import Breadcrumb, BreadcrumbHint, Event, Hint

# Parts of an event that carry free text or arbitrary data from the code.
_EVENT_FIELDS = ("logentry", "message", "extra", "tags")
_BREADCRUMB_FIELDS = ("message", "data")


def redact_event(event: Event, _hint: Hint) -> Event:
    """Mask personal data in log messages, extra data and exception texts."""
    data: dict[str, Any] = dict(event)
    for field in _EVENT_FIELDS:
        if field in data:
            data[field] = redact(data[field])
    for exception in data.get("exception", {}).get("values", []):
        if "value" in exception:
            exception["value"] = redact(exception["value"])
    redacted: Event = data  # type: ignore[assignment]
    return redacted


def redact_breadcrumb(crumb: Breadcrumb, _hint: BreadcrumbHint) -> Breadcrumb:
    """Mask personal data in breadcrumbs, which also come from log records."""
    redacted = dict(crumb)
    for field in _BREADCRUMB_FIELDS:
        if field in redacted:
            redacted[field] = redact(redacted[field])
    return redacted


def configure_sentry(settings: Settings, *, process: str) -> bool:
    """Enable error reporting if a DSN is configured; return whether it is on."""
    if settings.sentry_dsn is None:
        return False
    sentry_sdk.init(
        dsn=settings.sentry_dsn.get_secret_value(),
        environment=settings.environment,
        release=settings.release or f"campus@{__version__}",
        traces_sample_rate=settings.sentry_traces_sample_rate,
        # Personal data stays out of error events (specification, 5.2).
        data_collection={
            "user_info": False,
            "cookies": {"mode": "off"},
            "http_headers": {"request": {"mode": "off"}},
            "http_bodies": [],
            "url_query_params": {"mode": "off"},
            "graphql": {"document": False, "variables": False},
            "gen_ai": {"inputs": False, "outputs": False},
            "database_query_data": False,
            "queues": False,
            "stack_frame_variables": False,
        },
        before_send=redact_event,
        before_breadcrumb=redact_breadcrumb,
    )
    sentry_sdk.set_tag("process", process)
    return True
