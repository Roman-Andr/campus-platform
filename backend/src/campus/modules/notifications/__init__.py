"""Transactional notification interface; delivery belongs to #85."""

from typing import Any
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from campus.core.i18n import N_, translate
from campus.core.outbox import add_message

LISTING_CHANGED = N_("There is an update to your listing.")
LISTING_WAITLIST_JOINED = N_("Someone joined the queue of your listing.")
LISTING_WAITLIST_CLEARED = N_("The listing is closed; you are no longer in its queue.")
LISTING_WAITLIST_OPEN = N_("Places are open to everyone; book now.")
LISTING_OFFER = N_(
    "A place in the queue is available for you. Confirm it before the timer ends."
)
LISTING_OFFER_EXPIRED = N_("Your place offer has expired.")

# Important notifications are not grouped and pass through quiet hours (#88).
IMPORTANT_TYPES = frozenset({"listing.offer"})


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
            "important": notification_type in IMPORTANT_TYPES,
            "params": params,
            "text": {locale: translate(message, locale) for locale in ("ru", "en")},
        },
    )
