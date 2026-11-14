"""Identity tables: one-time challenges and rotating device credentials."""

from datetime import datetime
from uuid import UUID

from sqlalchemy import CheckConstraint, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column

from campus.core.db import Entity


class User(Entity):
    __tablename__ = "identity_user"
    __table_args__ = (CheckConstraint("email = lower(email)", name="email_lowercase"),)

    email: Mapped[str] = mapped_column(String(320), unique=True)
    first_name: Mapped[str] = mapped_column(String(100))
    last_name: Mapped[str] = mapped_column(String(100))
    account_type: Mapped[str] = mapped_column(String(16))


class SignInCode(Entity):
    __tablename__ = "identity_sign_in_code"

    email: Mapped[str] = mapped_column(String(320), unique=True)
    code_hash: Mapped[str] = mapped_column(String(64))
    expires_at: Mapped[datetime]
    attempts: Mapped[int] = mapped_column(default=0)
    consumed_at: Mapped[datetime | None]


class Session(Entity):
    __tablename__ = "identity_session"

    user_id: Mapped[UUID] = mapped_column(ForeignKey("identity_user.id"), index=True)
    device_id: Mapped[UUID]
    device_name: Mapped[str | None] = mapped_column(String(100))
    platform: Mapped[str] = mapped_column(String(16))
    revoked_at: Mapped[datetime | None]


class RefreshToken(Entity):
    __tablename__ = "identity_refresh_token"

    session_id: Mapped[UUID] = mapped_column(
        ForeignKey("identity_session.id"), index=True
    )
    token_hash: Mapped[str] = mapped_column(String(64), unique=True)
    expires_at: Mapped[datetime]
    used_at: Mapped[datetime | None]
