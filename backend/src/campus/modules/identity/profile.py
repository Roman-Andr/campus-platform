"""The signed-in user's own account and profile (specification, 5.1.1,
module 2, item 1), and the name change (module 1, item 2).

The profile is filled in after the first sign-in: campus city, faculty and
course from the university reference data, and a dormitory or none ("does
not live in a dormitory"). The dormitory and the faculty must be of the
chosen city. Employees have no course. Publishing and responding require a
filled profile: their endpoints take :data:`ProfiledUser` instead of
``CurrentUser``.

The name may change at most once per ``name_change_interval`` (90 days by
default); every change is appended to the name history, which the database
keeps immutable.
"""

from datetime import datetime
from typing import Annotated, Literal
from uuid import UUID

from fastapi import Depends, Request
from pydantic import BaseModel, ConfigDict, Field, field_validator
from pydantic_core import PydanticCustomError
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from campus.core import clock
from campus.core.config import Locale, Settings
from campus.core.i18n import N_, translate
from campus.core.web import (
    DbSession,
    FieldError,
    Principal,
    Problem,
    ProblemError,
    ProblemType,
    api_router,
    request_locale,
)
from campus.core.web.auth import CurrentUser
from campus.core.web.datetimes import Instant
from campus.core.web.problems import VALIDATION_FAILED
from campus.modules.identity.consents import cross_border_allowed
from campus.modules.identity.models import NameChange, User
from campus.modules.identity.roles import RoleOutput, user_roles
from campus.modules.university import AccountType, City, Dormitory, Faculty

PROFILE_INCOMPLETE = ProblemType(
    "profile_incomplete",
    403,
    N_("Profile incomplete"),
    N_("Fill in your profile first: campus city, faculty and course."),
)
NAME_CHANGE_TOO_SOON = ProblemType(
    "name_change_too_soon",
    409,
    N_("Name changed recently"),
    N_("The name can be changed once in {days} days; see available_at."),
)
CITY_NOT_FOUND = N_("No such campus city.")
NOT_OF_CITY = N_("Must be one of the chosen city.")
COURSE_REQUIRED = N_("Students must give their course.")
COURSE_TOO_HIGH = N_("Must be at most {max}.")
COURSE_NOT_ALLOWED = N_("Employees have no course.")

router = api_router(
    prefix="/me",
    tags=["Profile"],
    responses={401: {"model": Problem, "description": "Not signed in."}},
)


class UserOutput(BaseModel):
    """The user's account and profile."""

    model_config = ConfigDict(from_attributes=True)
    cross_border_transfer_allowed: bool = False
    roles: tuple[RoleOutput, ...]
    id: UUID
    email: str
    first_name: str
    last_name: str
    account_type: Literal["student", "employee", "former_employee"]
    city_id: UUID | None = Field(description="Campus city; empty until filled in.")
    city_timezone: str | None
    dormitory_id: UUID | None = Field(
        description="Empty when the user does not live in a dormitory."
    )
    faculty_id: UUID | None
    course: int | None = Field(description="Year of study; employees have none.")
    profile_complete: bool = Field(
        description="Whether the profile is filled in; publishing and responding"
        " need it."
    )
    name_change_available_at: Instant | None = Field(
        description="When the name may change next; empty: now."
    )


def check_name(value: str) -> str:
    """A real first or last name: letters, spaces, hyphens, apostrophes."""
    value = value.strip()
    if (
        not value
        or not any(c.isalpha() for c in value)
        or not all(c.isalpha() or c in " -'\u2019" for c in value)
    ):
        raise PydanticCustomError("string_pattern_mismatch", "Has an invalid format.")
    return value


class NameInput(BaseModel):
    """The new real name."""

    model_config = ConfigDict(extra="forbid")
    first_name: str = Field(min_length=1, max_length=100)
    last_name: str = Field(min_length=1, max_length=100)

    @field_validator("first_name", "last_name")
    @classmethod
    def validate_name(cls, value: str) -> str:
        return check_name(value)


class ProfileInput(BaseModel):
    """The whole profile; omitted fields are not kept."""

    model_config = ConfigDict(extra="forbid")
    city_id: UUID
    dormitory_id: UUID | None = Field(
        default=None, description="Empty: does not live in a dormitory."
    )
    faculty_id: UUID
    course: int | None = Field(
        default=None,
        ge=1,
        description="Year of study: required for students, absent for employees.",
    )


def _error(
    locale: Locale, field: str, code: str, message: str, **params: object
) -> FieldError:
    return FieldError(
        detail=translate(message, locale, **params), code=code, pointer=f"#/{field}"
    )


