"""Transactional notification interface; delivery belongs to #85."""

from typing import Any
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from campus.core.i18n import N_, translate
from campus.core.outbox import add_message

LISTING_CHANGED = N_("There is an update to your listing.")


def notify(
    session: AsyncSession,
    recipients: set[UUID],
    notification_type: str,
    params: dict[str, Any],
) -> None:
    """Enqueue a notification in the caller's transaction, without delivery."""
    add_message(
        session,
        "notifications.send",
        {
            "recipients": sorted(str(value) for value in recipients),
            "type": notification_type,
            "params": params,
            "text": {
                locale: translate(LISTING_CHANGED, locale) for locale in ("ru", "en")
            },
        },
    )
