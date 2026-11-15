"""Alembic: the schema changes only through migrations (specification, 4.4)."""

import asyncio
from collections.abc import Iterator

import asyncpg
import pytest
from alembic.config import CommandLine, Config
from alembic.script import ScriptDirectory
from sqlalchemy import Column, Integer, Table
from sqlalchemy.engine import URL

from campus.core.db import Base, DatabaseNotConfiguredError
from tests.database import (
    PYPROJECT,
    asyncpg_url,
    create_database,
    drop_database,
    run_alembic,
    unique_database_name,
)


def test_migrations_have_single_head() -> None:
    scripts = ScriptDirectory.from_config(Config(toml_file=str(PYPROJECT)))
    heads = scripts.get_heads()

    assert len(heads) == 1, (
        f"Expected exactly one Alembic migration head, found {len(heads)}: {heads}. "
        "Multiple heads must be merged with an Alembic merge revision."
    )


@pytest.fixture
def empty_database(postgres_server: URL) -> Iterator[str]:
    """URL of a new database with no schema at all."""
    name = unique_database_name()
    asyncio.run(create_database(postgres_server, name))
    yield asyncpg_url(postgres_server, name)
    asyncio.run(drop_database(postgres_server, name))


async def fetch(url: str, query: str) -> list[asyncpg.Record]:
    connection = await asyncpg.connect(url.replace("+asyncpg", ""))
    try:
        return await connection.fetch(query)
    finally:
        await connection.close()


def extensions(url: str) -> set[str]:
    rows = asyncio.run(fetch(url, "SELECT extname FROM pg_extension"))
    return {row["extname"] for row in rows}


def applied_revisions(url: str) -> list[str]:
    rows = asyncio.run(fetch(url, "SELECT version_num FROM alembic_version"))
    return [row["version_num"] for row in rows]


def test_upgrade_and_downgrade_on_empty_database(empty_database: str) -> None:
    run_alembic(empty_database, "upgrade", "head")

    assert "vector" in extensions(empty_database)
    assert len(applied_revisions(empty_database)) == 1

    run_alembic(empty_database, "downgrade", "base")

    assert "vector" not in extensions(empty_database)
    assert applied_revisions(empty_database) == []


def test_reservation_and_exchange_columns_migrate(empty_database: str) -> None:
    columns = """
        SELECT column_name FROM information_schema.columns
        WHERE table_name = 'listing_interaction'
    """

    run_alembic(empty_database, "upgrade", "head")
    names = {row["column_name"] for row in asyncio.run(fetch(empty_database, columns))}
    assert {"reservation_due_at", "offer_description"} <= names

    # Later migrations may sit on top of this one, so step back past it
    # explicitly instead of counting a single revision.
    run_alembic(empty_database, "downgrade", "86a000000001")
    names = {row["column_name"] for row in asyncio.run(fetch(empty_database, columns))}
    assert "reservation_due_at" not in names
    assert "offer_description" not in names


def test_purchase_columns_migrate(empty_database: str) -> None:
    columns = """
        SELECT table_name, column_name FROM information_schema.columns
        WHERE table_name IN ('listing', 'listing_interaction', 'listing_waitlist')
    """
    constraints = """
        SELECT conname FROM pg_constraint
        WHERE conname IN (
            'ck_listing_purchase_details', 'ck_listing_purchase_units',
            'ck_listing_purchase_absent', 'ck_listing_interaction_units',
            'ck_listing_waitlist_units', 'ck_listing_waitlist_offer_units'
        )
    """

    run_alembic(empty_database, "upgrade", "head")
    names = {
        (row["table_name"], row["column_name"])
        for row in asyncio.run(fetch(empty_database, columns))
    }
    assert {
        ("listing", "purchase_unit_price"),
        ("listing", "purchase_min_units"),
        ("listing", "purchase_max_units"),
        ("listing", "purchase_taken_units"),
        ("listing", "purchase_fixed_units"),
        ("listing", "purchase_collection_deadline"),
        ("listing", "purchase_stage"),
        ("listing_interaction", "units"),
        ("listing_interaction", "leave_requested_at"),
        ("listing_waitlist", "units"),
        ("listing_waitlist", "offer_units"),
    } <= names
    assert len(asyncio.run(fetch(empty_database, constraints))) == 6

    # Step back past the purchase migration explicitly: "-1" now removes
    # whatever revision sits on top of it.
    run_alembic(empty_database, "downgrade", "291a00000001")
    names = {
        (row["table_name"], row["column_name"])
        for row in asyncio.run(fetch(empty_database, columns))
    }
    assert not {name for name in names if name[1].startswith("purchase_")}
    assert ("listing_interaction", "units") not in names
    assert ("listing_waitlist", "units") not in names
    assert asyncio.run(fetch(empty_database, constraints)) == []


