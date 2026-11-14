"""Tables of the university structure (specification, 4.5, module 11).

One service instance serves one university: its campus cities, the
dormitories and faculties of each city, and the e-mail domains whose
addresses may register. Reference entities have a stable ``code`` (their
natural key, used by the seed data and the admin panel) and names in every
supported language.
"""

from enum import StrEnum
from functools import cache
from uuid import UUID
from zoneinfo import available_timezones

from sqlalchemy import CheckConstraint, Enum, ForeignKey, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, validates

from campus.core.db import Entity, LocalizedName

CODE_MAX_LENGTH = 64
CODE_PATTERN = r"^[a-z0-9]+(-[a-z0-9]+)*$"
TIMEZONE_MAX_LENGTH = 64
DOMAIN_MAX_LENGTH = 253
# Lowercase host name: labels of letters, digits and inner hyphens.
DOMAIN_PATTERN = r"^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z][a-z0-9-]*[a-z0-9]$"


class InvalidTimezoneError(ValueError):
    """The time zone is not a name from the IANA time zone database."""

    def __init__(self, timezone: str) -> None:
        super().__init__(f"{timezone!r} is not an IANA time zone")
        self.timezone = timezone


@cache
def iana_timezones() -> frozenset[str]:
    """Names of the IANA time zone database (system or ``tzdata`` package)."""
    return frozenset(available_timezones())


def check_timezone(timezone: str) -> str:
    """Return ``timezone`` if it is an IANA name, e.g. ``Europe/Moscow``."""
    if timezone not in iana_timezones():
        raise InvalidTimezoneError(timezone)
    return timezone


def _code_check() -> CheckConstraint:
    return CheckConstraint(f"code ~ '{CODE_PATTERN}'", name="code_format")


class AccountType(StrEnum):
    """Account type given by the e-mail domain an address belongs to."""

    STUDENT = "student"
    EMPLOYEE = "employee"


class City(LocalizedName, Entity):
    """A campus city; times of its events are shown in its time zone."""

    __tablename__ = "university_city"
    __table_args__ = (_code_check(),)

    code: Mapped[str] = mapped_column(String(CODE_MAX_LENGTH), unique=True)
    timezone: Mapped[str] = mapped_column(String(TIMEZONE_MAX_LENGTH))

    @validates("timezone")
    def _validate_timezone(self, _key: str, timezone: str) -> str:
        return check_timezone(timezone)


class Dormitory(LocalizedName, Entity):
    """A dormitory in a campus city."""

    __tablename__ = "university_dormitory"
    # (city_id, id) is the target of foreign keys that require the row to
    # belong to a given city, e.g. the dormitory of a user's city.
    __table_args__ = (
        UniqueConstraint("city_id", "code"),
        UniqueConstraint("city_id", "id"),
        _code_check(),
    )

    city_id: Mapped[UUID] = mapped_column(
        ForeignKey("university_city.id", ondelete="RESTRICT")
    )
    code: Mapped[str] = mapped_column(String(CODE_MAX_LENGTH))


class Faculty(LocalizedName, Entity):
    """A faculty (or school) of the university in a campus city."""

    __tablename__ = "university_faculty"
    # (city_id, id) is the target of foreign keys that require the row to
    # belong to a given city, e.g. the dormitory of a user's city.
    __table_args__ = (
        UniqueConstraint("city_id", "code"),
        UniqueConstraint("city_id", "id"),
        _code_check(),
    )

    city_id: Mapped[UUID] = mapped_column(
        ForeignKey("university_city.id", ondelete="RESTRICT")
    )
    code: Mapped[str] = mapped_column(String(CODE_MAX_LENGTH))


class EmailDomain(Entity):
    """An e-mail domain allowed to register; it sets the account type."""

    __tablename__ = "university_email_domain"
    __table_args__ = (
        CheckConstraint(f"domain ~ '{DOMAIN_PATTERN}'", name="domain_format"),
    )

    domain: Mapped[str] = mapped_column(String(DOMAIN_MAX_LENGTH), unique=True)
    account_type: Mapped[AccountType] = mapped_column(
        Enum(
            AccountType,
            name="account_type",
            native_enum=False,
            create_constraint=True,
            length=16,
            values_callable=lambda members: [member.value for member in members],
        )
    )
