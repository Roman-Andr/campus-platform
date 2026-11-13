import logging
import os
from collections.abc import Iterator
from pathlib import Path

import pytest
import structlog
from fastapi.testclient import TestClient

from campus.api.app import create_app
from campus.core.config import Settings, get_settings


@pytest.fixture(autouse=True)
def isolated_environment(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> Iterator[None]:
    """Hide the developer's CAMPUS_* variables and .env file from tests."""
    for name in os.environ:
        if name.startswith("CAMPUS_"):
            monkeypatch.delenv(name)
    monkeypatch.chdir(tmp_path)
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


@pytest.fixture(autouse=True)
def restore_logging() -> Iterator[None]:
    """Undo the global logging configuration done by a test."""
    root = logging.getLogger()
    handlers, level = root.handlers[:], root.level
    yield
    root.handlers, root.level = handlers, level
    structlog.reset_defaults()
    structlog.contextvars.clear_contextvars()


@pytest.fixture
def settings() -> Settings:
    return Settings()


@pytest.fixture
def client(settings: Settings) -> Iterator[TestClient]:
    with TestClient(create_app(settings)) as test_client:
        yield test_client
