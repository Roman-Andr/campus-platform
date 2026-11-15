"""Ed25519 device keys and online QR confirmation of an interaction."""

import base64
import binascii
import hashlib
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
from sqlalchemy.ext.asyncio import AsyncSession

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
    LoanStage,
    accepted_at,
    hand_over_loan,
    locked,
    no_showed_at,
    transition,
)
from campus.modules.moderation import Dispute, DisputeStatus
from campus.modules.reputation.models import (
    ConfirmationCode,
    DeviceKey,
    NoShowMark,
    NoShowStatus,
    QrMode,
    QrScan,
)

# These are the scenarios that are completed by meeting a person. Events,
# group purchases and publications use other workflows. A loan is completed
# by the return action; its handover and return reuse the same signed code
# but are separate endpoints, so a loan is never completed by a plain scan.
QR_COMPLETION_KINDS = frozenset({"giveaway", "exchange", "skill", "help", "loan"})
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
QR_ISSUED_IN_FUTURE = ProblemType(
    "qr_issued_in_future",
    409,
    N_("QR code is from the future"),
    N_("The offline QR code time is later than the server received it."),
)
QR_BEFORE_ACCEPTANCE = ProblemType(
    "qr_before_acceptance",
    409,
    N_("QR code predates acceptance"),
    N_("The offline QR code was formed before the interaction was accepted."),
)
QR_ACCEPTANCE_UNKNOWN = ProblemType(
    "qr_acceptance_unknown",
    409,
    N_("QR acceptance time is unavailable"),
    N_(
        "The server has no trusted acceptance time for this interaction and"
        " cannot verify the offline QR code."
    ),
)
QR_CONFIRMATION_CONFLICT = ProblemType(
    "qr_confirmation_conflict",
    409,
    N_("QR confirmation conflict"),
    N_("This device confirmation ID was already used for a different payload."),
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
QR_AFTER_NO_SHOW = ProblemType(
    "qr_after_no_show",
    409,
    N_("QR code formed after the no-show"),
    N_(
        "The interaction was marked 'did not take place' before this QR code"
        " was formed; only a code formed earlier lifts the mark."
    ),
)
QR_ALREADY_CONFIRMED = ProblemType(
    "qr_already_confirmed",
    409,
    N_("Interaction already confirmed"),
    N_(
        "The interaction is already completed by a stored QR confirmation;"
        " this offline confirmation was not stored."
    ),
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
QR_LOAN_ACTION_REQUIRED = ProblemType(
    "qr_loan_action_required",
    409,
    N_("Confirm the loan by its own action"),
    N_(
        "A loan is confirmed by its handover or return action; a plain code"
        " does not complete it."
    ),
)
QR_LOAN_ALREADY_ISSUED = ProblemType(
    "qr_loan_already_issued",
    409,
    N_("The item was already handed over"),
    N_("Confirm the return of the item instead of handing it over again."),
)
QR_LOAN_NOT_HANDED_OVER = ProblemType(
    "qr_loan_not_handed_over",
    409,
    N_("The item was not handed over yet"),
    N_("A return can be confirmed only after the handover of the item."),
)
QR_LOAN_RETURN_MARKED = ProblemType(
    "qr_loan_return_marked",
    409,
    N_("The loan was marked 'not returned'"),
    N_(
        "The owner marked the item as not returned; the returned item is"
        " confirmed through the dispute decision."
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

# These problems are part of the code-confirmation attempt and are safe to
# commit together with the idempotency key: none of them is raised after the
# interaction or the journal has been modified.
CODE_CONFIRM_PROBLEMS = frozenset(
    {
        CODE_INVALID,
        CODE_EXPIRED,
        CODE_ATTEMPTS_EXCEEDED,
        CODE_NOT_PARTICIPANT,
        CODE_SAME_PARTICIPANT,
        CODE_NOT_ACCEPTED,
        CODE_ALREADY_COMPLETED,
        CODE_UNAVAILABLE,
        CODE_STAGE_UNAVAILABLE,
    }
)

_BASE64URL = re.compile(r"[A-Za-z0-9_-]+={0,2}")


async def _lift_no_show(
    session: AsyncSession, interaction_id: UUID, now: datetime
) -> list[UUID]:
    """Remove every no-show mark of an interaction a valid QR just completed.

    The dispute of mutual allegations becomes moot: the meeting did happen.
    Marks stay as rows so the chronology and the audit trail keep the fact.
    """
    removed = list(
        (
            await session.execute(
                update(NoShowMark)
                .where(
                    NoShowMark.interaction_id == interaction_id,
                    NoShowMark.status != NoShowStatus.REMOVED,
                )
                .values(
                    status=NoShowStatus.REMOVED.value,
                    removed_at=now,
                    updated_at=now,
                )
                .returning(NoShowMark.id)
            )
        ).scalars()
    )
    await session.execute(
        update(Dispute)
        .where(
            Dispute.interaction_id == interaction_id,
            Dispute.status == DisputeStatus.OPEN.value,
        )
        .values(
            status=DisputeStatus.RESOLVED.value,
            resolved_at=now,
            resolution="late_qr",
            version=Dispute.version + 1,
            updated_at=now,
        )
    )
    return removed


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


class OfflineQrPayload(BaseModel):
    """The JSON document signed once and delivered later without a network.

    ``version`` is ``2``. ``confirmation_id`` is generated by the showing
    device and survives the delivery retry, so the server can recognise the
    same submission after the ``Idempotency-Key`` expired. ``nonce`` remains
    single-use: a different submission of the same code is rejected.
    """

    model_config = ConfigDict(extra="forbid")

    version: Literal[2] = Field(alias="v")
    confirmation_id: UUID
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
    mode: str = QrMode.ONLINE.value
    confirmation_id: UUID | None = None
    replayed: bool = False


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


def decode_offline_payload(encoded: str) -> tuple[bytes, OfflineQrPayload]:
    """Decode the version 2 payload, keeping the exact signed bytes."""
    try:
        raw = base64url_decode(encoded)
        document: Any = json.loads(raw)
        payload = OfflineQrPayload.model_validate(document)
    except ValueError, UnicodeDecodeError, json.JSONDecodeError, ValidationError:
        raise ProblemError(QR_PAYLOAD_INVALID) from None
    return raw, payload


def payload_digest(raw: bytes) -> str:
    """The stable digest of the exact signed bytes stored with a scan."""
    return hashlib.sha256(raw).hexdigest()


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


async def offline_signing_key(
    session: AsyncSession, payload: OfflineQrPayload
) -> DeviceKey:
    """Lock and return the key that was valid when the offline code was formed.

    A revoked key still verifies a code formed strictly before its
    revocation: a reinstall, sign-out or block cannot invalidate a meeting
    that already happened. The active interval is
    ``[created_at, revoked_at)``: a code formed at the registration instant
    is accepted, a code formed at the revocation instant is refused. The
    same interval rejects every code formed after revocation and every code
    formed before its key was registered, so re-registering a device never
    revives the old key for new codes.
    """
    key = await session.scalar(
        select(DeviceKey).where(DeviceKey.id == payload.key_id).with_for_update()
    )
    if key is None or key.user_id != payload.presenter_id:
        raise ProblemError(QR_KEY_INVALID)
    if payload.issued_at < key.created_at:
        raise ProblemError(QR_KEY_INVALID)
    device = await session.get(Session, key.session_id)
    if device is None or device.user_id != key.user_id:
        raise ProblemError(QR_KEY_INVALID)
    revocations = [
        moment for moment in (key.revoked_at, device.revoked_at) if moment is not None
    ]
    if revocations and payload.issued_at >= min(revocations):
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
    if listing.kind == "loan":
        # A loan is confirmed by its handover or return action; a six-digit
        # code cannot name the action, so it is refused rather than guessed.
        raise ProblemError(CODE_STAGE_UNAVAILABLE)
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
    session: AsyncSession,
    settings: Settings,
    interaction_id: UUID,
    code: str,
    scanner_id: UUID,
    author_id: UUID,
    participant_id: UUID,
) -> CodeCheck:
    """Check the code and count a mismatch in the request transaction.

    The caller commits the 4xx response together with the incremented
    counter, so a retried request with the same idempotency key neither
    changes the counter nor opens a second database transaction. The listing
    row is already locked, so attempts and redemption are serialized.
    """
    now = clock.now()
    expected = _code_digest(settings, interaction_id, code)
    row = await session.scalar(
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
    listing_id: UUID,
    interaction_id: UUID,
    scanner_id: UUID,
    code: str,
    settings: Settings,
) -> CodeResult:
    """Check and atomically apply a six-digit confirmation code.

    The listing lock serializes this request with QR scans, cancellation
    and reissue. A wrong code increments the counter in the same transaction
    as the committed 4xx response; the successful interaction update, its
    journal event and its outbox message commit together, and the code is
    consumed only then.
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
    if listing.kind == "loan":
        # A loan is confirmed by its handover or return action; a six-digit
        # code cannot name the action, so it is refused rather than guessed.
        raise ProblemError(CODE_STAGE_UNAVAILABLE)
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
        session,
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
    received_at = scan.received_at if scan is not None else now
    return QrResult(
        interaction=interaction,
        scan=scan,
        presenter_id=payload.presenter_id,
        scanner_id=scanner_id,
        nonce=payload.nonce,
        issued_at=payload.issued_at,
        received_at=received_at,
        mode=QrMode.ONLINE.value,
    )


@dataclass(frozen=True)
class VerifiedOnlineCode:
    """An online code that passed the shared payload, time and key checks."""

    listing: Listing
    interaction: Interaction
    payload: QrPayload
    key: DeviceKey
    now: datetime


async def verify_online_code(  # noqa: PLR0913, PLR0917 - request parts
    session: AsyncSession,
    settings: Settings,
    listing_id: UUID,
    interaction_id: UUID,
    scanner_id: UUID,
    payload_encoded: str,
    signature_encoded: str,
) -> VerifiedOnlineCode:
    """Run the shared checks of every signed online confirmation.

    The payload names the interaction, the showing participant, the device
    key, the issue time and a one-time nonce; the signature covers its exact
    bytes and the scanner must be the other participant. Scenarios differ
    only in what they do with a verified code, never in how they trust it.
    """
    raw, payload = decode_payload(payload_encoded)
    if payload.listing_id != listing_id or payload.interaction_id != interaction_id:
        raise ProblemError(QR_PAYLOAD_INVALID)
    now = _check_time(payload, settings)
    listing, interaction = await _load_interaction(session, listing_id, interaction_id)
    _two_participants(listing, interaction, payload.presenter_id, scanner_id)
    key = await active_signing_key(session, payload)
    verify_signature(key, raw, signature_encoded)
    # A one-time nonce is never accepted twice, even for the same payload.
    # A genuine retry carries the same Idempotency-Key and is answered by the
    # stored idempotent response before this handler runs.
    if await _existing_scan(session, payload.nonce) is not None:
        raise ProblemError(QR_NONCE_REUSED)
    return VerifiedOnlineCode(listing, interaction, payload, key, now)


async def store_online_scan(
    session: AsyncSession,
    code: VerifiedOnlineCode,
    scanner_id: UUID,
    *,
    result: str,
) -> QrScan:
    """Persist the single-use scan row in the caller's transaction."""
    payload = code.payload
    now = code.now
    scan_id = await session.scalar(
        insert(QrScan)
        .values(
            listing_id=code.listing.id,
            interaction_id=code.interaction.id,
            device_key_id=code.key.id,
            presenter_id=payload.presenter_id,
            scanner_id=scanner_id,
            nonce=payload.nonce,
            issued_at=payload.issued_at,
            received_at=now,
            mode=QrMode.ONLINE.value,
            result=result,
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
    return scan


def scan_details(code: VerifiedOnlineCode, scanner_id: UUID) -> dict[str, Any]:
    """Journal details of a scan; they never contain user-written text."""
    payload = code.payload
    return {
        "method": CompletionMethod.QR.value,
        "presenter_id": str(payload.presenter_id),
        "scanner_id": str(scanner_id),
        "device_key_id": str(code.key.id),
        "nonce": str(payload.nonce),
        "issued_at": payload.issued_at.isoformat(),
        "received_at": code.now.isoformat(),
    }


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
    code = await verify_online_code(
        session,
        settings,
        listing_id,
        interaction_id,
        scanner_id,
        payload_encoded,
        signature_encoded,
    )
    listing = code.listing
    interaction = code.interaction
    payload = code.payload
    now = code.now
    if listing.kind not in QR_COMPLETION_KINDS:
        raise ProblemError(QR_UNAVAILABLE)
    if listing.kind == "loan":
        # The handover and the return are separate signed actions; a plain
        # scan must never finish a loan as if it were a flat giveaway.
        raise ProblemError(QR_LOAN_ACTION_REQUIRED)
    # A manual stage action must never be replaced by the final completion.
    if interaction.stage is not None:
        raise ProblemError(QR_STAGE_UNAVAILABLE)
    status = InteractionStatus(interaction.status)
    late_mark: datetime | None = None
    if status == InteractionStatus.COMPLETED:
        if interaction.completion_method == CompletionMethod.QR.value:
            return qr_result(interaction, None, payload, scanner_id, now)
        raise ProblemError(QR_ALREADY_COMPLETED)
    if status == InteractionStatus.NO_SHOW:
        # #66: an online code formed before the no-show mark still confirms
        # the meeting; the mark is not a terminal state.
        late_mark = await no_showed_at(session, interaction.id)
        if late_mark is None:
            raise ProblemError(QR_NOT_ACCEPTED)
        if payload.issued_at >= late_mark:
            raise ProblemError(QR_AFTER_NO_SHOW)
    elif status != InteractionStatus.ACCEPTED:
        raise ProblemError(QR_NOT_ACCEPTED)

    scan = await store_online_scan(session, code, scanner_id, result="completed")
    details = scan_details(code, scanner_id)
    action = "qr_completed"
    if late_mark is not None:
        details["no_show_at"] = late_mark.isoformat()
        details["lifted_no_show_ids"] = [
            str(value) for value in await _lift_no_show(session, interaction.id, now)
        ]
        action = "qr_completed_after_no_show"
    await transition(
        session,
        listing,
        interaction,
        InteractionStatus.COMPLETED,
        scanner_id,
        settings=settings,
        completion_method=CompletionMethod.QR,
        action=action,
        details=details,
    )
    return qr_result(interaction, scan, payload, scanner_id, now)


async def hand_over_loan_with_qr(  # noqa: PLR0913, PLR0917 - request parts
    session: AsyncSession,
    listing_id: UUID,
    interaction_id: UUID,
    scanner_id: UUID,
    payload_encoded: str,
    signature_encoded: str,
    settings: Settings,
) -> QrResult:
    """Confirm the handover of a lent item with the other participant's code.

    The interaction stays accepted and moves to the ``issued`` stage; the
    return deadline is the handover moment plus the author's loan period.
    The same signed payload, time window, device key and single-use nonce
    checks as a final completion apply, so a handover scan is as trustworthy
    as any other confirmation. A repeated handover is refused, and a
    non-loan interaction cannot use this action.
    """
    code = await verify_online_code(
        session,
        settings,
        listing_id,
        interaction_id,
        scanner_id,
        payload_encoded,
        signature_encoded,
    )
    listing = code.listing
    interaction = code.interaction
    if listing.kind != "loan":
        raise ProblemError(QR_UNAVAILABLE)
    status = InteractionStatus(interaction.status)
    if status == InteractionStatus.COMPLETED:
        raise ProblemError(QR_ALREADY_COMPLETED)
    if status != InteractionStatus.ACCEPTED:
        raise ProblemError(QR_NOT_ACCEPTED)
    if interaction.stage == LoanStage.ISSUED.value:
        raise ProblemError(QR_LOAN_ALREADY_ISSUED)
    if interaction.stage is not None:
        raise ProblemError(QR_STAGE_UNAVAILABLE)

    scan = await store_online_scan(session, code, scanner_id, result="stage_advanced")
    details = scan_details(code, scanner_id)
    details["result"] = "stage_advanced"
    await hand_over_loan(
        session,
        listing,
        interaction,
        scanner_id,
        settings=settings,
        details=details,
    )
    return qr_result(interaction, scan, code.payload, scanner_id, code.now)


async def return_loan_with_qr(  # noqa: PLR0913, PLR0917 - request parts
    session: AsyncSession,
    listing_id: UUID,
    interaction_id: UUID,
    scanner_id: UUID,
    payload_encoded: str,
    signature_encoded: str,
    settings: Settings,
) -> QrResult:
    """Confirm the return of a lent item and complete the interaction.

    A return is possible only after the confirmed handover: a code presented
    before the ``issued`` stage is refused, so the two actions cannot be
    collapsed into one. The same validation as every other signed code
    applies. A loan already marked "not returned" is closed for QR returns;
    the returned item is then decided through the dispute.
    """
    code = await verify_online_code(
        session,
        settings,
        listing_id,
        interaction_id,
        scanner_id,
        payload_encoded,
        signature_encoded,
    )
    listing = code.listing
    interaction = code.interaction
    if listing.kind != "loan":
        raise ProblemError(QR_UNAVAILABLE)
    status = InteractionStatus(interaction.status)
    if status == InteractionStatus.COMPLETED:
        if interaction.completion_method == CompletionMethod.QR.value:
            return qr_result(interaction, None, code.payload, scanner_id, code.now)
        raise ProblemError(QR_ALREADY_COMPLETED)
    if status == InteractionStatus.NO_SHOW:
        raise ProblemError(QR_LOAN_RETURN_MARKED)
    if status != InteractionStatus.ACCEPTED:
        raise ProblemError(QR_NOT_ACCEPTED)
    if interaction.stage is None:
        raise ProblemError(QR_LOAN_NOT_HANDED_OVER)
    if interaction.stage != LoanStage.ISSUED.value:
        raise ProblemError(QR_STAGE_UNAVAILABLE)

    scan = await store_online_scan(session, code, scanner_id, result="completed")
    details = scan_details(code, scanner_id)
    if interaction.return_due_at is not None:
        details["return_due_at"] = interaction.return_due_at.isoformat()
        details["overdue"] = interaction.overdue
    await transition(
        session,
        listing,
        interaction,
        InteractionStatus.COMPLETED,
        scanner_id,
        settings=settings,
        completion_method=CompletionMethod.QR,
        action="loan_returned",
        details=details,
    )
    return qr_result(interaction, scan, code.payload, scanner_id, code.now)


def _check_offline_time(
    payload: OfflineQrPayload,
    accepted: datetime,
    received_at: datetime,
    settings: Settings,
) -> None:
    """Accept ``accepted_at <= issued_at <= received_at`` and age <= ttl.

    All three bounds are inclusive. The device clock is not trusted on its
    own: the journal acceptance time and the server receipt time bracket it.
    """
    if payload.issued_at > received_at:
        raise ProblemError(QR_ISSUED_IN_FUTURE)
    if payload.issued_at < accepted:
        raise ProblemError(QR_BEFORE_ACCEPTANCE)
    if received_at - payload.issued_at > settings.qr_offline_ttl:
        raise ProblemError(QR_EXPIRED)


async def _scan_by_confirmation(
    session: AsyncSession, confirmation_id: UUID
) -> QrScan | None:
    return await session.scalar(
        select(QrScan).where(QrScan.confirmation_id == confirmation_id)
    )


def _matches_offline_scan(  # noqa: PLR0913, PLR0917 - submission parts
    scan: QrScan,
    payload: OfflineQrPayload,
    scanner_id: UUID,
    listing_id: UUID,
    interaction_id: UUID,
    digest: str,
) -> bool:
    """Whether a stored row is exactly the submission being repeated."""
    return (
        scan.mode == QrMode.OFFLINE
        and scan.confirmation_id == payload.confirmation_id
        and scan.listing_id == listing_id
        and scan.interaction_id == interaction_id
        and scan.device_key_id == payload.key_id
        and scan.presenter_id == payload.presenter_id
        and scan.scanner_id == scanner_id
        and scan.nonce == payload.nonce
        and scan.issued_at == payload.issued_at
        and scan.payload_hash == digest
    )


def _offline_result(  # noqa: PLR0913 - the parts of a result
    interaction: Interaction,
    scan: QrScan | None,
    payload: OfflineQrPayload,
    scanner_id: UUID,
    received_at: datetime,
    *,
    replayed: bool,
) -> QrResult:
    return QrResult(
        interaction=interaction,
        scan=scan,
        presenter_id=payload.presenter_id,
        scanner_id=scanner_id,
        nonce=payload.nonce,
        issued_at=payload.issued_at,
        received_at=scan.received_at if scan is not None else received_at,
        mode=QrMode.OFFLINE.value,
        confirmation_id=payload.confirmation_id,
        replayed=replayed,
    )


async def complete_offline_qr(  # noqa: PLR0913, PLR0917 - submission parts
    session: AsyncSession,
    listing: Listing,
    interaction: Interaction,
    payload: OfflineQrPayload,
    key: DeviceKey,
    scanner_id: UUID,
    received_at: datetime,
    digest: str,
    settings: Settings,
    *,
    no_show_at: datetime | None = None,
) -> QrResult:
    """Trusted completion of an offline code that already passed validation.

    This is the single completion primitive of the offline flow and of the
    late-QR contract for #66. The caller must have verified the signature,
    the key window, the participants and the time bounds; this function
    inserts the unique scan row, applies the shared ``transition`` and writes
    the journal/outbox in the caller's transaction. A concurrent repeat
    resolves to the stored row instead of a second completion. When
    ``no_show_at`` names the mark the code was formed before, the marks are
    lifted and the dispute of the mutual allegations is closed in the same
    transaction.
    """
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
            received_at=received_at,
            mode=QrMode.OFFLINE.value,
            confirmation_id=payload.confirmation_id,
            payload_hash=digest,
            result="completed",
            created_at=received_at,
            updated_at=received_at,
        )
        .on_conflict_do_nothing()
        .returning(QrScan.id)
    )
    if scan_id is None:
        # A unique constraint serialized two submissions: the same
        # confirmation id is a retry, any other row means the nonce was used.
        existing = await _scan_by_confirmation(session, payload.confirmation_id)
        if existing is None:
            raise ProblemError(QR_NONCE_REUSED)
        if not _matches_offline_scan(
            existing,
            payload,
            scanner_id,
            listing.id,
            interaction.id,
            digest,
        ):
            raise ProblemError(QR_CONFIRMATION_CONFLICT)
        return _offline_result(
            interaction, existing, payload, scanner_id, received_at, replayed=True
        )
    scan = await session.get(QrScan, scan_id)
    if scan is None:  # pragma: no cover - the insert just returned this id
        raise RuntimeError("offline QR scan disappeared")

    details: dict[str, Any] = {
        "method": CompletionMethod.QR.value,
        "mode": QrMode.OFFLINE.value,
        "presenter_id": str(payload.presenter_id),
        "scanner_id": str(scanner_id),
        "device_key_id": str(key.id),
        "confirmation_id": str(payload.confirmation_id),
        "nonce": str(payload.nonce),
        "issued_at": payload.issued_at.isoformat(),
        "received_at": received_at.isoformat(),
    }
    action = "qr_completed"
    if no_show_at is not None:
        details["no_show_at"] = no_show_at.isoformat()
        details["lifted_no_show_ids"] = [
            str(value)
            for value in await _lift_no_show(session, interaction.id, received_at)
        ]
        action = "qr_completed_after_no_show"
    await transition(
        session,
        listing,
        interaction,
        InteractionStatus.COMPLETED,
        scanner_id,
        settings=settings,
        completion_method=CompletionMethod.QR,
        action=action,
        details=details,
        offline_qr=True,
    )
    return _offline_result(
        interaction, scan, payload, scanner_id, received_at, replayed=False
    )


async def confirm_with_offline_qr(  # noqa: PLR0912, PLR0913, PLR0917 - request
    session: AsyncSession,
    listing_id: UUID,
    interaction_id: UUID,
    scanner_id: UUID,
    payload_encoded: str,
    signature_encoded: str,
    settings: Settings,
) -> QrResult:
    """Verify and atomically apply a delayed offline QR confirmation.

    Validation contract (shared with the late-QR flow in #66):

    - the signed payload names the session listing and interaction;
    - the presenter is one participant and the authenticated scanner is the
      other one of a previously accepted interaction;
    - the key existed when the code was formed and was not revoked before
      that moment, so a code formed before a reinstall/sign-out stays valid
      within the window while a code formed after revocation does not;
    - ``accepted_at <= issued_at <= received_at`` and the age is at most the
      configured 24 hours, all bounds inclusive;
    - ``confirmation_id`` is unique forever, so a retry after the
      idempotency key expired returns the stored result, while an altered
      payload reusing it conflicts; ``nonce`` stays single-use across
      devices and deliveries.

    A non-accepted state is not bypassed by a valid signature, with one
    exception: a code formed before a no-show mark completes the interaction
    and lifts the marks through :func:`complete_offline_qr`; a code formed
    after the mark must not. Intermediate scenario stages are refused here;
    only the final meeting completes. A loan is refused entirely: its
    handover and return are separate actions, and an offline submission
    cannot name the action it was signed for.
    """
    raw, payload = decode_offline_payload(payload_encoded)
    if payload.listing_id != listing_id or payload.interaction_id != interaction_id:
        raise ProblemError(QR_PAYLOAD_INVALID)
    received_at = clock.now()
    digest = payload_digest(raw)
    key = await offline_signing_key(session, payload)
    verify_signature(key, raw, signature_encoded)
    listing, interaction = await _load_interaction(session, listing_id, interaction_id)
    _two_participants(listing, interaction, payload.presenter_id, scanner_id)

    # The stored row is checked before the state gate: a genuine retry of a
    # completed submission must return its original result after any timeout.
    existing = await _scan_by_confirmation(session, payload.confirmation_id)
    if existing is not None:
        if not _matches_offline_scan(
            existing,
            payload,
            scanner_id,
            listing.id,
            interaction.id,
            digest,
        ):
            raise ProblemError(QR_CONFIRMATION_CONFLICT)
        return _offline_result(
            interaction, existing, payload, scanner_id, received_at, replayed=True
        )
    if await _existing_scan(session, payload.nonce) is not None:
        raise ProblemError(QR_NONCE_REUSED)
    if listing.kind == "loan":
        # An offline code is signed before delivery and cannot name the loan
        # action; guessing between the handover and the return could finish a
        # loan nobody returned. The loan actions are online only for now.
        raise ProblemError(QR_LOAN_ACTION_REQUIRED)

    status = InteractionStatus(interaction.status)
    if status == InteractionStatus.COMPLETED:
        if interaction.completion_method == CompletionMethod.QR.value:
            # Unlike the online endpoint, an offline confirmation is durable
            # only when its own row exists. A different confirmation id on a
            # QR-completed interaction must not get a fabricated success
            # response: that would let a changed payload reuse its id.
            raise ProblemError(QR_ALREADY_CONFIRMED)
        raise ProblemError(QR_ALREADY_COMPLETED)
    if status == InteractionStatus.NO_SHOW:
        # #66 late-QR contract: a code formed before the mark completes the
        # interaction and lifts the mark; a code formed after it has no effect.
        if listing.kind not in QR_COMPLETION_KINDS:
            raise ProblemError(QR_UNAVAILABLE)
        if interaction.stage is not None:
            raise ProblemError(QR_STAGE_UNAVAILABLE)
        accepted = await accepted_at(session, interaction.id)
        if accepted is None:
            raise ProblemError(QR_ACCEPTANCE_UNKNOWN)
        _check_offline_time(payload, accepted, received_at, settings)
        late_mark = await no_showed_at(session, interaction.id)
        if late_mark is None:
            raise ProblemError(QR_NOT_ACCEPTED)
        if payload.issued_at >= late_mark:
            raise ProblemError(QR_AFTER_NO_SHOW)
        return await complete_offline_qr(
            session,
            listing,
            interaction,
            payload,
            key,
            scanner_id,
            received_at,
            digest,
            settings,
            no_show_at=late_mark,
        )
    if status != InteractionStatus.ACCEPTED:
        raise ProblemError(QR_NOT_ACCEPTED)
    if listing.kind not in QR_COMPLETION_KINDS:
        raise ProblemError(QR_UNAVAILABLE)
    if interaction.stage is not None:
        # Loan handover (#214) is an intermediate stage with its own action;
        # it must never complete the interaction like a flat giveaway.
        raise ProblemError(QR_STAGE_UNAVAILABLE)

    accepted = await accepted_at(session, interaction.id)
    if accepted is None:
        raise ProblemError(QR_ACCEPTANCE_UNKNOWN)
    _check_offline_time(payload, accepted, received_at, settings)

    return await complete_offline_qr(
        session,
        listing,
        interaction,
        payload,
        key,
        scanner_id,
        received_at,
        digest,
        settings,
    )
