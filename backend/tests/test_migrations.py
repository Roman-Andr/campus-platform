"""Alembic: the schema changes only through migrations (specification, 4.4)."""

import asyncio
from collections.abc import Iterator
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import asyncpg
import pytest
from alembic.config import CommandLine, Config
from alembic.script import ScriptDirectory
from sqlalchemy import Column, Integer, Table
from sqlalchemy.engine import URL

from campus.core.db import Base, DatabaseNotConfiguredError
from campus.modules.chat.service import body_fingerprint, content_hash
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


async def fetch(url: str, query: str, *arguments: object) -> list[asyncpg.Record]:
    connection = await asyncpg.connect(url.replace("+asyncpg", ""))
    try:
        return await connection.fetch(query, *arguments)
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


@pytest.mark.parametrize("start", ["55merge00001", "59a000000001"])
def test_existing_main_upgrade_adds_block_schema(
    empty_database: str, start: str
) -> None:
    """Deployed main revisions must still receive the block migration."""
    tables = """
        SELECT table_name FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'identity_block'
    """
    columns = """
        SELECT column_name FROM information_schema.columns
        WHERE table_name = 'identity_user'
    """

    run_alembic(empty_database, "upgrade", start)
    assert asyncio.run(fetch(empty_database, tables)) == []
    assert "message_policy" not in {
        row["column_name"] for row in asyncio.run(fetch(empty_database, columns))
    }

    run_alembic(empty_database, "upgrade", "head")
    assert asyncio.run(fetch(empty_database, tables))
    assert "message_policy" in {
        row["column_name"] for row in asyncio.run(fetch(empty_database, columns))
    }


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


def test_chat_archive_and_retention_schema_migrates(empty_database: str) -> None:
    columns = """
        SELECT table_name, column_name FROM information_schema.columns
        WHERE (table_name = 'chat' AND column_name = 'empty_since')
           OR (table_name = 'chat_member' AND column_name = 'left_at')
           OR (table_name = 'file' AND column_name = 'chat_id')
    """
    partitions = """
        SELECT relname FROM pg_class
        WHERE relname LIKE 'chat_message_archive_%' AND relkind = 'r'
    """
    index = """
        SELECT indexname FROM pg_indexes
        WHERE tablename = 'chat_message_archive'
    """
    view = """
        SELECT pg_get_viewdef('chat_message_history'::regclass) AS definition
    """
    snapshot_fks = """
        SELECT conname FROM pg_constraint
        WHERE conrelid = to_regclass('chat_message_snapshot') AND contype = 'f'
    """

    run_alembic(empty_database, "upgrade", "head")
    names = {
        (row["table_name"], row["column_name"])
        for row in asyncio.run(fetch(empty_database, columns))
    }
    assert names == {
        ("chat", "empty_since"),
        ("chat_member", "left_at"),
        ("file", "chat_id"),
    }
    partition_names = {
        row["relname"] for row in asyncio.run(fetch(empty_database, partitions))
    }
    assert {
        "chat_message_archive_2020",
        "chat_message_archive_2035",
        "chat_message_archive_default",
    } <= partition_names
    index_names = {
        row["indexname"] for row in asyncio.run(fetch(empty_database, index))
    }
    assert {
        "ix_chat_message_archive_chat_id_sequence",
        "ix_chat_message_archive_search",
    } <= index_names
    definition = asyncio.run(fetch(empty_database, view))[0]["definition"]
    assert "chat_message" in definition
    assert "chat_message_archive" in definition
    assert asyncio.run(fetch(empty_database, snapshot_fks)) == []

    run_alembic(empty_database, "downgrade", "78c0a7000001")
    names = {
        (row["table_name"], row["column_name"])
        for row in asyncio.run(fetch(empty_database, columns))
    }
    assert names == set()
    assert asyncio.run(fetch(empty_database, partitions)) == []
    assert asyncio.run(fetch(empty_database, snapshot_fks)) == []


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


