"""One-call setup of logging and error reporting for every process."""

from campus.core.config import Settings
from campus.core.logging import configure_logging
from campus.core.sentry import configure_sentry


def configure_observability(settings: Settings, *, process: str) -> None:
    """Configure logging and error reporting for the named process."""
    configure_logging(settings, process=process)
    configure_sentry(settings, process=process)
