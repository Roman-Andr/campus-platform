"""Ed25519 device keys and online QR confirmation of an interaction."""

import base64
import binascii
import hmac
import json
import re
import secrets
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Literal
from uuid import UUID

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
from pydantic import BaseModel, ConfigDict, Field, ValidationError
from sqlalchemy import select, update
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from campus.core import clock
from campus.core.config import Settings
from campus.core.i18n import N_
from campus.core.web import Instant, ProblemError, ProblemType
from campus.core.web.auth import digest
from campus.core.web.problems import NOT_FOUND
from campus.modules.identity import Session
from campus.modules.listings import (
    CompletionMethod,
    Interaction,
    InteractionStatus,
    Listing,
    locked,
    transition,
)
from campus.modules.reputation.models import ConfirmationCode, DeviceKey, QrScan

# These are the scenarios that are completed by meeting a person. Events,
# group purchases and publications use other workflows, and a loan needs a
# separate return stage rather than the final completion.
QR_COMPLETION_KINDS = frozenset({"giveaway", "exchange", "skill", "help"})
QR_ALGORITHM = "ed25519"
PUBLIC_KEY_SIZE = 32
SIGNATURE_SIZE = 64
CONFIRMATION_CODE_LENGTH = 6

QR_PAYLOAD_INVALID = ProblemType(
    "qr_payload_invalid",
    422,
    N_("QR code rejected"),
    N_("The QR code payload is malformed or does not match the request."),
)
QR_SIGNATURE_INVALID = ProblemType(
    "qr_signature_invalid",
    422,
    N_("QR code rejected"),
    N_("The QR code signature is invalid."),
)
QR_KEY_INVALID = ProblemType(
    "qr_key_invalid",
    403,
    N_("QR code rejected"),
    N_("The device key is unknown, revoked or belongs to another user."),
)
QR_NOT_PARTICIPANT = ProblemType(
    "qr_not_participant",
    403,
    N_("Forbidden"),
    N_("Only the two participants of the interaction can confirm it."),
)
QR_SAME_PARTICIPANT = ProblemType(
    "qr_same_participant",
    403,
    N_("Forbidden"),
    N_("The same participant cannot show and scan the same QR code."),
)
QR_NOT_ACCEPTED = ProblemType(
    "qr_not_accepted",
    409,
    N_("QR code cannot be used"),
    N_("The interaction is not accepted and cannot be completed."),
)
QR_EXPIRED = ProblemType(
    "qr_expired",
    409,
    N_("QR code expired"),
    N_("The online QR code is older than the allowed lifetime."),
)
QR_NOT_YET_VALID = ProblemType(
    "qr_not_yet_valid",
    409,
    N_("QR code is from the future"),
    N_("The QR code time is ahead of the server clock by too much."),
)
QR_NONCE_REUSED = ProblemType(
    "qr_nonce_reused",
    409,
    N_("QR code already used"),
    N_("This one-time QR code has already been used."),
)
QR_ALREADY_COMPLETED = ProblemType(
    "qr_already_completed",
    409,
    N_("Interaction already completed"),
    N_("The interaction was completed by another method."),
)
QR_UNAVAILABLE = ProblemType(
    "qr_unavailable",
    409,
    N_("QR confirmation is unavailable"),
    N_("This type of interaction is not completed with an online QR code."),
)
QR_STAGE_UNAVAILABLE = ProblemType(
    "qr_stage_unavailable",
    409,
    N_("QR code cannot complete this stage"),
    N_(
        "Confirm the current scenario stage by its own action; an online QR"
        " code completes only the final meeting."
    ),
)
DEVICE_KEY_CONFLICT = ProblemType(
    "device_key_conflict",
    409,
    N_("Device key conflict"),
    N_("This public key is already registered to another device session."),
)
CODE_INVALID = ProblemType(
    "confirmation_code_invalid",
    422,
    N_("Confirmation code rejected"),
    N_("The six-digit confirmation code is invalid."),
)
CODE_EXPIRED = ProblemType(
    "confirmation_code_expired",
    409,
    N_("Confirmation code expired"),
    N_("The six-digit confirmation code has expired; request a new one."),
)
CODE_ATTEMPTS_EXCEEDED = ProblemType(
    "confirmation_code_attempts_exceeded",
    429,
    N_("Confirmation code attempts exceeded"),
    N_("This interaction has no confirmation-code attempts left."),
)
CODE_NOT_PARTICIPANT = ProblemType(
    "confirmation_code_not_participant",
    403,
    N_("Forbidden"),
    N_("Only the two participants of the interaction can use its code."),
)
CODE_SAME_PARTICIPANT = ProblemType(
    "confirmation_code_same_participant",
    403,
    N_("Forbidden"),
    N_("The same participant cannot issue and enter the same code."),
)
CODE_NOT_ACCEPTED = ProblemType(
    "confirmation_code_not_accepted",
    409,
    N_("Confirmation code cannot be used"),
    N_("The interaction is not accepted and cannot be completed."),
)
CODE_ALREADY_COMPLETED = ProblemType(
    "confirmation_code_already_completed",
    409,
    N_("Interaction already completed"),
    N_("The interaction was completed by another method."),
)
CODE_UNAVAILABLE = ProblemType(
    "confirmation_code_unavailable",
    409,
    N_("Confirmation code is unavailable"),
    N_("This type of interaction is not completed with a confirmation code."),
)
CODE_STAGE_UNAVAILABLE = ProblemType(
    "confirmation_code_stage_unavailable",
    409,
    N_("Confirmation code cannot complete this stage"),
    N_(
        "Confirm the current scenario stage by its own action; a confirmation"
        " code completes only the final meeting."
    ),
)

