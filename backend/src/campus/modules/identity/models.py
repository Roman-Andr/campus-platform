"""Identity tables: users with their profiles, one-time challenges and
rotating device credentials."""

from datetime import datetime
from enum import StrEnum
from uuid import UUID

from sqlalchemy import (
    CheckConstraint,
    ForeignKey,
    ForeignKeyConstraint,
    Index,
    SmallInteger,
    String,
    UniqueConstraint,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column

from campus.core import clock
from campus.core.db import Base, Entity, LocalizedName
from campus.modules.university import CODE_MAX_LENGTH, CODE_PATTERN, AccountType


class User(Entity):
    """An account and its profile (specification, 5.1.1, module 2).

    The profile — campus city, faculty, course and an optional dormitory —
    is filled in after the first sign-in; until then the city is empty.
    The dormitory and the faculty must belong to the city: the composite
    foreign keys enforce it. An empty dormitory of a filled profile means
    "does not live in a dormitory".
    """

    __tablename__ = "identity_user"
    __table_args__ = (
        CheckConstraint("email = lower(email)", name="email_lowercase"),
        # The profile is saved whole: city and faculty together, the rest
        # only with them.
        CheckConstraint(
            "(city_id IS NULL) = (faculty_id IS NULL)"
            " AND (city_id IS NOT NULL OR (dormitory_id IS NULL AND course IS NULL))",
            name="profile_whole",
        ),
        CheckConstraint("course >= 1", name="course_positive"),
        CheckConstraint("message_policy IN ('all', 'related')", name="message_policy"),
        ForeignKeyConstraint(
            ["city_id", "dormitory_id"],
            ["university_dormitory.city_id", "university_dormitory.id"],
            name="fk_identity_user_dormitory_of_city",
            ondelete="RESTRICT",
        ),
        ForeignKeyConstraint(
            ["city_id", "faculty_id"],
            ["university_faculty.city_id", "university_faculty.id"],
            name="fk_identity_user_faculty_of_city",
            ondelete="RESTRICT",
        ),
    )

    email: Mapped[str] = mapped_column(String(320), unique=True)
    first_name: Mapped[str] = mapped_column(String(100))
    last_name: Mapped[str] = mapped_column(String(100))
    account_type: Mapped[str] = mapped_column(String(16))
    city_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("university_city.id", ondelete="RESTRICT"), index=True
    )
    dormitory_id: Mapped[UUID | None] = mapped_column(index=True)
    faculty_id: Mapped[UUID | None] = mapped_column(index=True)
    course: Mapped[int | None] = mapped_column(SmallInteger)
    # Who may start a personal dialog with this user: everybody or only
    # users with a permitted listing/interaction relation. Enforced by the
    # contact policy, not only by clients.
    message_policy: Mapped[str] = mapped_column(
        String(16), default="all", server_default=text("'all'")
    )

    @property
    def profile_complete(self) -> bool:
        """Whether the profile is filled in; required to publish and respond."""
        return self.city_id is not None and (
            self.course is not None
            or self.account_type in (AccountType.EMPLOYEE, "former_employee")
        )


class UserEmail(Entity):
    """Verified addresses; User.email is the compatible primary-address cache."""

    __tablename__ = "identity_user_email"
    __table_args__ = (
        CheckConstraint("email = lower(email)", name="email_lowercase"),
        CheckConstraint("kind IN ('corporate', 'backup')", name="kind_valid"),
        Index(
            "uq_identity_user_email_backup",
            "user_id",
            unique=True,
            postgresql_where=text("kind = 'backup'"),
        ),
    )

    user_id: Mapped[UUID] = mapped_column(
        ForeignKey("identity_user.id", ondelete="CASCADE"), index=True
    )
    email: Mapped[str] = mapped_column(String(320), unique=True)
    kind: Mapped[str] = mapped_column(String(16))
    verified_at: Mapped[datetime]


class SignInCode(Entity):
    __tablename__ = "identity_sign_in_code"
    __table_args__ = (
        UniqueConstraint(
            "email", "purpose", "user_id", postgresql_nulls_not_distinct=True
        ),
    )

    email: Mapped[str] = mapped_column(String(320))
    purpose: Mapped[str] = mapped_column(String(16), default="sign_in")
    user_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("identity_user.id", ondelete="CASCADE")
    )
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


class SkillTag(LocalizedName, Entity):
    """A skill of the common tag reference (specification, 5.1.1, module 10,
    item 2): what a user can do or wants to learn."""

    __tablename__ = "identity_skill_tag"
    __table_args__ = (CheckConstraint(f"code ~ '{CODE_PATTERN}'", name="code_format"),)

    code: Mapped[str] = mapped_column(String(CODE_MAX_LENGTH), unique=True)


class SkillKind(StrEnum):
    """Which list of the profile a skill is in."""

    CAN = "can"
    WANTS = "wants"


class UserSkill(Base):
    """A skill tag in one of the profile lists (specification, 5.1.1,
    module 2, item 1); a list is replaced whole."""

    __tablename__ = "identity_user_skill"
    __table_args__ = (CheckConstraint("kind IN ('can', 'wants')", name="kind"),)

    user_id: Mapped[UUID] = mapped_column(
        ForeignKey("identity_user.id", ondelete="CASCADE"), primary_key=True
    )
    kind: Mapped[str] = mapped_column(String(8), primary_key=True)
    tag_id: Mapped[UUID] = mapped_column(
        ForeignKey("identity_skill_tag.id", ondelete="RESTRICT"),
        primary_key=True,
        index=True,
    )


class NameChange(Entity):
    """One change of the user's name (specification, 5.1.1, module 1,
    item 2). Append-only: a database trigger rejects updates and deletes."""

    __tablename__ = "identity_name_change"
    __table_args__ = (Index("ix_identity_name_change_user", "user_id", "created_at"),)

    user_id: Mapped[UUID] = mapped_column(ForeignKey("identity_user.id"))
    old_first_name: Mapped[str] = mapped_column(String(100))
    old_last_name: Mapped[str] = mapped_column(String(100))
    new_first_name: Mapped[str] = mapped_column(String(100))
    new_last_name: Mapped[str] = mapped_column(String(100))


class Block(Base):
    """A personal blacklist entry: ``blocker_id`` refuses ``blocked_id``.

    A block is directional in storage and mutual in effect: the contact
    policy rejects personal messages and responses in both directions, and
    hides each author's listings from the other. Existing interactions stay
    readable and completable; blocking never cancels them.
    """

    __tablename__ = "identity_block"
    __table_args__ = (
        CheckConstraint("blocker_id <> blocked_id", name="not_self"),
        Index("ix_identity_block_blocked_id", "blocked_id"),
    )

    blocker_id: Mapped[UUID] = mapped_column(
        ForeignKey("identity_user.id", ondelete="CASCADE"), primary_key=True
    )
    blocked_id: Mapped[UUID] = mapped_column(
        ForeignKey("identity_user.id", ondelete="CASCADE"), primary_key=True
    )
    created_at: Mapped[datetime] = mapped_column(default=clock.now)
