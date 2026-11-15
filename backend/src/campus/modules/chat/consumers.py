"""Chat outbox: publish a committed message to its realtime channel.

The publication is written in the transaction that stores the message, so
a rollback publishes nothing and a failing Centrifugo is retried with the
outbox id as the idempotency key. Realtime is only a wakeup: clients that
miss a publication fetch the history by sequence.
"""

from uuid import UUID

from sqlalchemy import update
from sqlalchemy.ext.asyncio import AsyncSession

from campus.core.jobs import JobInfo
from campus.core.outbox import OutboxMessage, outbox_handlers
from campus.modules.chat.service import MESSAGE_TOPIC
from campus.modules.realtime import chat_channel, publish_channel


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
