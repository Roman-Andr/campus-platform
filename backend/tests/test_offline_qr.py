"""Offline Ed25519 QR confirmation on PostgreSQL with controlled time.

The offline code is signed once by the showing device and delivered later.
The tests cover the database-level confirmation deduplication, exact time
bounds, the key validity interval around revocation and re-registration,
participant rights, shared transitions and the late-QR contract boundary.
"""

import asyncio
import json
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID, uuid4

import httpx2
import pytest
import time_machine
from sqlalchemy import select, update

from campus.modules.identity import Block, Role, RoleAssignment, User
from campus.modules.listings import Interaction, Listing, ListingEvent
from campus.modules.reputation import (
    QrMode,
    QrScan,
    base64url_decode,
    base64url_encode,
)
from tests.test_identity import Auth
from tests.test_listings import (
    auth,
    borrower,
    move,
    owner,
    places,
    publish,
    reserve,
    staff,
)
from tests.test_profile import Account
from tests.test_qr import (
    Signer,
    accepted,
    counts,
    register_key,
    revoke_key,
    set_settings,
    user_id,
)

__all__ = ["auth", "borrower", "owner", "places", "staff"]

ROOT = "/api/v1/listings"
TIME_URL = "/api/v1/time"
FIXED = datetime(2026, 11, 15, 12, 0, 0, tzinfo=UTC)


@pytest.fixture(autouse=True)
def long_lived_access(auth: Auth) -> None:
    """Keep access tokens valid while tests move time by up to a day."""
    auth.settings = auth.settings.model_copy(
        update={"access_token_ttl": timedelta(days=365)}
    )
    auth.app.state.settings = auth.settings


def instant(at: datetime) -> str:
    return at.astimezone(UTC).isoformat().replace("+00:00", "Z")


def payload_document(body: dict[str, str]) -> dict[str, Any]:
    document: dict[str, Any] = json.loads(base64url_decode(body["payload"]))
    return document


def offline_body(  # noqa: PLR0913 - a test payload builder
    signer: Signer,
    listing_id: UUID | str,
    interaction_id: UUID | str,
    presenter_id: UUID | str,
    *,
    issued_at: datetime,
    confirmation_id: UUID | None = None,
    nonce: UUID | None = None,
    key_id: UUID | str | None = None,
    sign: bool = True,
    **overrides: Any,
) -> dict[str, str]:
    if signer.key_id is None and key_id is None:
        raise AssertionError("register the signer first")
    document: dict[str, Any] = {
        "v": 2,
        "confirmation_id": str(confirmation_id or uuid4()),
        "listing_id": str(listing_id),
        "interaction_id": str(interaction_id),
        "presenter_id": str(presenter_id),
        "key_id": str(key_id or signer.key_id),
        "issued_at": instant(issued_at),
        "nonce": str(nonce or uuid4()),
        **overrides,
    }
    raw = json.dumps(
        document, ensure_ascii=False, separators=(",", ":"), sort_keys=True
    ).encode()
    signature = signer.private.sign(raw) if sign else b"\x00" * 64
    return {
        "payload": base64url_encode(raw),
        "signature": base64url_encode(signature),
    }


async def offline_scan(
    account: Account,
    listing: dict[str, Any],
    interaction: dict[str, Any],
    body: dict[str, str],
    key: str | None = None,
) -> httpx2.Response:
    return await account.auth.client.post(
        f"{ROOT}/{listing['id']}/interactions/{interaction['id']}/qr/offline",
        json=body,
        headers={"Idempotency-Key": key or str(uuid4()), **account.headers},
    )


async def register_at(account: Account, signer: Signer, at: datetime) -> None:
    with time_machine.travel(at, tick=False):
        response = await register_key(account, signer)
    assert response.status_code == 200, response.text


async def accepted_at_time(
    author: Account, participant: Account, at: datetime
) -> tuple[dict[str, Any], dict[str, Any]]:
    with time_machine.travel(at, tick=False):
        return await accepted(author, participant)


async def scan_rows(account: Account, interaction_id: UUID) -> list[QrScan]:
    db = account.auth.db
    await db.rollback()
    return list(
        await db.scalars(
            select(QrScan)
            .where(QrScan.interaction_id == interaction_id)
            .order_by(QrScan.created_at, QrScan.id)
        )
    )


async def qr_events(account: Account, interaction_id: UUID) -> list[ListingEvent]:
    db = account.auth.db
    await db.rollback()
    return list(
        await db.scalars(
            select(ListingEvent)
            .where(
                ListingEvent.interaction_id == interaction_id,
                ListingEvent.action == "qr_completed",
            )
            .order_by(ListingEvent.created_at, ListingEvent.id)
        )
    )


