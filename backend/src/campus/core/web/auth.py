"""Access tokens, request principals and Redis-backed revocation/rate limits."""

import hashlib
import hmac
import math
from dataclasses import dataclass
from typing import Annotated
from uuid import UUID

import jwt
from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from limits import parse_many
from limits.aio.storage import RedisStorage
from limits.aio.strategies import FixedWindowRateLimiter
from redis.asyncio import Redis

from campus.core import clock
from campus.core.config import Settings
from campus.core.i18n import N_
from campus.core.web.problems import ProblemError, ProblemType

UNAUTHORIZED = ProblemType("unauthorized", 401, N_("Authentication required"))
RATE_LIMITED = ProblemType("rate_limited", 429, N_("Too many requests"))
bearer = HTTPBearer(auto_error=False)


@dataclass(frozen=True)
class Principal:
    """Verified identity and device session carried by an access token."""

    user_id: UUID
    session_id: UUID


def secret(settings: Settings) -> bytes:
    if settings.auth_secret_key is None:
        raise RuntimeError("CAMPUS_AUTH_SECRET_KEY is required")
    return settings.auth_secret_key.get_secret_value().encode()


def digest(settings: Settings, value: str) -> str:
    return hmac.new(secret(settings), value.encode(), hashlib.sha256).hexdigest()


def redis_client(request: Request) -> Redis:
    client: Redis | None = getattr(request.app.state, "auth_redis", None)
    if client is None:
        settings: Settings = request.app.state.settings
        if settings.redis_url is None:
            raise RuntimeError("CAMPUS_REDIS_URL is required")
        client = Redis.from_url(settings.redis_url.get_secret_value())
        request.app.state.auth_redis = client
    return client


async def authenticate(request: Request) -> Principal | None:
    authorization = request.headers.get("Authorization")
    if authorization is None:
        request.state.principal = None
        return None
    scheme, _, token = authorization.partition(" ")
    settings: Settings = request.app.state.settings
    try:
        if scheme.lower() != "bearer" or not token:
            raise ValueError
        payload = jwt.decode(
            token,
            secret(settings),
            algorithms=["HS256"],
            options={"require": ["sub", "sid", "exp"], "verify_exp": False},
        )
        if float(payload["exp"]) <= clock.now().timestamp():
            raise ValueError
        principal = Principal(UUID(payload["sub"]), UUID(payload["sid"]))
        if await redis_client(request).exists(f"auth:revoked:{principal.session_id}"):
            raise ValueError
    except jwt.InvalidTokenError, ValueError, TypeError, KeyError:
        raise ProblemError(
            UNAUTHORIZED, headers={"WWW-Authenticate": "Bearer"}
        ) from None
    request.state.principal = principal
    return principal


async def current_user(
    request: Request,
    _credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
) -> Principal:
    principal: Principal | None = getattr(request.state, "principal", None)
    if principal is None:
        raise ProblemError(UNAUTHORIZED, headers={"WWW-Authenticate": "Bearer"})
    return principal


CurrentUser = Annotated[Principal, Depends(current_user)]

# The Redis client of the request, shared with revocation and rate limits.
RedisClient = Annotated[Redis, Depends(redis_client)]


async def revoke_access(request: Request, session_id: UUID) -> None:
    settings: Settings = request.app.state.settings
    await redis_client(request).set(
        f"auth:revoked:{session_id}",
        "1",
        ex=math.ceil(settings.access_token_ttl.total_seconds()),
    )


async def rate_limit(request: Request, email: str | None = None) -> None:
    settings: Settings = request.app.state.settings
    limiter: FixedWindowRateLimiter | None = getattr(
        request.app.state, "auth_limiter", None
    )
    if limiter is None:
        if settings.redis_url is None:
            raise RuntimeError("CAMPUS_REDIS_URL is required")
        storage = RedisStorage("async+" + settings.redis_url.get_secret_value())
        request.app.state.auth_limit_storage = storage
        limiter = FixedWindowRateLimiter(storage)
        request.app.state.auth_limiter = limiter
    ip = request.client.host if request.client else "unknown"
    rules = [("ip", ip, settings.sign_in_ip_limits)]
    if email is not None:
        rules.append(("email", email, settings.sign_in_email_limits))
    for namespace, value, limits in rules:
        for limit in parse_many(limits):
            key = digest(settings, namespace + ":" + value)
            if not await limiter.hit(limit, "auth", namespace, key):
                window = await limiter.get_window_stats(limit, "auth", namespace, key)
                retry = max(1, math.ceil(window.reset_time - clock.now().timestamp()))
                raise ProblemError(RATE_LIMITED, headers={"Retry-After": str(retry)})