_BASE64URL = re.compile(r"[A-Za-z0-9_-]+={0,2}")


def base64url_encode(value: bytes) -> str:
    """Encode bytes for JSON without padding."""
    return base64.urlsafe_b64encode(value).decode().rstrip("=")


def base64url_decode(value: str, *, maximum: int = 4096) -> bytes:
    """Decode strict, unpadded (or padded) base64url; raise ``ValueError``."""
    if not value or len(value) > maximum or _BASE64URL.fullmatch(value) is None:
        raise ValueError
    unpadded = value.rstrip("=")
    padding = "=" * (-len(unpadded) % 4)
    try:
        return base64.urlsafe_b64decode(unpadded + padding)
    except binascii.Error, ValueError:
        raise ValueError from None


def public_key_bytes(value: str) -> bytes:
    """Decode and validate an Ed25519 public key supplied by a client."""
    try:
        raw = base64url_decode(value, maximum=128)
        if len(raw) != PUBLIC_KEY_SIZE:
            raise ValueError
        _ = Ed25519PublicKey.from_public_bytes(raw)
    except ValueError:
        raise ValueError("invalid Ed25519 public key") from None
    return raw


class QrPayload(BaseModel):
    """The JSON document signed by the showing device.

    ``version`` is ``1`` for online codes. The signature covers the exact
    UTF-8 bytes of this document, so any field change invalidates it.
    """

    model_config = ConfigDict(extra="forbid")

    version: Literal[1] = Field(alias="v")
    listing_id: UUID
    interaction_id: UUID
    presenter_id: UUID
    key_id: UUID
    issued_at: Instant
    nonce: UUID


@dataclass(frozen=True)
class QrResult:
    """The completed interaction and the stored scan when one was created."""

    interaction: Interaction
    scan: QrScan | None
    presenter_id: UUID
    scanner_id: UUID
    nonce: UUID
    issued_at: datetime
    received_at: datetime


@dataclass(frozen=True)
class CodeIssue:
    """A freshly issued six-digit code; the only place its plaintext exists."""

    interaction: Interaction
    presenter_id: UUID
    code: str
    issued_at: datetime
    expires_at: datetime
    attempts_left: int


@dataclass(frozen=True)
class CodeResult:
    """The interaction after a code was entered."""

    interaction: Interaction
    presenter_id: UUID
    scanner_id: UUID
    received_at: datetime


@dataclass(frozen=True)
class CodeCheck:
    """The locked code row and the outcome of one verification attempt."""

    id: UUID
    presenter_id: UUID
    matched: bool
    attempts_left: int


def decode_payload(encoded: str) -> tuple[bytes, QrPayload]:
    """Decode and validate the signed payload, keeping its exact bytes."""
    try:
        raw = base64url_decode(encoded)
        document: Any = json.loads(raw)
        payload = QrPayload.model_validate(document)
    except ValueError, UnicodeDecodeError, json.JSONDecodeError, ValidationError:
        raise ProblemError(QR_PAYLOAD_INVALID) from None
    return raw, payload


