"""Durable session revocation delivery; channel consumers register on import."""

from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from campus.core.event_dispatch import DispatchReceipt, EventConsumers
from campus.core.jobs import JobInfo

SESSIONS_REVOKED = "identity.sessions_revoked"


class SessionDispatch(DispatchReceipt):
    """Permanent receipts survive cleanup of completed delivery jobs."""

    __tablename__ = "identity_session_dispatch"


@dataclass(frozen=True)
class SessionsRevoked:
    """Use delivery_id as the provider's external idempotency key.

    A lost acknowledgement can repeat the callback with the same key.
    session_ids contains the revoked devices, never the user's other
    sessions (which may have been created since the event).
    """

    delivery_id: UUID
    user_id: UUID
    session_ids: tuple[UUID, ...]


type SessionConsumer = Callable[[AsyncSession, SessionsRevoked], Awaitable[None]]


class SessionConsumers(EventConsumers):
    def __init__(self) -> None:
        super().__init__(SESSIONS_REVOKED, "identity.session", SessionDispatch)

    def register(self, name: str) -> Callable[[SessionConsumer], SessionConsumer]:
        register = self.register_handler(name)

        def decorator(consumer: SessionConsumer) -> SessionConsumer:
            async def deliver(session: AsyncSession, job: JobInfo) -> None:
                await consumer(
                    session,
                    SessionsRevoked(
                        job.id,
                        UUID(job.payload["user_id"]),
                        tuple(UUID(value) for value in job.payload["session_ids"]),
                    ),
                )

            register(deliver)
            return consumer

        return decorator


session_consumers = SessionConsumers()


async def replay_session_events(session: AsyncSession) -> int:
    """Replay retained events, including legacy UnknownTopicError failures."""
    return await session_consumers.replay(session)
