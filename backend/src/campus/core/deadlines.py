"""Deadlines stored in the database (specification, 4.3, 5.2).

Instead of delayed tasks in the queue, a module records a deadline with
:func:`schedule_deadline` in its own transaction; the scheduler triggers
:func:`process_due_deadlines` every minute, which runs the handler of every
deadline whose time has come (``@deadline_handlers.register(topic)``).
A deadline missed while the scheduler was down is simply due, so it is
processed on the first run after the start. Rows are claimed with
``FOR UPDATE SKIP LOCKED``: concurrent runs never process one deadline twice.
"""

from datetime import datetime
from typing import Any

from sqlalchemy import Index, String, delete, text
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker
from sqlalchemy.orm import Mapped, mapped_column

from campus.core import clock
from campus.core.config import Settings
from campus.core.jobs import (
    Handlers,
    Job,
    RetryPolicy,
    delete_finished_jobs,
    run_due_jobs,
)

deadline_handlers = Handlers()

_PENDING = "processed_at IS NULL AND failed_at IS NULL"


class Deadline(Job):
    __tablename__ = "deadline"
    __table_args__ = (
        Index("ix_deadline_pending", "available_at", postgresql_where=text(_PENDING)),
        Index(
            "uq_deadline_pending_key",
            "key",
            unique=True,
            postgresql_where=text(_PENDING),
        ),
    )

    due_at: Mapped[datetime]

    # Identifies a pending deadline to move or cancel it, e.g.
    # "booking-expiry:<booking id>". Unique among pending deadlines.
    key: Mapped[str | None] = mapped_column(String(200))


async def schedule_deadline(
    session: AsyncSession,
    topic: str,
    due_at: datetime,
    payload: dict[str, Any],
    *,
    key: str | None = None,
) -> None:
    """Record a deadline in the current transaction of ``session``.

    A pending deadline with the same ``key`` is replaced: its time, topic and
    payload change and its attempts start over.
    """
    now = clock.now()
    values = {
        "topic": topic,
        "payload": payload,
        "available_at": due_at,
        "due_at": due_at,
        "attempts": 0,
        "last_error": None,
        "updated_at": now,
    }
    statement = insert(Deadline).values(key=key, created_at=now, **values)
    if key is not None:
        statement = statement.on_conflict_do_update(
            index_elements=[Deadline.key],
            index_where=text(_PENDING),
            set_=values,
        )
    await session.execute(statement)


async def cancel_deadline(session: AsyncSession, key: str) -> bool:
    """Cancel the pending deadline with ``key``; ``False`` if there is none."""
    result = await session.execute(
        delete(Deadline).where(Deadline.key == key, Deadline.is_pending())
    )
    return bool(result.rowcount)  # type: ignore[attr-defined]


async def process_due_deadlines(
    sessions: async_sessionmaker[AsyncSession], settings: Settings
) -> int:
    """Run every due deadline; return the number attempted."""
    policy = RetryPolicy.from_settings(settings)
    total = 0
    while True:
        attempted = await run_due_jobs(
            sessions,
            Deadline,
            deadline_handlers,
            policy,
            limit=settings.job_batch_size,
        )
        total += attempted
        if attempted < settings.job_batch_size:
            return total


async def delete_finished_deadlines(
    sessions: async_sessionmaker[AsyncSession], settings: Settings
) -> int:
    """Delete deadlines finished longer than the retention period ago."""
    return await delete_finished_jobs(
        sessions,
        Deadline,
        retention=settings.deadline_retention,
    )
