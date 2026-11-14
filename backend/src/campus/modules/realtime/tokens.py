"""Centrifugo connection and subscription JWT tokens.

Both tokens are HMAC-signed with the secret shared with Centrifugo. The
connection token identifies the user and the device session; the
subscription token additionally binds the token to one channel, so a token
for one channel cannot be used on another. Short lifetimes (configuration)
bound how long a forced unsubscribe or disconnect can be bypassed by an
already issued token; clients refresh their tokens through the API, where the
current session and membership are checked again.
"""

from datetime import datetime
from uuid import UUID, uuid4

import jwt

from campus.core import clock
from campus.core.config import Settings
from campus.modules.realtime.channels import Channel


class RealtimeSecretMissingError(RuntimeError):
    """CAMPUS_CENTRIFUGO_TOKEN_HMAC_SECRET is required to issue tokens."""

    def __init__(self) -> None:
        super().__init__("CAMPUS_CENTRIFUGO_TOKEN_HMAC_SECRET is required")


def _secret(settings: Settings) -> str:
    if settings.centrifugo_token_hmac_secret is None:
        raise RealtimeSecretMissingError
    return settings.centrifugo_token_hmac_secret.get_secret_value()


def _encode(settings: Settings, claims: dict[str, object]) -> str:
    return jwt.encode(claims, _secret(settings), algorithm="HS256")


def connection_token(
    settings: Settings, user_id: UUID, session_id: UUID
) -> tuple[str, datetime]:
    """A connection token of the user's device session and its expiry."""
    issued_at = clock.now()
    expires_at = issued_at + settings.centrifugo_connection_token_ttl
    token = _encode(
        settings,
        {
            "sub": str(user_id),
            "sid": str(session_id),
            "iat": int(issued_at.timestamp()),
            "exp": int(expires_at.timestamp()),
            "jti": str(uuid4()),
        },
    )
    return token, expires_at


def subscription_token(
    settings: Settings, user_id: UUID, session_id: UUID, channel: Channel
) -> tuple[str, datetime]:
    """A token to subscribe to exactly ``channel`` and its expiry."""
    issued_at = clock.now()
    expires_at = issued_at + settings.centrifugo_subscription_token_ttl
    token = _encode(
        settings,
        {
            "sub": str(user_id),
            "sid": str(session_id),
            "channel": channel.name,
            "iat": int(issued_at.timestamp()),
            "exp": int(expires_at.timestamp()),
            "jti": str(uuid4()),
        },
    )
    return token, expires_at
