"""Shared listing, type-specific item and interaction persistence."""

from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from enum import StrEnum
from typing import Any
from uuid import UUID

from sqlalchemy import (
    CheckConstraint,
    Computed,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
    inspect,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB, TSVECTOR
from sqlalchemy.orm import Mapped, mapped_column, relationship

from campus.core import clock
from campus.core.db import Base, Entity, LocalizedName
from campus.modules.identity import User
from campus.modules.university import City


class ListingStatus(StrEnum):
    DRAFT = "draft"
    COMPLETED = "completed"
    HIDDEN = "hidden"
    ACTIVE = "active"
    BUSY = "busy"
    CANCELLED = "cancelled"
    EXPIRED = "expired"


# Listings of these kinds do not expire and have no archive deadline.
PERMANENT_KINDS = frozenset({"publication", "skill", "event"})


class SkillDirection(StrEnum):
    """Whether the author can teach a skill or wants to learn it."""

    TEACH = "teach"
    LEARN = "learn"


class InteractionStatus(StrEnum):
    COMPLETED = "completed"
    NO_SHOW = "no_show"
    PENDING = "pending"
    ACCEPTED = "accepted"
    REJECTED = "rejected"
    CANCELLED = "cancelled"


class MeetingStatus(StrEnum):
    """The current proposal of a meeting: pending or already in force."""

    PROPOSED = "proposed"
    SCHEDULED = "scheduled"


class CompletionMethod(StrEnum):
    """How an accepted interaction reached the completed status."""

    QR = "qr"
    NO_MEETING = "no_meeting"


class CancellationActor(StrEnum):
    """Who ended an interaction: its author, participant or the server."""

    AUTHOR = "author"
    PARTICIPANT = "participant"
    SYSTEM = "system"


class Visibility(StrEnum):
    UNIVERSITY = "university"
    CITY = "city"
    FACULTY = "faculty"
    DORMITORY = "dormitory"


class Audience(StrEnum):
    STUDENTS = "students"
    COMMUNITY = "community"


class PurchaseStage(StrEnum):
    """Stages of a group purchase owned by the listing aggregate."""

    COLLECTING = "collecting"
    FIXED = "fixed"
    CANCELLED = "cancelled"


class Category(LocalizedName, Entity):
    """Stable localized listing categories, managed by the reference API."""

    __tablename__ = "listing_category"
    code: Mapped[str] = mapped_column(String(64), unique=True)


class Listing(Entity):
    """Common aggregate root; other scenarios add their own detail table.

    Mutations lock this row first, including interaction mutations. A
    version covers the entire aggregate, not just the editable text.
    Visibility is a snapshot of the author's area at publication time.
    """

    __tablename__ = "listing"
    __table_args__ = (
        CheckConstraint(
            "event_registered >= 0 AND (event_capacity IS NULL OR "
            "event_registered <= event_capacity)",
            name="event_count",
        ),
        CheckConstraint(
            "kind != 'event' OR (event_starts_at IS NOT NULL AND "
            "event_ends_at IS NOT NULL AND event_ends_at > event_starts_at "
            "AND event_location IS NOT NULL "
            "AND event_capacity IS NOT NULL AND event_capacity > 0)",
            name="event_details",
        ),
        CheckConstraint(
            "kind != 'purchase' OR (purchase_unit_price IS NOT NULL "
            "AND purchase_unit_price > 0 AND purchase_min_units IS NOT NULL "
            "AND purchase_min_units >= 1 AND purchase_max_units IS NOT NULL "
            "AND purchase_max_units >= purchase_min_units "
            "AND purchase_collection_deadline IS NOT NULL "
            "AND purchase_stage IN ('collecting','fixed','cancelled') "
            "AND (purchase_stage != 'fixed' OR purchase_fixed_units IS NOT NULL))",
            name="purchase_details",
        ),
        CheckConstraint(
            "purchase_taken_units >= 0 AND (purchase_max_units IS NULL "
            "OR purchase_taken_units <= purchase_max_units)",
            name="purchase_units",
        ),
        CheckConstraint(
            "kind = 'purchase' OR (purchase_unit_price IS NULL "
            "AND purchase_min_units IS NULL AND purchase_max_units IS NULL "
            "AND purchase_collection_deadline IS NULL AND purchase_stage IS NULL "
            "AND purchase_fixed_units IS NULL AND purchase_taken_units = 0)",
            name="purchase_absent",
        ),
        CheckConstraint("version >= 1", name="version_positive"),
        CheckConstraint(
            "status IN ('draft','active','busy','completed',"
            "'cancelled','expired','hidden')",
            name="status",
        ),
        CheckConstraint(
            "visibility IN ('city','faculty','dormitory','university')",
            name="visibility",
        ),
        CheckConstraint("audience IN ('students','community')", name="audience"),
        CheckConstraint(
            "(visibility IN ('city','university') AND dormitory_id IS NULL "
            "AND faculty_id IS NULL) OR "
            "(visibility = 'faculty' AND faculty_id IS NOT NULL "
            "AND dormitory_id IS NULL) OR "
            "(visibility = 'dormitory' AND dormitory_id IS NOT NULL "
            "AND faculty_id IS NULL)",
            name="scope",
        ),
        Index("ix_listing_search", "search_vector", postgresql_using="gin"),
        Index("ix_listing_feed", "city_id", "created_at", "id"),
        Index(
            "ix_listing_archive_cleanup",
            "archived_at",
            "id",
            postgresql_where=text("archived_at IS NOT NULL AND purged_at IS NULL"),
        ),
    )

    event_starts_at: Mapped[datetime | None]
    event_ends_at: Mapped[datetime | None]
    event_location: Mapped[str | None] = mapped_column(Text)
    event_capacity: Mapped[int | None]
    event_registered: Mapped[int] = mapped_column(default=0, server_default="0")

    purchase_unit_price: Mapped[Decimal | None]
    purchase_min_units: Mapped[int | None]
    purchase_max_units: Mapped[int | None]
    # Accepted units; a database check keeps it at or below the maximum.
    purchase_taken_units: Mapped[int] = mapped_column(default=0, server_default="0")
    # Units frozen at the collection deadline; NULL while collecting.
    purchase_fixed_units: Mapped[int | None]
    purchase_collection_deadline: Mapped[datetime | None]
    purchase_stage: Mapped[str | None] = mapped_column(String(16))

    @property
    def purchase_limit(self) -> int | None:
        """The volume available to participants: frozen units once fixed."""
        if self.purchase_stage == PurchaseStage.FIXED:
            return self.purchase_fixed_units
        return self.purchase_max_units

    @property
    def remaining_places(self) -> int | None:
        if self.event_capacity is None:
            return None
        return self.event_capacity - self.event_registered

    author_id: Mapped[UUID] = mapped_column(ForeignKey("identity_user.id"))
    author: Mapped[User] = relationship(lazy="joined", innerjoin=True)

    @property
    def author_name(self) -> str:
        return f"{self.author.first_name} {self.author.last_name}"

    kind: Mapped[str] = mapped_column(String(32))
    title: Mapped[str] = mapped_column(Text)
    description: Mapped[str] = mapped_column(Text)
    search_vector: Mapped[Any] = mapped_column(
        TSVECTOR,
        Computed(
            "setweight(to_tsvector('russian'::regconfig, title), 'A') || "
            "setweight(to_tsvector('english'::regconfig, title), 'A') || "
            "setweight(to_tsvector('russian'::regconfig, description), 'B') || "
            "setweight(to_tsvector('english'::regconfig, description), 'B')",
            persisted=True,
        ),
        deferred=True,
    )
    status: Mapped[str] = mapped_column(String(16), default=ListingStatus.ACTIVE)
    visibility: Mapped[str] = mapped_column(String(16))
    audience: Mapped[str] = mapped_column(String(16), default=Audience.STUDENTS)
    city_id: Mapped[UUID] = mapped_column(ForeignKey("university_city.id"))
    city: Mapped[City] = relationship(lazy="joined", innerjoin=True)

    @property
    def city_timezone(self) -> str:
        return self.city.timezone

    faculty_id: Mapped[UUID | None] = mapped_column(ForeignKey("university_faculty.id"))
    dormitory_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("university_dormitory.id")
    )
    author_dormitory_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("university_dormitory.id")
    )
    version: Mapped[int] = mapped_column(default=1)
    expires_at: Mapped[datetime | None]
    category_id: Mapped[UUID | None] = mapped_column(ForeignKey("listing_category.id"))
    skill: Mapped[Skill | None] = relationship(
        lazy="joined", uselist=False, cascade="all, delete-orphan"
    )

    @property
    def direction(self) -> str | None:
        """Direction of a skill listing; ``None`` for every other kind."""
        # A new non-skill listing has not loaded the relationship; reading it
        # must not start a lazy query while the response is serialized.
        if "skill" in inspect(self).unloaded:
            return None
        return self.skill.direction if self.skill is not None else None

    pinned_until: Mapped[datetime | None]
    hidden_reason: Mapped[str | None] = mapped_column(Text)
    # When the listing last entered the archive (expired, completed or
    # cancelled); cleared when it leaves it. Retention counts from here.
    archived_at: Mapped[datetime | None]
    # Archive cleanup removed the description and photos; the row stays
    # so interactions, history and reviews remain readable.
    purged_at: Mapped[datetime | None]