def test_models_match_migrations(empty_database: str) -> None:
    run_alembic(empty_database, "upgrade", "head")

    run_alembic(empty_database, "check")


def test_check_detects_model_without_migration(
    empty_database: str, capsys: pytest.CaptureFixture[str]
) -> None:
    run_alembic(empty_database, "upgrade", "head")
    table = Table("unmigrated", Base.metadata, Column("id", Integer, primary_key=True))
    try:
        with pytest.raises(SystemExit) as exit_info:
            run_alembic(empty_database, "check")
    finally:
        Base.metadata.remove(table)

    assert exit_info.value.code != 0
    assert "New upgrade operations detected" in capsys.readouterr().out


def test_sql_script_is_rendered_without_database(
    capsys: pytest.CaptureFixture[str],
) -> None:
    run_alembic(
        "postgresql+asyncpg://user:secret@unreachable.invalid/db",
        "upgrade",
        "head",
        "--sql",
    )

    output = capsys.readouterr().out
    assert "CREATE EXTENSION IF NOT EXISTS vector;" in output
    assert '"event"' not in output  # no log records mixed into the script


@pytest.mark.parametrize("mode", [["upgrade", "head"], ["upgrade", "head", "--sql"]])
def test_database_url_is_required(mode: list[str]) -> None:
    # CAMPUS_DATABASE_URL is unset by the isolated_environment fixture.
    with pytest.raises(DatabaseNotConfiguredError):
        CommandLine().main(argv=["-c", str(PYPROJECT), *mode])


def test_existing_email_is_migrated(empty_database: str) -> None:
    run_alembic(empty_database, "upgrade", "90fb233ce001")
    asyncio.run(
        fetch(
            empty_database,
            """
        INSERT INTO identity_user (email, first_name, last_name, account_type,
                                   created_at, updated_at)
        VALUES ('existing@university.example', 'Existing', 'User', 'student',
                now(), now()) RETURNING id
    """,
        )
    )
    run_alembic(empty_database, "upgrade", "head")
    rows = asyncio.run(
        fetch(
            empty_database,
            """
        SELECT e.email, e.kind, e.verified_at = u.created_at AS verified
        FROM identity_user_email e JOIN identity_user u ON u.id = e.user_id
    """,
        )
    )
    assert len(rows) == 1
    assert rows[0]["email"] == "existing@university.example"
    assert rows[0]["kind"] == "corporate"
    assert rows[0]["verified"]


def test_deadline_due_time_is_backfilled(empty_database: str) -> None:
    run_alembic(empty_database, "upgrade", "77c3f7a00001")
    asyncio.run(
        fetch(
            empty_database,
            """
        INSERT INTO deadline (topic, payload, available_at, attempts,
                              created_at, updated_at)
        VALUES ('test.metrics', '{}', '2027-03-01T12:00:00Z', 1,
                '2027-03-01T11:00:00Z', '2027-03-01T11:00:00Z')
        RETURNING id
    """,
        )
    )
    run_alembic(empty_database, "upgrade", "head")
    rows = asyncio.run(
        fetch(empty_database, "SELECT due_at = available_at AS preserved FROM deadline")
    )
    assert len(rows) == 1
    assert rows[0]["preserved"]
    run_alembic(empty_database, "downgrade", "77c3f7a00001")
    assert len(asyncio.run(fetch(empty_database, "SELECT id FROM deadline"))) == 1


def test_notification_importance_is_backfilled(empty_database: str) -> None:
    run_alembic(empty_database, "upgrade", "85a000000001")
    user = asyncio.run(
        fetch(
            empty_database,
            """
        INSERT INTO identity_user (email, first_name, last_name, account_type,
                                   created_at, updated_at)
        VALUES ('notified@university.example', 'Notified', 'User', 'student',
                now(), now()) RETURNING id
    """,
        )
    )[0]
    asyncio.run(
        fetch(
            empty_database,
            """
        INSERT INTO notification (event_id, recipient_id, sequence, type,
                                  occurred_at, text, params,
                                  created_at, updated_at)
        VALUES (gen_random_uuid(), $1, 1, 'status.changed', now(),
                '{}', '{}', now(), now())
    """.replace("$1", f"'{user['id']}'"),
        )
    )
    run_alembic(empty_database, "upgrade", "head")
    rows = asyncio.run(fetch(empty_database, "SELECT important FROM notification"))
    assert len(rows) == 1
    assert rows[0]["important"] is False
    run_alembic(empty_database, "downgrade", "85a000000001")
    assert len(asyncio.run(fetch(empty_database, "SELECT id FROM notification"))) == 1