def test_chat_dedup_fingerprint_is_backfilled(empty_database: str) -> None:
    run_alembic(empty_database, "upgrade", "81a000000001")
    alice, bob = uuid4(), uuid4()
    for user_id, email in (
        (alice, "dedup-alice@university.example"),
        (bob, "dedup-bob@university.example"),
    ):
        asyncio.run(
            fetch(
                empty_database,
                """
            INSERT INTO identity_user (id, email, first_name, last_name,
                                       account_type, created_at, updated_at)
            VALUES ($1, $2, 'Dedup', 'User', 'student', now(), now())
        """,
                user_id,
                email,
            )
        )
    low, high = sorted((alice, bob))
    chat_id = uuid4()
    asyncio.run(
        fetch(
            empty_database,
            """
        INSERT INTO chat (id, kind, user_low_id, user_high_id, last_sequence,
                          created_at, updated_at)
        VALUES ($1, 'personal', $2, $3, 5, now(), now())
    """,
            chat_id,
            low,
            high,
        )
    )

    quote_id, plain_id, rich_id, deleted_id, archived_id = (uuid4() for _ in range(5))
    plain_client, rich_client, deleted_client, archived_client = (
        uuid4() for _ in range(4)
    )
    rich_photo_a, rich_photo_b = uuid4(), uuid4()
    created, deleted_at = (
        datetime(2026, 11, 15, 12, tzinfo=UTC),
        datetime(2026, 11, 15, 13, tzinfo=UTC),
    )
    archived_created = datetime(2025, 6, 1, 12, tzinfo=UTC)

    def insert_message(  # noqa: PLR0913, PLR0917 - row fields
        message_id: UUID,
        client_id: UUID,
        sequence: int,
        text: str,
        reply_to_id: UUID | None,
        version: int,
        deleted: datetime | None,
        message_created_at: datetime,
    ) -> None:
        asyncio.run(
            fetch(
                empty_database,
                """
            INSERT INTO chat_message (id, chat_id, sender_id, client_id,
                                      sequence, text, reply_to_id, version,
                                      deleted_at, created_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
        """,
                message_id,
                chat_id,
                alice,
                client_id,
                sequence,
                text,
                reply_to_id,
                version,
                deleted,
                message_created_at,
            )
        )

    insert_message(quote_id, uuid4(), 1, "quoted", None, 1, None, created)
    insert_message(plain_id, plain_client, 2, "plain legacy", None, 1, None, created)
    insert_message(rich_id, rich_client, 3, "rich legacy", quote_id, 1, None, created)
    insert_message(deleted_id, deleted_client, 4, " ", None, 2, deleted_at, created)
    asyncio.run(
        fetch(
            empty_database,
            """
        INSERT INTO chat_message_archive (id, chat_id, sender_id, client_id,
                                          sequence, text, reply_to_id, version,
                                          deleted_at, created_at)
        VALUES ($1, $2, $3, $4, 5, 'archived legacy', NULL, 1, NULL, $5)
    """,
            archived_id,
            chat_id,
            alice,
            archived_client,
            archived_created,
        )
    )
    for message_id, client_id, sequence, text, message_created_at in (
        (plain_id, plain_client, 2, "plain legacy", created),
        (rich_id, rich_client, 3, "rich legacy", created),
        (deleted_id, deleted_client, 4, " ", created),
        (archived_id, archived_client, 5, "archived legacy", archived_created),
    ):
        asyncio.run(
            fetch(
                empty_database,
                """
            INSERT INTO chat_message_dedup (chat_id, client_id, sender_id,
                                            sequence, message_id,
                                            message_created_at, content_hash,
                                            created_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        """,
                chat_id,
                client_id,
                alice,
                sequence,
                message_id,
                message_created_at,
                content_hash(text),
                created,
            )
        )
    for message_id, position, photo_id in (
        (rich_id, 0, rich_photo_a),
        (rich_id, 1, rich_photo_b),
        (deleted_id, 0, uuid4()),
    ):
        asyncio.run(
            fetch(
                empty_database,
                """
            INSERT INTO file (id, created_at, updated_at, owner_id, purpose,
                              key, status, size, upload_expires_at, expires_at,
                              chat_id, message_id, message_position)
            VALUES ($1, now(), now(), $2, 'chat_photo', $3, 'ready', 10,
                    now() + interval '1 hour', now() + interval '1 day',
                    $4, $5, $6)
        """,
                photo_id,
                alice,
                f"photos/{photo_id}",
                chat_id,
                message_id,
                position,
            )
        )

    run_alembic(empty_database, "upgrade", "head")
    rows = asyncio.run(
        fetch(
            empty_database,
            """
        SELECT client_id, content_hash, content_fingerprint
        FROM chat_message_dedup
    """,
        )
    )
    by_client = {row["client_id"]: row for row in rows}
    assert by_client[plain_client]["content_fingerprint"] == body_fingerprint(
        content_hash("plain legacy"), None, []
    )
    assert by_client[rich_client]["content_fingerprint"] == body_fingerprint(
        content_hash("rich legacy"), quote_id, [rich_photo_a, rich_photo_b]
    )
    assert by_client[archived_client]["content_fingerprint"] == body_fingerprint(
        content_hash("archived legacy"), None, []
    )
    assert by_client[deleted_client]["content_fingerprint"] is None
    assert by_client[deleted_client]["content_hash"] == content_hash(" ")

    run_alembic(empty_database, "downgrade", "81a000000001")
    columns = asyncio.run(
        fetch(
            empty_database,
            """
        SELECT column_name FROM information_schema.columns
        WHERE table_name = 'chat_message_dedup'
    """,
        )
    )
    assert "content_fingerprint" not in {row["column_name"] for row in columns}
    preserved = asyncio.run(
        fetch(
            empty_database,
            "SELECT content_hash FROM chat_message_dedup WHERE client_id = $1",
            rich_client,
        )
    )
    assert preserved[0]["content_hash"] == content_hash("rich legacy")


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


