"""Chat outbox: publish committed messages and chat activity.

The publication is written in the transaction that stores the change, so a
rollback publishes nothing and a failing Centrifugo is retried with the
outbox id as the idempotency key. Realtime is only a wakeup: clients that
miss a publication fetch the history, the read state or the ephemeral
activity through the API.
"""

from uuid import UUID

from sqlalchemy import update
from sqlalchemy.ext.asyncio import AsyncSession

from campus.core.jobs import JobInfo
from campus.core.outbox import OutboxMessage, outbox_handlers
from campus.modules.chat.service import MESSAGE_TOPIC, PRESENCE_TOPIC, READ_TOPIC
from campus.modules.realtime import (
    chat_channel,
    publish_channel,
    publish_personal,
)


@outbox_handlers.register(MESSAGE_TOPIC)
async def _publish_message(session: AsyncSession, job: JobInfo) -> None:
    """Publish metadata only, also for rows queued before the payload change."""
    payload = {key: value for key, value in job.payload.items() if key != "text"}
    if payload != job.payload:
        await session.execute(
            update(OutboxMessage)
            .where(OutboxMessage.id == job.id)
            .values(payload=payload)
            .execution_options(synchronize_session=False)
        )
    chat_id = UUID(str(payload["chat_id"]))
    await publish_channel(chat_channel(chat_id).name, payload, job.id)


@outbox_handlers.register(READ_TOPIC)
async def _publish_read(_session: AsyncSession, job: JobInfo) -> None:
    """Announce a committed read position to every device of the member.

    The personal channel is user-limited, so the marker reaches all active
    sessions of one user and never another member: who has read the chat is
    not the other participant's event yet.
    """
    user_id = UUID(str(job.payload["user_id"]))
    await publish_personal(user_id, dict(job.payload), job.id)


@outbox_handlers.register(PRESENCE_TOPIC)
async def _publish_presence(_session: AsyncSession, job: JobInfo) -> None:
    """Wake up the chat channel after an ephemeral heartbeat.

    The payload carries identifiers and the two flags only; the truth is the
    ephemeral REST state, which the chat members read after the wakeup. The
    channel is granted to members only, so an outsider cannot observe the
    activity.
    """
    chat_id = UUID(str(job.payload["chat_id"]))
    await publish_channel(chat_channel(chat_id).name, dict(job.payload), job.id)