async def _check(
    session: DbSession, data: ProfileInput, user: User, request: Request
) -> list[FieldError]:
    """Field errors of ``data`` against the reference data and the account."""
    locale = request_locale(request)
    settings: Settings = request.app.state.settings
    errors: list[FieldError] = []
    if await session.get(City, data.city_id) is None:
        errors.append(_error(locale, "city_id", "not_found", CITY_NOT_FOUND))
    else:
        places: list[tuple[str, type[Dormitory | Faculty], UUID | None]] = [
            ("dormitory_id", Dormitory, data.dormitory_id),
            ("faculty_id", Faculty, data.faculty_id),
        ]
        for field, model, place_id in places:
            if place_id is None:
                continue
            city_id = await session.scalar(
                select(model.city_id).where(model.id == place_id)
            )
            if city_id != data.city_id:
                errors.append(_error(locale, field, "not_of_city", NOT_OF_CITY))
    if user.account_type in (AccountType.EMPLOYEE, "former_employee"):
        if data.course is not None:
            errors.append(_error(locale, "course", "not_allowed", COURSE_NOT_ALLOWED))
    elif data.course is None:
        errors.append(_error(locale, "course", "missing", COURSE_REQUIRED))
    elif data.course > settings.profile_max_course:
        errors.append(
            _error(
                locale,
                "course",
                "less_than_equal",
                COURSE_TOO_HIGH,
                max=settings.profile_max_course,
            )
        )
    return errors


async def _user(session: DbSession, principal: Principal) -> User:
    user = await session.get(User, principal.user_id)
    # A session outlives no user: users are not deleted yet.
    assert user is not None  # noqa: S101
    return user


async def name_change_available_at(
    session: AsyncSession, user_id: UUID, settings: Settings
) -> datetime | None:
    """When the user may change the name next; ``None`` if now."""
    last = await session.scalar(
        select(NameChange.created_at)
        .where(NameChange.user_id == user_id)
        .order_by(NameChange.created_at.desc())
        .limit(1)
    )
    if last is None or last + settings.name_change_interval <= clock.now():
        return None
    return last + settings.name_change_interval


async def user_output(
    session: AsyncSession, user: User, settings: Settings
) -> UserOutput:
    city = await session.get(City, user.city_id) if user.city_id else None
    return UserOutput.model_validate(
        {
            **{
                name: getattr(user, name)
                for name in UserOutput.model_fields
                if name
                not in {
                    "roles",
                    "cross_border_transfer_allowed",
                    "city_timezone",
                    "name_change_available_at",
                }
            },
            "name_change_available_at": await name_change_available_at(
                session, user.id, settings
            ),
            "city_timezone": city.timezone if city else None,
            "roles": await user_roles(session, user.id),
            "cross_border_transfer_allowed": await cross_border_allowed(
                session, user.id
            ),
        }
    )


@router.get("")
async def get_me(
    request: Request, session: DbSession, principal: CurrentUser
) -> UserOutput:
    """The signed-in user's account and profile."""
    return await user_output(
        session, await _user(session, principal), request.app.state.settings
    )


@router.put("/profile", responses={422: {"model": Problem}})
async def update_profile(
    data: ProfileInput, request: Request, session: DbSession, principal: CurrentUser
) -> UserOutput:
    """Fill in or change the profile; the dormitory and the faculty must be of
    the city (``validation_failed`` with ``not_of_city`` otherwise)."""
    user = await session.get(User, principal.user_id, with_for_update=True)
    assert user is not None  # noqa: S101 - see _user
    errors = await _check(session, data, user, request)
    if errors:
        raise ProblemError(VALIDATION_FAILED, errors=errors)
    user.city_id = data.city_id
    user.dormitory_id = data.dormitory_id
    user.faculty_id = data.faculty_id
    user.course = data.course
    await session.flush()
    return await user_output(session, user, request.app.state.settings)


@router.put("/name", responses={409: {"model": Problem}, 422: {"model": Problem}})
async def change_name(
    data: NameInput, request: Request, session: DbSession, principal: CurrentUser
) -> UserOutput:
    """Change the real name; it is recorded in the name history.

    A change sooner than ``name_change_interval`` after the previous one
    answers ``409 name_change_too_soon`` with ``available_at``. Giving the
    current name changes nothing."""
    settings: Settings = request.app.state.settings
    user = await session.get(User, principal.user_id, with_for_update=True)
    assert user is not None  # noqa: S101 - see _user
    if (data.first_name, data.last_name) != (user.first_name, user.last_name):
        available_at = await name_change_available_at(session, user.id, settings)
        if available_at is not None:
            raise ProblemError(
                NAME_CHANGE_TOO_SOON,
                available_at=available_at,
                days=settings.name_change_interval.days,
            )
        session.add(
            NameChange(
                user_id=user.id,
                old_first_name=user.first_name,
                old_last_name=user.last_name,
                new_first_name=data.first_name,
                new_last_name=data.last_name,
            )
        )
        user.first_name, user.last_name = data.first_name, data.last_name
        await session.flush()
    return await user_output(session, user, settings)


async def profiled_user(session: DbSession, principal: CurrentUser) -> Principal:
    """The signed-in user, if their profile is filled in."""
    if not (await _user(session, principal)).profile_complete:
        raise ProblemError(PROFILE_INCOMPLETE)
    return principal


ProfiledUser = Annotated[Principal, Depends(profiled_user)]
"""A signed-in user with a filled profile; required to publish and respond.

Answers ``403 profile_incomplete`` otherwise."""
