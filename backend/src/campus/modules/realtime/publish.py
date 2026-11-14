"""Private inbox wakeups; clients recover persisted rows through the API."""

from typing import Any
from uuid import UUID

from campus.core.config import get_settings
from campus.modules.realtime.centrifugo import centrifugo_client
from campus.modules.realtime.channels import personal_channel


async def publish_personal(
    user_id: UUID, data: dict[str, Any], delivery_id: UUID
) -> None:
    async with centrifugo_client(get_settings()) as client:
        await client.publish(
            channel=personal_channel(user_id).name,
            data=data,
            idempotency_key=str(delivery_id),
        )
