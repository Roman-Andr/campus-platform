"""Event attendance on PostgreSQL: modes, boundaries, races and recovery.

The tests use the real HTTP API and controlled time. They pin the inclusive
marking window and rotating-code lifetime, the role matrix of both modes,
the shared organiser code that must not be consumed by its first scanner,
parallel scans of one participant, soft removal, the realtime outbox written
only with a committed mark, and the contract the future no-show logic reads.
"""

import asyncio
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID, uuid4

import httpx2
import pytest
import time_machine
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker

from campus.core import clock
from campus.core.db import create_session_factory
from campus.core.outbox import OutboxMessage, process_outbox
from campus.modules.listings import AttendanceMode, ListingEvent, locked
from campus.modules.reputation import (
    AttendanceRecord,
    current_attendance_participant_ids,
)
from campus.modules.reputation.attendance import accepted_interaction, record_mark
from tests.test_identity import Auth
from tests.test_listings import (
    auth,
    borrower,
    move,
    owner,
    places,
    request,
)
from tests.test_profile import Account, Places, moscow_profile

__all__ = ["auth", "borrower", "owner", "places"]

ROOT = "/api/v1/listings"
ATTENDANCE_TOPIC = "listing.attendance"
FIXED = datetime(2026, 11, 15, 12, 0, tzinfo=UTC)


@pytest.fixture(autouse=True)
def long_lived_access(auth: Auth) -> None:
    """Keep access tokens valid while tests move time by hours."""
    auth.settings = auth.settings.model_copy(
        update={"access_token_ttl": timedelta(days=365)}
    )
    auth.app.state.settings = auth.settings


@pytest.fixture
async def sessions(engine: AsyncEngine) -> async_sessionmaker[AsyncSession]:
    return create_session_factory(engine)


def instant(at: datetime) -> str:
    return at.astimezone(UTC).isoformat().replace("+00:00", "Z")


