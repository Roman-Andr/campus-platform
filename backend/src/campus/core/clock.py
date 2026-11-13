"""The single source of the current time.

Application code reads the time only through :func:`now` (direct calls to
``datetime.now()`` and similar are banned by ruff), so tests control it with
time-machine. SQL must not use ``now()`` for business rules either: pass
:func:`now` as a parameter instead.
"""

from datetime import UTC, datetime


def now() -> datetime:
    """Return the current time as a timezone-aware UTC datetime."""
    return datetime.now(UTC)