def verify_signature(key: DeviceKey, raw: bytes, encoded: str) -> None:
    """Verify an Ed25519 signature over the raw payload bytes."""
    try:
        signature = base64url_decode(encoded, maximum=256)
        if len(signature) != SIGNATURE_SIZE:
            raise ValueError
        Ed25519PublicKey.from_public_bytes(bytes(key.public_key)).verify(signature, raw)
    except InvalidSignature, ValueError:
        raise ProblemError(QR_SIGNATURE_INVALID) from None


async def active_signing_key(session: AsyncSession, payload: QrPayload) -> DeviceKey:
    """Lock and return the payload's active key of an active session.

    The row lock serializes verification with key replacement and
    revocation. The session itself must still be active: blocking an account
    revokes its sessions, so it also closes QR confirmation.
    """
    key = await session.scalar(
        select(DeviceKey).where(DeviceKey.id == payload.key_id).with_for_update()
    )
    if key is None or key.user_id != payload.presenter_id or key.revoked_at is not None:
        raise ProblemError(QR_KEY_INVALID)
    device = await session.get(Session, key.session_id)
    if device is None or device.user_id != key.user_id or device.revoked_at is not None:
        raise ProblemError(QR_KEY_INVALID)
    return key


async def register_device_key(
    session: AsyncSession, user_id: UUID, session_id: UUID, public_key: bytes
) -> DeviceKey:
    """Register a key for the current session and revoke older device keys.

    One active key per session is enforced by a partial unique index. A new
    registration for the same device (reinstall or sign-in recovery) also
    revokes keys of its other sessions, so an old installation cannot keep
    showing valid codes after the device is re-registered.
    """
    now = clock.now()
    current = await session.scalar(
        select(DeviceKey)
        .where(
            DeviceKey.session_id == session_id,
            DeviceKey.revoked_at.is_(None),
        )
        .with_for_update()
    )
    if current is not None and bytes(current.public_key) == public_key:
        return current

    existing = await session.scalar(
        select(DeviceKey).where(DeviceKey.public_key == public_key)
    )
    if existing is not None:
        if (
            existing.user_id == user_id
            and existing.session_id == session_id
            and existing.revoked_at is None
        ):
            return existing
        raise ProblemError(DEVICE_KEY_CONFLICT)

    if current is not None:
        current.revoked_at = now

    device = await session.get(Session, session_id)
    if device is not None:
        siblings = select(Session.id).where(
            Session.user_id == user_id,
            Session.device_id == device.device_id,
        )
        await session.execute(
            update(DeviceKey)
            .where(
                DeviceKey.user_id == user_id,
                DeviceKey.revoked_at.is_(None),
                DeviceKey.session_id.in_(siblings),
            )
            .values(revoked_at=now, updated_at=now)
            .execution_options(synchronize_session="fetch")
        )

    key_id = await session.scalar(
        insert(DeviceKey)
        .values(
            user_id=user_id,
            session_id=session_id,
            public_key=public_key,
            revoked_at=None,
            created_at=now,
            updated_at=now,
        )
        .on_conflict_do_nothing(index_elements=["public_key"])
        .returning(DeviceKey.id)
    )
    if key_id is None:
        raise ProblemError(DEVICE_KEY_CONFLICT)
    key = await session.get(DeviceKey, key_id)
    if key is None:  # pragma: no cover - the insert just returned this id
        raise RuntimeError("registered device key disappeared")
    return key


async def revoke_device_key(session: AsyncSession, session_id: UUID) -> None:
    """Revoke the current session's active key; repeated calls are no-ops."""
    key = await session.scalar(
        select(DeviceKey)
        .where(
            DeviceKey.session_id == session_id,
            DeviceKey.revoked_at.is_(None),
        )
        .with_for_update()
    )
    if key is not None:
        key.revoked_at = clock.now()


def _two_participants(
    listing: Listing, interaction: Interaction, presenter_id: UUID, scanner_id: UUID
) -> None:
    author_id = listing.author_id
    participant_id = interaction.participant_id
    if author_id == participant_id:
        raise ProblemError(QR_NOT_PARTICIPANT)
    if scanner_id not in (author_id, participant_id):
        raise ProblemError(QR_NOT_PARTICIPANT)
    if presenter_id not in (author_id, participant_id):
        raise ProblemError(QR_NOT_PARTICIPANT)
    if presenter_id == scanner_id:
        raise ProblemError(QR_SAME_PARTICIPANT)