async def test_offline_qr_completes_and_records_offline_chronology(
    owner: Account, borrower: Account
) -> None:
    fixed = FIXED
    signer = Signer.generate()
    await register_at(owner, signer, fixed - timedelta(hours=1))
    listing, interaction = await accepted_at_time(owner, borrower, fixed)
    before = await counts(owner, UUID(interaction["id"]))
    body = offline_body(
        signer,
        listing["id"],
        interaction["id"],
        user_id(owner),
        issued_at=fixed + timedelta(minutes=1),
    )

    with time_machine.travel(fixed + timedelta(minutes=2), tick=False):
        response = await offline_scan(borrower, listing, interaction, body)

    assert response.status_code == 200, response.text
    result = response.json()
    assert result["mode"] == "offline"
    assert result["status"] == "completed"
    assert result["completed"] is True
    assert result["completion_method"] == "qr"
    assert result["replayed"] is False
    assert result["presenter_id"] == str(user_id(owner))
    assert result["scanner_id"] == str(user_id(borrower))
    assert result["confirmation_id"] == payload_document(body)["confirmation_id"]
    assert "sessions" not in result

    db = owner.auth.db
    await db.rollback()
    row = await db.get(Interaction, UUID(interaction["id"]))
    assert row is not None
    assert row.status == "completed"
    assert row.completion_method == "qr"
    scans = await scan_rows(owner, UUID(interaction["id"]))
    assert len(scans) == 1
    assert scans[0].mode == QrMode.OFFLINE
    assert scans[0].confirmation_id is not None
    assert scans[0].payload_hash is not None
    assert scans[0].received_at == fixed + timedelta(minutes=2)
    assert scans[0].issued_at == fixed + timedelta(minutes=1)
    events = await qr_events(owner, UUID(interaction["id"]))
    assert len(events) == 1
    assert events[0].offline_qr is True
    assert events[0].details is not None
    assert events[0].details["mode"] == "offline"
    assert events[0].details["method"] == "qr"
    after = await counts(owner, UUID(interaction["id"]))
    assert after[0] == before[0] + 1
    assert after[1] == before[1] + 2
    assert after[2:] == (1, 1)


async def test_replay_after_idempotency_ttl_returns_stored_result(
    owner: Account, borrower: Account
) -> None:
    fixed = FIXED
    set_settings(owner, idempotency_key_ttl=timedelta(seconds=1))
    signer = Signer.generate()
    await register_at(owner, signer, fixed - timedelta(hours=1))
    listing, interaction = await accepted_at_time(owner, borrower, fixed)
    body = offline_body(
        signer,
        listing["id"],
        interaction["id"],
        user_id(owner),
        issued_at=fixed,
    )
    with time_machine.travel(fixed + timedelta(minutes=1), tick=False):
        first = await offline_scan(
            borrower, listing, interaction, body, key=str(uuid4())
        )
    assert first.status_code == 200, first.text
    before = await counts(owner, UUID(interaction["id"]))

    with time_machine.travel(fixed + timedelta(minutes=1, seconds=2), tick=False):
        replay = await offline_scan(
            borrower, listing, interaction, body, key=str(uuid4())
        )

    assert replay.status_code == 200, replay.text
    assert replay.json()["replayed"] is True
    assert replay.json()["confirmation_id"] == first.json()["confirmation_id"]
    assert replay.json()["completed_at"] == first.json()["completed_at"]
    assert replay.headers.get("Idempotent-Replayed") != "true"
    assert await counts(owner, UUID(interaction["id"])) == before


async def test_altered_payload_with_same_confirmation_id_conflicts(
    owner: Account, borrower: Account
) -> None:
    fixed = FIXED
    set_settings(owner, idempotency_key_ttl=timedelta(seconds=1))
    signer = Signer.generate()
    await register_at(owner, signer, fixed - timedelta(hours=1))
    listing, interaction = await accepted_at_time(owner, borrower, fixed)
    confirmation_id = uuid4()
    first_body = offline_body(
        signer,
        listing["id"],
        interaction["id"],
        user_id(owner),
        issued_at=fixed,
        confirmation_id=confirmation_id,
    )
    key = str(uuid4())
    altered_body = offline_body(
        signer,
        listing["id"],
        interaction["id"],
        user_id(owner),
        issued_at=fixed,
        confirmation_id=confirmation_id,
        nonce=uuid4(),
    )
    with time_machine.travel(fixed + timedelta(minutes=1), tick=False):
        first = await offline_scan(borrower, listing, interaction, first_body, key=key)
        same_key = await offline_scan(
            borrower, listing, interaction, altered_body, key=key
        )
    assert first.status_code == 200, first.text
    assert same_key.status_code == 422
    assert same_key.json()["code"] == "idempotency_key_reused"

    before = await counts(owner, UUID(interaction["id"]))
    with time_machine.travel(fixed + timedelta(minutes=1, seconds=2), tick=False):
        conflict = await offline_scan(
            borrower, listing, interaction, altered_body, key=str(uuid4())
        )
    assert conflict.status_code == 409
    assert conflict.json()["code"] == "qr_confirmation_conflict"
    assert await counts(owner, UUID(interaction["id"])) == before


async def test_parallel_same_submission_completes_once(
    owner: Account, borrower: Account
) -> None:
    fixed = FIXED
    signer = Signer.generate()
    await register_at(owner, signer, fixed - timedelta(hours=1))
    listing, interaction = await accepted_at_time(owner, borrower, fixed)
    body = offline_body(
        signer,
        listing["id"],
        interaction["id"],
        user_id(owner),
        issued_at=fixed,
    )
    before = await counts(owner, UUID(interaction["id"]))

    with time_machine.travel(fixed + timedelta(minutes=1), tick=False):
        responses = await asyncio.gather(
            offline_scan(borrower, listing, interaction, body),
            offline_scan(borrower, listing, interaction, body),
        )

    assert [response.status_code for response in responses] == [200, 200]
    assert sorted(response.json()["replayed"] for response in responses) == [
        False,
        True,
    ]
    after = await counts(owner, UUID(interaction["id"]))
    assert after[0] == before[0] + 1
    assert after[1] == before[1] + 2
    assert after[2:] == (1, 1)


