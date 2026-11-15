"""Device signing keys and online QR confirmation endpoints."""

import math
from typing import Annotated
from uuid import UUID

from fastapi import Depends, Request, Response
from pydantic import BaseModel, ConfigDict, Field, field_validator
from pydantic_core import PydanticCustomError
from sqlalchemy import select

from campus.core import clock
from campus.core.web import (
    DbSession,
    Instant,
    Problem,
    ProblemError,
    api_router,
)
from campus.core.web.auth import UNAUTHORIZED, CurrentUser, Principal
from campus.core.web.problems import IdempotentProblemResponse, problem_from_error
from campus.modules.identity import Session
from campus.modules.listings import CompletionMethod, InteractionStatus
from campus.modules.reputation.models import DeviceKey
from campus.modules.reputation.service import (
    CODE_CONFIRM_PROBLEMS,
    QR_ALGORITHM,
    CodeIssue,
    CodeResult,
    QrResult,
    base64url_encode,
    confirm_with_code,
    confirm_with_offline_qr,
    confirm_with_qr,
    issue_confirmation_code,
    public_key_bytes,
    register_device_key,
    revoke_device_key,
)

device_router = api_router(
    prefix="/me/device-key",
    tags=["Device keys"],
    responses={
        401: {"model": Problem},
        409: {"model": Problem},
        422: {"model": Problem},
    },
)
qr_router = api_router(
    prefix="/listings/{listing_id}/interactions/{interaction_id}/qr",
    tags=["QR"],
    responses={
        401: {"model": Problem},
        403: {"model": Problem},
        404: {"model": Problem},
        409: {"model": Problem},
        422: {"model": Problem},
    },
)
code_router = api_router(
    prefix="/listings/{listing_id}/interactions/{interaction_id}/code",
    tags=["Confirmation code"],
    responses={
        401: {"model": Problem},
        403: {"model": Problem},
        404: {"model": Problem},
        409: {"model": Problem},
        422: {"model": Problem},
        429: {"model": Problem},
    },
)
time_router = api_router(prefix="/time", tags=["Server time"])


async def active_session(session: DbSession, principal: CurrentUser) -> Principal:
    """Reject a revoked device session, not only a revoked access token.

    Blocking an account revokes its sessions (#93), so this also stops a
    blocked user from replacing a key or confirming a meeting.
    """
    device = await session.scalar(
        select(Session).where(Session.id == principal.session_id).with_for_update()
    )
    if (
        device is None
        or device.user_id != principal.user_id
        or device.revoked_at is not None
    ):
        raise ProblemError(UNAUTHORIZED, headers={"WWW-Authenticate": "Bearer"})
    return principal


ActiveSession = Annotated[Principal, Depends(active_session)]


class DeviceKeyInput(BaseModel):
    """The public half of a device-generated Ed25519 key pair."""

    model_config = ConfigDict(extra="forbid")

    public_key: str = Field(
        min_length=40,
        max_length=64,
        description=(
            "Base64url-encoded 32-byte Ed25519 public key. The private key is"
            " generated and kept on the device and is never sent to the server."
        ),
    )

    @field_validator("public_key")
    @classmethod
    def valid_public_key(cls, value: str) -> str:
        try:
            raw = public_key_bytes(value)
        except ValueError:
            raise PydanticCustomError(
                "ed25519_public_key",
                "Use an unpadded base64url-encoded 32-byte Ed25519 public key.",
            ) from None
        return base64url_encode(raw)


class DeviceKeyOutput(BaseModel):
    """A registered key; it never contains private material."""

    model_config = ConfigDict(from_attributes=True)

    id: UUID
    algorithm: str = Field(default=QR_ALGORITHM, description="Always 'ed25519'.")
    public_key: str = Field(description="Base64url-encoded Ed25519 public key.")
    registered_at: Instant
    revoked_at: Instant | None