class Skill(Base):
    """Type details of a skill listing: it offers or requests a lesson."""

    __tablename__ = "listing_skill"
    __table_args__ = (
        CheckConstraint("direction IN ('teach','learn')", name="direction"),
    )
    listing_id: Mapped[UUID] = mapped_column(ForeignKey("listing.id"), primary_key=True)
    direction: Mapped[str] = mapped_column(String(16))


class Item(Base):
    """Details shared by giveaway, exchange and loan scenarios."""

    __tablename__ = "listing_item"
    listing_id: Mapped[UUID] = mapped_column(ForeignKey("listing.id"), primary_key=True)
    mode: Mapped[str] = mapped_column(String(16))


class Interaction(Entity):
    """Participation in a listing; slot 1 is exclusive for single items.

    Capacity scenarios can allocate multiple slots; unlimited scenarios
    use NULL, which PostgreSQL excludes from uniqueness comparisons.
    Help-request applications use NULL slots, and the one selected as the
    executor carries ``executor``: only one accepted executor is allowed
    per listing, while the other applications stay pending as a reserve.
    An exchange offer is an interaction with a NULL slot and a description
    of the item the participant offers, so several offers coexist.
    """

    __tablename__ = "listing_interaction"
    __table_args__ = (
        CheckConstraint(
            "status IN ('pending','accepted','rejected','cancelled',"
            "'completed','no_show')",
            name="status",
        ),
        Index(
            "uq_listing_one_active_interaction",
            "listing_id",
            "slot",
            unique=True,
            postgresql_where=text("status IN ('pending', 'accepted')"),
        ),
        Index(
            "uq_listing_one_executor",
            "listing_id",
            unique=True,
            postgresql_where=text("status = 'accepted' AND executor"),
        ),
        CheckConstraint(
            "completion_method IS NULL OR completion_method IN ('qr','no_meeting')",
            name="completion_method",
        ),
        CheckConstraint(
            "(completion_method IS NULL AND completed_at IS NULL "
            "AND completion_weight IS NULL) OR "
            "(completion_method IS NOT NULL AND completed_at IS NOT NULL "
            "AND completion_weight IS NOT NULL AND completion_weight >= 0)",
            name="completion_complete",
        ),
        CheckConstraint("units IS NULL OR units > 0", name="units"),
        CheckConstraint(
            "cancelled_by IS NULL OR cancelled_by IN ('author','participant','system')",
            name="cancelled_by",
        ),
        CheckConstraint(
            "(cancelled_by IS NULL AND cancellation_reason IS NULL "
            "AND NOT late_cancelled) OR status = 'cancelled'",
            name="cancellation_complete",
        ),
        Index(
            "ix_listing_interaction_late_cancelled",
            "participant_id",
            postgresql_where=text("late_cancelled"),
        ),
    )
    listing_id: Mapped[UUID] = mapped_column(ForeignKey("listing.id"))
    # Loaded explicitly by participant views; mutations lock the listing.
    listing: Mapped[Listing] = relationship(lazy="raise", viewonly=True)
    # Preserve explicit None for unlimited capacity; only omission defaults to 1.
    slot: Mapped[int | None] = mapped_column(Integer().evaluates_none(), default=1)
    participant_id: Mapped[UUID] = mapped_column(ForeignKey("identity_user.id"))
    participant: Mapped[User] = relationship(
        lazy="joined", innerjoin=True, foreign_keys=[participant_id]
    )

    @property
    def participant_name(self) -> str:
        return f"{self.participant.first_name} {self.participant.last_name}"

    status: Mapped[str] = mapped_column(String(16), default=InteractionStatus.PENDING)
    # The selected executor of a help request; other applications stay pending.
    executor: Mapped[bool] = mapped_column(default=False)

    stage: Mapped[str | None] = mapped_column(String(32))
    response_due_at: Mapped[datetime | None]
    # An accepted item reservation lasts until this moment: the configured
    # reservation window, extended by a scheduled meeting to its time.
    reservation_due_at: Mapped[datetime | None]
    # What a participant offers in exchange; NULL for other scenarios.
    offer_description: Mapped[str | None] = mapped_column(Text)
    # A purchase share: the number of units this participant took.
    units: Mapped[int | None]
    # Set while the participant asks to leave a fixed purchase.
    leave_requested_at: Mapped[datetime | None]

    # Set together when the interaction is completed: how it was confirmed
    # and the weight its review contributes to the rating.
    completion_method: Mapped[str | None] = mapped_column(String(16))
    completed_at: Mapped[datetime | None]
    completion_weight: Mapped[float | None]

    # Set when the interaction is cancelled: who ended it, why (the author's
    # reason) and whether it counted as a late cancellation by the participant.
    cancelled_by: Mapped[str | None] = mapped_column(String(16))
    cancellation_reason: Mapped[str | None] = mapped_column(Text)
    late_cancelled: Mapped[bool] = mapped_column(default=False)
    # The last author-side change of time, place, price or event conditions.
    # A participant who cancels after it is not counted as late (#55).
    conditions_changed_at: Mapped[datetime | None]
    conditions_changed_by_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("identity_user.id")
    )

    @property
    def without_meeting(self) -> bool:
        """Whether the interaction was completed by mutual confirmation."""
        return self.completion_method == CompletionMethod.NO_MEETING

    meeting: Mapped[Meeting | None] = relationship(
        lazy="joined", uselist=False, cascade="all, delete-orphan"
    )
    options: Mapped[list[LessonOption]] = relationship(
        lazy="selectin",
        cascade="all, delete-orphan",
        order_by="LessonOption.position",
    )


