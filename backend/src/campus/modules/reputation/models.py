"""Persistent state of QR confirmation and device signing keys."""

from datetime import datetime
from uuid import UUID

from sqlalchemy import (
    CheckConstraint,
    ForeignKey,
    Index,
    LargeBinary,
    String,
    UniqueConstraint,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column

from campus.core.db import Entity


class DeviceKey(Entity):
    """An Ed25519 public key registered by one device session.

    The private key never leaves the device. A replacement registration
    revokes the previous key, and a partial unique index keeps at most one
    active key per session. Revoked rows stay for the audit trail and for
    offline codes issued before revocation.
    """

    __tablename__ = "reputation_device_key"
    __table_args__ = (
        CheckConstraint("octet_length(public_key) = 32", name="public_key_length"),
        UniqueConstraint("public_key"),
        Index(
            "uq_reputation_device_key_session_active",
            "session_id",
            unique=True,
            postgresql_where=text("revoked_at IS NULL"),
        ),
        Index("ix_reputation_device_key_user", "user_id", "created_at"),
    )

    user_id: Mapped[UUID] = mapped_column(
        ForeignKey("identity_user.id", ondelete="CASCADE")
    )
    session_id: Mapped[UUID] = mapped_column(
        ForeignKey("identity_session.id", ondelete="CASCADE")
    )
    public_key: Mapped[bytes] = mapped_column(LargeBinary(32))
    revoked_at: Mapped[datetime | None]


class QrScan(Entity):
    """A successfully used online QR code.

    The row is inserted in the same transaction as the completion. Its
    unique nonce makes a code single-use; the signature and the participant
    checks are performed before the row is written. Only successful scans
    are stored, so a rejected request leaves no journal entry either.
    """

    __tablename__ = "reputation_qr_scan"
    __table_args__ = (
        CheckConstraint("presenter_id <> scanner_id", name="distinct_participants"),
        CheckConstraint("result = 'completed'", name="result"),
        UniqueConstraint("nonce"),
        Index("ix_reputation_qr_scan_interaction", "interaction_id", "created_at"),
    )

    listing_id: Mapped[UUID] = mapped_column(
        ForeignKey("listing.id", ondelete="CASCADE")
    )
    interaction_id: Mapped[UUID] = mapped_column(
        ForeignKey("listing_interaction.id", ondelete="CASCADE")
    )
    device_key_id: Mapped[UUID] = mapped_column(
        ForeignKey("reputation_device_key.id", ondelete="RESTRICT")
    )
    presenter_id: Mapped[UUID] = mapped_column(ForeignKey("identity_user.id"))
    scanner_id: Mapped[UUID] = mapped_column(ForeignKey("identity_user.id"))
    nonce: Mapped[UUID]
    issued_at: Mapped[datetime]
    result: Mapped[str] = mapped_column(String(16), default="completed")


class ConfirmationCode(Entity):
    """The server-issued six-digit code of one interaction.

    A single row per interaction keeps the lifetime and the cumulative
    counter of incorrect attempts across reissues. Only a keyed hash of the
    code is stored; the plaintext exists in the issuing response only.
    """

    __tablename__ = "reputation_confirmation_code"
    __table_args__ = (
        CheckConstraint("attempts >= 0", name="attempts"),
        CheckConstraint("char_length(code_hash) = 64", name="code_hash"),
        CheckConstraint("expires_at > issued_at", name="validity"),
        UniqueConstraint("interaction_id"),
    )

    listing_id: Mapped[UUID] = mapped_column(
        ForeignKey("listing.id", ondelete="CASCADE")
    )
    interaction_id: Mapped[UUID] = mapped_column(
        ForeignKey("listing_interaction.id", ondelete="CASCADE")
    )
    presenter_id: Mapped[UUID] = mapped_column(ForeignKey("identity_user.id"))
    code_hash: Mapped[str] = mapped_column(String(64))
    issued_at: Mapped[datetime]
    expires_at: Mapped[datetime]
    attempts: Mapped[int] = mapped_column(default=0)
    consumed_at: Mapped[datetime | None]
