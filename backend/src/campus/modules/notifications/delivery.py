"""Validate events, persist inboxes, then fan out independently retried channels."""

from collections.abc import Awaitable, Callable
from typing import Any
from uuid import UUID, uuid5

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field
from sqlalchemy import select, update
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from campus.core import clock
from campus.core.event_dispatch import EventConsumers
from campus.core.jobs import JobInfo
from campus.core.outbox import OutboxMessage
from campus.modules.notifications.models import (
    Inbox,
    Notification,
    NotificationDispatch,
    Reminder,
)
from campus.modules.notifications.preferences import external_delivery_allowed

# A producer can only address explicit recipients. Payloads contain no fetched
# content; the owning domain authorizes recipients in its source transaction.
NOTIFICATION_TYPES = frozenset(
    {
        "listing.activity",
        "listing.waitlist_joined",
        "listing.waitlist_cleared",
        "listing.waitlist_open",
        "listing.offer",
        "listing.offer_expired",
        "listing.meeting.proposed",
        "listing.meeting.scheduled",
        "listing.meeting.rescheduled",
        "listing.meeting.reminder",
        "response.created",
        "booking.changed",
        "status.changed",
        "message.received",
        "deadline.reminder",
        "moderation.decided",
        "event.reminder",
        "return.reminder",
    }
)


class NotificationEvent(BaseModel):
    """Version 1 wire contract; event_id survives producer retries/replays.

    Legacy producers use the stable source delivery ID without event_id.
    Never put a message body, listing description or moderation evidence in
    params: channels send only an inbox reference, and clients fetch content
    from its owning API, which checks current access.
    """

    model_config = ConfigDict(extra="forbid")
    version: int = Field(default=1, ge=1, le=1)
    event_id: UUID | None = None
    recipients: set[UUID]
    type: str
    important: bool = False
    params: dict[str, Any]
    text: dict[str, str]
    occurred_at: AwareDatetime | None = None
    reminder_key: str | None = None
    reminder_revision: UUID | None = None


type EventValidator = Callable[[AsyncSession, NotificationEvent], Awaitable[bool]]
validators: dict[str, EventValidator] = {}


def register_validator(kind: str) -> Callable[[EventValidator], EventValidator]:
    """Let a producer recheck a mutable source before saving a notification."""
    if kind not in NOTIFICATION_TYPES:
        raise ValueError(f"Unknown notification type: {kind}")

    def decorator(validator: EventValidator) -> EventValidator:
        validators[kind] = validator
        return validator

    return decorator


source_consumers = EventConsumers(
    "notifications.send", "notifications.event", NotificationDispatch
)
notification_consumers = EventConsumers(
    "notifications.saved", "notifications.channel", NotificationDispatch
)


@source_consumers.register_handler("inbox")
async def persist_notifications(session: AsyncSession, job: JobInfo) -> None:
    event = NotificationEvent.model_validate(job.payload)
    if event.type not in NOTIFICATION_TYPES:
        raise ValueError(f"Unknown notification type: {event.type}")
    validator = validators.get(event.type)
    if validator is not None and not await validator(session, event):
        return
    if event.reminder_key is not None:
        reminder = await session.scalar(
            select(Reminder).where(Reminder.key == event.reminder_key).with_for_update()
        )
        if (
            reminder is None
            or not reminder.active
            or reminder.starts_at <= clock.now()
            or reminder.revision != event.reminder_revision
        ):
            return
    event_id = event.event_id or job.id
    # All transactions acquire recipient locks in the same order.
    for recipient in sorted(event.recipients):
        await session.execute(
            insert(Inbox)
            .values(user_id=recipient, sequence=0, read_sequence=0)
            .on_conflict_do_nothing()
        )
        inbox = await session.scalar(
            select(Inbox).where(Inbox.user_id == recipient).with_for_update()
        )
        assert inbox is not None  # noqa: S101 - inserted above
        existing = await session.scalar(
            select(Notification.id).where(
                Notification.event_id == event_id,
                Notification.recipient_id == recipient,
            )
        )
        if existing is not None:
            continue
        # The row lock is held through commit, including the channel jobs.
        sequence = await session.scalar(
            update(Inbox)
            .where(Inbox.user_id == recipient)
            .values(sequence=Inbox.sequence + 1)
            .returning(Inbox.sequence)
        )
        assert sequence is not None  # noqa: S101 - locked inbox
        object_value = next(
            (
                event.params[key]
                for key in ("object_id", "listing_id", "event_id", "booking_id")
                if event.params.get(key)
            ),
            None,
        )
        notification_id = uuid5(event_id, str(recipient))
        session.add(
            Notification(
                id=notification_id,
                event_id=event_id,
                recipient_id=recipient,
                sequence=sequence,
                type=event.type,
                object_id=UUID(str(object_value)) if object_value else None,
                occurred_at=event.occurred_at or clock.now(),
                text=event.text,
                params=event.params,
                important=event.important,
            )
        )
        session.add(
            OutboxMessage(
                id=uuid5(notification_id, "saved"),
                topic="notifications.saved",
                payload={"notification_id": str(notification_id)},
                available_at=clock.now(),
            )
        )


type ChannelAdapter = Callable[[AsyncSession, Notification, UUID], Awaitable[None]]


def register_channel(
    name: str, *, cross_border: bool = False, in_app: bool = False
) -> Callable[[ChannelAdapter], ChannelAdapter]:
    """Register a delivery adapter, retried independently per channel.

    The last argument is the stable external idempotency key. Every adapter
    is external and honors the user's disabled types, muted chats and quiet
    hours, except in_app=True ones: the in-app realtime wakeup only points to
    the saved feed row. Adapters that must not run at all without consent
    register with cross_border=True; an adapter that sends a reduced,
    non-personal payload without consent (FCM) rechecks the live decision
    itself. External providers stay disabled until configured
    (#88 / Telegram are separate).
    """
    register = notification_consumers.register_handler(name)

    def decorator(adapter: ChannelAdapter) -> ChannelAdapter:
        async def deliver(session: AsyncSession, job: JobInfo) -> None:
            notification = await session.get(
                Notification, UUID(job.payload["notification_id"])
            )
            if notification is None:
                return
            if not in_app and not await external_delivery_allowed(
                session, notification
            ):
                return
            if cross_border:
                from campus.modules.identity import (  # noqa: PLC0415
                    cross_border_allowed,
                    lock_consent_state,
                )

                await lock_consent_state(session, notification.recipient_id)
                if not await cross_border_allowed(session, notification.recipient_id):
                    return
            await adapter(session, notification, job.id)

        register(deliver)
        return adapter

    return decorator


@register_channel("realtime", in_app=True)
async def publish_realtime(
    _session: AsyncSession, notification: Notification, delivery_id: UUID
) -> None:
    # Late import avoids cycles with modules that produce notifications.
    from campus.modules.realtime import publish_personal  # noqa: PLC0415

    await publish_personal(
        notification.recipient_id,
        {
            "notification_id": str(notification.id),
            "sequence": notification.sequence,
        },
        delivery_id,
    )


async def replay_notification_events(session: AsyncSession) -> int:
    """Replay retained events after registering all channel adapters."""
    return await source_consumers.replay(session) + await notification_consumers.replay(
        session
    )