class Meeting(Entity):
    """Time and place of an accepted interaction, agreed or only proposed.

    One row per interaction holds the effective meeting (``scheduled_*``)
    and the current pending proposal (``proposed_*``). A counter-proposal
    replaces the pending one; it takes effect only when accepted, and
    ``version`` rejects acceptance of a proposal that has been replaced.
    """

    __tablename__ = "listing_meeting"
    __table_args__ = (
        CheckConstraint("version >= 1", name="version_positive"),
        CheckConstraint(
            "(scheduled_at IS NULL AND location IS NULL "
            "AND scheduled_by_id IS NULL AND online = false) OR "
            "(scheduled_at IS NOT NULL AND scheduled_by_id IS NOT NULL "
            "AND (online OR location IS NOT NULL))",
            name="scheduled_complete",
        ),
        CheckConstraint(
            "(proposed_at IS NULL AND proposed_location IS NULL "
            "AND proposed_by_id IS NULL) OR (proposed_at IS NOT NULL "
            "AND proposed_location IS NOT NULL AND proposed_by_id IS NOT NULL)",
            name="proposal_complete",
        ),
        CheckConstraint(
            "scheduled_at IS NOT NULL OR proposed_at IS NOT NULL",
            name="has_values",
        ),
    )
    interaction_id: Mapped[UUID] = mapped_column(
        ForeignKey("listing_interaction.id"), unique=True
    )
    scheduled_at: Mapped[datetime | None]
    location: Mapped[str | None] = mapped_column(Text)
    online: Mapped[bool] = mapped_column(default=False)
    scheduled_by_id: Mapped[UUID | None] = mapped_column(ForeignKey("identity_user.id"))
    proposed_at: Mapped[datetime | None]
    proposed_location: Mapped[str | None] = mapped_column(Text)
    proposed_by_id: Mapped[UUID | None] = mapped_column(ForeignKey("identity_user.id"))
    version: Mapped[int] = mapped_column(default=1)

    @property
    def status(self) -> MeetingStatus:
        return MeetingStatus.PROPOSED if self.proposed_at else MeetingStatus.SCHEDULED