async def second_device(
    auth: Auth, email: str, device_id: str | None = None
) -> Account:
    tokens = await auth.login(email=email, device_id=device_id or str(uuid4()))
    return Account(auth, tokens)


async def test_confirmation_id_unique_across_parallel_interactions(
    owner: Account, borrower: Account, auth: Auth
) -> None:
    fixed = FIXED
    first_listing, first_interaction = await accepted_at_time(owner, borrower, fixed)
    second_listing, second_interaction = await accepted_at_time(owner, borrower, fixed)
    first_signer = Signer.generate()
    second_signer = Signer.generate()
    await register_at(owner, first_signer, fixed - timedelta(hours=2))
    other_owner = await second_device(auth, "student@university.example")
    await register_at(other_owner, second_signer, fixed - timedelta(hours=2))
    confirmation_id = uuid4()

    first_body = offline_body(
        first_signer,
        first_listing["id"],
        first_interaction["id"],
        user_id(owner),
        issued_at=fixed,
        confirmation_id=confirmation_id,
    )
    second_body = offline_body(
        second_signer,
        second_listing["id"],
        second_interaction["id"],
        user_id(owner),
        issued_at=fixed,
        confirmation_id=confirmation_id,
    )

    with time_machine.travel(fixed + timedelta(minutes=1), tick=False):
        responses = await asyncio.gather(
            offline_scan(borrower, first_listing, first_interaction, first_body),
            offline_scan(borrower, second_listing, second_interaction, second_body),
        )

    assert sorted(response.status_code for response in responses) == [200, 409]
    conflict = next(response for response in responses if response.status_code == 409)
    assert conflict.json()["code"] == "qr_confirmation_conflict"
    db = owner.auth.db
    await db.rollback()
    scans = list(
        await db.scalars(
            select(QrScan).where(QrScan.confirmation_id == confirmation_id)
        )
    )
    assert len(scans) == 1
    statuses = set(
        await db.scalars(
            select(Interaction.status).where(
                Interaction.id.in_(
                    [
                        UUID(first_interaction["id"]),
                        UUID(second_interaction["id"]),
                    ]
                )
            )
        )
    )
    assert statuses == {"accepted", "completed"}


async def test_nonce_is_unique_across_parallel_interactions(
    owner: Account, borrower: Account, auth: Auth
) -> None:
    fixed = FIXED
    first_listing, first_interaction = await accepted_at_time(owner, borrower, fixed)
    second_listing, second_interaction = await accepted_at_time(owner, borrower, fixed)
    first_signer = Signer.generate()
    second_signer = Signer.generate()
    await register_at(owner, first_signer, fixed - timedelta(hours=2))
    other_owner = await second_device(auth, "student@university.example")
    await register_at(other_owner, second_signer, fixed - timedelta(hours=2))
    nonce = uuid4()

    first_body = offline_body(
        first_signer,
        first_listing["id"],
        first_interaction["id"],
        user_id(owner),
        issued_at=fixed,
        nonce=nonce,
    )
    second_body = offline_body(
        second_signer,
        second_listing["id"],
        second_interaction["id"],
        user_id(owner),
        issued_at=fixed,
        nonce=nonce,
    )

    with time_machine.travel(fixed + timedelta(minutes=1), tick=False):
        responses = await asyncio.gather(
            offline_scan(borrower, first_listing, first_interaction, first_body),
            offline_scan(borrower, second_listing, second_interaction, second_body),
        )

    assert sorted(response.status_code for response in responses) == [200, 409]
    refused = next(response for response in responses if response.status_code == 409)
    assert refused.json()["code"] == "qr_nonce_reused"
    db = owner.auth.db
    await db.rollback()
    rows = list(await db.scalars(select(QrScan).where(QrScan.nonce == nonce)))
    assert len(rows) == 1


async def test_nonce_stays_single_use_after_the_window_and_idempotency_ttl(
    owner: Account, borrower: Account, auth: Auth
) -> None:
    fixed = FIXED
    set_settings(owner, idempotency_key_ttl=timedelta(seconds=1))
    signer = Signer.generate()
    await register_at(owner, signer, fixed - timedelta(hours=2))
    listing, interaction = await accepted_at_time(owner, borrower, fixed)
    nonce = uuid4()
    first_body = offline_body(
        signer,
        listing["id"],
        interaction["id"],
        user_id(owner),
        issued_at=fixed,
        nonce=nonce,
    )
    with time_machine.travel(fixed + timedelta(minutes=1), tick=False):
        first = await offline_scan(borrower, listing, interaction, first_body)
    assert first.status_code == 200, first.text

    other_owner = await second_device(auth, "student@university.example")
    other_signer = Signer.generate()
    await register_at(other_owner, other_signer, fixed)
    before = await counts(owner, UUID(interaction["id"]))
    replay_body = offline_body(
        other_signer,
        listing["id"],
        interaction["id"],
        user_id(owner),
        issued_at=fixed + timedelta(hours=25),
        nonce=nonce,
    )
    with time_machine.travel(fixed + timedelta(hours=25), tick=False):
        reused = await offline_scan(
            borrower, listing, interaction, replay_body, key=str(uuid4())
        )

    assert reused.status_code == 409
    assert reused.json()["code"] == "qr_nonce_reused"
    assert await counts(owner, UUID(interaction["id"])) == before


