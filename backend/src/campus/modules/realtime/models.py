"""Persistence of realtime channel access granted by domain modules."""

from datetime import datetime
from uuid import UUID

from sqlalchemy import ForeignKey, Index, String
from sqlalchemy.orm import Mapped, mapped_column

from campus.core import clock
from campus.core.db import Base


class ChannelGrant(Base):
    """A user's subscription grant for one chat channel.

    Chat modules own their membership and call the public interface of this
    module to project it here, in the same transaction. The grant is the
    authoritative realtime ACL: subscription tokens are issued only while it
    is active, and revoking it queues a forced unsubscribe. A revoked row is
    kept so that a re-grant has a lock to serialize with.
    """

    __tablename__ = "realtime_channel_grant"
    __table_args__ = (Index("ix_realtime_channel_grant_user_id", "user_id"),)

    channel: Mapped[str] = mapped_column(String(255), primary_key=True)
    user_id: Mapped[UUID] = mapped_column(
        ForeignKey("identity_user.id", ondelete="CASCADE"), primary_key=True
    )
    created_at: Mapped[datetime] = mapped_column(default=clock.now)
    revoked_at: Mapped[datetime | None]
