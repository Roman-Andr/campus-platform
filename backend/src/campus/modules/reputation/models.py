"""Persistent state of QR confirmation and device signing keys."""

from datetime import datetime
from enum import StrEnum
from uuid import UUID

from sqlalchemy import (
    CheckConstraint,
    ForeignKey,
    Index,
    LargeBinary,
    String,
    Text,
    UniqueConstraint,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from campus.core import clock
from campus.core.db import Entity
from campus.modules.identity import User


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


class QrMode(StrEnum):
    """How a confirmation code reached the server."""

    ONLINE = "online"
    OFFLINE = "offline"


class QrScan(Entity):
    """A successfully used online or offline QR code.

    The row is inserted in the same transaction as the completion. Its
    unique nonce makes a code single-use; the signature and the participant
    checks are performed before the row is written. Only successful scans
    are stored, so a rejected request leaves no journal entry either.

    An offline code also carries a device-generated ``confirmation_id``.
    It is unique, so a retry after the idempotency key expired returns the
    stored result instead of completing the interaction twice, and an
    altered payload reusing the id is rejected. ``payload_hash`` makes that
    comparison exact.
    """

    __tablename__ = "reputation_qr_scan"
    __table_args__ = (
        CheckConstraint("presenter_id <> scanner_id", name="distinct_participants"),
        CheckConstraint("result = 'completed'", name="result"),
        CheckConstraint("mode IN ('online','offline')", name="mode"),
        CheckConstraint(
            "(mode = 'offline') = (confirmation_id IS NOT NULL)"
            " AND (mode = 'offline') = (payload_hash IS NOT NULL)",
            name="offline_fields",
        ),
        UniqueConstraint("nonce"),
        UniqueConstraint("confirmation_id"),
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
    received_at: Mapped[datetime] = mapped_column(default=clock.now)
    mode: Mapped[str] = mapped_column(String(8), default=QrMode.ONLINE.value)
    confirmation_id: Mapped[UUID | None]
    payload_hash: Mapped[str | None] = mapped_column(String(64))
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


class NoShowKind(StrEnum):
    """Where a no-show of one participant comes from.

    ``PERSONAL`` is an allegation of one participant against the other about
    an agreed meeting; ``EVENT_AUTO`` is the automatic penalty of a
    registered participant the organiser did not mark; ``EVENT_VOTE`` is the
    penalty of an event organiser after at least a third of the registered
    participants said the event did not take place.
    """

    PERSONAL = "personal"
    EVENT_AUTO = "event_auto"
    EVENT_VOTE = "event_vote"


class NoShowStatus(StrEnum):
    """Whether a no-show counts, is suspended by a dispute or was removed."""

    COUNTED = "counted"
    DISPUTED = "disputed"
    REMOVED = "removed"


class NoShowMark(Entity):
    """One no-show charged to one participant.

    A personal mark names the reporting participant and its reason; an
    automatic or vote-based mark has no reporter and no free text. Mutual
    personal marks are suspended together (``disputed``) and are counted
    again only by the moderator decision in #94. A valid late QR or a later
    "the event did not take place" vote removes a mark instead of deleting
    it, so the chronology and the audit trail stay complete.
    """

    __tablename__ = "reputation_no_show"
    __table_args__ = (
        CheckConstraint("kind IN ('personal','event_auto','event_vote')", name="kind"),
        CheckConstraint("status IN ('counted','disputed','removed')", name="status"),
        CheckConstraint(
            "(kind = 'personal') = (reason IS NOT NULL)", name="reason_presence"
        ),
        CheckConstraint(
            "reason IS NULL OR char_length(reason) > 0", name="reason_not_empty"
        ),
        CheckConstraint(
            "reporter_id IS NULL OR reporter_id <> subject_id", name="distinct_people"
        ),
        CheckConstraint(
            "(interaction_id IS NULL) = (kind = 'event_vote')", name="mark_scope"
        ),
        CheckConstraint(
            "(status = 'disputed') = (disputed_at IS NOT NULL)",
            name="dispute_time",
        ),
        CheckConstraint(
            "(status = 'removed') = (removed_at IS NOT NULL)", name="removal_time"
        ),
        Index(
            "uq_reputation_no_show_interaction_subject",
            "interaction_id",
            "subject_id",
            unique=True,
            postgresql_where=text("interaction_id IS NOT NULL"),
        ),
        Index(
            "uq_reputation_no_show_event_subject",
            "listing_id",
            "subject_id",
            unique=True,
            postgresql_where=text("interaction_id IS NULL"),
        ),
        Index("ix_reputation_no_show_subject", "subject_id", "status", "created_at"),
        Index("ix_reputation_no_show_listing", "listing_id", "created_at"),
    )

    listing_id: Mapped[UUID] = mapped_column(
        ForeignKey("listing.id", ondelete="CASCADE")
    )
    # The signup of the charged participant; NULL for a vote against the
    # organiser of an event, who has no signup.
    interaction_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("listing_interaction.id", ondelete="CASCADE")
    )
    # The participant who marked the other one; NULL for automatic rules.
    reporter_id: Mapped[UUID | None] = mapped_column(ForeignKey("identity_user.id"))
    # The participant the no-show is charged to.
    subject_id: Mapped[UUID] = mapped_column(ForeignKey("identity_user.id"))
    kind: Mapped[str] = mapped_column(String(16), default=NoShowKind.PERSONAL)
    status: Mapped[str] = mapped_column(String(16), default=NoShowStatus.COUNTED)
    reason: Mapped[str | None] = mapped_column(Text)
    disputed_at: Mapped[datetime | None]
    removed_at: Mapped[datetime | None]
    removed_by_id: Mapped[UUID | None] = mapped_column(ForeignKey("identity_user.id"))


class EventNoShowVote(Entity):
    """One registered participant's vote that an event did not take place.

    The unique (listing, voter) key makes a repeated vote a no-op: only the
    number of distinct voters matters for the third-of-registrations
    threshold.
    """

    __tablename__ = "reputation_event_no_show_vote"
    __table_args__ = (
        UniqueConstraint("listing_id", "voter_id"),
        Index("ix_reputation_event_no_show_vote_listing", "listing_id", "created_at"),
    )

    listing_id: Mapped[UUID] = mapped_column(
        ForeignKey("listing.id", ondelete="CASCADE")
    )
    interaction_id: Mapped[UUID] = mapped_column(
        ForeignKey("listing_interaction.id", ondelete="CASCADE")
    )
    voter_id: Mapped[UUID] = mapped_column(ForeignKey("identity_user.id"))


class AttendanceRecord(Entity):
    """A participant marked present at an event by one of the two modes.

    One row per (event, participant): marking again updates the row instead
    of adding a duplicate, and removing a mark is soft, so the organiser's
    list and the future no-show logic still see the latest state. The
    ``interaction_id`` names the signup that was active when the mark was
    taken; a cancelled signup is not a registration any more.
    """

    __tablename__ = "reputation_attendance"
    __table_args__ = (
        CheckConstraint("method IN ('self', 'scan')", name="method"),
        CheckConstraint(
            "(removed_at IS NULL AND removed_by_id IS NULL) OR "
            "(removed_at IS NOT NULL AND removed_by_id IS NOT NULL)",
            name="removal_complete",
        ),
        UniqueConstraint("listing_id", "participant_id"),
        Index("ix_reputation_attendance_listing", "listing_id", "marked_at", "id"),
    )

    listing_id: Mapped[UUID] = mapped_column(
        ForeignKey("listing.id", ondelete="CASCADE")
    )
    participant_id: Mapped[UUID] = mapped_column(ForeignKey("identity_user.id"))
    participant: Mapped[User] = relationship(
        lazy="joined", innerjoin=True, foreign_keys=[participant_id]
    )
    interaction_id: Mapped[UUID] = mapped_column(
        ForeignKey("listing_interaction.id", ondelete="CASCADE")
    )
    # How the mark was taken; the event's current mode is read from the listing.
    method: Mapped[str] = mapped_column(String(8))
    marked_at: Mapped[datetime]
    marked_by_id: Mapped[UUID] = mapped_column(ForeignKey("identity_user.id"))
    removed_at: Mapped[datetime | None]
    removed_by_id: Mapped[UUID | None] = mapped_column(ForeignKey("identity_user.id"))

    @property
    def active(self) -> bool:
        return self.removed_at is None

    @property
    def participant_name(self) -> str:
        return f"{self.participant.first_name} {self.participant.last_name}"