def _check_time(payload: QrPayload, settings: Settings) -> datetime:
    """Accept ``-clock_skew <= now - issued_at <= ttl``, bounds included."""
    now = clock.now()
    delta = now - payload.issued_at
    if delta > settings.qr_online_ttl:
        raise ProblemError(QR_EXPIRED)
    if delta < -settings.qr_clock_skew:
        raise ProblemError(QR_NOT_YET_VALID)
    return now


async def _load_interaction(
    session: AsyncSession, listing_id: UUID, interaction_id: UUID
) -> tuple[Listing, Interaction]:
    listing = await locked(session, listing_id)
    # The listing row lock serializes every interaction mutation; FOR UPDATE
    # on the interaction would hit the nullable side of its eager joins.
    interaction = await session.scalar(
        select(Interaction).where(Interaction.id == interaction_id)
    )
    if interaction is None or interaction.listing_id != listing.id:
        raise ProblemError(NOT_FOUND)
    return listing, interaction


async def _existing_scan(session: AsyncSession, nonce: UUID) -> QrScan | None:
    return await session.scalar(select(QrScan).where(QrScan.nonce == nonce))


def _participant_pair(listing: Listing, interaction: Interaction) -> tuple[UUID, UUID]:
    """Return the author and participant of a valid two-person interaction."""
    author_id = listing.author_id
    participant_id = interaction.participant_id
    if author_id == participant_id:
        raise ProblemError(CODE_NOT_PARTICIPANT)
    return author_id, participant_id


def _code_digest(settings: Settings, interaction_id: UUID, code: str) -> str:
    """Keyed hash of a code; the database never stores the plaintext."""
    return digest(settings, f"confirmation-code:{interaction_id}:{code}")


def _new_code() -> str:
    """Generate exactly six decimal digits, preserving leading zeroes."""
    upper = 10**CONFIRMATION_CODE_LENGTH
    return f"{secrets.randbelow(upper):0{CONFIRMATION_CODE_LENGTH}d}"


async def issue_confirmation_code(
    session: AsyncSession,
    listing_id: UUID,
    interaction_id: UUID,
    presenter_id: UUID,
    settings: Settings,
) -> CodeIssue:
    """Issue or reissue the current six-digit code of an interaction.

    The code row is locked with the listing, so two requests cannot issue
    different valid codes at once. Reissue keeps the cumulative number of
    incorrect attempts: requesting a new code never resets the limit.
    """
    listing, interaction = await _load_interaction(session, listing_id, interaction_id)
    author_id, participant_id = _participant_pair(listing, interaction)
    if presenter_id not in (author_id, participant_id):
        raise ProblemError(CODE_NOT_PARTICIPANT)
    if listing.kind not in QR_COMPLETION_KINDS:
        raise ProblemError(CODE_UNAVAILABLE)
    if interaction.stage is not None:
        raise ProblemError(CODE_STAGE_UNAVAILABLE)
    status = InteractionStatus(interaction.status)
    if status == InteractionStatus.COMPLETED:
        raise ProblemError(CODE_ALREADY_COMPLETED)
    if status != InteractionStatus.ACCEPTED:
        raise ProblemError(CODE_NOT_ACCEPTED)

    now = clock.now()
    code = _new_code()
    expires_at = now + settings.confirmation_code_ttl
    row = await session.scalar(
        select(ConfirmationCode)
        .where(ConfirmationCode.interaction_id == interaction.id)
        .with_for_update()
    )
    if row is None:
        row = ConfirmationCode(
            listing_id=listing.id,
            interaction_id=interaction.id,
            presenter_id=presenter_id,
            code_hash=_code_digest(settings, interaction.id, code),
            issued_at=now,
            expires_at=expires_at,
            attempts=0,
            consumed_at=None,
            created_at=now,
            updated_at=now,
        )
        session.add(row)
        attempts = 0
    else:
        if row.consumed_at is not None:
            raise ProblemError(CODE_INVALID)
        if row.attempts >= settings.confirmation_code_max_attempts:
            raise ProblemError(CODE_ATTEMPTS_EXCEEDED)
        attempts = row.attempts
        row.presenter_id = presenter_id
        row.code_hash = _code_digest(settings, interaction.id, code)
        row.issued_at = now
        row.expires_at = expires_at
        row.consumed_at = None
        row.updated_at = now

    return CodeIssue(
        interaction=interaction,
        presenter_id=presenter_id,
        code=code,
        issued_at=now,
        expires_at=expires_at,
        attempts_left=max(0, settings.confirmation_code_max_attempts - attempts),
    )


