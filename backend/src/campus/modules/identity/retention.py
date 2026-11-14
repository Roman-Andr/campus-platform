"""Retention of sign-in codes, sessions and refresh tokens.

Run by the cleanup task (``CAMPUS_CLEANUP_CRON``):

- a sign-in code is deleted ``sign_in_code_retention`` after it expires;
  a deleted code reads as expired, so nothing changes for the client;
- a session is finished when it is revoked or its newest refresh token
  has expired (the chain cannot be continued). It is deleted with all its
  refresh tokens ``session_retention`` after that; an old token of a
  deleted session is rejected just as one of a revoked session;
- a used refresh token of a live session is kept until
  ``refresh_token_reuse_window`` after its own expiry: its reuse revokes
  the session (theft detection). Afterwards it is deleted, so a long-lived
  session does not keep every token it has ever rotated.

Every rule deletes by a cutoff in the past, so a repeated or concurrent
run deletes nothing more.
"""

from sqlalchemy import and_, delete, exists, or_, select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from campus.core import clock
from campus.core.config import Settings
from campus.core.tasks import register_cleanup
from campus.modules.identity.models import RefreshToken, Session, SignInCode


def _rowcount(result: object) -> int:
    return int(getattr(result, "rowcount", 0))


@register_cleanup("identity")
async def delete_expired_credentials(
    sessions: async_sessionmaker[AsyncSession], settings: Settings
) -> dict[str, int]:
    """Delete expired codes, finished sessions and stale used tokens."""
    now = clock.now()
    session_cutoff = now - settings.session_retention
    async with sessions() as db, db.begin():
        codes = await db.execute(
            delete(SignInCode).where(
                SignInCode.expires_at <= now - settings.sign_in_code_retention
            )
        )
        # Lock finished sessions: a concurrent refresh or sign-out holds
        # its session row, and its session is skipped until the next run.
        finished = (
            await db.scalars(
                select(Session.id)
                .where(
                    or_(
                        Session.revoked_at <= session_cutoff,
                        and_(
                            Session.created_at <= session_cutoff,
                            ~exists().where(
                                RefreshToken.session_id == Session.id,
                                RefreshToken.expires_at > session_cutoff,
                            ),
                        ),
                    )
                )
                .with_for_update(skip_locked=True)
            )
        ).all()
        session_tokens = await db.execute(
            delete(RefreshToken).where(RefreshToken.session_id.in_(finished))
        )
        devices = await db.execute(delete(Session).where(Session.id.in_(finished)))
        used_tokens = await db.execute(
            delete(RefreshToken).where(
                RefreshToken.used_at.is_not(None),
                RefreshToken.expires_at <= now - settings.refresh_token_reuse_window,
            )
        )
    return {
        "sign_in_codes": _rowcount(codes),
        "sessions": _rowcount(devices),
        "refresh_tokens": _rowcount(session_tokens) + _rowcount(used_tokens),
    }