class NoMeetingConfirmation(Entity):
    """One participant's consent to complete an interaction without a meeting.

    Two rows (one per participant) complete an accepted online lesson or a
    help interaction that needs no meeting. ``agreed_at`` is the same server
    moment in both rows: the scheduled online lesson time, or the moment the
    first participant confirmed a help interaction.
    """

    __tablename__ = "listing_no_meeting_confirmation"
    __table_args__ = (UniqueConstraint("interaction_id", "participant_id"),)
    interaction_id: Mapped[UUID] = mapped_column(
        ForeignKey("listing_interaction.id", ondelete="CASCADE")
    )
    participant_id: Mapped[UUID] = mapped_column(ForeignKey("identity_user.id"))
    agreed_at: Mapped[datetime]


class LessonOptionStatus(StrEnum):
    PROPOSED = "proposed"
    SELECTED = "selected"
    DECLINED = "declined"


class LessonOption(Entity):
    """A time option of a skill lesson, with its place or online flag.

    The responder proposes two or three options; the author selects one, or
    proposes a counter-option that the responder accepts. Exactly one option
    of an interaction becomes selected, and its values become the meeting.
    """

    __tablename__ = "listing_lesson_option"
    __table_args__ = (
        CheckConstraint("position >= 0", name="position"),
        CheckConstraint(
            "(online AND location IS NULL) OR (NOT online AND location IS NOT NULL)",
            name="place",
        ),
        CheckConstraint("status IN ('proposed','selected','declined')", name="status"),
        UniqueConstraint("interaction_id", "position"),
        Index(
            "uq_listing_lesson_option_selected",
            "interaction_id",
            unique=True,
            postgresql_where=text("status = 'selected'"),
        ),
    )
    interaction_id: Mapped[UUID] = mapped_column(ForeignKey("listing_interaction.id"))
    position: Mapped[int]
    time: Mapped[datetime]
    location: Mapped[str | None] = mapped_column(Text)
    online: Mapped[bool] = mapped_column(default=False)
    proposed_by_id: Mapped[UUID] = mapped_column(ForeignKey("identity_user.id"))
    status: Mapped[str] = mapped_column(String(16), default=LessonOptionStatus.PROPOSED)


