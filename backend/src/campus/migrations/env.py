"""Alembic environment: migrates the database at CAMPUS_DATABASE_URL."""

import asyncio
import re

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

# Child partitions of chat_message are data storage, not schema: migrations
# create and drop them with their parent, and autogenerate must neither see
# them as extra tables nor compare their indexes.
PARTITION_TABLE = re.compile(r"^chat_message_(?:\d{4}_\d{2}|default)$")


def include_object(
    obj: object, name: str | None, type_: str, reflected: bool, compare_to: object
) -> bool:
    """Keep reflected chat_message partitions out of autogenerate."""
    del compare_to
    if reflected and name is not None:
        if type_ == "table" and PARTITION_TABLE.match(name):
            return False
        if type_ == "index":
            table = getattr(obj, "table", None)
            table_name = getattr(table, "name", None)
            if isinstance(table_name, str) and PARTITION_TABLE.match(table_name):
                return False
    return True


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
        include_object=include_object,
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
        include_object=include_object,
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