class QrScanInput(BaseModel):
    """A scanned online QR code and its detached signature."""

    model_config = ConfigDict(extra="forbid")

    payload: str = Field(
        max_length=4096,
        description=(
            "Base64url-encoded UTF-8 JSON with v=1, listing_id, interaction_id,"
            " presenter_id, key_id, issued_at and nonce."
        ),
    )
    signature: str = Field(
        max_length=256,
        description=(
            "Base64url-encoded 64-byte Ed25519 signature of the decoded payload"
            " bytes, made by the showing device."
        ),
    )


class QrScanOutput(BaseModel):
    """The interaction after a successful or replayed QR scan."""

    listing_id: UUID
    interaction_id: UUID
    presenter_id: UUID
    scanner_id: UUID
    status: InteractionStatus
    completed: bool
    completed_at: Instant | None
    completion_method: CompletionMethod | None
    rating_weight: float | None
    nonce: UUID
    issued_at: Instant
    received_at: Instant
    server_time: Instant = Field(
        description="Current server time, so the client can correct its clock."
    )


class OfflineQrScanInput(BaseModel):
    """A stored offline QR code and its detached signature."""

    model_config = ConfigDict(extra="forbid")

    payload: str = Field(
        max_length=4096,
        description=(
            "Base64url-encoded UTF-8 JSON with v=2, confirmation_id,"
            " listing_id, interaction_id, presenter_id, key_id, issued_at"
            " and nonce. The private key never leaves the showing device."
        ),
    )
    signature: str = Field(
        max_length=256,
        description=(
            "Base64url-encoded 64-byte Ed25519 signature of the decoded payload"
            " bytes, made by the showing device."
        ),
    )


class OfflineQrScanOutput(BaseModel):
    """The interaction after a delayed offline QR confirmation."""

    listing_id: UUID
    interaction_id: UUID
    confirmation_id: UUID
    presenter_id: UUID
    scanner_id: UUID
    mode: str = Field(default="offline", description="Always 'offline'.")
    status: InteractionStatus
    completed: bool
    completed_at: Instant | None
    completion_method: CompletionMethod | None
    rating_weight: float | None
    nonce: UUID
    issued_at: Instant
    received_at: Instant
    replayed: bool = Field(
        description=(
            "True when the same confirmation_id was already stored and the"
            " original result is returned without a second effect."
        )
    )
    server_time: Instant = Field(
        description="Current server time, so the client can correct its clock."
    )


class CodeIssueOutput(BaseModel):
    """A freshly issued code; only its requester receives the plaintext."""

    listing_id: UUID
    interaction_id: UUID
    presenter_id: UUID
    code: str = Field(
        min_length=6,
        max_length=6,
        pattern=r"^[0-9]{6}$",
        description="Exactly six digits, including leading zeroes.",
    )
    issued_at: Instant
    expires_at: Instant
    attempts_left: int = Field(
        ge=0, description="Incorrect attempts remaining for this interaction."
    )
    server_time: Instant


class CodeConfirmInput(BaseModel):
    """The six-digit code entered by the second participant."""

    model_config = ConfigDict(extra="forbid")

    code: str = Field(
        min_length=6,
        max_length=6,
        pattern=r"^[0-9]{6}$",
        description="Exactly six digits, including leading zeroes.",
    )


class CodeConfirmOutput(BaseModel):
    """The interaction after a successful or replayed code confirmation."""

    listing_id: UUID
    interaction_id: UUID
    presenter_id: UUID
    scanner_id: UUID
    status: InteractionStatus
    completed: bool
    completed_at: Instant | None
    completion_method: CompletionMethod | None
    rating_weight: float | None
    server_time: Instant


class ServerTimeOutput(BaseModel):
    """Server time and the QR timing parameters."""

    now: Instant
    qr_online_ttl: int = Field(
        ge=1, description="Maximum age of an online QR code, in seconds."
    )
    qr_offline_ttl: int = Field(
        ge=1, description="Maximum accepted age of an offline QR code, in seconds."
    )
    qr_clock_skew: int = Field(
        ge=0, description="Accepted clock skew into the future, in seconds."
    )


