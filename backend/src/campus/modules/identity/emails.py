"""Verified secondary addresses and reusable account security notifications."""

import hmac
import math
from datetime import datetime
from typing import Literal
from uuid import UUID

from fastapi import Request, Response
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from campus.core import clock
from campus.core.i18n import N_, translate
from campus.core.mail import queue_email
from campus.core.web import (
    DbSession,
    Problem,
    ProblemError,
    ProblemType,
    api_router,
    request_locale,
)
from campus.core.web.auth import RATE_LIMITED, CurrentUser, digest, rate_limit
from campus.modules.identity.api import (
    ATTEMPTS_EXCEEDED,
    CODE_EXPIRED,
    CODE_INVALID,
    EMAIL_CONFLICT,
    EmailInput,
    count_attempt,
    send_code,
)
from campus.modules.identity.models import SignInCode, User, UserEmail
from campus.modules.identity.roles import revoke_headman_roles
from campus.modules.university import AccountType, EmailDomain

EMAIL_KIND_INVALID = ProblemType(
    "email_kind_invalid", 422, N_("E-mail domain does not match address kind")
)
LAST_CORPORATE = ProblemType(
    "last_corporate_email", 409, N_("Cannot remove the last corporate address")
)
EMAIL_NOT_FOUND = ProblemType("email_not_found", 404, N_("E-mail address not found"))
SECURITY_SUBJECT = N_("Campus account security notification")
SECURITY_TEXT = N_(
    "Your account e-mail addresses have changed. If this was not you, contact support."
)
router = api_router(
    prefix="/me/emails",
    tags=["Account emails"],
    responses={
        401: {"model": Problem, "description": "Not signed in or invalid code."},
        409: {
            "model": Problem,
            "description": "Address in use or last corporate address.",
        },
        422: {"model": Problem, "description": "Invalid address kind or domain."},
        429: {
            "model": Problem,
            "description": "Code limit exceeded; Retry-After in seconds.",
        },
    },
)


class AddressInput(EmailInput):
    kind: Literal["corporate", "backup"]


class ConfirmAddressInput(AddressInput):
    code: str = Field(pattern=r"^[0-9]{6}$")


