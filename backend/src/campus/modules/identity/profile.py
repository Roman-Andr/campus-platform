"""The signed-in user's own account and profile (specification, 5.1.1,
module 2, item 1).

The profile is filled in after the first sign-in: campus city, faculty and
course from the university reference data, and a dormitory or none ("does
not live in a dormitory"). The dormitory and the faculty must be of the
chosen city. Employees have no course. Publishing and responding require a
filled profile: their endpoints take :data:`ProfiledUser` instead of
``CurrentUser``.
"""

from typing import Annotated
from uuid import UUID

from fastapi import Depends, Request
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select

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
from campus.core.web.problems import VALIDATION_FAILED
from campus.modules.identity.consents import cross_border_allowed
from campus.modules.identity.models import User
from campus.modules.identity.roles import RoleOutput, user_roles
from campus.modules.university import AccountType, City, Dormitory, Faculty

PROFILE_INCOMPLETE = ProblemType(
    "profile_incomplete",
    403,
    N_("Profile incomplete"),
    N_("Fill in your profile first: campus city, faculty and course."),
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
    account_type: AccountType
    city_id: UUID | None = Field(description="Campus city; empty until filled in.")
    dormitory_id: UUID | None = Field(
        description="Empty when the user does not live in a dormitory."
    )
    faculty_id: UUID | None
    course: int | None = Field(description="Year of study; employees have none.")
    profile_complete: bool = Field(
        description="Whether the profile is filled in; publishing and responding"
        " need it."
    )


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
    if user.account_type == AccountType.EMPLOYEE:
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


async def user_output(session: DbSession, user: User) -> UserOutput:
    return UserOutput.model_validate(
        {
            **{
                name: getattr(user, name)
                for name in UserOutput.model_fields
                if name not in {"roles", "cross_border_transfer_allowed"}
            },
            "roles": await user_roles(session, user.id),
            "cross_border_transfer_allowed": await cross_border_allowed(session, user.id),
        }
    )


@router.get("")
async def get_me(session: DbSession, principal: CurrentUser) -> UserOutput:
    """The signed-in user's account and profile."""
    return await user_output(session, await _user(session, principal))


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
    return await user_output(session, user)


async def profiled_user(session: DbSession, principal: CurrentUser) -> Principal:
    """The signed-in user, if their profile is filled in."""
    if not (await _user(session, principal)).profile_complete:
        raise ProblemError(PROFILE_INCOMPLETE)
    return principal


ProfiledUser = Annotated[Principal, Depends(profiled_user)]
"""A signed-in user with a filled profile; required to publish and respond.

Answers ``403 profile_incomplete`` otherwise."""