def code_issue_output(result: CodeIssue, now: Instant) -> CodeIssueOutput:
    return CodeIssueOutput(
        listing_id=result.interaction.listing_id,
        interaction_id=result.interaction.id,
        presenter_id=result.presenter_id,
        code=result.code,
        issued_at=result.issued_at,
        expires_at=result.expires_at,
        attempts_left=result.attempts_left,
        server_time=now,
    )


def code_result_output(result: CodeResult, now: Instant) -> CodeConfirmOutput:
    interaction = result.interaction
    status = InteractionStatus(interaction.status)
    method = (
        CompletionMethod(interaction.completion_method)
        if interaction.completion_method is not None
        else None
    )
    return CodeConfirmOutput(
        listing_id=interaction.listing_id,
        interaction_id=interaction.id,
        presenter_id=result.presenter_id,
        scanner_id=result.scanner_id,
        status=status,
        completed=status == InteractionStatus.COMPLETED,
        completed_at=interaction.completed_at,
        completion_method=method,
        rating_weight=interaction.completion_weight,
        server_time=now,
    )


def device_key_output(key: DeviceKey) -> DeviceKeyOutput:
    return DeviceKeyOutput(
        id=key.id,
        public_key=base64url_encode(bytes(key.public_key)),
        registered_at=key.created_at,
        revoked_at=key.revoked_at,
    )


def qr_scan_output(result: QrResult, now: Instant) -> QrScanOutput:
    interaction = result.interaction
    status = InteractionStatus(interaction.status)
    method = (
        CompletionMethod(interaction.completion_method)
        if interaction.completion_method is not None
        else None
    )
    return QrScanOutput(
        listing_id=interaction.listing_id,
        interaction_id=interaction.id,
        presenter_id=result.presenter_id,
        scanner_id=result.scanner_id,
        status=status,
        completed=status == InteractionStatus.COMPLETED,
        completed_at=interaction.completed_at,
        completion_method=method,
        rating_weight=interaction.completion_weight,
        nonce=result.nonce,
        issued_at=result.issued_at,
        received_at=result.received_at,
        server_time=now,
    )


def offline_qr_scan_output(result: QrResult, now: Instant) -> OfflineQrScanOutput:
    interaction = result.interaction
    status = InteractionStatus(interaction.status)
    method = (
        CompletionMethod(interaction.completion_method)
        if interaction.completion_method is not None
        else None
    )
    if result.confirmation_id is None:  # pragma: no cover - offline always has one
        raise RuntimeError("offline QR result without a confirmation id")
    return OfflineQrScanOutput(
        listing_id=interaction.listing_id,
        interaction_id=interaction.id,
        confirmation_id=result.confirmation_id,
        presenter_id=result.presenter_id,
        scanner_id=result.scanner_id,
        status=status,
        completed=status == InteractionStatus.COMPLETED,
        completed_at=interaction.completed_at,
        completion_method=method,
        rating_weight=interaction.completion_weight,
        nonce=result.nonce,
        issued_at=result.issued_at,
        received_at=result.received_at,
        replayed=result.replayed,
        server_time=now,
    )


@device_router.put("")
async def register_key(
    data: DeviceKeyInput,
    session: DbSession,
    principal: ActiveSession,
) -> DeviceKeyOutput:
    """Register or replace this device session's Ed25519 public key.

    A different key for the same device revokes the previous key, including
    keys of older sessions of that device. The private key never reaches the
    API.
    """
    key = await register_device_key(
        session,
        principal.user_id,
        principal.session_id,
        public_key_bytes(data.public_key),
    )
    return device_key_output(key)


@device_router.delete("", status_code=204)
async def revoke_key(session: DbSession, principal: ActiveSession) -> Response:
    """Revoke this device session's active key; repeating it is harmless."""
    await revoke_device_key(session, principal.session_id)
    return Response(status_code=204)


@qr_router.post("")
async def scan_qr(  # noqa: PLR0913, PLR0917 - request parts
    listing_id: UUID,
    interaction_id: UUID,
    data: QrScanInput,
    request: Request,
    session: DbSession,
    principal: ActiveSession,
) -> QrScanOutput:
    """Confirm an accepted interaction with a scanned online QR code.

    The signed payload names the interaction, the showing participant, the
    device key, the issue time and a one-time nonce. The authenticated
    scanner must be the other participant. The server accepts a code whose
    receipt time differs from its issue time by -10 to +30 seconds inclusive.
    """
    now = clock.now()
    result = await confirm_with_qr(
        session,
        listing_id,
        interaction_id,
        principal.user_id,
        data.payload,
        data.signature,
        request.app.state.settings,
    )
    return qr_scan_output(result, now)


