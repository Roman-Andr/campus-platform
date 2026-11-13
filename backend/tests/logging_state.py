"""Save and restore the global logging configuration."""

import logging
from collections.abc import Iterator
from contextlib import contextmanager

import structlog


@contextmanager
def preserved_logging() -> Iterator[None]:
    """Undo logging configuration done inside the block."""
    root = logging.getLogger()
    handlers, level = root.handlers[:], root.level
    try:
        yield
    finally:
        root.handlers, root.level = handlers, level
        structlog.reset_defaults()
        structlog.contextvars.clear_contextvars()