@pytest.mark.parametrize(
    ("received_offset", "issued_offset", "accepted_scan"),
    [
        (0, 0, True),
        (3600, -1, False),
        (3600, 3601, False),
        (86400, 0, True),
        (86401, 0, False),
    ],
)
async def test_offline_time_boundaries(
    owner: Account,
    borrower: Account,
    received_offset: int,
    issued_offset: int,
    accepted_scan: bool,
) -> None:
    fixed = FIXED
    signer = Signer.generate()
    await register_at(owner, signer, fixed - timedelta(hours=2))
    listing, interaction = await accepted_at_time(owner, borrower, fixed)
    received = fixed + timedelta(seconds=received_offset)
    issued = fixed + timedelta(seconds=issued_offset)
    body = offline_body(
        signer,
        listing["id"],
        interaction["id"],
        user_id(owner),
        issued_at=issued,
    )

    with time_machine.travel(received, tick=False):
        response = await offline_scan(borrower, listing, interaction, body)

    if accepted_scan:
        assert response.status_code == 200, response.text
        assert response.json()["status"] == "completed"
    else:
        assert response.status_code == 409
        expected = (
            "qr_before_acceptance"
            if issued_offset < 0
            else "qr_issued_in_future"
            if issued_offset > received_offset
            else "qr_expired"
        )
        assert response.json()["code"] == expected


@pytest.mark.parametrize("revoke_with_sign_out", [False, True])
async def test_code_signed_before_key_revocation_is_accepted(
    owner: Account, borrower: Account, revoke_with_sign_out: bool
) -> None:
    fixed = FIXED
    signer = Signer.generate()
    await register_at(owner, signer, fixed - timedelta(hours=2))
    listing, interaction = await accepted_at_time(owner, borrower, fixed)
    body = offline_body(
        signer,
        listing["id"],
        interaction["id"],
        user_id(owner),
        issued_at=fixed,
    )
    with time_machine.travel(fixed + timedelta(hours=1), tick=False):
        if revoke_with_sign_out:
            signed_out = await owner.auth.client.post(
                "/api/v1/auth/sign-out",
                headers={"Idempotency-Key": str(uuid4()), **owner.headers},
            )
            assert signed_out.status_code == 204
        else:
            assert (await revoke_key(owner)).status_code == 204

    with time_machine.travel(fixed + timedelta(hours=2), tick=False):
        response = await offline_scan(borrower, listing, interaction, body)

    assert response.status_code == 200, response.text
    assert response.json()["status"] == "completed"


async def test_code_signed_after_key_revocation_is_rejected(
    owner: Account, borrower: Account
) -> None:
    fixed = FIXED
    signer = Signer.generate()
    await register_at(owner, signer, fixed - timedelta(hours=2))
    listing, interaction = await accepted_at_time(owner, borrower, fixed)
    with time_machine.travel(fixed + timedelta(hours=1), tick=False):
        assert (await revoke_key(owner)).status_code == 204
    body = offline_body(
        signer,
        listing["id"],
        interaction["id"],
        user_id(owner),
        issued_at=fixed + timedelta(hours=2),
    )

    with time_machine.travel(fixed + timedelta(hours=3), tick=False):
        response = await offline_scan(borrower, listing, interaction, body)

    assert response.status_code == 403
    assert response.json()["code"] == "qr_key_invalid"
    assert await qr_events(owner, UUID(interaction["id"])) == []


async def test_code_issued_exactly_at_revocation_is_rejected(
    owner: Account, borrower: Account
) -> None:
    fixed = FIXED
    signer = Signer.generate()
    await register_at(owner, signer, fixed - timedelta(hours=2))
    listing, interaction = await accepted_at_time(owner, borrower, fixed)
    with time_machine.travel(fixed + timedelta(hours=1), tick=False):
        assert (await revoke_key(owner)).status_code == 204
    body = offline_body(
        signer,
        listing["id"],
        interaction["id"],
        user_id(owner),
        issued_at=fixed + timedelta(hours=1),
    )

    with time_machine.travel(fixed + timedelta(hours=2), tick=False):
        response = await offline_scan(borrower, listing, interaction, body)

    assert response.status_code == 403
    assert response.json()["code"] == "qr_key_invalid"


