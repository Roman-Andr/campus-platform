"""Online QR confirmation: device keys, Ed25519, time window and races."""

import asyncio
import json
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID, uuid4

import httpx2
import pytest
import time_machine
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat
from sqlalchemy import func, select, update

from campus.core import clock
from campus.core.outbox import OutboxMessage
from campus.modules.identity import Role, RoleAssignment, Session, User
from campus.modules.listings import Interaction, Listing, ListingEvent
from campus.modules.reputation import (
    DeviceKey,
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

__all__ = ["auth", "borrower", "owner", "places", "staff"]

ROOT = "/api/v1/listings"
KEY_URL = "/api/v1/me/device-key"
TIME_URL = "/api/v1/time"


def instant(at: datetime) -> str:
    return at.astimezone(UTC).isoformat().replace("+00:00", "Z")


def parse_instant(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def set_settings(account: Account, **changes: Any) -> None:
    account.auth.settings = account.auth.settings.model_copy(update=changes)
    account.auth.app.state.settings = account.auth.settings


@dataclass
class Signer:
    private: Ed25519PrivateKey
    key_id: UUID | None = None

    @classmethod
    def generate(cls) -> Signer:
        return cls(Ed25519PrivateKey.generate())

    @property
    def public_key(self) -> str:
        raw = self.private.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)
        return base64url_encode(raw)

    def body(  # noqa: PLR0913 - a test payload builder
        self,
        listing_id: UUID | str,
        interaction_id: UUID | str,
        presenter_id: UUID | str,
        *,
        issued_at: datetime | None = None,
        nonce: UUID | None = None,
        key_id: UUID | str | None = None,
        sign: bool = True,
        **overrides: Any,
    ) -> dict[str, str]:
        if self.key_id is None and key_id is None:
            raise AssertionError("register the signer first")
        document: dict[str, Any] = {
            "v": 1,
            "listing_id": str(listing_id),
            "interaction_id": str(interaction_id),
            "presenter_id": str(presenter_id),
            "key_id": str(key_id or self.key_id),
            "issued_at": instant(issued_at or clock.now()),
            "nonce": str(nonce or uuid4()),
            **overrides,
        }
        raw = json.dumps(
            document, ensure_ascii=False, separators=(",", ":"), sort_keys=True
        ).encode()
        signature = self.private.sign(raw) if sign else b"\x00" * 64
        return {
            "payload": base64url_encode(raw),
            "signature": base64url_encode(signature),
        }


async def register_key(
    account: Account, signer: Signer, key: str | None = None
) -> httpx2.Response:
    response = await account.auth.client.put(
        KEY_URL,
        json={"public_key": signer.public_key},
        headers={"Idempotency-Key": key or str(uuid4()), **account.headers},
    )
    if response.status_code == 200:
        signer.key_id = UUID(response.json()["id"])
    return response


async def revoke_key(account: Account, key: str | None = None) -> httpx2.Response:
    return await account.auth.client.delete(
        KEY_URL,
        headers={"Idempotency-Key": key or str(uuid4()), **account.headers},
    )


async def scan(
    account: Account,
    listing: dict[str, Any],
    interaction: dict[str, Any],
    body: dict[str, str],
    key: str | None = None,
) -> httpx2.Response:
    return await account.auth.client.post(
        f"{ROOT}/{listing['id']}/interactions/{interaction['id']}/qr",
        json=body,
        headers={"Idempotency-Key": key or str(uuid4()), **account.headers},
    )


async def accepted(
    author: Account, participant: Account
) -> tuple[dict[str, Any], dict[str, Any]]:
    listing = await publish(author)
    interaction = (await reserve(participant, listing)).json()
    response = await move(author, listing, interaction, "accepted")
    assert response.status_code == 200, response.text
    return listing, response.json()


def user_id(account: Account) -> UUID:
    return UUID(account.tokens["user"]["id"])


async def counts(account: Account, interaction_id: UUID) -> tuple[int, int, int, int]:
    """Journal, outbox, scans and completed rows for one interaction."""
    db = account.auth.db
    await db.rollback()
    events = await db.scalar(
        select(func.count())
        .select_from(ListingEvent)
        .where(ListingEvent.interaction_id == interaction_id)
    )
    outbox = await db.scalar(select(func.count()).select_from(OutboxMessage))
    scans = await db.scalar(
        select(func.count())
        .select_from(QrScan)
        .where(QrScan.interaction_id == interaction_id)
    )
    completed = await db.scalar(
        select(func.count())
        .select_from(ListingEvent)
        .where(
            ListingEvent.interaction_id == interaction_id,
            ListingEvent.action == "qr_completed",
        )
    )
    return int(events or 0), int(outbox or 0), int(scans or 0), int(completed or 0)


@pytest.mark.parametrize("presenter", ["author", "participant"])
async def test_qr_completes_accepted_interaction(
    owner: Account, borrower: Account, presenter: str
) -> None:
    listing, interaction = await accepted(owner, borrower)
    showing = owner if presenter == "author" else borrower
    scanning = borrower if presenter == "author" else owner
    signer = Signer.generate()
    assert (await register_key(showing, signer)).status_code == 200
    before = await counts(owner, UUID(interaction["id"]))

    response = await scan(
        scanning,
        listing,
        interaction,
        signer.body(listing["id"], interaction["id"], user_id(showing)),
    )

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["status"] == "completed"
    assert body["completed"] is True
    assert body["completion_method"] == "qr"
    assert body["rating_weight"] == 1.0
    assert body["presenter_id"] == str(user_id(showing))
    assert body["scanner_id"] == str(user_id(scanning))
    assert body["completed_at"] is not None
    assert body["server_time"].endswith("Z")

    db = owner.auth.db
    await db.rollback()
    row = await db.get(Interaction, UUID(interaction["id"]))
    assert row is not None
    assert row.status == "completed"
    assert row.completion_method == "qr"
    assert row.completed_at is not None
    events = list(
        await db.scalars(
            select(ListingEvent)
            .where(ListingEvent.interaction_id == UUID(interaction["id"]))
            .order_by(ListingEvent.created_at, ListingEvent.id)
        )
    )
    assert events[-1].action == "qr_completed"
    assert events[-1].details is not None
    assert events[-1].details["method"] == "qr"
    assert events[-1].details["presenter_id"] == str(user_id(showing))
    assert events[-1].offline_qr is False
    after = await counts(owner, UUID(interaction["id"]))
    # Completion closes the listing, records the event and queues the profile
    # aggregate refresh: one journal event and three outbox rows.
    assert after[0] == before[0] + 1
    assert after[1] == before[1] + 3
    assert after[2:] == (1, 1)
    listing_row = await db.get(Listing, UUID(listing["id"]))
    assert listing_row is not None
    assert listing_row.status == "completed"
    scan_row = await db.scalar(
        select(QrScan).where(QrScan.interaction_id == UUID(interaction["id"]))
    )
    assert scan_row is not None
    assert scan_row.result == "completed"
    assert scan_row.presenter_id == user_id(showing)
    assert scan_row.scanner_id == user_id(scanning)


async def test_key_registration_returns_only_public_material(
    owner: Account,
) -> None:
    signer = Signer.generate()
    response = await register_key(owner, signer)

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["algorithm"] == "ed25519"
    assert body["public_key"] == signer.public_key
    assert body["registered_at"].endswith("Z")
    assert body["revoked_at"] is None
    assert "private" not in json.dumps(body).lower()
    assert set(body) == {
        "id",
        "algorithm",
        "public_key",
        "registered_at",
        "revoked_at",
    }

    db = owner.auth.db
    await db.rollback()
    row = await db.get(DeviceKey, UUID(body["id"]))
    assert row is not None
    assert len(bytes(row.public_key)) == 32
    assert len(signer.public_key) == 43


async def test_key_registration_requires_an_active_session(owner: Account) -> None:
    signer = Signer.generate()
    response = await owner.auth.client.put(
        KEY_URL,
        json={"public_key": signer.public_key},
        headers={"Idempotency-Key": str(uuid4())},
    )

    assert response.status_code == 401
    assert response.json()["code"] == "unauthorized"

    signed_out = await owner.auth.client.post(
        "/api/v1/auth/sign-out",
        headers={"Idempotency-Key": str(uuid4()), **owner.headers},
    )
    assert signed_out.status_code == 204
    response = await owner.auth.client.put(
        KEY_URL,
        json={"public_key": signer.public_key},
        headers={"Idempotency-Key": str(uuid4()), **owner.headers},
    )
    assert response.status_code == 401


@pytest.mark.parametrize(
    "public_key",
    [
        "!" * 43,
        base64url_encode(b"x" * 31),
        base64url_encode(b"x" * 33),
    ],
)
async def test_invalid_device_key_is_a_validation_problem(
    owner: Account, public_key: str
) -> None:
    response = await owner.auth.client.put(
        KEY_URL,
        json={"public_key": public_key},
        headers={"Idempotency-Key": str(uuid4()), **owner.headers},
    )

    assert response.status_code == 422
    assert response.headers["content-type"] == "application/problem+json"
    assert response.json()["code"] == "validation_failed"


async def test_public_key_is_unique_across_users(
    owner: Account, borrower: Account
) -> None:
    signer = Signer.generate()
    assert (await register_key(owner, signer)).status_code == 200

    response = await register_key(borrower, signer)

    assert response.status_code == 409
    assert response.json()["code"] == "device_key_conflict"


async def test_replacement_revokes_the_previous_key(
    owner: Account, borrower: Account
) -> None:
    listing, interaction = await accepted(owner, borrower)
    old = Signer.generate()
    new = Signer.generate()
    assert (await register_key(owner, old)).status_code == 200
    old_key_id = old.key_id
    assert (await register_key(owner, new)).status_code == 200
    assert new.key_id != old_key_id

    db = owner.auth.db
    await db.rollback()
    old_row = await db.get(DeviceKey, old_key_id)
    assert old_row is not None
    assert old_row.revoked_at is not None
    active = await db.scalar(
        select(func.count())
        .select_from(DeviceKey)
        .where(
            DeviceKey.session_id == old_row.session_id,
            DeviceKey.revoked_at.is_(None),
        )
    )
    assert active == 1

    refused = await scan(
        borrower,
        listing,
        interaction,
        old.body(listing["id"], interaction["id"], user_id(owner)),
    )
    assert refused.status_code == 403
    assert refused.json()["code"] == "qr_key_invalid"

    completed = await scan(
        borrower,
        listing,
        interaction,
        new.body(listing["id"], interaction["id"], user_id(owner)),
    )
    assert completed.status_code == 200, completed.text


async def test_reinstall_revokes_old_session_key(
    owner: Account, borrower: Account, auth: Auth
) -> None:
    old_signer = Signer.generate()
    assert (await register_key(borrower, old_signer)).status_code == 200
    old_key_id = old_signer.key_id
    db = owner.auth.db
    await db.rollback()
    old_session = await db.scalar(
        select(Session.id).where(Session.user_id == user_id(borrower))
    )

    reinstalled = Account(auth, await auth.login(email="borrower@university.example"))
    new_signer = Signer.generate()
    assert (await register_key(reinstalled, new_signer)).status_code == 200

    db = owner.auth.db
    await db.rollback()
    old_row = await db.get(DeviceKey, old_key_id)
    assert old_row is not None
    assert old_row.revoked_at is not None
    assert old_session is not None
    old_session_row = await db.get(Session, old_session)
    assert old_session_row is not None
    assert old_session_row.revoked_at is not None

    listing, interaction = await accepted(owner, reinstalled)
    refused = await scan(
        owner,
        listing,
        interaction,
        old_signer.body(listing["id"], interaction["id"], user_id(reinstalled)),
    )
    assert refused.status_code == 403
    assert refused.json()["code"] == "qr_key_invalid"


async def test_revoked_key_and_unknown_key_are_refused(
    owner: Account, borrower: Account
) -> None:
    listing, interaction = await accepted(owner, borrower)
    signer = Signer.generate()
    assert (await register_key(owner, signer)).status_code == 200

    unknown = signer.body(
        listing["id"], interaction["id"], user_id(owner), key_id=uuid4()
    )
    response = await scan(borrower, listing, interaction, unknown)
    assert response.status_code == 403
    assert response.json()["code"] == "qr_key_invalid"

    assert (await revoke_key(owner)).status_code == 204
    response = await scan(
        borrower,
        listing,
        interaction,
        signer.body(listing["id"], interaction["id"], user_id(owner)),
    )
    assert response.status_code == 403
    assert response.json()["code"] == "qr_key_invalid"

    repeated = await revoke_key(owner)
    assert repeated.status_code == 204


async def test_foreign_key_is_refused(
    owner: Account, borrower: Account, auth: Auth
) -> None:
    outsider = Account(auth, await auth.login(email="key-owner@university.example"))
    signer = Signer.generate()
    assert (await register_key(outsider, signer)).status_code == 200
    listing, interaction = await accepted(owner, borrower)
    body = signer.body(listing["id"], interaction["id"], user_id(owner))

    response = await scan(borrower, listing, interaction, body)

    assert response.status_code == 403
    assert response.json()["code"] == "qr_key_invalid"


async def test_tampered_payload_and_bad_signature_leave_no_trace(
    owner: Account, borrower: Account
) -> None:
    listing, interaction = await accepted(owner, borrower)
    signer = Signer.generate()
    assert (await register_key(owner, signer)).status_code == 200
    before = await counts(owner, UUID(interaction["id"]))

    body = signer.body(listing["id"], interaction["id"], user_id(owner))
    document = json.loads(base64url_decode(body["payload"]))
    document["nonce"] = str(uuid4())
    body["payload"] = base64url_encode(
        json.dumps(document, separators=(",", ":"), sort_keys=True).encode()
    )
    tampered = await scan(borrower, listing, interaction, body)
    assert tampered.status_code == 422
    assert tampered.json()["code"] == "qr_signature_invalid"

    bad_signature = signer.body(listing["id"], interaction["id"], user_id(owner))
    bad_signature["signature"] = base64url_encode(b"\x00" * 64)
    rejected = await scan(borrower, listing, interaction, bad_signature)
    assert rejected.status_code == 422
    assert rejected.json()["code"] == "qr_signature_invalid"

    malformed = await scan(
        borrower,
        listing,
        interaction,
        {"payload": "not base64", "signature": "also not"},
    )
    assert malformed.status_code == 422
    assert malformed.json()["code"] == "qr_payload_invalid"

    assert await counts(owner, UUID(interaction["id"])) == before


@pytest.mark.parametrize(
    ("status", "code"),
    [
        ("pending", "qr_not_accepted"),
        ("rejected", "qr_not_accepted"),
        ("cancelled", "qr_not_accepted"),
        ("no_show", "qr_not_accepted"),
        ("completed", "qr_already_completed"),
    ],
)
async def test_only_an_accepted_interaction_completes(
    owner: Account, borrower: Account, status: str, code: str
) -> None:
    listing, interaction = await accepted(owner, borrower)
    signer = Signer.generate()
    assert (await register_key(owner, signer)).status_code == 200
    db = owner.auth.db
    await db.execute(
        update(Interaction)
        .where(Interaction.id == UUID(interaction["id"]))
        .values(status=status)
    )
    await db.commit()

    before = await counts(owner, UUID(interaction["id"]))
    response = await scan(
        borrower,
        listing,
        interaction,
        signer.body(listing["id"], interaction["id"], user_id(owner)),
    )

    assert response.status_code == 409, response.text
    assert response.json()["code"] == code
    assert await counts(owner, UUID(interaction["id"])) == before


async def test_completed_by_no_meeting_is_not_replaced(
    owner: Account, borrower: Account
) -> None:
    listing, interaction = await accepted(owner, borrower)
    signer = Signer.generate()
    assert (await register_key(owner, signer)).status_code == 200
    db = owner.auth.db
    await db.execute(
        update(Interaction)
        .where(Interaction.id == UUID(interaction["id"]))
        .values(
            status="completed",
            completion_method="no_meeting",
            completed_at=clock.now(),
            completion_weight=0.5,
        )
    )
    await db.commit()

    response = await scan(
        borrower,
        listing,
        interaction,
        signer.body(listing["id"], interaction["id"], user_id(owner)),
    )

    assert response.status_code == 409
    assert response.json()["code"] == "qr_already_completed"


async def test_qr_after_qr_completion_is_idempotent(
    owner: Account, borrower: Account
) -> None:
    listing, interaction = await accepted(owner, borrower)
    signer = Signer.generate()
    assert (await register_key(owner, signer)).status_code == 200
    first = await scan(
        borrower,
        listing,
        interaction,
        signer.body(listing["id"], interaction["id"], user_id(owner)),
    )
    assert first.status_code == 200
    before = await counts(owner, UUID(interaction["id"]))

    repeated = await scan(
        borrower,
        listing,
        interaction,
        signer.body(listing["id"], interaction["id"], user_id(owner)),
    )

    assert repeated.status_code == 200
    assert repeated.json()["completed_at"] == first.json()["completed_at"]
    assert await counts(owner, UUID(interaction["id"])) == before


async def test_outsider_same_participant_admin_and_anonymous_are_refused(
    owner: Account, borrower: Account, auth: Auth
) -> None:
    listing, interaction = await accepted(owner, borrower)
    signer = Signer.generate()
    assert (await register_key(owner, signer)).status_code == 200
    body = signer.body(listing["id"], interaction["id"], user_id(owner))

    outsider = Account(auth, await auth.login(email="outsider@university.example"))
    before = await counts(owner, UUID(interaction["id"]))
    same = await scan(owner, listing, interaction, body)
    assert same.status_code == 403
    assert same.json()["code"] == "qr_same_participant"

    stranger = await scan(outsider, listing, interaction, body)
    assert stranger.status_code == 403
    assert stranger.json()["code"] == "qr_not_participant"

    outsider_signer = Signer.generate()
    assert (await register_key(outsider, outsider_signer)).status_code == 200
    outsider_body = outsider_signer.body(
        listing["id"], interaction["id"], user_id(outsider)
    )
    presenter = await scan(borrower, listing, interaction, outsider_body)
    assert presenter.status_code == 403
    assert presenter.json()["code"] == "qr_not_participant"

    db = owner.auth.db
    db.add(RoleAssignment(user_id=user_id(outsider), role=Role.ADMINISTRATOR))
    await db.commit()
    administrator = await scan(outsider, listing, interaction, body)
    assert administrator.status_code == 403
    assert administrator.json()["code"] == "qr_not_participant"

    anonymous = await auth.client.post(
        f"{ROOT}/{listing['id']}/interactions/{interaction['id']}/qr",
        json=body,
        headers={"Idempotency-Key": str(uuid4())},
    )
    assert anonymous.status_code == 401
    assert anonymous.json()["code"] == "unauthorized"

    assert await counts(owner, UUID(interaction["id"])) == before


async def test_revoked_session_is_refused(owner: Account, borrower: Account) -> None:
    listing, interaction = await accepted(owner, borrower)
    signer = Signer.generate()
    assert (await register_key(owner, signer)).status_code == 200
    body = signer.body(listing["id"], interaction["id"], user_id(owner))

    signed_out = await borrower.auth.client.post(
        "/api/v1/auth/sign-out",
        headers={"Idempotency-Key": str(uuid4()), **borrower.headers},
    )
    assert signed_out.status_code == 204

    response = await scan(borrower, listing, interaction, body)
    assert response.status_code == 401
    assert response.json()["code"] == "unauthorized"


async def test_graduate_completes_previously_accepted_interaction(
    owner: Account, borrower: Account
) -> None:
    listing, interaction = await accepted(owner, borrower)
    signer = Signer.generate()
    assert (await register_key(owner, signer)).status_code == 200
    db = owner.auth.db
    await db.execute(
        update(User).where(User.id == user_id(borrower)).values(account_type="alumni")
    )
    await db.commit()

    response = await scan(
        borrower,
        listing,
        interaction,
        signer.body(listing["id"], interaction["id"], user_id(owner)),
    )

    assert response.status_code == 200, response.text
    assert response.json()["status"] == "completed"


async def test_employee_completes_own_interaction(
    staff: Account, borrower: Account
) -> None:
    listing = await publish(staff, audience="community")
    interaction = (await reserve(borrower, listing)).json()
    accepted_response = await move(staff, listing, interaction, "accepted")
    assert accepted_response.status_code == 200, accepted_response.text
    interaction = accepted_response.json()
    signer = Signer.generate()
    assert (await register_key(staff, signer)).status_code == 200

    response = await scan(
        borrower,
        listing,
        interaction,
        signer.body(listing["id"], interaction["id"], user_id(staff)),
    )

    assert response.status_code == 200, response.text
    assert response.json()["status"] == "completed"


async def test_qr_idempotency_replay_and_body_conflict(
    owner: Account, borrower: Account
) -> None:
    listing, interaction = await accepted(owner, borrower)
    signer = Signer.generate()
    assert (await register_key(owner, signer)).status_code == 200
    key = str(uuid4())
    body = signer.body(listing["id"], interaction["id"], user_id(owner))

    first = await scan(borrower, listing, interaction, body, key=key)
    assert first.status_code == 200
    before = await counts(owner, UUID(interaction["id"]))
    replay = await scan(borrower, listing, interaction, body, key=key)
    assert replay.status_code == 200
    assert replay.headers["Idempotent-Replayed"] == "true"
    assert replay.json() == first.json()
    assert await counts(owner, UUID(interaction["id"])) == before

    changed = signer.body(listing["id"], interaction["id"], user_id(owner))
    conflict = await scan(borrower, listing, interaction, changed, key=key)
    assert conflict.status_code == 422
    assert conflict.json()["code"] == "idempotency_key_reused"


async def test_key_registration_idempotency(
    owner: Account,
) -> None:
    signer = Signer.generate()
    first = await register_key(owner, signer)
    assert first.status_code == 200
    key = str(uuid4())
    first = await register_key(owner, signer, key=key)
    replay = await register_key(owner, signer, key=key)
    assert first.status_code == 200
    assert replay.headers["Idempotent-Replayed"] == "true"
    assert replay.json() == first.json()

    other = Signer.generate()
    conflict = await register_key(owner, other, key=key)
    assert conflict.status_code == 422
    assert conflict.json()["code"] == "idempotency_key_reused"


async def test_parallel_scans_complete_exactly_once(
    owner: Account, borrower: Account
) -> None:
    listing, interaction = await accepted(owner, borrower)
    signer = Signer.generate()
    assert (await register_key(owner, signer)).status_code == 200
    before = await counts(owner, UUID(interaction["id"]))
    first = signer.body(listing["id"], interaction["id"], user_id(owner))
    second = signer.body(listing["id"], interaction["id"], user_id(owner))

    responses = await asyncio.gather(
        scan(borrower, listing, interaction, first),
        scan(borrower, listing, interaction, second),
    )

    assert [response.status_code for response in responses] == [200, 200]
    after = await counts(owner, UUID(interaction["id"]))
    # Completion closes the listing, records the event and queues the profile
    # aggregate refresh: one journal event and three outbox rows.
    assert after[0] == before[0] + 1
    assert after[1] == before[1] + 3
    assert after[2:] == (1, 1)


async def test_parallel_replay_of_one_nonce_completes_once(
    owner: Account, borrower: Account
) -> None:
    listing, interaction = await accepted(owner, borrower)
    signer = Signer.generate()
    assert (await register_key(owner, signer)).status_code == 200
    body = signer.body(listing["id"], interaction["id"], user_id(owner))
    before = await counts(owner, UUID(interaction["id"]))

    responses = await asyncio.gather(
        scan(borrower, listing, interaction, body),
        scan(borrower, listing, interaction, body),
    )

    assert sorted(response.status_code for response in responses) == [200, 409]
    refused = next(response for response in responses if response.status_code == 409)
    assert refused.json()["code"] == "qr_nonce_reused"
    after = await counts(owner, UUID(interaction["id"]))
    # Completion closes the listing, records the event and queues the profile
    # aggregate refresh: one journal event and three outbox rows.
    assert after[0] == before[0] + 1
    assert after[1] == before[1] + 3
    assert after[2:] == (1, 1)


async def test_cancel_race_is_consistent(owner: Account, borrower: Account) -> None:
    listing, interaction = await accepted(owner, borrower)
    signer = Signer.generate()
    assert (await register_key(owner, signer)).status_code == 200
    body = signer.body(listing["id"], interaction["id"], user_id(owner))

    scan_response, cancel_response = await asyncio.gather(
        scan(borrower, listing, interaction, body),
        move(borrower, listing, interaction, "cancelled"),
    )

    assert scan_response.status_code in (200, 409)
    assert cancel_response.status_code in (200, 409)
    db = owner.auth.db
    await db.rollback()
    row = await db.get(Interaction, UUID(interaction["id"]))
    assert row is not None
    assert row.status in ("completed", "cancelled")
    qr_events = await db.scalar(
        select(func.count())
        .select_from(ListingEvent)
        .where(
            ListingEvent.interaction_id == UUID(interaction["id"]),
            ListingEvent.action == "qr_completed",
        )
    )
    scans = await db.scalar(
        select(func.count())
        .select_from(QrScan)
        .where(QrScan.interaction_id == UUID(interaction["id"]))
    )
    if row.status == "completed":
        assert qr_events == 1
        assert scans == 1
        assert scan_response.status_code == 200
    else:
        assert qr_events == 0
        assert scans == 0
        assert scan_response.status_code == 409
        assert scan_response.json()["code"] == "qr_not_accepted"


async def test_failed_transition_rolls_back_scan_and_outbox(
    owner: Account,
    borrower: Account,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    listing, interaction = await accepted(owner, borrower)
    signer = Signer.generate()
    assert (await register_key(owner, signer)).status_code == 200
    before = await counts(owner, UUID(interaction["id"]))

    async def fail(*_args: Any, **_kwargs: Any) -> None:
        raise RuntimeError("forced failure")

    monkeypatch.setattr("campus.modules.reputation.service.transition", fail)
    response = await scan(
        borrower,
        listing,
        interaction,
        signer.body(listing["id"], interaction["id"], user_id(owner)),
    )

    assert response.status_code == 500
    assert await counts(owner, UUID(interaction["id"])) == before
    db = owner.auth.db
    await db.rollback()
    row = await db.get(Interaction, UUID(interaction["id"]))
    assert row is not None
    assert row.status == "accepted"
    assert row.completion_method is None


@pytest.mark.parametrize(
    ("delta", "accepted_scan"),
    [
        (-10, True),
        (-9, True),
        (0, True),
        (10, True),
        (30, True),
        (-11, False),
        (-30, False),
        (-40, False),
        (31, False),
        (40, False),
    ],
)
async def test_online_qr_delta_boundaries(
    owner: Account,
    borrower: Account,
    delta: int,
    accepted_scan: bool,
) -> None:
    listing, interaction = await accepted(owner, borrower)
    signer = Signer.generate()
    assert (await register_key(owner, signer)).status_code == 200
    fixed = clock.now()
    issued = fixed - timedelta(seconds=delta)

    with time_machine.travel(fixed, tick=False):
        response = await scan(
            borrower,
            listing,
            interaction,
            signer.body(
                listing["id"],
                interaction["id"],
                user_id(owner),
                issued_at=issued,
            ),
        )

    if accepted_scan:
        assert response.status_code == 200, response.text
        assert response.json()["status"] == "completed"
    else:
        assert response.status_code == 409
        assert response.json()["code"] == (
            "qr_expired" if delta > 0 else "qr_not_yet_valid"
        )


async def test_qr_window_is_configurable(owner: Account, borrower: Account) -> None:
    listing, interaction = await accepted(owner, borrower)
    signer = Signer.generate()
    assert (await register_key(owner, signer)).status_code == 200
    set_settings(
        owner,
        qr_online_ttl=timedelta(seconds=5),
        qr_clock_skew=timedelta(seconds=2),
    )
    fixed = clock.now()

    with time_machine.travel(fixed, tick=False):
        too_old = await scan(
            borrower,
            listing,
            interaction,
            signer.body(
                listing["id"],
                interaction["id"],
                user_id(owner),
                issued_at=fixed - timedelta(seconds=6),
            ),
        )
        too_future = await scan(
            borrower,
            listing,
            interaction,
            signer.body(
                listing["id"],
                interaction["id"],
                user_id(owner),
                issued_at=fixed + timedelta(seconds=3),
            ),
        )
        edge = await scan(
            borrower,
            listing,
            interaction,
            signer.body(
                listing["id"],
                interaction["id"],
                user_id(owner),
                issued_at=fixed - timedelta(seconds=5),
            ),
        )

    assert too_old.status_code == 409
    assert too_old.json()["code"] == "qr_expired"
    assert too_future.status_code == 409
    assert too_future.json()["code"] == "qr_not_yet_valid"
    assert edge.status_code == 200, edge.text


async def test_server_time_exposes_clock_and_window(owner: Account) -> None:
    fixed = clock.now().replace(microsecond=0)
    with time_machine.travel(fixed, tick=False):
        response = await owner.auth.client.get(TIME_URL)

    assert response.status_code == 200, response.text
    body = response.json()
    assert parse_instant(body["now"]) == fixed
    assert body["qr_online_ttl"] == 30
    assert body["qr_clock_skew"] == 10


async def test_intermediate_stage_is_not_the_final_completion(
    owner: Account, borrower: Account
) -> None:
    listing, interaction = await accepted(owner, borrower)
    signer = Signer.generate()
    assert (await register_key(owner, signer)).status_code == 200
    db = owner.auth.db
    await db.execute(
        update(Interaction)
        .where(Interaction.id == UUID(interaction["id"]))
        .values(stage="issued")
    )
    await db.commit()

    response = await scan(
        borrower,
        listing,
        interaction,
        signer.body(listing["id"], interaction["id"], user_id(owner)),
    )

    assert response.status_code == 409
    assert response.json()["code"] == "qr_stage_unavailable"
    await db.rollback()
    row = await db.get(Interaction, UUID(interaction["id"]))
    assert row is not None
    assert row.status == "accepted"
    assert row.stage == "issued"


async def test_session_revocation_marks_the_key_revoked(owner: Account) -> None:
    signer = Signer.generate()
    response = await register_key(owner, signer)
    assert response.status_code == 200

    signed_out = await owner.auth.client.post(
        "/api/v1/auth/sign-out",
        headers={"Idempotency-Key": str(uuid4()), **owner.headers},
    )
    assert signed_out.status_code == 204

    db = owner.auth.db
    await db.rollback()
    row = await db.get(DeviceKey, signer.key_id)
    assert row is not None
    assert row.revoked_at is not None
