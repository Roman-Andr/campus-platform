"""API of Centrifugo tokens and stream recovery."""

from dataclasses import dataclass
from typing import Annotated, Any
from uuid import UUID

from cent import ApiError, CentError, StreamPosition, UnrecoverablePositionError
from fastapi import Depends, Request
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy.ext.asyncio import AsyncSession

from campus.core.config import Settings
from campus.core.i18n import N_
from campus.core.web import (
    CurrentUser,
    DbSession,
    Instant,
    Problem,
    ProblemError,
    ProblemType,
    api_router,
)
from campus.core.web.auth import UNAUTHORIZED, Principal
from campus.modules.identity import Session
from campus.modules.realtime.centrifugo import (
    CentrifugoNotConfiguredError,
    centrifugo_client,
)
from campus.modules.realtime.channels import Channel, can_access, parse_channel
from campus.modules.realtime.tokens import (
    RealtimeSecretMissingError,
    connection_token,
    subscription_token,
)

CHANNEL_INVALID = ProblemType(
    "realtime_channel_invalid",
    422,
    N_("Invalid realtime channel"),
    N_("The channel name is not a Campus realtime channel."),
)
CHANNEL_FORBIDDEN = ProblemType(
    "realtime_channel_forbidden",
    403,
    N_("Channel is not available"),
    N_("You are not a member of this channel."),
)
HISTORY_LOST = ProblemType(
    "realtime_history_lost",
    409,
    N_("Realtime history expired"),
    N_(
        "The requested position is no longer in realtime history."
        " Reload the channel state through the API."
    ),
)
REALTIME_UNAVAILABLE = ProblemType(
    "realtime_unavailable",
    503,
    N_("Realtime is unavailable"),
    N_("The realtime server is temporarily unavailable. Try again later."),
)
router = api_router(
    prefix="/realtime",
    tags=["Realtime"],
    responses={
        401: {"model": Problem},
        403: {"model": Problem},
        409: {"model": Problem},
        422: {"model": Problem},
        503: {"model": Problem},
    },
)


async def active_session(session: DbSession, principal: CurrentUser) -> Principal:
    """Reject a device session revoked in the database, not only in Redis.

    Dependencies run on idempotent replays too, so a stored token response is
    never returned to a revoked session even if Redis lost the revocation key.
    Blocking an account revokes its sessions (#93), so the same check closes
    realtime access for a blocked user.
    """
    device = await session.get(Session, principal.session_id)
    if device is None or device.revoked_at is not None:
        raise ProblemError(UNAUTHORIZED, headers={"WWW-Authenticate": "Bearer"})
    return principal


ActiveSession = Annotated[Principal, Depends(active_session)]


class TokenOutput(BaseModel):
    token: str = Field(description="JWT for the Centrifugo client.")
    expires_at: Instant


class SubscriptionTokenInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    channel: str = Field(min_length=1, max_length=255)


class SubscriptionTokenOutput(TokenOutput):
    channel: str


class Position(BaseModel):
    epoch: str = Field(min_length=1)
    offset: int = Field(ge=0)


class RecoverInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    channel: str = Field(min_length=1, max_length=255)
    since: Position | None = Field(
        default=None,
        description=(
            "Last seen stream position. Omit it to ask only for the current"
            " position without publications."
        ),
    )


class PublicationOutput(BaseModel):
    offset: int = Field(ge=0)
    data: Any = None


class RecoverOutput(BaseModel):
    channel: str
    epoch: str
    offset: int = Field(ge=0)
    publications: list[PublicationOutput] = Field(default_factory=list)


def channel_or_problem(name: str) -> Channel:
    try:
        return parse_channel(name)
    except ValueError:
        raise ProblemError(CHANNEL_INVALID) from None


async def require_access(
    session: AsyncSession, channel: Channel, user_id: UUID
) -> None:
    if not await can_access(session, channel.name, user_id):
        raise ProblemError(CHANNEL_FORBIDDEN)


async def subscription_channel(
    data: SubscriptionTokenInput,
    session: DbSession,
    principal: ActiveSession,
) -> Channel:
    """The channel of the request, if the user may subscribe to it now.

    A dependency, not a call inside the endpoint: FastAPI resolves it on an
    idempotent replay too, so a stored token is never returned after the
    membership was revoked.
    """
    channel = channel_or_problem(data.channel)
    await require_access(session, channel, principal.user_id)
    return channel


@dataclass(frozen=True, slots=True)
class Recovery:
    """A checked recovery request: the channel and the requested position."""

    channel: Channel
    since: StreamPosition | None


async def recovery_request(
    data: RecoverInput,
    session: DbSession,
    principal: ActiveSession,
) -> Recovery:
    """Check access before reading history, including on an idempotent replay."""
    channel = channel_or_problem(data.channel)
    await require_access(session, channel, principal.user_id)
    since = (
        StreamPosition(offset=data.since.offset, epoch=data.since.epoch)
        if data.since is not None
        else None
    )
    return Recovery(channel, since)


SubscriptionChannel = Annotated[Channel, Depends(subscription_channel)]
RecoveryRequest = Annotated[Recovery, Depends(recovery_request)]


@router.post("/connection-token")
async def issue_connection_token(
    request: Request, principal: ActiveSession
) -> TokenOutput:
    """Issue a connection token for the current device session.

    A retry with the same ``Idempotency-Key`` returns the stored token; the
    session check still runs first, so a revoked session never receives it.
    """
    settings: Settings = request.app.state.settings
    try:
        token, expires_at = connection_token(
            settings, principal.user_id, principal.session_id
        )
    except RealtimeSecretMissingError as error:
        raise ProblemError(REALTIME_UNAVAILABLE) from error
    return TokenOutput(token=token, expires_at=expires_at)


@router.post("/subscription-token")
async def issue_subscription_token(
    request: Request,
    channel: SubscriptionChannel,
    principal: ActiveSession,
) -> SubscriptionTokenOutput:
    """Issue a token bound to one channel, if the user may subscribe now."""
    settings: Settings = request.app.state.settings
    try:
        token, expires_at = subscription_token(
            settings, principal.user_id, principal.session_id, channel
        )
    except RealtimeSecretMissingError as error:
        raise ProblemError(REALTIME_UNAVAILABLE) from error
    return SubscriptionTokenOutput(
        token=token, expires_at=expires_at, channel=channel.name
    )


@router.post("/recover")
async def recover(request: Request, recovery: RecoveryRequest) -> RecoverOutput:
    """Return publications missing after ``since`` and the current position.

    Realtime history is ephemeral. When Centrifugo no longer has the stream
    position, the explicit ``realtime_history_lost`` problem tells the client
    to reload the channel state through the API; the answer never promises
    that the whole history is retained.
    """
    settings: Settings = request.app.state.settings
    try:
        async with centrifugo_client(settings) as client:
            result = await client.history(
                channel=recovery.channel.name,
                limit=(
                    settings.centrifugo_history_limit
                    if recovery.since is not None
                    else 0
                ),
                since=recovery.since,
            )
    except UnrecoverablePositionError:
        raise ProblemError(HISTORY_LOST) from None
    except (ApiError, CentError, CentrifugoNotConfiguredError) as error:
        raise ProblemError(REALTIME_UNAVAILABLE) from error
    return RecoverOutput(
        channel=recovery.channel.name,
        epoch=result.epoch,
        offset=result.offset,
        publications=[
            PublicationOutput(offset=publication.offset, data=publication.data)
            for publication in result.publications
        ],
    )
