"""Android push through FCM HTTP v1 with live consent and token hygiene.

The payload depends on the current cross-border consent: the full
notification text is sent only while the current document version is
accepted. Without consent the message carries opaque identifiers and a
generic body only. The adapter rechecks the decision right before every
transfer and never caches a grant, so a late replayed "allowed" event
cannot restore text after a revocation.

The worker retries temporary FCM failures and forgets tokens the provider
reports as invalid. A permanent provider or configuration error is logged
and the channel job succeeds: the stored notification remains in the feed
and a bad payload is not retried forever.
"""

from datetime import timedelta
from http import HTTPStatus
from typing import Any
from uuid import UUID

import httpx2
import jwt
import structlog
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from campus.core import clock
from campus.core.config import Settings, get_settings
from campus.core.i18n import N_, translate
from campus.modules.identity import (
    ConsentChange,
    Session,
    SessionsRevoked,
    consent_consumers,
    cross_border_allowed,
    lock_consent_state,
    session_consumers,
)
from campus.modules.notifications.delivery import register_channel
from campus.modules.notifications.models import Notification, PushToken

logger = structlog.get_logger(__name__)

FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
OAUTH_ENDPOINT = "https://oauth2.googleapis.com/token"
PUSH_TITLE = "Campus"
GENERIC_BODY = N_("You have a new notification.")
ASSERTION_TTL = timedelta(minutes=5)


class FcmError(Exception):
    """Base of FCM delivery errors."""


class FcmTemporaryError(FcmError):
    """The provider may accept the same message on a later attempt."""


class FcmPermanentError(FcmError):
    """The provider rejected the message for a non-token reason."""


class FcmTokenInvalidError(FcmError):
    """The registration token is unknown or no longer valid."""


class FcmNotConfiguredError(FcmPermanentError):
    """The service account credentials are not configured."""


def _credentials(settings: Settings) -> tuple[str, str, str]:
    if (
        not settings.fcm_project_id
        or not settings.fcm_client_email
        or settings.fcm_private_key is None
        or not settings.fcm_private_key.get_secret_value()
    ):
        raise FcmNotConfiguredError
    private_key = settings.fcm_private_key.get_secret_value().replace("\\n", "\n")
    return settings.fcm_project_id, settings.fcm_client_email, private_key


async def _access_token(settings: Settings, client_email: str, private_key: str) -> str:
    issued_at = clock.now()
    try:
        assertion = jwt.encode(
            {
                "iss": client_email,
                "scope": FCM_SCOPE,
                "aud": OAUTH_ENDPOINT,
                "iat": int(issued_at.timestamp()),
                "exp": int((issued_at + ASSERTION_TTL).timestamp()),
            },
            private_key,
            algorithm="RS256",
        )
    except (ValueError, TypeError, jwt.PyJWTError) as error:
        raise FcmPermanentError from error
    try:
        async with httpx2.AsyncClient(timeout=settings.fcm_timeout) as client:
            response = await client.post(
                OAUTH_ENDPOINT,
                data={
                    "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
                    "assertion": assertion,
                },
            )
    except httpx2.HTTPError as error:
        raise FcmTemporaryError from error
    if response.status_code == HTTPStatus.OK:
        try:
            access_token = response.json().get("access_token")
        except ValueError:
            raise FcmPermanentError from None
        if not isinstance(access_token, str) or not access_token:
            raise FcmPermanentError
        return access_token
    if (
        response.status_code == HTTPStatus.TOO_MANY_REQUESTS
        or response.status_code >= HTTPStatus.INTERNAL_SERVER_ERROR
    ):
        raise FcmTemporaryError
    raise FcmPermanentError


def _error(response: httpx2.Response) -> dict[str, Any]:
    try:
        body = response.json()
    except ValueError:
        return {}
    error = body.get("error") if isinstance(body, dict) else None
    return error if isinstance(error, dict) else {}


def _error_codes(error: dict[str, Any]) -> set[str]:
    details = error.get("details")
    if not isinstance(details, list):
        return set()
    return {
        str(detail.get("errorCode"))
        for detail in details
        if isinstance(detail, dict) and detail.get("errorCode")
    }


def _mentions_token(error: dict[str, Any]) -> bool:
    message = error.get("message")
    return isinstance(message, str) and "token" in message.lower()


