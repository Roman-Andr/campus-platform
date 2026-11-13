import sys

import pytest
from pydantic import SecretStr, ValidationError

from campus import modules
from campus.core.config import Settings
from campus.core.db import DatabaseNotConfiguredError, create_engine

URL = "postgresql+asyncpg://campus:secret@db.example.org:5432/campus"


@pytest.mark.parametrize(
    "given",
    [
        URL,
        "postgresql://campus:secret@db.example.org:5432/campus",
        "postgres://campus:secret@db.example.org:5432/campus",
        "postgresql+psycopg://campus:secret@db.example.org:5432/campus",
    ],
)
def test_database_url_uses_asyncpg_driver(
    monkeypatch: pytest.MonkeyPatch, given: str
) -> None:
    monkeypatch.setenv("CAMPUS_DATABASE_URL", given)

    settings = Settings()

    assert settings.database_url is not None
    assert settings.database_url.get_secret_value() == URL


@pytest.mark.parametrize("given", ["mysql://u:p@host/db", "not a url"])
def test_non_postgresql_url_is_rejected(
    monkeypatch: pytest.MonkeyPatch, given: str
) -> None:
    monkeypatch.setenv("CAMPUS_DATABASE_URL", given)

    with pytest.raises(ValidationError):
        Settings()


def test_database_password_is_hidden_from_repr(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("CAMPUS_DATABASE_URL", URL)

    assert "secret" not in repr(Settings())


def test_engine_requires_database_url() -> None:
    with pytest.raises(DatabaseNotConfiguredError, match="CAMPUS_DATABASE_URL"):
        create_engine(Settings())


async def test_engine_pool_is_configured(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("CAMPUS_DATABASE_POOL_SIZE", "3")
    monkeypatch.setenv("CAMPUS_DATABASE_MAX_OVERFLOW", "2")
    monkeypatch.setenv("CAMPUS_DATABASE_POOL_TIMEOUT", "5")
    settings = Settings(database_url=SecretStr(URL))

    engine = create_engine(settings)
    try:
        pool = engine.pool
        assert pool.size() == 3  # type: ignore[attr-defined]
        assert pool._max_overflow == 2  # type: ignore[attr-defined]
        assert pool._timeout == 5  # type: ignore[attr-defined]
    finally:
        await engine.dispose()


def test_import_all_loads_every_module() -> None:
    modules.import_all()

    for name in ("identity", "listings", "points", "administration"):
        assert f"campus.modules.{name}" in sys.modules
