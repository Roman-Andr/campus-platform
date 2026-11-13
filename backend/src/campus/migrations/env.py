"""Alembic environment: migrates the database at CAMPUS_DATABASE_URL."""

import asyncio

from alembic import context
from sqlalchemy.engine import Connection

from campus import modules
from campus.core import deadlines, idempotency, outbox  # noqa: F401 - their tables
from campus.core.config import Settings
from campus.core.db import Base, DatabaseNotConfiguredError, create_engine
from campus.core.logging import configure_logging

settings = Settings()
if not context.is_offline_mode():
    # In --sql mode stdout carries the SQL script, so it gets no log records.
    configure_logging(settings, process="migrations")

# Every module registers its tables in Base.metadata when imported; the
# job tables of the shared kernel are imported above.
modules.import_all()
target_metadata = Base.metadata


def run_migrations_offline() -> None:
    """Render SQL to stdout (``--sql``) without connecting."""
    if settings.database_url is None:
        raise DatabaseNotConfiguredError
    context.configure(
        url=settings.database_url.get_secret_value(),
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        compare_server_default=True,
    )
    with context.begin_transaction():
        context.run_migrations()


def do_run_migrations(connection: Connection) -> None:
    """Run the migrations, each in its own transaction."""
    context.configure(
        connection=connection,
        target_metadata=target_metadata,
        transaction_per_migration=True,
        compare_server_default=True,
    )
    with context.begin_transaction():
        context.run_migrations()


async def run_migrations_online() -> None:
    """Connect to the database and run the migrations."""
    engine = create_engine(settings, pooled=False)
    try:
        async with engine.connect() as connection:
            await connection.run_sync(do_run_migrations)
    finally:
        await engine.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    asyncio.run(run_migrations_online())
