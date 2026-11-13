"""Pytest plugin: PostgreSQL 18 + pgvector for tests.

One server per test session: a testcontainers container, or an existing
server from CAMPUS_TEST_DATABASE_URL (its user must be allowed to create
databases). Migrations are applied once to a template database; every test
that asks for the database gets its own copy of the template, so tests may
commit and run concurrent transactions without affecting each other.
"""

import asyncio
import os
import uuid
from collections.abc import AsyncIterator, Iterator
from pathlib import Path

import asyncpg
import pytest
from alembic.config import CommandLine
from pydantic import SecretStr
from sqlalchemy.engine import URL, make_url
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession
from testcontainers.community.postgres import PostgresContainer

from campus.core.config import Settings
from campus.core.db import create_engine, create_session_factory
from tests.factories import EntityFactory
from tests.logging_state import preserved_logging
from tests.models import ExampleEntity

# Keep in step with the image in infra/compose.yaml.
POSTGRES_IMAGE = "pgvector/pgvector:0.8.7-pg18-trixie"
TEMPLATE_DATABASE = "campus_test_template"
PYPROJECT = Path(__file__).parents[1] / "pyproject.toml"

# Read at import: the autouse fixture hides CAMPUS_* variables from tests.
EXTERNAL_SERVER_URL = os.environ.get("CAMPUS_TEST_DATABASE_URL")


def asyncpg_url(url: URL, database: str) -> str:
    """Render ``url`` for SQLAlchemy with the asyncpg driver."""
    return url.set(drivername="postgresql+asyncpg", database=database).render_as_string(
        hide_password=False
    )


async def execute_on_server(server: URL, *statements: str) -> None:
    """Run maintenance statements (CREATE/DROP DATABASE) on the server."""
    dsn = server.set(drivername="postgresql", database="postgres")
    connection = await asyncpg.connect(dsn.render_as_string(hide_password=False))
    try:
        for statement in statements:
            await connection.execute(statement)
    finally:
        await connection.close()


async def create_database(server: URL, name: str, template: str | None = None) -> None:
    clause = f' TEMPLATE "{template}"' if template else ""
    await execute_on_server(server, f'CREATE DATABASE "{name}"{clause}')


async def drop_database(server: URL, name: str) -> None:
    await execute_on_server(server, f'DROP DATABASE IF EXISTS "{name}" WITH (FORCE)')


def run_alembic(database_url: str, *arguments: str) -> None:
    """Run the alembic command line, as in production, against a database."""
    with pytest.MonkeyPatch.context() as patch, preserved_logging():
        patch.setenv("CAMPUS_DATABASE_URL", database_url)
        CommandLine().main(argv=["-c", str(PYPROJECT), *arguments])


def unique_database_name() -> str:
    return f"campus_test_{uuid.uuid4().hex}"


@pytest.fixture(scope="session")
def postgres_server() -> Iterator[URL]:
    """URL of the PostgreSQL server used by the test session."""
    if EXTERNAL_SERVER_URL:
        yield make_url(EXTERNAL_SERVER_URL)
        return
    with PostgresContainer(POSTGRES_IMAGE, driver="asyncpg") as container:
        yield make_url(container.get_connection_url())


@pytest.fixture(scope="session")
def template_database(postgres_server: URL) -> Iterator[str]:
    """A database with all migrations and the test tables applied."""
    asyncio.run(drop_database(postgres_server, TEMPLATE_DATABASE))
    asyncio.run(create_database(postgres_server, TEMPLATE_DATABASE))
    url = asyncpg_url(postgres_server, TEMPLATE_DATABASE)
    run_alembic(url, "upgrade", "head")
    asyncio.run(create_test_tables(url))
    yield TEMPLATE_DATABASE
    asyncio.run(drop_database(postgres_server, TEMPLATE_DATABASE))


async def create_test_tables(url: str) -> None:
    engine = create_engine(Settings(database_url=SecretStr(url)), pooled=False)
    try:
        async with engine.begin() as connection:
            await connection.run_sync(ExampleEntity.metadata.create_all)
    finally:
        await engine.dispose()


@pytest.fixture
async def database_url(
    postgres_server: URL, template_database: str
) -> AsyncIterator[str]:
    """URL of a fresh, migrated database owned by the current test."""
    name = unique_database_name()
    await create_database(postgres_server, name, template=template_database)
    yield asyncpg_url(postgres_server, name)
    await drop_database(postgres_server, name)


@pytest.fixture
async def engine(database_url: str) -> AsyncIterator[AsyncEngine]:
    engine = create_engine(Settings(database_url=SecretStr(database_url)))
    yield engine
    await engine.dispose()


@pytest.fixture
async def session(engine: AsyncEngine) -> AsyncIterator[AsyncSession]:
    """A session on the test database; factories create rows through it."""
    async with create_session_factory(engine)() as session:
        EntityFactory.__async_session__ = session
        yield session
        EntityFactory.__async_session__ = None