def parse_instant(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def user_id(account: Account) -> UUID:
    return UUID(account.tokens["user"]["id"])


def new_key() -> str:
    return str(uuid4())


async def student(auth: Auth, places: Places, number: int) -> Account:
    account = Account(
        auth, await auth.login(email=f"attendance{number}@university.example")
    )
    assert (await account.put(moscow_profile(places))).status_code == 200
    return account


async def event_at(
    account: Account,
    starts_at: datetime,
    ends_at: datetime,
    **overrides: Any,
) -> dict[str, Any]:
    category = (await request(account, "GET", "/categories")).json()["items"][0]["id"]
    response = await request(
        account,
        "POST",
        "/events",
        {
            "title": "Campus concert",
            "description": "Meet in the hall",
            "category_id": category,
            "starts_at": instant(starts_at),
            "ends_at": instant(ends_at),
            "location": "Hall A",
            "capacity": 10,
            **overrides,
        },
    )
    assert response.status_code == 201, response.text
    result: dict[str, Any] = response.json()
    return result


async def signup(account: Account, listing: dict[str, Any]) -> dict[str, Any]:
    response = await request(
        account, "POST", f"/{listing['id']}/signup", {"join_queue": False}
    )
    assert response.status_code == 200, response.text
    result: dict[str, Any] = response.json()["interaction"]
    return result


async def issue_qr(
    account: Account, listing: dict[str, Any], key: str | None = None
) -> httpx2.Response:
    return await request(
        account, "POST", f"/{listing['id']}/event/attendance/qr", key=key
    )


async def issue_code(
    account: Account, listing: dict[str, Any], key: str | None = None
) -> httpx2.Response:
    return await request(
        account, "POST", f"/{listing['id']}/event/attendance/code", key=key
    )


async def check_in(
    account: Account,
    listing: dict[str, Any],
    code: str,
    key: str | None = None,
) -> httpx2.Response:
    return await request(
        account,
        "POST",
        f"/{listing['id']}/event/attendance/self",
        {"code": code},
        key=key,
    )


async def scan(
    account: Account,
    listing: dict[str, Any],
    code: str,
    key: str | None = None,
) -> httpx2.Response:
    return await request(
        account,
        "POST",
        f"/{listing['id']}/event/attendance/scan",
        {"code": code},
        key=key,
    )


async def set_mode(
    account: Account, listing: dict[str, Any], mode: AttendanceMode
) -> httpx2.Response:
    return await request(
        account,
        "PUT",
        f"/{listing['id']}/event/attendance/mode",
        {"mode": mode.value},
    )


async def attendance_list(account: Account, listing: dict[str, Any]) -> httpx2.Response:
    return await request(account, "GET", f"/{listing['id']}/event/attendance")


async def remove(
    account: Account,
    listing: dict[str, Any],
    participant_id: UUID,
    key: str | None = None,
) -> httpx2.Response:
    return await request(
        account,
        "DELETE",
        f"/{listing['id']}/event/attendance/{participant_id}",
        key=key,
    )


async def stored_messages(account: Account, listing_id: UUID) -> list[OutboxMessage]:
    db = account.auth.db
    await db.rollback()
    messages = list(
        await db.scalars(
            select(OutboxMessage)
            .where(OutboxMessage.topic == ATTENDANCE_TOPIC)
            .order_by(OutboxMessage.id)
        )
    )
    return [
        message
        for message in messages
        if message.payload["listing_id"] == str(listing_id)
    ]


async def stored_marks(account: Account, listing_id: UUID) -> list[AttendanceRecord]:
    db = account.auth.db
    await db.rollback()
    return list(
        await db.scalars(
            select(AttendanceRecord)
            .where(AttendanceRecord.listing_id == listing_id)
            .order_by(AttendanceRecord.marked_at, AttendanceRecord.id)
        )
    )


async def journal(account: Account, listing_id: UUID) -> list[ListingEvent]:
    db = account.auth.db
    await db.rollback()
    return list(
        await db.scalars(
            select(ListingEvent)
            .where(
                ListingEvent.listing_id == listing_id,
                ListingEvent.action.in_(("attendance_marked", "attendance_removed")),
            )
            .order_by(ListingEvent.created_at, ListingEvent.id)
        )
    )


async def test_window_is_inclusive_at_both_ends(
    auth: Auth, owner: Account, borrower: Account, places: Places
) -> None:
    third = await student(auth, places, 1)
    start = FIXED + timedelta(hours=3)
    end = FIXED + timedelta(hours=5)
    opens = start - timedelta(minutes=30)
    with time_machine.travel(FIXED, tick=False):
        listing = await event_at(owner, start, end)
        await signup(borrower, listing)
        await signup(third, listing)
    with time_machine.travel(opens - timedelta(seconds=1), tick=False):
        refused = await issue_qr(owner, listing)
        assert refused.status_code == 409, refused.text
        assert refused.json()["code"] == "event_attendance_closed"
        assert parse_instant(refused.json()["available_at"]) == opens
        assert (await check_in(borrower, listing, "anything")).status_code == 409
    with time_machine.travel(opens, tick=False):
        issued = await issue_qr(owner, listing)
        assert issued.status_code == 200, issued.text
        marked = await check_in(borrower, listing, issued.json()["code"])
        assert marked.status_code == 200, marked.text
        assert marked.json()["result"] == "marked"
    with time_machine.travel(end, tick=False):
        last = await issue_qr(owner, listing)
        assert last.status_code == 200, last.text
        marked_third = await check_in(third, listing, last.json()["code"])
        assert marked_third.status_code == 200, marked_third.text
    with time_machine.travel(end + timedelta(seconds=1), tick=False):
        assert (await issue_qr(owner, listing)).json()["code"] == (
            "event_attendance_closed"
        )
        late = await check_in(third, listing, last.json()["code"])
        assert late.status_code == 409
        assert late.json()["code"] == "event_attendance_closed"


async def test_code_lifetime_is_inclusive(
    auth: Auth, owner: Account, borrower: Account, places: Places
) -> None:
    third = await student(auth, places, 2)
    with time_machine.travel(FIXED, tick=False):
        listing = await event_at(
            owner,
            FIXED + timedelta(minutes=30),
            FIXED + timedelta(hours=2),
        )
        await signup(borrower, listing)
        await signup(third, listing)
        issued = await issue_qr(owner, listing)
        assert issued.status_code == 200, issued.text
        body = issued.json()
        assert parse_instant(body["expires_at"]) == FIXED + timedelta(seconds=30)
        code = body["code"]
    with time_machine.travel(FIXED + timedelta(seconds=30), tick=False):
        assert (await check_in(borrower, listing, code)).status_code == 200
    with time_machine.travel(FIXED + timedelta(seconds=31), tick=False):
        expired = await check_in(third, listing, code)
        assert expired.status_code == 409, expired.text
        assert expired.json()["code"] == "event_attendance_code_expired"
        tampered = await check_in(
            third, listing, ("A" if code[0] != "A" else "B") + code[1:]
        )
        assert tampered.status_code == 422
        assert tampered.json()["code"] == "event_attendance_code_invalid"


async def test_self_mode_role_matrix(
    auth: Auth, owner: Account, borrower: Account, places: Places
) -> None:
    outsider = await student(auth, places, 3)
    leaving = await student(auth, places, 4)
    other_owner = await student(auth, places, 5)
    with time_machine.travel(FIXED, tick=False):
        listing = await event_at(
            owner, FIXED + timedelta(minutes=30), FIXED + timedelta(hours=2)
        )
        await signup(borrower, listing)
        interaction = await signup(leaving, listing)
        assert (
            await move(leaving, listing, interaction, "cancelled")
        ).status_code == 200
        other_listing = await event_at(
            other_owner, FIXED + timedelta(minutes=30), FIXED + timedelta(hours=2)
        )
        issued = await issue_qr(owner, listing)
        code = issued.json()["code"]

        assert (await issue_qr(other_owner, listing)).status_code == 403
        assert (await issue_qr(borrower, listing)).status_code == 403
        assert (await issue_qr(owner, other_listing)).status_code == 403

        outsider_reply = await check_in(outsider, listing, code)
        assert outsider_reply.status_code == 403
        assert outsider_reply.json()["code"] == "event_attendance_not_registered"
        leaving_reply = await check_in(leaving, listing, code)
        assert leaving_reply.status_code == 403
        assert leaving_reply.json()["code"] == "event_attendance_not_registered"
        organizer_self = await check_in(owner, listing, code)
        assert organizer_self.status_code == 403
        assert organizer_self.json()["code"] == "event_attendance_not_registered"

        marked = await check_in(borrower, listing, code)
        assert marked.status_code == 200, marked.text
        assert marked.json()["method"] == "self"
        assert marked.json()["marked_by_id"] == str(user_id(borrower))


async def test_mode_switch_keeps_marks_and_old_codes_fail(
    auth: Auth, owner: Account, borrower: Account, places: Places
) -> None:
    third = await student(auth, places, 6)
    with time_machine.travel(FIXED, tick=False):
        listing = await event_at(
            owner, FIXED + timedelta(minutes=30), FIXED + timedelta(hours=2)
        )
        await signup(borrower, listing)
        await signup(third, listing)
        old_self = (await issue_qr(owner, listing)).json()["code"]
        marked = await check_in(borrower, listing, old_self)
        assert marked.status_code == 200, marked.text

        denied_mode = await set_mode(borrower, listing, AttendanceMode.SCAN)
        assert denied_mode.status_code == 403
        switched = await set_mode(owner, listing, AttendanceMode.SCAN)
        assert switched.status_code == 200, switched.text
        assert switched.json()["changed"] is True
        repeated_switch = await set_mode(owner, listing, AttendanceMode.SCAN)
        assert repeated_switch.json()["changed"] is False

        # A code of the previous mode does not work after the switch.
        stale = await check_in(third, listing, old_self)
        assert stale.status_code == 409
        assert stale.json()["code"] == "event_attendance_mode_conflict"

        personal = await issue_code(third, listing)
        assert personal.status_code == 200, personal.text
        scanned = await scan(owner, listing, personal.json()["code"])
        assert scanned.status_code == 200, scanned.text
        assert scanned.json()["method"] == "scan"

        recovered = await attendance_list(owner, listing)
        assert recovered.status_code == 200, recovered.text
        body = recovered.json()
        assert body["mode"] == "scan"
        assert body["marked_count"] == 2
        assert {item["status"] for item in body["items"]} == {"marked"}
        assert (await attendance_list(borrower, listing)).status_code == 403

        switched_back = await set_mode(owner, listing, AttendanceMode.SELF)
        assert switched_back.json()["mode"] == "self"
        again = await check_in(third, listing, old_self, key=new_key())
        assert again.status_code == 200
        assert again.json()["result"] == "already_marked"
        assert again.json()["id"] == scanned.json()["id"]


async def test_scan_mode_role_matrix(
    auth: Auth, owner: Account, borrower: Account, places: Places
) -> None:
    third = await student(auth, places, 7)
    outsider = await student(auth, places, 8)
    other_owner = await student(auth, places, 12)
    with time_machine.travel(FIXED, tick=False):
        listing = await event_at(
            owner, FIXED + timedelta(minutes=30), FIXED + timedelta(hours=2)
        )
        await event_at(
            other_owner, FIXED + timedelta(minutes=30), FIXED + timedelta(hours=2)
        )
        await signup(borrower, listing)
        await signup(third, listing)
        self_code = (await issue_qr(owner, listing)).json()["code"]
        marked = await check_in(borrower, listing, self_code)
        assert marked.status_code == 200, marked.text
        assert (await set_mode(owner, listing, AttendanceMode.SCAN)).status_code == 200

        assert (await issue_code(outsider, listing)).status_code == 403
        assert (await issue_code(owner, listing)).status_code == 403
        personal = await issue_code(third, listing)
        assert personal.status_code == 200, personal.text
        scanned = await scan(owner, listing, personal.json()["code"])
        assert scanned.status_code == 200, scanned.text
        assert scanned.json()["marked_by_id"] == str(user_id(owner))
        assert scanned.json()["participant_id"] == str(user_id(third))
        repeated = await scan(owner, listing, personal.json()["code"], key=new_key())
        assert repeated.status_code == 200
        assert repeated.json()["result"] == "already_marked"
        assert repeated.json()["id"] == scanned.json()["id"]

        borrower_code = (await issue_code(borrower, listing)).json()["code"]
        already_self = await scan(owner, listing, borrower_code, key=new_key())
        assert already_self.status_code == 200
        assert already_self.json()["result"] == "already_marked"
        assert already_self.json()["id"] == marked.json()["id"]
        assert already_self.json()["method"] == "self"

        assert (
            await scan(borrower, listing, personal.json()["code"])
        ).status_code == 403
        assert (
            await scan(outsider, listing, personal.json()["code"])
        ).status_code == 403
        assert (
            await scan(other_owner, listing, personal.json()["code"])
        ).status_code == 403
        assert (await scan(owner, listing, "garbage")).status_code == 422

        recovered = await attendance_list(owner, listing)
        assert recovered.status_code == 200, recovered.text
        assert recovered.json()["marked_count"] == 2


async def test_shared_organizer_code_and_idempotent_marks(
    auth: Auth, owner: Account, borrower: Account, places: Places
) -> None:
    second = await student(auth, places, 8)
    third = await student(auth, places, 9)
    with time_machine.travel(FIXED, tick=False):
        listing = await event_at(
            owner, FIXED + timedelta(minutes=30), FIXED + timedelta(hours=2)
        )
        participants = [borrower, second, third]
        for participant in participants:
            await signup(participant, listing)
        code = (await issue_qr(owner, listing)).json()["code"]
        listing_id = UUID(listing["id"])

        first_wave = await asyncio.gather(
            *(check_in(participant, listing, code) for participant in participants[:2])
        )
        assert {reply.status_code for reply in first_wave} == {200}
        assert {reply.json()["result"] for reply in first_wave} == {"marked"}

        same = await asyncio.gather(
            *(check_in(participants[2], listing, code, key=new_key()) for _ in range(6))
        )
        assert {reply.status_code for reply in same} == {200}
        assert sum(reply.json()["result"] == "marked" for reply in same) == 1
        assert sum(reply.json()["result"] == "already_marked" for reply in same) == 5
        assert len({reply.json()["id"] for reply in same}) == 1

        marks = await stored_marks(owner, listing_id)
        assert len(marks) == 3
        assert {record.participant_id for record in marks} == {
            user_id(participant) for participant in participants
        }
        events = await journal(owner, listing_id)
        assert [event.action for event in events] == ["attendance_marked"] * 3
        assert len(await stored_messages(owner, listing_id)) == 3

        key = new_key()
        first = await check_in(participants[2], listing, code, key=key)
        again = await check_in(participants[2], listing, code, key=key)
        assert again.json() == first.json()
        assert again.headers["Idempotent-Replayed"] == "true"
        new_code = (await issue_qr(owner, listing)).json()["code"]
        reused = await check_in(participants[2], listing, new_code, key=key)
        assert reused.status_code == 422
        assert reused.json()["code"] == "idempotency_key_reused"


async def test_removal_is_soft_and_organizer_only(
    owner: Account, borrower: Account
) -> None:
    with time_machine.travel(FIXED, tick=False):
        listing = await event_at(
            owner, FIXED + timedelta(minutes=30), FIXED + timedelta(hours=2)
        )
        await signup(borrower, listing)
        listing_id = UUID(listing["id"])
        code = (await issue_qr(owner, listing)).json()["code"]
        marked = await check_in(borrower, listing, code)
        attendance_id = UUID(marked.json()["id"])

        assert (await remove(borrower, listing, user_id(borrower))).status_code == 403
        removed = await remove(owner, listing, user_id(borrower))
        assert removed.status_code == 200, removed.text
        assert removed.json()["status"] == "removed"
        assert removed.json()["result"] == "removed"
        assert removed.json()["removed_at"] is not None
        assert removed.json()["removed_by_id"] == str(user_id(owner))

        again = await remove(owner, listing, user_id(borrower), key=new_key())
        assert again.status_code == 200
        assert again.json()["result"] == "already_removed"
        assert again.json()["id"] == str(attendance_id)
        assert (await remove(owner, listing, uuid4())).status_code == 404

        recovered = (await attendance_list(owner, listing)).json()
        assert recovered["marked_count"] == 0
        assert recovered["items"][0]["status"] == "removed"

        remarked = await check_in(borrower, listing, code)
        assert remarked.status_code == 200, remarked.text
        assert remarked.json()["result"] == "marked"
        assert remarked.json()["id"] == str(attendance_id)
        assert remarked.json()["removed_at"] is None
        marks = await stored_marks(owner, listing_id)
        assert len(marks) == 1
        events = await journal(owner, listing_id)
        assert [event.action for event in events] == [
            "attendance_marked",
            "attendance_removed",
            "attendance_marked",
        ]


async def test_rollback_leaves_no_mark_or_outbox(
    owner: Account,
    borrower: Account,
    sessions: async_sessionmaker[AsyncSession],
) -> None:
    with time_machine.travel(FIXED, tick=False):
        listing = await event_at(
            owner, FIXED + timedelta(minutes=30), FIXED + timedelta(hours=2)
        )
        await signup(borrower, listing)
        listing_id = UUID(listing["id"])
        participant_id = user_id(borrower)

        async with sessions() as session:
            listing_row = await locked(session, listing_id)
            interaction = await accepted_interaction(
                session, listing_id, participant_id
            )
            result = await record_mark(
                session,
                listing_row,
                interaction,
                participant_id,
                AttendanceMode.SELF,
                participant_id,
                clock.now(),
            )
            assert result.result == "marked"
            assert (
                await session.scalar(select(func.count()).select_from(AttendanceRecord))
                == 1
            )
            assert (
                await session.scalar(
                    select(func.count())
                    .select_from(OutboxMessage)
                    .where(OutboxMessage.topic == ATTENDANCE_TOPIC)
                )
                == 1
            )
            await session.rollback()

        async with sessions() as session:
            assert (
                await session.scalar(select(func.count()).select_from(AttendanceRecord))
                == 0
            )
            assert (
                await session.scalar(
                    select(func.count())
                    .select_from(OutboxMessage)
                    .where(OutboxMessage.topic == ATTENDANCE_TOPIC)
                )
                == 0
            )


async def test_outbox_publishes_to_organizer_after_commit(
    owner: Account,
    borrower: Account,
    places: Places,
    sessions: async_sessionmaker[AsyncSession],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    with time_machine.travel(FIXED, tick=False):
        listing = await event_at(
            owner, FIXED + timedelta(minutes=30), FIXED + timedelta(hours=2)
        )
        await signup(borrower, listing)
        listing_id = UUID(listing["id"])
        code = (await issue_qr(owner, listing)).json()["code"]
        marked = await check_in(borrower, listing, code)
        assert marked.status_code == 200, marked.text

    # Other sign-in and signup jobs are not under test here.
    await owner.auth.db.execute(
        delete(OutboxMessage).where(OutboxMessage.topic != ATTENDANCE_TOPIC)
    )
    await owner.auth.db.commit()

    calls: list[tuple[UUID, dict[str, Any], UUID]] = []

    async def fake_publish(
        user_id_value: UUID, data: dict[str, Any], delivery_id: UUID
    ) -> None:
        calls.append((user_id_value, data, delivery_id))

    monkeypatch.setattr("campus.modules.realtime.publish_personal", fake_publish)
    assert await process_outbox(sessions, owner.auth.settings) == 1
    assert len(calls) == 1
    organizer_id, payload, delivery_id = calls[0]
    assert organizer_id == user_id(owner)
    assert payload["listing_id"] == str(listing_id)
    assert payload["participant_id"] == str(user_id(borrower))
    assert payload["status"] == "marked"
    assert payload["method"] == "self"
    assert "organizer_id" not in payload
    assert delivery_id

    # A lost acknowledgement keeps the message for a retry.
    with time_machine.travel(FIXED, tick=False):
        second = await student(owner.auth, places, 10)
        await signup(second, listing)
        code = (await issue_qr(owner, listing)).json()["code"]
        marked_second = await check_in(second, listing, code)
        assert marked_second.status_code == 200, marked_second.text
    await owner.auth.db.execute(
        delete(OutboxMessage).where(OutboxMessage.topic != ATTENDANCE_TOPIC)
    )
    await owner.auth.db.commit()

    async def broken(_user_id: UUID, _data: dict[str, Any], _delivery_id: UUID) -> None:
        raise ConnectionError("realtime is down")

    monkeypatch.setattr("campus.modules.realtime.publish_personal", broken)
    assert await process_outbox(sessions, owner.auth.settings) == 1
    await owner.auth.db.rollback()
    pending = list(
        await owner.auth.db.scalars(
            select(OutboxMessage).where(
                OutboxMessage.topic == ATTENDANCE_TOPIC,
                OutboxMessage.processed_at.is_(None),
            )
        )
    )
    assert len(pending) == 1
    assert pending[0].attempts == 1
    assert pending[0].failed_at is None
    # The list is the recovery path while realtime is down.
    recovered = await attendance_list(owner, listing)
    assert recovered.status_code == 200
    assert recovered.json()["marked_count"] == 2


async def test_no_show_contract_counts_only_current_signups(
    auth: Auth, owner: Account, borrower: Account, places: Places
) -> None:
    leaving = await student(auth, places, 11)
    with time_machine.travel(FIXED, tick=False):
        listing = await event_at(
            owner, FIXED + timedelta(minutes=30), FIXED + timedelta(hours=2)
        )
        await signup(borrower, listing)
        interaction = await signup(leaving, listing)
        listing_id = UUID(listing["id"])
        db = owner.auth.db
        await db.rollback()
        assert await current_attendance_participant_ids(db, listing_id) == set()

        code = (await issue_qr(owner, listing)).json()["code"]
        assert (await check_in(borrower, listing, code)).status_code == 200
        await db.rollback()
        assert await current_attendance_participant_ids(db, listing_id) == {
            user_id(borrower)
        }

        assert (await check_in(leaving, listing, code)).status_code == 200
        await db.rollback()
        assert await current_attendance_participant_ids(db, listing_id) == {
            user_id(borrower),
            user_id(leaving),
        }

        assert (
            await move(leaving, listing, interaction, "cancelled")
        ).status_code == 200
        await db.rollback()
        # The mark stays for the organiser's list, but a cancelled signup is
        # not a registered participant any more.
        assert await current_attendance_participant_ids(db, listing_id) == {
            user_id(borrower)
        }
        listed = (await attendance_list(owner, listing)).json()
        cancelled_item = next(
            item
            for item in listed["items"]
            if item["participant_id"] == str(user_id(leaving))
        )
        assert cancelled_item["status"] == "marked"
        assert cancelled_item["registered"] is False

        assert (await remove(owner, listing, user_id(borrower))).status_code == 200
        await db.rollback()
        assert await current_attendance_participant_ids(db, listing_id) == set()

    # After the end the organiser still recovers the authoritative list.
    with time_machine.travel(FIXED + timedelta(hours=2, seconds=1), tick=False):
        late_list = await attendance_list(owner, listing)
        assert late_list.status_code == 200
        assert late_list.json()["marked_count"] == 1
