"""Shared listing, type-specific item and interaction persistence."""

from datetime import datetime
from enum import StrEnum
from uuid import UUID

from sqlalchemy import CheckConstraint, ForeignKey, Index, String, Text, text
from sqlalchemy.orm import Mapped, mapped_column

from campus.core.db import Base, Entity, LocalizedName


class ListingStatus(StrEnum):
    DRAFT = "draft"
    COMPLETED = "completed"
    HIDDEN = "hidden"
    ACTIVE = "active"
    BUSY = "busy"
    CANCELLED = "cancelled"
    EXPIRED = "expired"


class InteractionStatus(StrEnum):
    COMPLETED = "completed"
    NO_SHOW = "no_show"
    PENDING = "pending"
    ACCEPTED = "accepted"
    REJECTED = "rejected"
    CANCELLED = "cancelled"


class Visibility(StrEnum):
    CITY = "city"
    FACULTY = "faculty"
    DORMITORY = "dormitory"


class Audience(StrEnum):
    STUDENTS = "students"
    COMMUNITY = "community"


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
        CheckConstraint("version >= 1", name="version_positive"),
        CheckConstraint(
            "status IN ('draft','active','busy','completed',"
            "'cancelled','expired','hidden')",
            name="status",
        ),
        CheckConstraint(
            "visibility IN ('city','faculty','dormitory')", name="visibility"
        ),
        CheckConstraint("audience IN ('students','community')", name="audience"),
        CheckConstraint(
            "(visibility = 'city' AND dormitory_id IS NULL AND faculty_id IS NULL) OR "
            "(visibility = 'faculty' AND faculty_id IS NOT NULL "
            "AND dormitory_id IS NULL) OR "
            "(visibility = 'dormitory' AND dormitory_id IS NOT NULL "
            "AND faculty_id IS NULL)",
            name="scope",
        ),
        Index("ix_listing_feed", "city_id", "created_at", "id"),
    )

    author_id: Mapped[UUID] = mapped_column(ForeignKey("identity_user.id"))
    kind: Mapped[str] = mapped_column(String(32))
    title: Mapped[str] = mapped_column(Text)
    description: Mapped[str] = mapped_column(Text)
    status: Mapped[str] = mapped_column(String(16), default=ListingStatus.ACTIVE)
    visibility: Mapped[str] = mapped_column(String(16))
    audience: Mapped[str] = mapped_column(String(16), default=Audience.STUDENTS)
    city_id: Mapped[UUID] = mapped_column(ForeignKey("university_city.id"))
    faculty_id: Mapped[UUID | None] = mapped_column(ForeignKey("university_faculty.id"))
    dormitory_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("university_dormitory.id")
    )
    version: Mapped[int] = mapped_column(default=1)
    expires_at: Mapped[datetime | None]
    category_id: Mapped[UUID | None] = mapped_column(ForeignKey("listing_category.id"))
    hidden_reason: Mapped[str | None] = mapped_column(Text)


class Item(Base):
    """Details shared by giveaway, exchange and loan scenarios."""

    __tablename__ = "listing_item"
    listing_id: Mapped[UUID] = mapped_column(ForeignKey("listing.id"), primary_key=True)
    mode: Mapped[str] = mapped_column(String(16))


class Interaction(Entity):
    """Participation in a listing; slot 1 is exclusive for single items.

    Capacity scenarios can allocate multiple slots; unlimited scenarios
    use NULL, which PostgreSQL excludes from uniqueness comparisons.
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
    )
    listing_id: Mapped[UUID] = mapped_column(ForeignKey("listing.id"))
    slot: Mapped[int | None] = mapped_column(default=1)
    participant_id: Mapped[UUID] = mapped_column(ForeignKey("identity_user.id"))
    status: Mapped[str] = mapped_column(String(16), default=InteractionStatus.PENDING)

    stage: Mapped[str | None] = mapped_column(String(32))
    response_due_at: Mapped[datetime | None]


class ListingEvent(Entity):
    """Append-only history, enforced by a database trigger in the migration."""

    __tablename__ = "listing_event"
    __table_args__ = (
        Index("ix_listing_event_history", "listing_id", "created_at", "id"),
        Index("ix_listing_event_quota", "actor_id", "action", "created_at"),
    )
    listing_id: Mapped[UUID] = mapped_column(ForeignKey("listing.id"))
    interaction_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("listing_interaction.id")
    )
    actor_id: Mapped[UUID | None] = mapped_column(ForeignKey("identity_user.id"))
    action: Mapped[str] = mapped_column(String(32))
    previous_status: Mapped[str | None] = mapped_column(String(16))
    status: Mapped[str] = mapped_column(String(16))
    version: Mapped[int]

    reason: Mapped[str | None] = mapped_column(Text)
    stage: Mapped[str | None] = mapped_column(String(32))
    via_assistant: Mapped[bool] = mapped_column(default=False)
    offline_qr: Mapped[bool] = mapped_column(default=False)