async def test_reregistration_does_not_revive_the_old_key(
    owner: Account, borrower: Account
) -> None:
    fixed = FIXED
    old = Signer.generate()
    await register_at(owner, old, fixed - timedelta(hours=2))
    listing, interaction = await accepted_at_time(owner, borrower, fixed)
    new = Signer.generate()
    with time_machine.travel(fixed + timedelta(hours=1), tick=False):
        assert (await register_key(owner, new)).status_code == 200

    old_after = offline_body(
        old,
        listing["id"],
        interaction["id"],
        user_id(owner),
        issued_at=fixed + timedelta(hours=2),
    )
    with time_machine.travel(fixed + timedelta(hours=3), tick=False):
        refused = await offline_scan(borrower, listing, interaction, old_after)
    assert refused.status_code == 403
    assert refused.json()["code"] == "qr_key_invalid"

    before_registration = offline_body(
        new,
        listing["id"],
        interaction["id"],
        user_id(owner),
        issued_at=fixed,
    )
    with time_machine.travel(fixed + timedelta(hours=3), tick=False):
        too_early = await offline_scan(
            borrower, listing, interaction, before_registration
        )
    assert too_early.status_code == 403
    assert too_early.json()["code"] == "qr_key_invalid"

    fresh = offline_body(
        new,
        listing["id"],
        interaction["id"],
        user_id(owner),
        issued_at=fixed + timedelta(hours=1),
    )
    with time_machine.travel(fixed + timedelta(hours=3), tick=False):
        completed = await offline_scan(borrower, listing, interaction, fresh)
    assert completed.status_code == 200, completed.text
    assert completed.json()["status"] == "completed"


async def test_outsider_same_participant_admin_and_anonymous_are_refused(
    owner: Account, borrower: Account, auth: Auth
) -> None:
    fixed = FIXED
    signer = Signer.generate()
    await register_at(owner, signer, fixed - timedelta(hours=1))
    listing, interaction = await accepted_at_time(owner, borrower, fixed)
    body = offline_body(
        signer,
        listing["id"],
        interaction["id"],
        user_id(owner),
        issued_at=fixed,
    )
    outsider = Account(
        auth, await auth.login(email="offline-outsider@university.example")
    )
    before = await counts(owner, UUID(interaction["id"]))

    with time_machine.travel(fixed + timedelta(minutes=1), tick=False):
        same = await offline_scan(owner, listing, interaction, body)
        stranger = await offline_scan(outsider, listing, interaction, body)

    assert same.status_code == 403
    assert same.json()["code"] == "qr_same_participant"
    assert stranger.status_code == 403
    assert stranger.json()["code"] == "qr_not_participant"

    db = owner.auth.db
    db.add(RoleAssignment(user_id=user_id(outsider), role=Role.ADMINISTRATOR))
    await db.commit()
    with time_machine.travel(fixed + timedelta(minutes=2), tick=False):
        administrator = await offline_scan(outsider, listing, interaction, body)
    assert administrator.status_code == 403
    assert administrator.json()["code"] == "qr_not_participant"

    with time_machine.travel(fixed + timedelta(minutes=3), tick=False):
        anonymous = await owner.auth.client.post(
            f"{ROOT}/{listing['id']}/interactions/{interaction['id']}/qr/offline",
            json=body,
            headers={"Idempotency-Key": str(uuid4())},
        )
    assert anonymous.status_code == 401
    assert anonymous.json()["code"] == "unauthorized"
    assert await counts(owner, UUID(interaction["id"])) == before


async def test_foreign_unknown_and_malformed_codes_leave_no_trace(
    owner: Account, borrower: Account, auth: Auth
) -> None:
    fixed = FIXED
    signer = Signer.generate()
    await register_at(owner, signer, fixed - timedelta(hours=1))
    listing, interaction = await accepted_at_time(owner, borrower, fixed)
    outsider = Account(
        auth, await auth.login(email="offline-key-owner@university.example")
    )
    outsider_signer = Signer.generate()
    await register_at(outsider, outsider_signer, fixed - timedelta(hours=1))
    before = await counts(owner, UUID(interaction["id"]))

    foreign = offline_body(
        outsider_signer,
        listing["id"],
        interaction["id"],
        user_id(outsider),
        issued_at=fixed,
    )
    unknown = offline_body(
        signer,
        listing["id"],
        interaction["id"],
        user_id(owner),
        issued_at=fixed,
        key_id=uuid4(),
    )
    body = offline_body(
        signer,
        listing["id"],
        interaction["id"],
        user_id(owner),
        issued_at=fixed,
    )
    document = payload_document(body)
    document["nonce"] = str(uuid4())
    tampered = {
        "payload": base64url_encode(
            json.dumps(document, separators=(",", ":"), sort_keys=True).encode()
        ),
        "signature": body["signature"],
    }

    with time_machine.travel(fixed + timedelta(minutes=1), tick=False):
        foreign_response = await offline_scan(outsider, listing, interaction, foreign)
        unknown_response = await offline_scan(borrower, listing, interaction, unknown)
        tampered_response = await offline_scan(borrower, listing, interaction, tampered)
        malformed_response = await offline_scan(
            borrower,
            listing,
            interaction,
            {"payload": "not base64", "signature": "also not"},
        )

    assert foreign_response.status_code == 403
    assert foreign_response.json()["code"] == "qr_not_participant"
    assert unknown_response.status_code == 403
    assert unknown_response.json()["code"] == "qr_key_invalid"
    assert tampered_response.status_code == 422
    assert tampered_response.json()["code"] == "qr_signature_invalid"
    assert malformed_response.status_code == 422
    assert malformed_response.json()["code"] == "qr_payload_invalid"
    assert await counts(owner, UUID(interaction["id"])) == before