class WaitlistStatus(StrEnum):
    WAITING = "waiting"
    OFFERED = "offered"
    CLAIMED = "claimed"
    DECLINED = "declined"
    EXPIRED = "expired"
    LEFT = "left"
    REMOVED = "removed"


class WaitlistEntry(Entity):
    """One active queue position per participant and listing.

    Released places are offered in FIFO order for a limited time. Events
    accept immediately; giveaways wait for the author's response. A partial
    index keeps one active position per participant. The offer slot is 1 for
    single-item listings and NULL for events with several concurrent offers.
    """

    __tablename__ = "listing_waitlist"
    __table_args__ = (
        CheckConstraint(
            "status IN ('waiting','offered','claimed','declined','expired',"
            "'left','removed')",
            name="status",
        ),
        CheckConstraint(
            "(offered_at IS NULL) = (offer_expires_at IS NULL)", name="offer_times"
        ),
        CheckConstraint("units IS NULL OR units > 0", name="units"),
        CheckConstraint(
            "offer_units IS NULL OR (offer_units > 0 "
            "AND (units IS NULL OR offer_units <= units))",
            name="offer_units",
        ),
        Index(
            "uq_listing_waitlist_participant",
            "listing_id",
            "participant_id",
            unique=True,
            postgresql_where=text("status IN ('waiting', 'offered')"),
        ),
        Index(
            "uq_listing_waitlist_offer",
            "listing_id",
            "offer_slot",
            unique=True,
            postgresql_where=text("status = 'offered'"),
        ),
        Index(
            "ix_listing_waitlist_queue",
            "listing_id",
            "created_at",
            "id",
            postgresql_where=text("status IN ('waiting', 'offered')"),
        ),
    )
    listing_id: Mapped[UUID] = mapped_column(ForeignKey("listing.id"))
    participant_id: Mapped[UUID] = mapped_column(ForeignKey("identity_user.id"))
    participant: Mapped[User] = relationship(lazy="joined", innerjoin=True)
    status: Mapped[str] = mapped_column(String(16), default=WaitlistStatus.WAITING)
    offer_slot: Mapped[int | None] = mapped_column(
        Integer().evaluates_none(), default=1, server_default="1"
    )
    offered_at: Mapped[datetime | None]
    offer_expires_at: Mapped[datetime | None]
    # A purchase queue position: how many units the member wants, and how
    # many of them an active offer holds.
    units: Mapped[int | None]
    offer_units: Mapped[int | None]
    interaction_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("listing_interaction.id")
    )

    @property
    def participant_name(self) -> str:
        return f"{self.participant.first_name} {self.participant.last_name}"


