"""Ed25519 device keys and online QR confirmation of an interaction."""

import base64
import binascii
import json
import re
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
from campus.modules.reputation.models import DeviceKey, QrScan

# These are the scenarios that are completed by meeting a person. Events,
# group purchases and publications use other workflows, and a loan needs a
# separate return stage rather than the final completion.
QR_COMPLETION_KINDS = frozenset({"giveaway", "exchange", "skill", "help"})
QR_ALGORITHM = "ed25519"
PUBLIC_KEY_SIZE = 32
SIGNATURE_SIZE = 64

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