async def test_payload_must_match_the_session_interaction(
    owner: Account, borrower: Account
) -> None:
    fixed = FIXED
    signer = Signer.generate()
    await register_at(owner, signer, fixed - timedelta(hours=1))
    listing, interaction = await accepted_at_time(owner, borrower, fixed)
    other_listing, other_interaction = await accepted_at_time(owner, borrower, fixed)
    body = offline_body(
        signer,
        listing["id"],
        interaction["id"],
        user_id(owner),
        issued_at=fixed,
    )
    other_body = offline_body(
        signer,
        other_listing["id"],
        other_interaction["id"],
        user_id(owner),
        issued_at=fixed,
    )

    with time_machine.travel(fixed + timedelta(minutes=1), tick=False):
        response = await owner.auth.client.post(
            f"{ROOT}/{other_listing['id']}/interactions/"
            f"{other_interaction['id']}/qr/offline",
            json=body,
            headers={
                "Idempotency-Key": str(uuid4()),
                **borrower.headers,
            },
        )
        mismatch = await offline_scan(
            borrower, other_listing, other_interaction, other_body
        )

    assert response.status_code == 422
    assert response.json()["code"] == "qr_payload_invalid"
    assert mismatch.status_code == 200, mismatch.text


@pytest.mark.parametrize(
    ("status", "completion_method", "expected"),
    [
        ("pending", None, "qr_not_accepted"),
        ("rejected", None, "qr_not_accepted"),
        ("cancelled", None, "qr_not_accepted"),
        ("no_show", None, "qr_not_accepted"),
        ("completed", "no_meeting", "qr_already_completed"),
    ],
)
async def test_only_an_accepted_interaction_is_completed(
    owner: Account,
    borrower: Account,
    status: str,
    completion_method: str | None,
    expected: str,
) -> None:
    fixed = FIXED
    signer = Signer.generate()
    await register_at(owner, signer, fixed - timedelta(hours=1))
    listing, interaction = await accepted_at_time(owner, borrower, fixed)
    body = offline_body(
        signer,
        listing["id"],
        interaction["id"],
        user_id(owner),
        issued_at=fixed,
    )
    db = owner.auth.db
    values: dict[str, Any] = {"status": status}
    if completion_method is not None:
        values.update(
            completion_method=completion_method,
            completed_at=fixed,
            completion_weight=0.5,
        )
    await db.execute(
        update(Interaction)
        .where(Interaction.id == UUID(interaction["id"]))
        .values(**values)
    )
    await db.commit()
    before = await counts(owner, UUID(interaction["id"]))

    with time_machine.travel(fixed + timedelta(minutes=1), tick=False):
        response = await offline_scan(borrower, listing, interaction, body)

    assert response.status_code == 409
    assert response.json()["code"] == expected
    assert await counts(owner, UUID(interaction["id"])) == before


async def test_completed_by_qr_refuses_an_unrelated_offline_id(
    owner: Account, borrower: Account
) -> None:
    fixed = FIXED
    signer = Signer.generate()
    await register_at(owner, signer, fixed - timedelta(hours=1))
    listing, interaction = await accepted_at_time(owner, borrower, fixed)
    first_body = offline_body(
        signer,
        listing["id"],
        interaction["id"],
        user_id(owner),
        issued_at=fixed,
    )
    with time_machine.travel(fixed + timedelta(minutes=1), tick=False):
        first = await offline_scan(borrower, listing, interaction, first_body)
    assert first.status_code == 200, first.text
    before = await counts(owner, UUID(interaction["id"]))
    second_body = offline_body(
        signer,
        listing["id"],
        interaction["id"],
        user_id(owner),
        issued_at=fixed + timedelta(minutes=2),
    )

    with time_machine.travel(fixed + timedelta(minutes=3), tick=False):
        repeated = await offline_scan(borrower, listing, interaction, second_body)

    assert repeated.status_code == 409
    assert repeated.json()["code"] == "qr_already_confirmed"
    assert await counts(owner, UUID(interaction["id"])) == before

    future_body = offline_body(
        signer,
        listing["id"],
        interaction["id"],
        user_id(owner),
        issued_at=fixed + timedelta(hours=1),
    )
    with time_machine.travel(fixed + timedelta(minutes=4), tick=False):
        invalid_time = await offline_scan(borrower, listing, interaction, future_body)
    assert invalid_time.status_code == 409
    assert invalid_time.json()["code"] == "qr_already_confirmed"
    assert await counts(owner, UUID(interaction["id"])) == before


async def test_personal_block_does_not_cancel_started_completion(
    owner: Account, borrower: Account
) -> None:
    fixed = FIXED
    signer = Signer.generate()
    await register_at(owner, signer, fixed - timedelta(hours=1))
    listing, interaction = await accepted_at_time(owner, borrower, fixed)
    db = owner.auth.db
    db.add(Block(blocker_id=user_id(borrower), blocked_id=user_id(owner)))
    await db.commit()
    body = offline_body(
        signer,
        listing["id"],
        interaction["id"],
        user_id(owner),
        issued_at=fixed,
    )

    with time_machine.travel(fixed + timedelta(minutes=1), tick=False):
        response = await offline_scan(borrower, listing, interaction, body)

    assert response.status_code == 200, response.text
    assert response.json()["status"] == "completed"