async def _check_code_attempt(  # noqa: PLR0913, PLR0917 - request parts
    session_factory: async_sessionmaker[AsyncSession],
    settings: Settings,
    interaction_id: UUID,
    code: str,
    scanner_id: UUID,
    author_id: UUID,
    participant_id: UUID,
) -> CodeCheck:
    """Check and, on mismatch, count an attempt in its own transaction.

    A failed request rolls the outer transaction back, so the counter would
    disappear with it. This short transaction commits the increment even
    when the endpoint then returns an error. The listing row is already
    locked, so attempts and redemption for one interaction are serialized.
    """
    now = clock.now()
    expected = _code_digest(settings, interaction_id, code)
    async with session_factory() as check_session, check_session.begin():
        row = await check_session.scalar(
            select(ConfirmationCode)
            .where(ConfirmationCode.interaction_id == interaction_id)
            .with_for_update()
        )
        if row is None or row.consumed_at is not None:
            raise ProblemError(CODE_INVALID)
        if row.presenter_id not in (author_id, participant_id):
            raise ProblemError(CODE_INVALID)
        if row.presenter_id == scanner_id:
            raise ProblemError(CODE_SAME_PARTICIPANT)
        if row.expires_at <= now:
            raise ProblemError(CODE_EXPIRED)
        if row.attempts >= settings.confirmation_code_max_attempts:
            raise ProblemError(CODE_ATTEMPTS_EXCEEDED)
        if hmac.compare_digest(row.code_hash, expected):
            return CodeCheck(
                id=row.id,
                presenter_id=row.presenter_id,
                matched=True,
                attempts_left=settings.confirmation_code_max_attempts - row.attempts,
            )
        row.attempts += 1
        row.updated_at = now
        return CodeCheck(
            id=row.id,
            presenter_id=row.presenter_id,
            matched=False,
            attempts_left=settings.confirmation_code_max_attempts - row.attempts,
        )


async def confirm_with_code(  # noqa: PLR0913, PLR0917 - request parts
    session: AsyncSession,
    session_factory: async_sessionmaker[AsyncSession],
    listing_id: UUID,
    interaction_id: UUID,
    scanner_id: UUID,
    code: str,
    settings: Settings,
) -> CodeResult:
    """Check and atomically apply a six-digit confirmation code.

    The listing lock serializes this request with QR scans, cancellation
    and reissue. A wrong code is counted in a separate committed
    transaction; the successful interaction update, its journal event and
    its outbox message commit together, and the code is consumed only then.
    """
    if (
        len(code) != CONFIRMATION_CODE_LENGTH
        or not code.isascii()
        or not code.isdigit()
    ):
        raise ProblemError(CODE_INVALID)
    listing, interaction = await _load_interaction(session, listing_id, interaction_id)
    author_id, participant_id = _participant_pair(listing, interaction)
    if scanner_id not in (author_id, participant_id):
        raise ProblemError(CODE_NOT_PARTICIPANT)
    if listing.kind not in QR_COMPLETION_KINDS:
        raise ProblemError(CODE_UNAVAILABLE)
    if interaction.stage is not None:
        raise ProblemError(CODE_STAGE_UNAVAILABLE)
    status = InteractionStatus(interaction.status)
    if status == InteractionStatus.COMPLETED:
        if interaction.completion_method == CompletionMethod.QR.value:
            presenter_id = participant_id if scanner_id == author_id else author_id
            return CodeResult(
                interaction=interaction,
                presenter_id=presenter_id,
                scanner_id=scanner_id,
                received_at=clock.now(),
            )
        raise ProblemError(CODE_ALREADY_COMPLETED)
    if status != InteractionStatus.ACCEPTED:
        raise ProblemError(CODE_NOT_ACCEPTED)

    checked = await _check_code_attempt(
        session_factory,
        settings,
        interaction.id,
        code,
        scanner_id,
        author_id,
        participant_id,
    )
    if not checked.matched:
        if checked.attempts_left <= 0:
            raise ProblemError(CODE_ATTEMPTS_EXCEEDED)
        raise ProblemError(CODE_INVALID)

    now = clock.now()
    await session.execute(
        update(ConfirmationCode)
        .where(ConfirmationCode.id == checked.id)
        .values(consumed_at=now, updated_at=now)
    )
    await transition(
        session,
        listing,
        interaction,
        InteractionStatus.COMPLETED,
        scanner_id,
        settings=settings,
        completion_method=CompletionMethod.QR,
        action="code_completed",
        details={
            "method": "code",
            "presenter_id": str(checked.presenter_id),
            "scanner_id": str(scanner_id),
            "code_id": str(checked.id),
            "received_at": now.isoformat(),
        },
    )
    return CodeResult(
        interaction=interaction,
        presenter_id=checked.presenter_id,
        scanner_id=scanner_id,
        received_at=now,
    )


