import os
from collections.abc import AsyncIterator, Iterator
from pathlib import Path

import httpx2
import pytest
from fastapi.testclient import TestClient
from pydantic import SecretStr

from campus.api.app import create_app
from campus.core.config import ClientPlatform, Settings, get_settings
from tests.logging_state import preserved_logging
from tests.web_app import create_test_app, serve

pytest_plugins = ["tests.database", "tests.services"]


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
    with preserved_logging():
        yield


@pytest.fixture
def settings() -> Settings:
    return Settings()


@pytest.fixture
def client(settings: Settings) -> Iterator[TestClient]:
    with TestClient(create_app(settings)) as test_client:
        yield test_client


def web_settings(database_url: str | None = None) -> Settings:
    """Settings of the test API: android clients must be 1.2.0 or newer."""
    return Settings(
        database_url=SecretStr(database_url) if database_url else None,
        client_min_versions={ClientPlatform.ANDROID: "1.2.0"},
    )


@pytest.fixture
async def api(database_url: str) -> AsyncIterator[httpx2.AsyncClient]:
    """Client of the API with the test router, on a fresh database."""
    async with serve(create_test_app(web_settings(database_url))) as client:
        yield client


@pytest.fixture
async def api_without_database() -> AsyncIterator[httpx2.AsyncClient]:
    """Client of the API with the test router and no database configured."""
    async with serve(create_test_app(web_settings())) as client:
        yield client
