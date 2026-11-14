"""Versioned event and return reminders on the shared deadline scheduler."""

from datetime import datetime
from typing import Literal
from uuid import UUID, uuid4, uuid5

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from campus.core import clock
from campus.core.config import Settings
from campus.core.deadlines import deadline_handlers, schedule_deadline
from campus.core.i18n import N_, translate
from campus.core.jobs import JobInfo
from campus.core.outbox import add_message
from campus.modules.notifications.models import Reminder

REMINDER_TEXT = N_("An event or return deadline is approaching.")


async def cancel_reminders(session: AsyncSession, key: str) -> None:
    """Serialize with firing and invalidate already queued, unsaved reminders."""
    reminder = await session.scalar(
        select(Reminder).where(Reminder.key == key).with_for_update()
    )
    if reminder is not None:
        reminder.active = False


async def schedule_reminders(  # noqa: PLR0913 - domain schedule contract
    session: AsyncSession,
    settings: Settings,
    *,
    key: str,
    category: Literal["event", "return"],
    object_id: UUID,
    recipients: set[UUID],
    starts_at: datetime,
) -> None:
    """Call in the source transaction on creation or rescheduling.

    The owning domain authorizes recipients and calls cancel_reminders on
    cancellation. Repeating the unchanged schedule keeps the same revision.
    """
    payload = {
        "type": f"{category}.reminder",
        "recipients": sorted(str(value) for value in recipients),
        "params": {"object_id": str(object_id), "time": starts_at.isoformat()},
        "text": {locale: translate(REMINDER_TEXT, locale) for locale in ("ru", "en")},
    }
    await session.execute(
        insert(Reminder)
        .values(
            key=key,
            revision=uuid4(),
            starts_at=starts_at,
            active=False,
            payload=payload,
        )
        .on_conflict_do_nothing()
    )
    reminder = await session.scalar(
        select(Reminder).where(Reminder.key == key).with_for_update()
    )
    assert reminder is not None  # noqa: S101 - inserted above
    if (
        reminder.active
        and reminder.starts_at == starts_at
        and reminder.payload == payload
    ):
        return
    await cancel_reminders(session, key)
    reminder.revision = uuid4()
    reminder.active = True
    reminder.starts_at = starts_at
    reminder.payload = payload
    offsets = (
        {"long": settings.return_reminder_before}
        if category == "return"
        else {
            "long": settings.meeting_reminder_long,
            "short": settings.meeting_reminder_short,
        }
    )
    for kind, offset in offsets.items():
        due_at = starts_at - offset
        if due_at <= clock.now():
            continue
        await schedule_deadline(
            session,
            "notifications.remind",
            due_at,
            {"key": key, "revision": str(reminder.revision), "kind": kind},
            key=f"notification:{reminder.revision}:{kind}",
        )


@deadline_handlers.register("notifications.remind")
async def remind(session: AsyncSession, job: JobInfo) -> None:
    reminder = await session.scalar(
        select(Reminder).where(Reminder.key == job.payload["key"]).with_for_update()
    )
    if (
        reminder is None
        or not reminder.active
        or str(reminder.revision) != job.payload["revision"]
        or reminder.starts_at <= clock.now()
    ):
        return
    add_message(
        session,
        "notifications.send",
        {
            **reminder.payload,
            "event_id": str(uuid5(reminder.revision, job.payload["kind"])),
            "reminder_key": reminder.key,
            "reminder_revision": str(reminder.revision),
            "occurred_at": clock.now().isoformat(),
        },
    )