async def test_revoked_account_session_gets_401(
    owner: Account, borrower: Account
) -> None:
    fixed = FIXED
    signer = Signer.generate()
    await register_at(owner, signer, fixed - timedelta(hours=1))
    listing, interaction = await accepted_at_time(owner, borrower, fixed)
    body = offline_body(
        signer,
        listing["id"],
        interaction["id"],
        user_id(owner),
        issued_at=fixed,
    )
    signed_out = await borrower.auth.client.post(
        "/api/v1/auth/sign-out",
        headers={"Idempotency-Key": str(uuid4()), **borrower.headers},
    )
    assert signed_out.status_code == 204
    before = await counts(owner, UUID(interaction["id"]))

    with time_machine.travel(fixed + timedelta(minutes=1), tick=False):
        response = await offline_scan(borrower, listing, interaction, body)

    assert response.status_code == 401
    assert response.json()["code"] == "unauthorized"
    assert await counts(owner, UUID(interaction["id"])) == before


async def test_alumni_can_finish_a_previously_accepted_interaction(
    owner: Account, borrower: Account
) -> None:
    fixed = FIXED
    signer = Signer.generate()
    await register_at(owner, signer, fixed - timedelta(hours=1))
    listing, interaction = await accepted_at_time(owner, borrower, fixed)
    db = owner.auth.db
    await db.execute(
        update(User).where(User.id == user_id(borrower)).values(account_type="alumni")
    )
    await db.commit()
    body = offline_body(
        signer,
        listing["id"],
        interaction["id"],
        user_id(owner),
        issued_at=fixed,
    )

    with time_machine.travel(fixed + timedelta(minutes=1), tick=False):
        response = await offline_scan(borrower, listing, interaction, body)

    assert response.status_code == 200, response.text
    assert response.json()["status"] == "completed"


async def test_intermediate_loan_stage_is_refused_and_final_stage_completes(
    owner: Account, borrower: Account
) -> None:
    fixed = FIXED
    signer = Signer.generate()
    await register_at(owner, signer, fixed - timedelta(hours=1))
    listing, interaction = await accepted_at_time(owner, borrower, fixed)
    db = owner.auth.db
    await db.execute(
        update(Interaction)
        .where(Interaction.id == UUID(interaction["id"]))
        .values(stage="issued")
    )
    await db.commit()
    body = offline_body(
        signer,
        listing["id"],
        interaction["id"],
        user_id(owner),
        issued_at=fixed,
    )

    with time_machine.travel(fixed + timedelta(minutes=1), tick=False):
        intermediate = await offline_scan(borrower, listing, interaction, body)
    assert intermediate.status_code == 409
    assert intermediate.json()["code"] == "qr_stage_unavailable"
    await db.rollback()
    row = await db.get(Interaction, UUID(interaction["id"]))
    assert row is not None
    assert row.status == "accepted"
    assert row.stage == "issued"

    await db.execute(
        update(Interaction)
        .where(Interaction.id == UUID(interaction["id"]))
        .values(stage=None)
    )
    await db.commit()
    with time_machine.travel(fixed + timedelta(minutes=2), tick=False):
        final = await offline_scan(borrower, listing, interaction, body)
    assert final.status_code == 200, final.text
    assert final.json()["status"] == "completed"


async def test_unsupported_loan_kind_is_not_completed_like_a_giveaway(
    owner: Account, borrower: Account
) -> None:
    fixed = FIXED
    signer = Signer.generate()
    await register_at(owner, signer, fixed - timedelta(hours=1))
    listing, interaction = await accepted_at_time(owner, borrower, fixed)
    db = owner.auth.db
    listing_row = await db.get(Listing, UUID(listing["id"]))
    assert listing_row is not None
    listing_row.kind = "loan"
    await db.commit()
    body = offline_body(
        signer,
        listing["id"],
        interaction["id"],
        user_id(owner),
        issued_at=fixed,
    )

    with time_machine.travel(fixed + timedelta(minutes=1), tick=False):
        response = await offline_scan(borrower, listing, interaction, body)

    assert response.status_code == 409
    assert response.json()["code"] == "qr_unavailable"
    await db.rollback()
    row = await db.get(Interaction, UUID(interaction["id"]))
    assert row is not None
    assert row.status == "accepted"
    assert row.completion_method is None


async def test_missing_acceptance_event_fails_closed(
    owner: Account, borrower: Account
) -> None:
    fixed = FIXED
    signer = Signer.generate()
    await register_at(owner, signer, fixed - timedelta(hours=1))
    listing = await publish(owner)
    interaction = (await reserve(borrower, listing)).json()
    db = owner.auth.db
    await db.execute(
        update(Interaction)
        .where(Interaction.id == UUID(interaction["id"]))
        .values(status="accepted")
    )
    await db.commit()
    body = offline_body(
        signer,
        listing["id"],
        interaction["id"],
        user_id(owner),
        issued_at=fixed,
    )

    with time_machine.travel(fixed + timedelta(minutes=1), tick=False):
        response = await offline_scan(borrower, listing, interaction, body)

    assert response.status_code == 409
    assert response.json()["code"] == "qr_acceptance_unknown"
    await db.rollback()
    row = await db.get(Interaction, UUID(interaction["id"]))
    assert row is not None
    assert row.status == "accepted"