async def send_message(settings: Settings, token: str, message: dict[str, Any]) -> None:
    """Send one FCM message or raise a classified delivery error."""
    project_id, client_email, private_key = _credentials(settings)
    access_token = await _access_token(settings, client_email, private_key)
    url = f"{settings.fcm_api_url.rstrip('/')}/v1/projects/{project_id}/messages:send"
    body = {"message": {**message, "token": token}}
    try:
        async with httpx2.AsyncClient(timeout=settings.fcm_timeout) as client:
            response = await client.post(
                url,
                json=body,
                headers={"Authorization": f"Bearer {access_token}"},
            )
    except httpx2.HTTPError as error:
        raise FcmTemporaryError from error
    if response.status_code == HTTPStatus.OK:
        return
    problem = _error(response)
    if response.status_code == HTTPStatus.NOT_FOUND or "UNREGISTERED" in (
        _error_codes(problem)
    ):
        raise FcmTokenInvalidError
    if response.status_code == HTTPStatus.BAD_REQUEST and _mentions_token(problem):
        raise FcmTokenInvalidError
    if (
        response.status_code
        in {
            HTTPStatus.REQUEST_TIMEOUT,
            HTTPStatus.TOO_MANY_REQUESTS,
        }
        or response.status_code >= HTTPStatus.INTERNAL_SERVER_ERROR
    ):
        raise FcmTemporaryError
    raise FcmPermanentError


def push_payload(
    settings: Settings,
    notification: Notification,
    delivery_id: UUID,
    *,
    allowed: bool,
) -> dict[str, Any]:
    """The FCM message of one notification, with or without personal text."""
    notification_id = str(notification.id)
    data = {
        "notification_id": notification_id,
        "sequence": str(notification.sequence),
        "delivery_id": str(delivery_id),
    }
    if allowed:
        body = (
            notification.text.get(settings.default_locale)
            or notification.text.get("en")
            or notification.text.get("ru")
            or ""
        )
        data["type"] = notification.type
        if notification.object_id is not None:
            data["object_id"] = str(notification.object_id)
    else:
        body = translate(GENERIC_BODY, settings.default_locale)
    return {
        "notification": {"title": PUSH_TITLE, "body": body},
        "data": data,
        "android": {
            "priority": "high",
            "collapse_key": notification_id,
            "notification": {
                "tag": notification_id,
                "channel_id": "campus_notifications",
            },
        },
    }


@register_channel("fcm")
async def deliver_push(
    session: AsyncSession, notification: Notification, delivery_id: UUID
) -> None:
    """Send the notification to every active device of its recipient."""
    tokens = list(
        await session.scalars(
            select(PushToken)
            .join(Session, Session.id == PushToken.session_id)
            .where(
                PushToken.user_id == notification.recipient_id,
                Session.user_id == notification.recipient_id,
                Session.revoked_at.is_(None),
            )
            .order_by(PushToken.id)
            # Serialize with revocation: a session revoked while this job runs
            # is either seen here or waits until the send finishes.
            .with_for_update(of=Session)
        )
    )
    if not tokens:
        return
    await lock_consent_state(session, notification.recipient_id)
    allowed = await cross_border_allowed(session, notification.recipient_id)
    settings = get_settings()
    payload = push_payload(settings, notification, delivery_id, allowed=allowed)
    temporary: FcmTemporaryError | None = None
    for token in tokens:
        try:
            await send_message(settings, token.token, payload)
        except FcmTokenInvalidError:
            await session.delete(token)
            logger.info("fcm_token_forgotten", notification_id=str(notification.id))
        except FcmTemporaryError as error:
            temporary = temporary or error
            logger.warning(
                "fcm_temporary_error",
                notification_id=str(notification.id),
                delivery_id=str(delivery_id),
            )
        except FcmPermanentError as error:
            logger.error(
                "fcm_permanent_error",
                notification_id=str(notification.id),
                delivery_id=str(delivery_id),
                error=type(error).__name__,
            )
        else:
            logger.info(
                "fcm_push_sent",
                notification_id=str(notification.id),
                delivery_id=str(delivery_id),
            )
    if temporary is not None:
        raise temporary


@consent_consumers.register("fcm")
async def _consent_changed(_session: AsyncSession, change: ConsentChange) -> None:
    """Acknowledge consent events; delivery rechecks the live decision.

    Nothing irreversible happens on a consent change: the next push builds
    its payload from the current decision, and a stale event that arrives
    after a revocation cannot restore full text.
    """
    logger.info(
        "fcm_consent_changed",
        user_id=str(change.user_id),
        allowed=change.allowed,
    )


@session_consumers.register("push_tokens")
async def _forget_revoked_tokens(
    session: AsyncSession, change: SessionsRevoked
) -> None:
    """Delete tokens of revoked devices; a reassigned token is untouched."""
    if not change.session_ids:
        return
    await session.execute(
        delete(PushToken).where(
            PushToken.session_id.in_(change.session_ids),
            PushToken.user_id == change.user_id,
        )
    )
    logger.info(
        "fcm_tokens_forgotten",
        user_id=str(change.user_id),
        sessions=len(change.session_ids),
    )
