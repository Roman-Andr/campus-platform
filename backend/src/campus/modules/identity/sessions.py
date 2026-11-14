"""Device session inventory and transactional revocation events."""

from collections.abc import Sequence
from uuid import UUID

from fastapi import Request, Response
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from campus.core import clock
from campus.core.i18n import N_
from campus.core.outbox import add_message
from campus.core.web import (
    DbSession,
    Instant,
    Problem,
    ProblemError,
    ProblemType,
    api_router,
)
from campus.core.web.auth import CurrentUser, revoke_access
from campus.modules.identity.models import RefreshToken, Session, User

SESSION_NOT_FOUND = ProblemType("session_not_found", 404, N_("Session not found"))
router = api_router(prefix="/me/sessions", tags=["Sessions"])


class SessionOutput(BaseModel):
    id: UUID
    device_name: str | None
    platform: str
    signed_in_at: Instant
    last_active_at: Instant
    current: bool


async def revoke_sessions(
    request: Request, session: AsyncSession, devices: Sequence[Session]
) -> None:
    """Call with session row locks held, including for refresh reuse."""
    active = [device for device in devices if device.revoked_at is None]
    if not active:
        return
    for device in active:
        device.revoked_at = clock.now()
        await revoke_access(request, device.id)
    add_message(
        session,
        "identity.sessions_revoked",
        {
            "user_id": str(active[0].user_id),
            "session_ids": [str(device.id) for device in active],
        },
    )


@router.get("")
async def list_sessions(
    session: DbSession, principal: CurrentUser
) -> list[SessionOutput]:
    devices = await session.scalars(
        select(Session)
        .where(
            Session.user_id == principal.user_id,
            Session.revoked_at.is_(None),
            select(RefreshToken.id)
            .where(
                RefreshToken.session_id == Session.id,
                RefreshToken.used_at.is_(None),
                RefreshToken.expires_at > clock.now(),
            )
            .exists(),
        )
        .order_by(Session.created_at.desc(), Session.id)
    )
    return [
        SessionOutput(
            id=device.id,
            device_name=device.device_name,
            platform=device.platform,
            signed_in_at=device.created_at,
            last_active_at=device.updated_at,
            current=device.id == principal.session_id,
        )
        for device in devices
    ]


@router.delete("/{session_id}", status_code=204, responses={404: {"model": Problem}})
async def revoke_session(
    session_id: UUID, request: Request, session: DbSession, principal: CurrentUser
) -> Response:
    device = await session.scalar(
        select(Session)
        .where(Session.id == session_id, Session.user_id == principal.user_id)
        .with_for_update()
    )
    if device is None:
        raise ProblemError(SESSION_NOT_FOUND)
    await revoke_sessions(request, session, [device])
    return Response(status_code=204)


@router.delete("", status_code=204)
async def revoke_all_sessions(
    request: Request, session: DbSession, principal: CurrentUser
) -> Response:
    # Serialize with sign-in so the inventory cannot gain a session halfway
    # through revocation. Session locks also serialize with refresh rotation.
    await session.scalar(
        select(User).where(User.id == principal.user_id).with_for_update()
    )
    devices = (
        await session.scalars(
            select(Session)
            .where(Session.user_id == principal.user_id, Session.revoked_at.is_(None))
            .order_by(Session.id)
            .with_for_update()
        )
    ).all()
    await revoke_sessions(request, session, devices)
    return Response(status_code=204)
