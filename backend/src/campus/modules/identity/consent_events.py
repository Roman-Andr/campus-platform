"""Durable fan-out of consent events to independently retried consumers."""

from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from campus.core.event_dispatch import DispatchReceipt, EventConsumers
from campus.core.jobs import JobInfo
from campus.modules.identity.consents import cross_border_allowed, lock_consent_state

CONSENT_CHANGED = "identity.cross_border_consent_changed"


class ConsentDispatch(DispatchReceipt):
    """Permanent deduplication receipt, independent of outbox retention."""

    __tablename__ = "identity_consent_dispatch"


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


class ConsentConsumers(EventConsumers):
    """Consumers register on module import, before starting the worker."""

    def __init__(self) -> None:
        super().__init__(CONSENT_CHANGED, "identity.consent", ConsentDispatch)

    def register(self, name: str) -> Callable[[ConsentConsumer], ConsentConsumer]:
        register = self.register_handler(name)

        def decorator(consumer: ConsentConsumer) -> ConsentConsumer:
            async def deliver(session: AsyncSession, job: JobInfo) -> None:
                user_id = UUID(job.payload["user_id"])
                # Serialize with revocation and document publication until
                # this transaction (including the external callback) ends.
                await lock_consent_state(session, user_id)
                allowed = await cross_border_allowed(session, user_id)
                await consumer(session, ConsentChange(job.id, user_id, allowed))

            register(deliver)
            return consumer

        return decorator


consent_consumers = ConsentConsumers()


async def replay_consent_events(session: AsyncSession) -> int:
    """Replay retained events after importing all domain modules."""
    return await consent_consumers.replay(session)