@qr_router.post("/offline")
async def scan_offline_qr(  # noqa: PLR0913, PLR0917 - request parts
    listing_id: UUID,
    interaction_id: UUID,
    data: OfflineQrScanInput,
    request: Request,
    session: DbSession,
    principal: ActiveSession,
) -> OfflineQrScanOutput:
    """Confirm an accepted interaction with a code stored while offline.

    The showing device signs the version 2 payload once and keeps it; the
    scanning device may deliver it later. The server accepts it when the
    Ed25519 signature is valid for the key that existed at ``issued_at``,
    the interaction was already accepted, ``issued_at`` is not later than
    the receipt and the code is at most 24 hours old. The device-generated
    ``confirmation_id`` makes a retry after the Idempotency-Key expiry
    return the stored result; an altered payload with the same id conflicts.
    """
    now = clock.now()
    result = await confirm_with_offline_qr(
        session,
        listing_id,
        interaction_id,
        principal.user_id,
        data.payload,
        data.signature,
        request.app.state.settings,
    )
    return offline_qr_scan_output(result, now)


@code_router.post("")
async def issue_code(  # noqa: PLR0913, PLR0917 - request parts
    listing_id: UUID,
    interaction_id: UUID,
    request: Request,
    response: Response,
    session: DbSession,
    principal: ActiveSession,
) -> CodeIssueOutput:
    """Issue a six-digit code for this participant to show to the other one.

    The code has six decimal digits (leading zeroes included), lives for the
    configured 30 seconds and carries the cumulative limit of incorrect
    entries. Reissuing replaces the code but never resets that limit.
    """
    now = clock.now()
    result = await issue_confirmation_code(
        session,
        listing_id,
        interaction_id,
        principal.user_id,
        request.app.state.settings,
    )
    response.headers["Cache-Control"] = "no-store"
    return code_issue_output(result, now)


@code_router.post("/confirm")
async def confirm_code(  # noqa: PLR0913, PLR0917 - request parts
    listing_id: UUID,
    interaction_id: UUID,
    data: CodeConfirmInput,
    request: Request,
    response: Response,
    session: DbSession,
    principal: ActiveSession,
) -> CodeConfirmOutput:
    """Complete an accepted interaction with the other participant's code.

    The server checks the code against a keyed hash and increments the
    counter in the request transaction. A wrong entry is returned as an
    idempotent 4xx response, so a retry with the same key neither changes
    the counter nor opens a second database transaction. A successful
    completion updates the interaction, its journal event and its outbox
    message atomically; the code response never contains the plaintext.
    """
    now = clock.now()
    try:
        result = await confirm_with_code(
            session,
            listing_id,
            interaction_id,
            principal.user_id,
            data.code,
            request.app.state.settings,
        )
    except ProblemError as exc:
        if exc.problem_type not in CODE_CONFIRM_PROBLEMS:
            raise
        return problem_from_error(  # type: ignore[return-value]
            request,
            exc,
            response_class=IdempotentProblemResponse,
        )
    response.headers["Cache-Control"] = "no-store"
    return code_result_output(result, now)


@time_router.get("")
async def server_time(request: Request) -> ServerTimeOutput:
    """Current server time and the online QR timing parameters.

    Clients use this to correct their local clock before signing a QR code.
    """
    settings = request.app.state.settings
    return ServerTimeOutput(
        now=clock.now(),
        qr_online_ttl=max(1, math.ceil(settings.qr_online_ttl.total_seconds())),
        qr_offline_ttl=max(1, math.ceil(settings.qr_offline_ttl.total_seconds())),
        qr_clock_skew=max(0, math.ceil(settings.qr_clock_skew.total_seconds())),
    )
