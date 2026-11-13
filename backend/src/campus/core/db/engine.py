"""Async engine and session factory (SQLAlchemy 2, asyncpg)."""

from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.pool import NullPool

from campus.core.config import Settings


class DatabaseNotConfiguredError(RuntimeError):
    """CAMPUS_DATABASE_URL is required but not set."""

    def __init__(self) -> None:
        super().__init__("CAMPUS_DATABASE_URL is not set")


def create_engine(settings: Settings, *, pooled: bool = True) -> AsyncEngine:
    """Create the engine for the configured database.

    ``pooled=False`` opens a connection per use; it suits one-off commands
    such as migrations.
    """
    if settings.database_url is None:
        raise DatabaseNotConfiguredError
    url = settings.database_url.get_secret_value()
    connect_args = {
        "server_settings": {"timezone": "UTC", "application_name": "campus"}
    }
    if not pooled:
        return create_async_engine(url, poolclass=NullPool, connect_args=connect_args)
    return create_async_engine(
        url,
        pool_size=settings.database_pool_size,
        max_overflow=settings.database_max_overflow,
        pool_timeout=settings.database_pool_timeout,
        pool_pre_ping=True,
        connect_args=connect_args,
    )


def create_session_factory(engine: AsyncEngine) -> async_sessionmaker[AsyncSession]:
    """Create the factory of sessions bound to ``engine``."""
    return async_sessionmaker(engine, expire_on_commit=False)