def test_offline_qr_schema_migrates(empty_database: str) -> None:
    columns = """
        SELECT column_name FROM information_schema.columns
        WHERE table_name = 'reputation_qr_scan'
    """
    constraints = """
        SELECT conname FROM pg_constraint
        WHERE conname IN (
            'uq_reputation_qr_scan_confirmation_id',
            'ck_reputation_qr_scan_mode',
            'ck_reputation_qr_scan_offline_fields'
        )
    """
    indexes = """
        SELECT indexname FROM pg_indexes
        WHERE indexname = 'ix_listing_event_interaction_accepted'
    """

    run_alembic(empty_database, "upgrade", "head")
    names = {row["column_name"] for row in asyncio.run(fetch(empty_database, columns))}
    assert {"mode", "confirmation_id", "payload_hash", "received_at"} <= names
    assert len(asyncio.run(fetch(empty_database, constraints))) == 3
    assert asyncio.run(fetch(empty_database, indexes))

    run_alembic(empty_database, "downgrade", "81a000000001")
    names = {row["column_name"] for row in asyncio.run(fetch(empty_database, columns))}
    assert not {"mode", "confirmation_id", "payload_hash", "received_at"} & names
    assert asyncio.run(fetch(empty_database, constraints)) == []
    assert asyncio.run(fetch(empty_database, indexes)) == []


def test_group_chats_are_backfilled_for_accepted_events(
    empty_database: str,
) -> None:
    """An event accepted before #83 gets its chat and realtime grants."""
    run_alembic(empty_database, "upgrade", "63a000000001")
    owner, participant = uuid4(), uuid4()
    for user_id, email in (
        (owner, "group-owner@university.example"),
        (participant, "group-participant@university.example"),
    ):
        asyncio.run(
            fetch(
                empty_database,
                """
            INSERT INTO identity_user (id, email, first_name, last_name,
                                       account_type, created_at, updated_at)
            VALUES ($1, $2, 'Group', 'User', 'student', now(), now())
        """,
                user_id,
                email,
            )
        )
    city = uuid4()
    asyncio.run(
        fetch(
            empty_database,
            """
        INSERT INTO university_city (id, code, timezone, name_ru, name_en,
                                     created_at, updated_at)
        VALUES ($1, 'moscow', 'Europe/Moscow', 'Москва', 'Moscow', now(), now())
    """,
            city,
        )
    )
    listing = uuid4()
    starts = datetime(2026, 12, 1, 12, tzinfo=UTC)
    asyncio.run(
        fetch(
            empty_database,
            """
        INSERT INTO listing
            (id, author_id, kind, title, description, status, visibility,
             audience, city_id, version, expires_at, event_starts_at,
             event_ends_at, event_location, event_capacity, event_registered,
             event_attendance_mode, created_at, updated_at)
        VALUES ($1, $2, 'event', 'Concert', 'Hall A', 'active', 'city',
                'community', $3, 1, $4, $4, $5, 'Hall A', 10, 1, 'self',
                now(), now())
    """,
            listing,
            owner,
            city,
            starts,
            starts + timedelta(hours=2),
        )
    )
    asyncio.run(
        fetch(
            empty_database,
            """
        INSERT INTO listing_interaction
            (listing_id, slot, participant_id, status, executor,
             late_cancelled, created_at, updated_at)
        VALUES ($1, NULL, $2, 'accepted', false, false, now(), now())
    """,
            listing,
            participant,
        )
    )

    run_alembic(empty_database, "upgrade", "head")
    chats = asyncio.run(
        fetch(
            empty_database,
            """
        SELECT c.id, c.kind, c.listing_id,
               (SELECT count(*) FROM chat_member m
                 WHERE m.chat_id = c.id AND m.left_at IS NULL) AS members,
               (SELECT count(*) FROM realtime_channel_grant g
                 WHERE g.channel = 'chat:' || c.id::text
                   AND g.revoked_at IS NULL) AS grants
        FROM chat c WHERE c.kind IN ('event', 'purchase')
    """,
        )
    )
    assert len(chats) == 1
    assert chats[0]["kind"] == "event"
    assert chats[0]["listing_id"] == listing
    assert chats[0]["members"] == 2
    assert chats[0]["grants"] == 2

    run_alembic(empty_database, "downgrade", "63a000000001")
    assert (
        asyncio.run(
            fetch(empty_database, "SELECT id FROM chat WHERE kind <> 'personal'")
        )
        == []
    )
    assert (
        asyncio.run(
            fetch(
                empty_database,
                """
        SELECT indexname FROM pg_indexes
        WHERE indexname = 'uq_chat_listing_group'
    """,
            )
        )
        == []
    )
