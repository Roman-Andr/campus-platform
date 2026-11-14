"""Durable fan-out of consent events to independently retried consumers."""

import re
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from uuid import UUID, uuid5

from sqlalchemy import String, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import Mapped, mapped_column

from campus.core import clock
from campus.core.db import Base
from campus.core.jobs import JobInfo
from campus.core.outbox import OutboxMessage, outbox_handlers
from campus.modules.identity.consents import cross_border_allowed, lock_consent_state

CONSENT_CHANGED = "identity.cross_border_consent_changed"


class ConsentDispatch(Base):
    """Permanent deduplication receipt, independent of outbox retention."""

    __tablename__ = "identity_consent_dispatch"

    event_id: Mapped[UUID] = mapped_column(primary_key=True)
    consumer: Mapped[str] = mapped_column(String(50), primary_key=True)


@dataclass(frozen=True)
class ConsentChange:
    """Current permission, never the historical grant in an event payload.

    Consumers must use delivery_id as the external idempotency key. They
    must perform transfers inside the callback, while consent locks are
    held, and recheck cross_border_allowed for any later queued transfer.
    """

    delivery_id: UUID
    user_id: UUID
    allowed: bool


type ConsentConsumer = Callable[[AsyncSession, ConsentChange], Awaitable[None]]


class ConsentConsumers:
    """Consumers register on module import, before starting the worker."""

    def __init__(self) -> None:
        self._topics: dict[str, str] = {}

    def register(self, name: str) -> Callable[[ConsentConsumer], ConsentConsumer]:
        if not re.fullmatch(r"[a-z][a-z0-9_]{0,49}", name):
            raise ValueError(
                "Consumer names must be lowercase identifiers up to 50 chars"
            )
        topic = f"identity.consent.{name}"

        def decorator(consumer: ConsentConsumer) -> ConsentConsumer:
            async def deliver(session: AsyncSession, job: JobInfo) -> None:
                user_id = UUID(job.payload["user_id"])
                # Serialize with revocation and document publication until
                # this transaction (including the external callback) ends.
                await lock_consent_state(session, user_id)
                allowed = await cross_border_allowed(session, user_id)
                await consumer(session, ConsentChange(job.id, user_id, allowed))

            outbox_handlers.register(topic)(deliver)
            self._topics[name] = topic
            return consumer

        return decorator

    def remove(self, name: str) -> None:
        """Remove a consumer (for tests)."""
        outbox_handlers.remove(self._topics.pop(name))

    async def dispatch(self, session: AsyncSession, event: JobInfo) -> None:
        for name, topic in self._topics.items():
            inserted = await session.scalar(
                insert(ConsentDispatch)
                .values(event_id=event.id, consumer=name)
                .on_conflict_do_nothing()
                .returning(ConsentDispatch.event_id)
            )
            if inserted is not None:
                session.add(
                    OutboxMessage(
                        id=uuid5(event.id, name),
                        topic=topic,
                        payload={"user_id": event.payload["user_id"]},
                        available_at=clock.now(),
                    )
                )


consent_consumers = ConsentConsumers()


@outbox_handlers.register(CONSENT_CHANGED)
async def dispatch_consent_change(session: AsyncSession, event: JobInfo) -> None:
    """No connected channels is a valid, successfully handled event."""
    await consent_consumers.dispatch(session, event)


async def replay_consent_events(session: AsyncSession) -> int:
    """Fan out retained events, including failed ones, after enabling consumers.

    Run in a deployment transaction after importing all domain modules.
    Receipts prevent resending to existing consumers, even after their
    completed delivery jobs have been pruned. Only legacy UnknownTopicError
    failures are marked recovered; other failures remain visible.
    """
    count = 0
    events = await session.stream_scalars(
        select(OutboxMessage)
        .where(OutboxMessage.topic == CONSENT_CHANGED)
        .order_by(OutboxMessage.id)
        .with_for_update()
        .execution_options(yield_per=100)
    )
    async for event in events:
        await dispatch_consent_change(
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