async def test_failed_transition_rolls_back_the_scan(
    owner: Account,
    borrower: Account,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    fixed = FIXED
    signer = Signer.generate()
    await register_at(owner, signer, fixed - timedelta(hours=1))
    listing, interaction = await accepted_at_time(owner, borrower, fixed)
    body = offline_body(
        signer,
        listing["id"],
        interaction["id"],
        user_id(owner),
        issued_at=fixed,
    )
    before = await counts(owner, UUID(interaction["id"]))

    async def fail(*_args: Any, **_kwargs: Any) -> None:
        raise RuntimeError("forced failure")

    monkeypatch.setattr("campus.modules.reputation.service.transition", fail)
    with time_machine.travel(fixed + timedelta(minutes=1), tick=False):
        response = await offline_scan(borrower, listing, interaction, body)

    assert response.status_code == 500
    assert await counts(owner, UUID(interaction["id"])) == before
    db = owner.auth.db
    await db.rollback()
    row = await db.get(Interaction, UUID(interaction["id"]))
    assert row is not None
    assert row.status == "accepted"
    assert row.completion_method is None


async def test_cancel_race_leaves_one_consistent_result(
    owner: Account, borrower: Account
) -> None:
    fixed = FIXED
    signer = Signer.generate()
    await register_at(owner, signer, fixed - timedelta(hours=1))
    listing, interaction = await accepted_at_time(owner, borrower, fixed)
    body = offline_body(
        signer,
        listing["id"],
        interaction["id"],
        user_id(owner),
        issued_at=fixed,
    )

    with time_machine.travel(fixed + timedelta(minutes=1), tick=False):
        scan_response, cancel_response = await asyncio.gather(
            offline_scan(borrower, listing, interaction, body),
            move(borrower, listing, interaction, "cancelled"),
        )

    assert cancel_response.status_code in (200, 409)
    db = owner.auth.db
    await db.rollback()
    row = await db.get(Interaction, UUID(interaction["id"]))
    assert row is not None
    status = row.status
    assert status in ("completed", "cancelled")
    scans = await scan_rows(owner, UUID(interaction["id"]))
    events = await qr_events(owner, UUID(interaction["id"]))
    if status == "completed":
        assert scan_response.status_code == 200
        assert len(scans) == 1
        assert len(events) == 1
        assert events[0].offline_qr is True
    else:
        assert scan_response.status_code == 409
        assert scan_response.json()["code"] == "qr_not_accepted"
        assert scans == []
        assert events == []


async def test_private_key_material_is_never_accepted(
    owner: Account, borrower: Account
) -> None:
    fixed = FIXED
    signer = Signer.generate()
    await register_at(owner, signer, fixed - timedelta(hours=1))
    private_key = signer.private.private_bytes_raw().hex()
    response = await owner.auth.client.put(
        "/api/v1/me/device-key",
        json={"public_key": signer.public_key, "private_key": private_key},
        headers={"Idempotency-Key": str(uuid4()), **owner.headers},
    )
    assert response.status_code == 422
    assert response.json()["code"] == "validation_failed"
    assert private_key not in response.text

    listing, interaction = await accepted_at_time(owner, borrower, fixed)
    body = offline_body(
        signer,
        listing["id"],
        interaction["id"],
        user_id(owner),
        issued_at=fixed,
        private_key=private_key,
    )
    with time_machine.travel(fixed + timedelta(minutes=1), tick=False):
        rejected = await offline_scan(borrower, listing, interaction, body)
    assert rejected.status_code == 422
    assert rejected.json()["code"] == "qr_payload_invalid"
    assert private_key not in rejected.text


async def test_offline_idempotency_replay_and_body_conflict(
    owner: Account, borrower: Account
) -> None:
    fixed = FIXED
    signer = Signer.generate()
    await register_at(owner, signer, fixed - timedelta(hours=1))
    listing, interaction = await accepted_at_time(owner, borrower, fixed)
    body = offline_body(
        signer,
        listing["id"],
        interaction["id"],
        user_id(owner),
        issued_at=fixed,
    )
    key = str(uuid4())
    with time_machine.travel(fixed + timedelta(minutes=1), tick=False):
        first = await offline_scan(borrower, listing, interaction, body, key=key)
        replay = await offline_scan(borrower, listing, interaction, body, key=key)
        changed = offline_body(
            signer,
            listing["id"],
            interaction["id"],
            user_id(owner),
            issued_at=fixed,
        )
        conflict = await offline_scan(borrower, listing, interaction, changed, key=key)

    assert first.status_code == 200, first.text
    assert replay.status_code == 200
    assert replay.headers["Idempotent-Replayed"] == "true"
    assert replay.json() == first.json()
    assert conflict.status_code == 422
    assert conflict.json()["code"] == "idempotency_key_reused"


async def test_server_time_exposes_the_offline_window(owner: Account) -> None:
    fixed = FIXED
    with time_machine.travel(fixed, tick=False):
        response = await owner.auth.client.get(TIME_URL)

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["qr_offline_ttl"] == 24 * 60 * 60
    assert body["qr_online_ttl"] == 30
