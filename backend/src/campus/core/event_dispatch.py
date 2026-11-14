"""Durable event fan-out using independently retried outbox deliveries."""

import re
from collections.abc import Callable
from uuid import UUID, uuid5

from sqlalchemy import String, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import Mapped, mapped_column

from campus.core import clock
from campus.core.db import Base
from campus.core.jobs import Handler, JobInfo
from campus.core.outbox import OutboxMessage, outbox_handlers


class DispatchReceipt(Base):
    """Permanent deduplication, independent of outbox retention.

    Each event family supplies its own concrete receipt table. Receipts
    and delivery jobs commit atomically; receipts must never be pruned
    while the source events can be replayed.
    """

    __abstract__ = True

    event_id: Mapped[UUID] = mapped_column(primary_key=True)
    consumer: Mapped[str] = mapped_column(String(50), primary_key=True)


class EventConsumers:
    """Register on module import; dispatch one outbox job per consumer.

    Callbacks use job.id as the external idempotency key, including after
    a lost acknowledgement. Database effects commit with job completion.
    Keep consumer names stable across deployments.
    """

    def __init__(
        self, event_topic: str, delivery_prefix: str, receipt: type[DispatchReceipt]
    ) -> None:
        self.event_topic = event_topic
        self.delivery_prefix = delivery_prefix
        self.receipt = receipt
        self._topics: dict[str, str] = {}
        outbox_handlers.register(event_topic)(self.dispatch)

    def register_handler(self, name: str) -> Callable[[Handler], Handler]:
        if not re.fullmatch(r"[a-z][a-z0-9_]{0,49}", name):
            raise ValueError(
                "Consumer names must be lowercase identifiers up to 50 chars"
            )
        topic = f"{self.delivery_prefix}.{name}"

        def decorator(consumer: Handler) -> Handler:
            outbox_handlers.register(topic)(consumer)
            self._topics[name] = topic
            return consumer

        return decorator

    def remove(self, name: str) -> None:
        """Remove a consumer (for tests)."""
        outbox_handlers.remove(self._topics.pop(name))

    async def dispatch(self, session: AsyncSession, event: JobInfo) -> None:
        """Zero consumers is a successfully handled event."""
        for name, topic in self._topics.items():
            inserted = await session.scalar(
                insert(self.receipt)
                .values(event_id=event.id, consumer=name)
                .on_conflict_do_nothing()
                .returning(self.receipt.event_id)
            )
            if inserted is not None:
                session.add(
                    OutboxMessage(
                        id=uuid5(event.id, name),
                        topic=topic,
                        payload=event.payload,
                        available_at=clock.now(),
                    )
                )

    async def replay(self, session: AsyncSession) -> int:
        """Fan out retained events in a deployment transaction.

        Import all modules first. Repeated/concurrent replay only adds
        missing deliveries; failed delivery jobs retain their retry state.
        Recover legacy UnknownTopicError source failures, leaving other
        failures visible. Pruned source events cannot be replayed.
        """
        count = 0
        events = await session.stream_scalars(
            select(OutboxMessage)
            .where(OutboxMessage.topic == self.event_topic)
            .order_by(OutboxMessage.id)
            .with_for_update()
            .execution_options(yield_per=100)
        )
        async for event in events:
            await self.dispatch(
                session,
                JobInfo(event.id, event.topic, event.payload, event.attempts),
            )
            if event.failed_at is not None and (event.last_error or "").startswith(
                "UnknownTopicError:"
            ):
                event.failed_at = None
                event.last_error = None
                event.processed_at = clock.now()
            count += 1
        return count