class ListingEvent(Entity):
    """Append-only history, enforced by a database trigger in the migration."""

    __tablename__ = "listing_event"
    __table_args__ = (
        Index("ix_listing_event_history", "listing_id", "created_at", "id"),
        Index("ix_listing_event_quota", "actor_id", "action", "created_at"),
        # The first accepted event is the interaction's acceptance time; the
        # offline QR lower bound reads it without a duplicate column.
        Index(
            "ix_listing_event_interaction_accepted",
            "interaction_id",
            "created_at",
            postgresql_where=text("status = 'accepted'"),
        ),
    )
    listing_id: Mapped[UUID] = mapped_column(ForeignKey("listing.id"))
    interaction_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("listing_interaction.id")
    )
    waitlist_entry_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("listing_waitlist.id")
    )
    actor_id: Mapped[UUID | None] = mapped_column(ForeignKey("identity_user.id"))
    action: Mapped[str] = mapped_column(String(32))
    previous_status: Mapped[str | None] = mapped_column(String(16))
    status: Mapped[str] = mapped_column(String(16))
    version: Mapped[int]

    reason: Mapped[str | None] = mapped_column(Text)
    stage: Mapped[str | None] = mapped_column(String(32))
    details: Mapped[dict[str, Any] | None] = mapped_column(JSONB)
    via_assistant: Mapped[bool] = mapped_column(default=False)
    offline_qr: Mapped[bool] = mapped_column(default=False)


class Favorite(Base):
    """A user's bookmark; the key makes repeated additions a no-op."""

    __tablename__ = "listing_favorite"
    __table_args__ = (Index("ix_listing_favorite_user", "user_id", "created_at"),)
    user_id: Mapped[UUID] = mapped_column(
        ForeignKey("identity_user.id"), primary_key=True
    )
    listing_id: Mapped[UUID] = mapped_column(ForeignKey("listing.id"), primary_key=True)
    listing: Mapped[Listing] = relationship(lazy="joined", innerjoin=True)
    created_at: Mapped[datetime] = mapped_column(default=clock.now)