def qr_result(
    interaction: Interaction,
    scan: QrScan | None,
    payload: QrPayload,
    scanner_id: UUID,
    now: datetime,
) -> QrResult:
    """Build the response data for a successful or replayed confirmation."""
    received_at = scan.created_at if scan is not None else now
    return QrResult(
        interaction=interaction,
        scan=scan,
        presenter_id=payload.presenter_id,
        scanner_id=scanner_id,
        nonce=payload.nonce,
        issued_at=payload.issued_at,
        received_at=received_at,
    )


async def confirm_with_qr(  # noqa: PLR0913, PLR0917 - request parts
    session: AsyncSession,
    listing_id: UUID,
    interaction_id: UUID,
    scanner_id: UUID,
    payload_encoded: str,
    signature_encoded: str,
    settings: Settings,
) -> QrResult:
    """Verify and atomically apply an online QR confirmation.

    The listing row lock serializes scans with cancellation, no-meeting
    completion and each other. The scan row, the interaction update, its
    journal event and the outbox message commit or roll back together.
    """
    raw, payload = decode_payload(payload_encoded)
    if payload.listing_id != listing_id or payload.interaction_id != interaction_id:
        raise ProblemError(QR_PAYLOAD_INVALID)
    now = _check_time(payload, settings)
    listing, interaction = await _load_interaction(session, listing_id, interaction_id)
    _two_participants(listing, interaction, payload.presenter_id, scanner_id)
    if listing.kind not in QR_COMPLETION_KINDS:
        raise ProblemError(QR_UNAVAILABLE)
    # A loan has a handover stage before the final return; a stage action must
    # never be replaced by the final QR completion.
    if interaction.stage is not None:
        raise ProblemError(QR_STAGE_UNAVAILABLE)
    key = await active_signing_key(session, payload)
    verify_signature(key, raw, signature_encoded)

    # A one-time nonce is never accepted twice, even for the same payload.
    # A genuine retry carries the same Idempotency-Key and is answered by the
    # stored idempotent response before this handler runs.
    if await _existing_scan(session, payload.nonce) is not None:
        raise ProblemError(QR_NONCE_REUSED)
    status = InteractionStatus(interaction.status)
    if status == InteractionStatus.COMPLETED:
        if interaction.completion_method == CompletionMethod.QR.value:
            return qr_result(interaction, None, payload, scanner_id, now)
        raise ProblemError(QR_ALREADY_COMPLETED)
    if status != InteractionStatus.ACCEPTED:
        raise ProblemError(QR_NOT_ACCEPTED)

    scan_id = await session.scalar(
        insert(QrScan)
        .values(
            listing_id=listing.id,
            interaction_id=interaction.id,
            device_key_id=key.id,
            presenter_id=payload.presenter_id,
            scanner_id=scanner_id,
            nonce=payload.nonce,
            issued_at=payload.issued_at,
            result="completed",
            created_at=now,
            updated_at=now,
        )
        .on_conflict_do_nothing(index_elements=["nonce"])
        .returning(QrScan.id)
    )
    if scan_id is None:
        # Another interaction raced for the same one-time nonce.
        raise ProblemError(QR_NONCE_REUSED)
    scan = await session.get(QrScan, scan_id)
    if scan is None:  # pragma: no cover - the insert just returned this id
        raise RuntimeError("QR scan disappeared")

    details: dict[str, Any] = {
        "method": CompletionMethod.QR.value,
        "presenter_id": str(payload.presenter_id),
        "scanner_id": str(scanner_id),
        "device_key_id": str(key.id),
        "nonce": str(payload.nonce),
        "issued_at": payload.issued_at.isoformat(),
        "received_at": now.isoformat(),
    }
    await transition(
        session,
        listing,
        interaction,
        InteractionStatus.COMPLETED,
        scanner_id,
        settings=settings,
        completion_method=CompletionMethod.QR,
        action="qr_completed",
        details=details,
    )
    return qr_result(interaction, scan, payload, scanner_id, now)
