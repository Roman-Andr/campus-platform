"""Transactional notification producers, inbox and delivery adapters."""

from campus.modules.notifications.api import router
from campus.modules.notifications.delivery import (
    NotificationEvent,
    notification_consumers,
    register_channel,
    register_validator,
    replay_notification_events,
)
from campus.modules.notifications.events import (
    IMPORTANT_TYPES,
    LISTING_CHANGED,
    LISTING_OFFER,
    LISTING_OFFER_EXPIRED,
    LISTING_WAITLIST_CLEARED,
    LISTING_WAITLIST_JOINED,
    LISTING_WAITLIST_OPEN,
    notify,
)
from campus.modules.notifications.models import (
    Inbox,
    MutedChat,
    Notification,
    NotificationSettings,
    Reminder,
)
from campus.modules.notifications.preferences import (
    EffectiveSettings,
    default_settings,
    effective_settings,
    external_delivery_allowed,
    is_chat_member,
    quiet_hours_active,
    user_timezone,
)
from campus.modules.notifications.reminders import cancel_reminders, schedule_reminders

__all__ = [
    "IMPORTANT_TYPES",
    "LISTING_CHANGED",
    "LISTING_OFFER",
    "LISTING_OFFER_EXPIRED",
    "LISTING_WAITLIST_CLEARED",
    "LISTING_WAITLIST_JOINED",
    "LISTING_WAITLIST_OPEN",
    "EffectiveSettings",
    "Inbox",
    "MutedChat",
    "Notification",
    "NotificationEvent",
    "NotificationSettings",
    "Reminder",
    "cancel_reminders",
    "default_settings",
    "effective_settings",
    "external_delivery_allowed",
    "is_chat_member",
    "notification_consumers",
    "notify",
    "quiet_hours_active",
    "register_channel",
    "register_validator",
    "replay_notification_events",
    "router",
    "schedule_reminders",
    "user_timezone",
]
