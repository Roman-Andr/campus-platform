"""E-mail code registration and sign-in; device-bound refresh rotation."""

import hashlib
import hmac
import secrets
from uuid import UUID

import jwt
from fastapi import Request, Response
from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator
from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.exc import IntegrityError

from campus.core import clock
from campus.core.config import Settings
from campus.core.i18n import N_, translate
from campus.core.mail import queue_email
from campus.core.web import (
    DbSession,
    Principal,
    Problem,
    ProblemError,
    ProblemType,
    api_router,
    request_locale,
)
from campus.core.web.auth import CurrentUser, digest, rate_limit, secret
from campus.modules.identity.consents import (
    current_documents,
    record_decision,
    require_registration_consents,
)
from campus.modules.identity.models import (
    RefreshToken,
    Session,
    SignInCode,
    User,
    UserEmail,
)
from campus.modules.identity.profile import UserOutput, check_name, user_output
from campus.modules.identity.sessions import revoke_sessions
from campus.modules.university import EmailDomain

EMAIL_CONFLICT = ProblemType("email_conflict", 409, N_("E-mail address already in use"))
CODE_INVALID = ProblemType("sign_in_code_invalid", 401, N_("Invalid sign-in code"))
CODE_EXPIRED = ProblemType(
    "sign_in_code_expired", 401, N_("Sign-in code expired or already used")
)
ATTEMPTS_EXCEEDED = ProblemType(
    "sign_in_code_attempts_exceeded", 401, N_("Sign-in attempts exceeded")
)
REGISTRATION_REQUIRED = ProblemType(
    "registration_required", 422, N_("First and last names are required")
)
REFRESH_INVALID = ProblemType("refresh_token_invalid", 401, N_("Invalid refresh token"))
MAIL_SUBJECT = N_("Your Campus sign-in code")
CONFIRM_SUBJECT = N_("Your Campus e-mail confirmation code")
CONFIRM_TEXT = N_(
    "Confirm your e-mail address with code: {code}. It expires in {minutes} minutes."
)
MAIL_TEXT = N_("Your sign-in code: {code}. It expires in {minutes} minutes.")
router = api_router(
    prefix="/auth",
    tags=["Authentication"],
    responses={
        401: {
            "model": Problem,
            "description": "Missing, invalid, expired or revoked credentials.",
        },
        429: {
            "model": Problem,
            "description": "Rate limit exceeded; Retry-After is in seconds.",
        },
    },
)


class EmailInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    email: EmailStr

    @field_validator("email")
    @classmethod
    def normalize_email(cls, value: str) -> str:
        return value.lower()


class SignInInput(EmailInput):
    accepted_document_ids: list[UUID] = Field(
        default_factory=list,
        description="Current document IDs explicitly accepted at registration; "
        "send cross-border consent separately in cross_border_document_id.",
    )
    cross_border_document_id: UUID | None = Field(
        default=None,
        description="Optional separate consent to this current "
        "cross-border document version.",
    )
    code: str = Field(pattern=r"^[0-9]{6}$")
    device_id: UUID
    device_name: str | None = Field(default=None, min_length=1, max_length=100)
    first_name: str | None = Field(default=None, min_length=1, max_length=100)
    last_name: str | None = Field(default=None, min_length=1, max_length=100)

    @field_validator("first_name", "last_name")
    @classmethod
    def validate_name(cls, value: str | None) -> str | None:
        return None if value is None else check_name(value)


class RefreshInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    refresh_token: str = Field(min_length=1, max_length=256)
    device_id: UUID


