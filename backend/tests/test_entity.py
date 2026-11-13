"""Base entity on a real database: keys, time columns, naming, isolation."""

import asyncio
from datetime import UTC, datetime, timedelta

import pytest
import time_machine
from sqlalchemy import func, select, text
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession

from campus.core.db import create_session_factory
from tests.factories import NoteFactory
from tests.models import Note


@pytest.mark.usefixtures("session")
async def test_key_is_uuidv7_generated_by_database() -> None:
    first = await NoteFactory.create_async()
    second = await NoteFactory.create_async()

    assert first.id.version == 7
    assert first.id < second.id  # ordered by creation


async def test_time_columns_are_timestamptz_without_database_defaults(
    session: AsyncSession,
) -> None:
    rows = await session.execute(
        text(
            "SELECT column_name, data_type, column_default"
            " FROM information_schema.columns WHERE table_name = 'test_note'"
        )
    )
    columns = {name: (data_type, default) for name, data_type, default in rows}

    assert columns["id"] == ("uuid", "uuidv7()")
    assert columns["created_at"] == ("timestamp with time zone", None)
    assert columns["updated_at"] == ("timestamp with time zone", None)


async def test_constraints_follow_naming_convention(session: AsyncSession) -> None:
    names = await session.scalars(
        text(
            # PostgreSQL 18 also lists NOT NULL constraints (contype 'n').
            "SELECT conname FROM pg_constraint"
            " WHERE conrelid = 'test_note'::regclass AND contype <> 'n'"
        )
    )

    assert list(names) == ["pk_test_note"]


async def test_times_come_from_the_controlled_clock(session: AsyncSession) -> None:
    created = datetime(2027, 2, 1, 9, 0, tzinfo=UTC)
    with time_machine.travel(created, tick=False) as traveller:
        note = await NoteFactory.create_async()
        await session.commit()

        traveller.shift(timedelta(hours=2))
        note.title = "Renamed"
        await session.commit()

    await session.refresh(note)
    assert note.created_at == created
    assert note.updated_at == created + timedelta(hours=2)


async def test_pgvector_is_available(session: AsyncSession) -> None:
    distance = await session.scalar(text("SELECT '[1,2,3]'::vector <-> '[1,2,5]'"))

    assert distance == 2.0


@pytest.mark.parametrize("run", [1, 2])
async def test_committed_rows_do_not_leak_between_tests(
    session: AsyncSession, run: int
) -> None:
    assert await session.scalar(select(func.count()).select_from(Note)) == 0

    await NoteFactory.create_async(title=f"run {run}")
    await session.commit()


async def test_concurrent_transactions_see_each_others_commits(
    engine: AsyncEngine,
) -> None:
    sessions = create_session_factory(engine)

    async def add_note(title: str) -> None:
        async with sessions() as session, session.begin():
            session.add(Note(title=title))

    await asyncio.gather(*(add_note(f"note {i}") for i in range(5)))

    async with sessions() as session:
        assert await session.scalar(select(func.count()).select_from(Note)) == 5
