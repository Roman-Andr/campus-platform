"""Publications of domain events; clients recover persisted rows through the API."""

from typing import Any
from uuid import UUID

from campus.core.config import get_settings
from campus.modules.realtime.centrifugo import centrifugo_client
from campus.modules.realtime.channels import personal_channel


async def publish_channel(
    channel: str, data: dict[str, Any], delivery_id: UUID
) -> None:
    """Publish ``data`` to ``channel`` with a stable idempotency key.

    ``delivery_id`` is the outbox message id: a retried publication carries
    the same key, so Centrifugo stores one publication, not a duplicate.
    """
    async with centrifugo_client(get_settings()) as client:
        await client.publish(
            channel=channel,
            data=data,
            idempotency_key=str(delivery_id),
        )


async def publish_personal(
    user_id: UUID, data: dict[str, Any], delivery_id: UUID
) -> None:
    await publish_channel(personal_channel(user_id).name, data, delivery_id)
