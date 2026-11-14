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
    message: str = LISTING_CHANGED,
) -> None:
    """Enqueue a notification in the caller's transaction, without delivery.

    ``message`` is an English message ID marked with :func:`N_`; the
    catalog of every supported locale is stored with the message, so the
    delivery stage can render it in the language of the recipient.
    """
    add_message(
        session,
        "notifications.send",
        {
            "recipients": sorted(str(value) for value in recipients),
            "type": notification_type,
            "params": params,
            "text": {locale: translate(message, locale) for locale in ("ru", "en")},
        },
    )