class AddressOutput(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    email: str
    kind: Literal["corporate", "backup"]
    verified_at: datetime


async def notify_account_security(
    session: AsyncSession,
    user_id: UUID,
    *,
    message: str = SECURITY_TEXT,
    locale: Literal["ru", "en"] = "ru",
) -> None:
    """Queue a security notice to every verified address in the transaction.

    Shared with account recovery; never include codes or credentials.
    """
    addresses = await session.scalars(
        select(UserEmail.email).where(UserEmail.user_id == user_id)
    )
    for email in addresses:
        queue_email(
            session,
            to=email,
            subject=translate(SECURITY_SUBJECT, locale),
            text=translate(message, locale),
        )


async def check_address(session: DbSession, data: AddressInput) -> None:
    domain = await session.scalar(
        select(EmailDomain).where(EmailDomain.domain == data.email.rpartition("@")[2])
    )
    if (domain is not None) != (data.kind == "corporate"):
        raise ProblemError(EMAIL_KIND_INVALID)
    if await session.scalar(select(UserEmail.id).where(UserEmail.email == data.email)):
        raise ProblemError(EMAIL_CONFLICT)


@router.get("")
async def list_addresses(
    session: DbSession, principal: CurrentUser
) -> list[AddressOutput]:
    return [
        AddressOutput.model_validate(row)
        for row in await session.scalars(
            select(UserEmail)
            .where(UserEmail.user_id == principal.user_id)
            .order_by(UserEmail.created_at, UserEmail.id)
        )
    ]


@router.post("/codes", status_code=202)
async def request_address_code(
    data: AddressInput, request: Request, session: DbSession, principal: CurrentUser
) -> None:
    await rate_limit(request, data.email)
    await check_address(session, data)
    await send_code(
        data.email, request, session, purpose=data.kind, user_id=principal.user_id
    )


async def recalculate_account(session: DbSession, user: User) -> None:
    corporate = (
        await session.scalars(
            select(UserEmail)
            .where(UserEmail.user_id == user.id, UserEmail.kind == "corporate")
            .order_by(UserEmail.created_at, UserEmail.id)
        )
    ).all()
    domains = (
        await session.scalars(
            select(EmailDomain).where(
                EmailDomain.domain.in_(
                    [row.email.rpartition("@")[2] for row in corporate]
                )
            )
        )
    ).all()
    user.account_type = (
        AccountType.STUDENT
        if any(d.account_type == AccountType.STUDENT for d in domains)
        else AccountType.EMPLOYEE
    )
    if user.account_type == AccountType.EMPLOYEE:
        user.course = None
        await revoke_headman_roles(session, user.id)
    if user.email not in {row.email for row in corporate}:
        user.email = corporate[0].email


@router.post("", status_code=201)
async def confirm_address(
    data: ConfirmAddressInput,
    request: Request,
    session: DbSession,
    principal: CurrentUser,
) -> AddressOutput:
    await rate_limit(request)
    settings = request.app.state.settings
    try:
        challenge_id, expected = await count_attempt(
            request, data.email, purpose=data.kind, user_id=principal.user_id
        )
    except ProblemError as error:
        if error.problem_type == ATTEMPTS_EXCEEDED:
            raise ProblemError(
                RATE_LIMITED,
                headers={
                    "Retry-After": str(
                        math.ceil(settings.sign_in_code_ttl.total_seconds())
                    )
                },
            ) from None
        raise
    if not hmac.compare_digest(
        expected, digest(settings, data.email + ":" + data.code)
    ):
        raise ProblemError(CODE_INVALID)
    # One account lock serializes replacements, deletions and type changes.
    user = await session.get(User, principal.user_id, with_for_update=True)
    assert user is not None  # noqa: S101 - authenticated account
    challenge = await session.scalar(
        select(SignInCode).where(SignInCode.id == challenge_id).with_for_update()
    )
    if (
        challenge is None
        or challenge.code_hash != expected
        or challenge.consumed_at
        or challenge.purpose != data.kind
        or challenge.user_id != principal.user_id
        or challenge.expires_at <= clock.now()
    ):
        raise ProblemError(CODE_EXPIRED)
    await check_address(session, data)
    if data.kind == "backup":
        old = await session.scalar(
            select(UserEmail).where(
                UserEmail.user_id == user.id, UserEmail.kind == "backup"
            )
        )
        if old is not None:
            await session.delete(old)
            await session.flush()
    address = UserEmail(
        user_id=user.id, email=data.email, kind=data.kind, verified_at=clock.now()
    )
    try:
        async with session.begin_nested():
            session.add(address)
            await session.flush()
    except IntegrityError:
        raise ProblemError(EMAIL_CONFLICT) from None
    challenge.consumed_at = clock.now()
    if data.kind == "corporate":
        await recalculate_account(session, user)
    await notify_account_security(session, user.id, locale=request_locale(request))
    return AddressOutput.model_validate(address)


@router.delete(
    "/{address_id}",
    status_code=204,
    responses={
        404: {"model": Problem, "description": "No such address of this account."}
    },
)
async def delete_address(
    address_id: UUID, request: Request, session: DbSession, principal: CurrentUser
) -> Response:
    user = await session.get(User, principal.user_id, with_for_update=True)
    assert user is not None  # noqa: S101 - authenticated account
    addresses = (
        await session.scalars(select(UserEmail).where(UserEmail.user_id == user.id))
    ).all()
    address = next((row for row in addresses if row.id == address_id), None)
    if address is None:
        raise ProblemError(EMAIL_NOT_FOUND)
    if (
        address.kind == "corporate"
        and sum(row.kind == "corporate" for row in addresses) == 1
    ):
        raise ProblemError(LAST_CORPORATE)
    await session.delete(address)
    await session.flush()
    if address.kind == "corporate":
        await recalculate_account(session, user)
    await notify_account_security(session, user.id, locale=request_locale(request))
    return Response(status_code=204)
