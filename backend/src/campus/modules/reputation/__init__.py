"""Public interface of the QR and reputation module."""

from campus.modules.reputation.api import (
    device_router,
    qr_router,
    time_router,
)
from campus.modules.reputation.models import DeviceKey, QrScan
from campus.modules.reputation.service import (
    QR_ALGORITHM,
    QR_COMPLETION_KINDS,
    QrPayload,
    QrResult,
    active_signing_key,
    base64url_decode,
    base64url_encode,
    confirm_with_qr,
    decode_payload,
    public_key_bytes,
    register_device_key,
    revoke_device_key,
    verify_signature,
)

__all__ = [
    "QR_ALGORITHM",
    "QR_COMPLETION_KINDS",
    "DeviceKey",
    "QrPayload",
    "QrResult",
    "QrScan",
    "active_signing_key",
    "base64url_decode",
    "base64url_encode",
    "confirm_with_qr",
    "decode_payload",
    "device_router",
    "public_key_bytes",
    "qr_router",
    "register_device_key",
    "revoke_device_key",
    "time_router",
    "verify_signature",
]
