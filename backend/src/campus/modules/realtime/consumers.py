"""Durable realtime side effects: forced unsubscribe and disconnect.

Both effects are written to the outbox in the transaction that changes the
source state, so a rollback never removes a live subscription and a lost
acknowledgement is retried. Centrifugo's ``unsubscribe`` and ``disconnect``
commands are idempotent, and the unsubscribe consumer rechecks the grant: a
delivery that arrives after the user was granted access again is skipped, so
a stale command cannot undo a fresh membership.
"""

from uuid import UUID

import structlog
from sqlalchemy.ext.asyncio import AsyncSession

from campus.core.config import get_settings
from campus.core.jobs import JobInfo
from campus.core.outbox import outbox_handlers
from campus.modules.identity import SessionsRevoked, session_consumers
from campus.modules.realtime.centrifugo import centrifugo_client
from campus.modules.realtime.channels import UNSUBSCRIBE_TOPIC, can_access

logger = structlog.get_logger(__name__)


@outbox_handlers.register(UNSUBSCRIBE_TOPIC)
async def _force_unsubscribe(session: AsyncSession, job: JobInfo) -> None:
    channel = str(job.payload["channel"])
    user_id = UUID(str(job.payload["user_id"]))
    if await can_access(session, channel, user_id):
        logger.info(
            "realtime_unsubscribe_skipped",
            channel=channel,
            user_id=str(user_id),
            reason="access_granted_again",
        )
        return
    settings = get_settings()
    async with centrifugo_client(settings) as client:
        await client.unsubscribe(channel=channel, user=str(user_id))
    logger.info(
        "realtime_unsubscribed",
        channel=channel,
        user_id=str(user_id),
        delivery_id=str(job.id),
    )


@session_consumers.register("realtime_connections")
async def _disconnect_revoked_session(
    _session: AsyncSession, change: SessionsRevoked
) -> None:
    """Disconnect every connection of the user whose session was revoked.

    A connection token is bound to one device session, but Centrifugo's
    server API disconnects by user, not by our session id. The other devices
    reconnect and subscribe again; the revoked device cannot get a new
    connection token because the API checks the session row and the revoked
    list on every issue. The command is idempotent, so outbox retries and
    session-event replay are safe.
    """
    settings = get_settings()
    async with centrifugo_client(settings) as client:
        await client.disconnect(user=str(change.user_id))
    logger.info(
        "realtime_disconnected",
        user_id=str(change.user_id),
        session_ids=[str(session_id) for session_id in change.session_ids],
        delivery_id=str(change.delivery_id),
    )