class Tokens(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"  # noqa: S105 - OAuth token type
    expires_in: int
    user: UserOutput


def token_hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


@router.post("/sign-in-codes", status_code=202)
async def request_sign_in_code(
    data: EmailInput, request: Request, session: DbSession
) -> None:
    await rate_limit(request, data.email)
    domain = await session.scalar(
        select(EmailDomain).where(EmailDomain.domain == data.email.rpartition("@")[2])
    )
    known = await session.scalar(
        select(UserEmail.id).where(UserEmail.email == data.email)
    )
    if domain is None and known is None:
        return
    await send_code(data.email, request, session)


async def send_code(
    email: str,
    request: Request,
    session: DbSession,
    *,
    purpose: str = "sign_in",
    user_id: UUID | None = None,
) -> None:
    settings: Settings = request.app.state.settings
    code = f"{secrets.randbelow(1_000_000):06d}"
    values = {
        "email": email,
        "purpose": purpose,
        "user_id": user_id,
        "code_hash": digest(settings, email + ":" + code),
        "expires_at": clock.now() + settings.sign_in_code_ttl,
        "attempts": 0,
        "consumed_at": None,
    }
    await session.execute(
        insert(SignInCode)
        .values(**values)
        .on_conflict_do_update(
            constraint="uq_identity_sign_in_code_email_purpose_user_id",
            set_={**values, "updated_at": clock.now()},
        )
    )
    locale = request_locale(request)
    queue_email(
        session,
        to=email,
        subject=translate(
            MAIL_SUBJECT if purpose == "sign_in" else CONFIRM_SUBJECT, locale
        ),
        text=translate(
            MAIL_TEXT if purpose == "sign_in" else CONFIRM_TEXT,
            locale,
            code=code,
            minutes=int(settings.sign_in_code_ttl.total_seconds() // 60),
        ),
    )


async def count_attempt(
    request: Request,
    email: str,
    *,
    purpose: str = "sign_in",
    user_id: UUID | None = None,
) -> tuple[UUID, str]:
    """Commit attempts even when the outer request transaction rolls back."""
    settings: Settings = request.app.state.settings
    async with request.app.state.session_factory() as session, session.begin():
        challenge = await session.scalar(
            select(SignInCode)
            .where(
                SignInCode.email == email,
                SignInCode.purpose == purpose,
                SignInCode.user_id == user_id,
            )
            .with_for_update()
        )
        if (
            challenge is None
            or challenge.purpose != purpose
            or challenge.user_id != user_id
            or challenge.consumed_at
            or challenge.expires_at <= clock.now()
        ):
            raise ProblemError(CODE_EXPIRED)
        if challenge.attempts >= settings.sign_in_code_max_attempts:
            raise ProblemError(ATTEMPTS_EXCEEDED)
        challenge.attempts += 1
        return challenge.id, challenge.code_hash


async def issue_tokens(
    session: DbSession, device: Session, user: User, settings: Settings
) -> Tokens:
    refresh = secrets.token_urlsafe(48)
    session.add(
        RefreshToken(
            session_id=device.id,
            token_hash=token_hash(refresh),
            expires_at=clock.now() + settings.refresh_token_ttl,
        )
    )
    access = jwt.encode(
        {
            "sub": str(user.id),
            "sid": str(device.id),
            "exp": clock.now() + settings.access_token_ttl,
        },
        secret(settings),
        algorithm="HS256",
    )
    return Tokens(
        access_token=access,
        refresh_token=refresh,
        expires_in=int(settings.access_token_ttl.total_seconds()),
        user=await user_output(session, user, settings),
    )


@router.post(
    "/sign-in",
    responses={409: {"model": Problem, "description": "Address claimed concurrently."}},
)
async def sign_in(data: SignInInput, request: Request, session: DbSession) -> Tokens:
    settings: Settings = request.app.state.settings
    await rate_limit(request)
    domain = await session.scalar(
        select(EmailDomain).where(EmailDomain.domain == data.email.rpartition("@")[2])
    )
    challenge_id, expected = await count_attempt(request, data.email)
    if not hmac.compare_digest(
        expected, digest(settings, data.email + ":" + data.code)
    ):
        raise ProblemError(CODE_INVALID)
    # The row lock serializes consumption, registration and device replacement.
    challenge = await session.scalar(
        select(SignInCode).where(SignInCode.id == challenge_id).with_for_update()
    )
    if (
        challenge is None
        or challenge.code_hash != expected
        or challenge.consumed_at
        or challenge.expires_at <= clock.now()
    ):
        raise ProblemError(CODE_EXPIRED)
    user = await session.scalar(
        select(User)
        .join(UserEmail, UserEmail.user_id == User.id)
        .where(UserEmail.email == data.email)
        .with_for_update(of=User)
    )
    registering = user is None
    if user is None:
        if domain is None:
            raise ProblemError(CODE_EXPIRED)
        if data.first_name is None or data.last_name is None:
            raise ProblemError(REGISTRATION_REQUIRED)
        await require_registration_consents(
            session, data.accepted_document_ids, data.cross_border_document_id
        )
        try:
            async with session.begin_nested():
                user = User(
                    email=data.email,
                    first_name=data.first_name,
                    last_name=data.last_name,
                    account_type=domain.account_type.value,
                )
                session.add(user)
                await session.flush()
                session.add(
                    UserEmail(
                        user_id=user.id,
                        email=data.email,
                        kind="corporate",
                        verified_at=clock.now(),
                    )
                )
                await session.flush()
        except IntegrityError:
            raise ProblemError(EMAIL_CONFLICT) from None
    challenge.consumed_at = clock.now()
    old_devices = (
        await session.scalars(
            select(Session)
            .where(
                Session.user_id == user.id,
                Session.device_id == data.device_id,
                Session.revoked_at.is_(None),
            )
            .with_for_update()
        )
    ).all()
    await revoke_sessions(request, session, old_devices)
    device = Session(
        user_id=user.id,
        device_id=data.device_id,
        device_name=data.device_name,
        platform=request.headers["X-Client-Platform"],
    )
    session.add(device)
    await session.flush()
    if registering:
        for document in await current_documents(session):
            if (
                document.id in data.accepted_document_ids
                or document.id == data.cross_border_document_id
            ):
                await record_decision(
                    session, Principal(user.id, device.id), document, accepted=True
                )
    return await issue_tokens(session, device, user, settings)


@router.post("/token/refresh")
async def refresh_tokens(
    data: RefreshInput, request: Request, session: DbSession
) -> Tokens:
    token = await session.scalar(
        select(RefreshToken).where(
            RefreshToken.token_hash == token_hash(data.refresh_token)
        )
    )
    if token is None:
        raise ProblemError(REFRESH_INVALID)
    # Lock the session before reloading the token: all descendants share
    # this lock, including concurrent refresh, sign-out and device sign-in.
    device = await session.scalar(
        select(Session).where(Session.id == token.session_id).with_for_update()
    )
    await session.refresh(token)
    if device is None or device.revoked_at:
        raise ProblemError(REFRESH_INVALID)
    if (
        token.used_at is not None
        or token.expires_at <= clock.now()
        or device.device_id != data.device_id
    ):
        session_id = device.id
        # Release the row lock and the failed idempotency claim first.
        # Revocation must survive the error response's transaction rollback.
        await session.rollback()
        async with (
            request.app.state.session_factory() as revocations,
            revocations.begin(),
        ):
            revoked = await revocations.scalar(
                select(Session).where(Session.id == session_id).with_for_update()
            )
            assert revoked is not None  # noqa: S101 - session exists
            await revoke_sessions(request, revocations, [revoked])
        raise ProblemError(REFRESH_INVALID)
    token.used_at = clock.now()
    device.updated_at = clock.now()
    user = await session.get(User, device.user_id)
    assert user is not None  # noqa: S101 - foreign key
    # Rotation and the idempotent response commit in one transaction.
    return await issue_tokens(session, device, user, request.app.state.settings)


@router.post("/sign-out", status_code=204)
async def sign_out(
    request: Request, session: DbSession, principal: CurrentUser
) -> Response:
    device = await session.scalar(
        select(Session).where(Session.id == principal.session_id).with_for_update()
    )
    if device is not None:
        await revoke_sessions(request, session, [device])
    return Response(status_code=204)
