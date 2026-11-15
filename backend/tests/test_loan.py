"""Loans: booking, the QR handover and return, reminders and "not returned"."""

import asyncio
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID, uuid4

import httpx2
import pytest
import time_machine
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncEngine

from campus.core import clock
from campus.core.db import create_session_factory
from campus.core.deadlines import process_due_deadlines
from campus.core.outbox import OutboxMessage
from campus.modules.listings import Interaction, Item, Listing, ListingEvent
from campus.modules.notifications import Reminder
from campus.modules.reputation import NoShowMark, QrScan
from tests.test_identity import Auth
from tests.test_listings import (
    auth,
    borrower,
    owner,
    places,
    request,
    reserve,
)
from tests.test_profile import Account, Places, moscow_profile
from tests.test_qr import Signer, register_key, user_id

__all__ = ["auth", "borrower", "owner", "places"]

ROOT = "/api/v1/listings"


@pytest.fixture(autouse=True)
def long_lived_test_access(auth: Auth) -> None:
    """Keep HTTP credentials valid while moving time by days."""
    auth.settings = auth.settings.model_copy(
        update={"access_token_ttl": timedelta(days=365)}
    )
    auth.app.state.settings = auth.settings


def instant(at: datetime) -> str:
    return at.astimezone(UTC).isoformat().replace("+00:00", "Z")


def parse_instant(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def set_settings(account: Account, **changes: Any) -> None:
    account.auth.settings = account.auth.settings.model_copy(update=changes)
    account.auth.app.state.settings = account.auth.settings


async def deadlines(account: Account) -> int:
    assert isinstance(account.auth.db.bind, AsyncEngine)
    return await process_due_deadlines(
        create_session_factory(account.auth.db.bind), account.auth.settings
    )


async def new_account(auth: Auth, places: Places, email: str) -> Account:
    account = Account(auth, await auth.login(email=email))
    assert (await account.put(moscow_profile(places))).status_code == 200
    return account


async def publish_loan(
    account: Account, *, loan_days: int = 7, **overrides: Any
) -> httpx2.Response:
    category = (await request(account, "GET", "/categories")).json()["items"][0]["id"]
    return await request(
        account,
        "POST",
        "/loans",
        {
            "category_id": category,
            "title": "A drill",
            "description": "Return it after the weekend",
            "loan_days": loan_days,
            **overrides,
        },
    )


async def loan(
    owner_account: Account,
    borrower_account: Account,
    *,
    loan_days: int = 7,
) -> tuple[dict[str, Any], dict[str, Any]]:
    """A published loan with an accepted borrower."""
    response = await publish_loan(owner_account, loan_days=loan_days)
    assert response.status_code == 201, response.text
    listing = response.json()
    reservation = await reserve(borrower_account, listing)
    assert reservation.status_code == 201, reservation.text
    accepted = await request(
        owner_account,
        "POST",
        f"/{listing['id']}/interactions/{reservation.json()['id']}/transition",
        {"status": "accepted"},
    )
    assert accepted.status_code == 200, accepted.text
    return listing, accepted.json()


async def confirm(  # noqa: PLR0913, PLR0917 - request parts
    scanner: Account,
    action: str,
    listing: dict[str, Any],
    interaction: dict[str, Any],
    body: dict[str, str],
    key: str | None = None,
) -> httpx2.Response:
    return await scanner.auth.client.post(
        f"{ROOT}/{listing['id']}/interactions/{interaction['id']}/qr/{action}",
        json=body,
        headers={"Idempotency-Key": key or str(uuid4()), **scanner.headers},
    )


async def hand_over(
    owner_account: Account,
    borrower_account: Account,
    listing: dict[str, Any],
    interaction: dict[str, Any],
    *,
    key: str | None = None,
) -> httpx2.Response:
    """The owner presents the code to the borrower, as at the hand-over."""
    signer = Signer.generate()
    assert (await register_key(owner_account, signer)).status_code == 200
    body = signer.body(listing["id"], interaction["id"], user_id(owner_account))
    return await confirm(borrower_account, "handover", listing, interaction, body, key)


async def give_back(
    owner_account: Account,
    borrower_account: Account,
    listing: dict[str, Any],
    interaction: dict[str, Any],
    *,
    key: str | None = None,
) -> httpx2.Response:
    """The borrower presents the code to the owner, as at the return."""
    signer = Signer.generate()
    assert (await register_key(borrower_account, signer)).status_code == 200
    body = signer.body(listing["id"], interaction["id"], user_id(borrower_account))
    return await confirm(owner_account, "return", listing, interaction, body, key)


async def plain_scan(
    scanner: Account,
    listing: dict[str, Any],
    interaction: dict[str, Any],
    presenter: Account,
) -> httpx2.Response:
    signer = Signer.generate()
    assert (await register_key(presenter, signer)).status_code == 200
    return await scanner.auth.client.post(
        f"{ROOT}/{listing['id']}/interactions/{interaction['id']}/qr",
        json=signer.body(listing["id"], interaction["id"], user_id(presenter)),
        headers={"Idempotency-Key": str(uuid4()), **scanner.headers},
    )


async def not_returned(
    account: Account,
    listing: dict[str, Any],
    interaction: dict[str, Any],
    key: str | None = None,
) -> httpx2.Response:
    return await account.auth.client.post(
        f"{ROOT}/{listing['id']}/interactions/{interaction['id']}/not-returned",
        headers={"Idempotency-Key": key or str(uuid4()), **account.headers},
    )


async def row_of(account: Account, interaction: dict[str, Any]) -> Interaction:
    await account.auth.db.rollback()
    row = await account.auth.db.get(Interaction, UUID(interaction["id"]))
    assert row is not None
    return row


async def listing_row(account: Account, listing: dict[str, Any]) -> Listing:
    await account.auth.db.rollback()
    row = await account.auth.db.get(Listing, UUID(listing["id"]))
    assert row is not None
    return row


async def journal(account: Account, interaction: dict[str, Any]) -> list[ListingEvent]:
    await account.auth.db.rollback()
    return list(
        await account.auth.db.scalars(
            select(ListingEvent)
            .where(ListingEvent.interaction_id == UUID(interaction["id"]))
            .order_by(ListingEvent.created_at, ListingEvent.id)
        )
    )


async def marks(account: Account, interaction: dict[str, Any]) -> list[NoShowMark]:
    await account.auth.db.rollback()
    return list(
        await account.auth.db.scalars(
            select(NoShowMark).where(
                NoShowMark.interaction_id == UUID(interaction["id"])
            )
        )
    )


async def interaction_view(account: Account, listing: dict[str, Any]) -> dict[str, Any]:
    """The author's own view of the interaction, via the API."""
    response = await request(account, "GET", f"/{listing['id']}/interactions")
    assert response.status_code == 200, response.text
    items = response.json()["items"]
    assert len(items) == 1
    view: dict[str, Any] = items[0]
    return view


async def test_a_loan_carries_the_authors_period(
    owner: Account, borrower: Account
) -> None:
    response = await publish_loan(owner, loan_days=5)

    assert response.status_code == 201, response.text
    body = response.json()
    assert body["kind"] == "loan"
    assert body["loan_days"] == 5
    assert body["status"] == "active"
    assert parse_instant(body["expires_at"]) > clock.now()

    db = owner.auth.db
    await db.rollback()
    details = await db.scalar(select(Item).where(Item.listing_id == UUID(body["id"])))
    assert details is not None
    assert details.mode == "loan"
    assert details.loan_days == 5

    read = await request(owner, "GET", f"/{body['id']}")
    assert read.status_code == 200, read.text
    assert read.json()["loan_days"] == 5
    assert read.json()["kind"] == "loan"

    feed = await request(borrower, "GET")
    assert feed.status_code == 200, feed.text
    found = [item for item in feed.json()["items"] if item["id"] == body["id"]]
    assert found
    assert found[0]["loan_days"] == 5


async def test_the_loan_period_is_validated(owner: Account) -> None:
    set_settings(owner, loan_period_max_days=30)

    too_short = await publish_loan(owner, loan_days=0)
    assert too_short.status_code == 422, too_short.text

    too_long = await publish_loan(owner, loan_days=31)
    assert too_long.status_code == 422, too_long.text
    assert too_long.json()["code"] == "listing_loan_period_invalid"
    assert "30" in too_long.json()["detail"]

    longest = await publish_loan(owner, loan_days=30)
    assert longest.status_code == 201, longest.text
    assert longest.json()["loan_days"] == 30


async def test_a_loan_is_booked_like_an_item(owner: Account, borrower: Account) -> None:
    listing, interaction = await loan(owner, borrower, loan_days=4)

    assert interaction["status"] == "accepted"
    assert interaction["stage"] is None
    assert interaction["return_due_at"] is None
    assert interaction["overdue"] is False
    row = await listing_row(owner, listing)
    assert row.status == "busy"

    second = await reserve(borrower, listing)
    assert second.status_code == 409, second.text


async def test_a_loan_queue_and_reservation_work_like_a_giveaway(
    owner: Account, borrower: Account, places: Places
) -> None:
    """#214: the item keeps the shared booking, queue and reservation rules."""
    set_settings(owner, listing_reservation_timeout=timedelta(hours=1))
    now = clock.now()
    with time_machine.travel(now, tick=False):
        listing, interaction = await loan(owner, borrower)
        next_in_line = await new_account(
            owner.auth, places, "queuer1@university.example"
        )
        joined = await request(next_in_line, "POST", f"/{listing['id']}/waitlist")
        assert joined.status_code == 201, joined.text

    # The reservation runs out before the handover: the loan is cancelled
    # without a late mark, the item reopens and the queue gets its offer.
    with time_machine.travel(now + timedelta(hours=1, minutes=1), tick=False):
        assert await deadlines(owner) >= 1
        entry = (
            await request(next_in_line, "GET", f"/{listing['id']}/waitlist/me")
        ).json()
        assert entry["status"] == "offered"
        row = await row_of(owner, interaction)
        assert row.status == "cancelled"
        assert row.stage is None
        assert row.cancelled_by == "system"
        assert (await listing_row(owner, listing)).status == "active"


async def test_the_handover_starts_the_loan_without_completing_it(
    owner: Account, borrower: Account, places: Places
) -> None:
    now = clock.now()
    with time_machine.travel(now, tick=False):
        listing, interaction = await loan(owner, borrower, loan_days=7)
        response = await hand_over(owner, borrower, listing, interaction)

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["status"] == "accepted"
    assert body["completed"] is False
    assert body["completion_method"] is None
    assert body["stage"] == "issued"
    assert parse_instant(body["return_due_at"]) == now + timedelta(days=7)
    assert body["presenter_id"] == str(user_id(owner))
    assert body["scanner_id"] == str(user_id(borrower))

    row = await row_of(owner, interaction)
    assert row.status == "accepted"
    assert row.stage == "issued"
    assert row.return_due_at == now + timedelta(days=7)
    assert row.reservation_due_at is None
    assert row.completion_method is None

    await owner.auth.db.rollback()
    scan = await owner.auth.db.scalar(
        select(QrScan).where(QrScan.interaction_id == UUID(interaction["id"]))
    )
    assert scan is not None
    assert scan.result == "stage_advanced"

    events = await journal(owner, interaction)
    assert events[-1].action == "loan_handed_over"
    assert events[-1].stage == "issued"
    assert events[-1].details is not None
    assert events[-1].details["loan_days"] == 7
    assert parse_instant(events[-1].details["return_due_at"]) == now + timedelta(days=7)

    still_busy = await listing_row(owner, listing)
    assert still_busy.status == "busy"

    await owner.auth.db.rollback()
    reminder = await owner.auth.db.scalar(
        select(Reminder).where(Reminder.key == f"return:{interaction['id']}")
    )
    assert reminder is not None
    assert reminder.active is True
    assert reminder.starts_at == now + timedelta(days=7)
    assert reminder.payload["type"] == "return.reminder"
    assert reminder.payload["recipients"] == [str(user_id(borrower))]
    assert reminder.payload["text"]["ru"] == (
        "Срок возврата по вашему займу приближается."
    )

    third = await new_account(owner.auth, places, "participant3@university.example")
    assert (await reserve(third, listing)).status_code == 409


async def test_the_return_completes_the_loan(owner: Account, borrower: Account) -> None:
    now = clock.now()
    with time_machine.travel(now, tick=False):
        listing, interaction = await loan(owner, borrower, loan_days=3)
        assert (
            await hand_over(owner, borrower, listing, interaction)
        ).status_code == 200
        returned = await give_back(owner, borrower, listing, interaction)

    assert returned.status_code == 200, returned.text
    body = returned.json()
    assert body["status"] == "completed"
    assert body["completed"] is True
    assert body["completion_method"] == "qr"
    assert body["rating_weight"] == 1.0
    assert body["stage"] is None
    assert body["return_due_at"] is None
    assert body["completed_at"] == instant(now)

    row = await row_of(owner, interaction)
    assert row.status == "completed"
    assert row.stage is None
    assert row.return_due_at is None
    assert row.completion_method == "qr"

    finished = await listing_row(owner, listing)
    assert finished.status == "completed"

    await owner.auth.db.rollback()
    returned_scan = await owner.auth.db.scalar(
        select(QrScan).where(
            QrScan.interaction_id == UUID(interaction["id"]),
            QrScan.result == "completed",
        )
    )
    assert returned_scan is not None

    events = await journal(owner, interaction)
    assert events[-1].action == "loan_returned"
    assert events[-1].details is not None
    assert events[-1].details["overdue"] is False

    await owner.auth.db.rollback()
    reminder = await owner.auth.db.scalar(
        select(Reminder).where(Reminder.key == f"return:{interaction['id']}")
    )
    assert reminder is not None
    assert reminder.active is False


async def test_the_return_before_the_handover_is_refused(
    owner: Account, borrower: Account
) -> None:
    listing, interaction = await loan(owner, borrower)
    before = await journal(owner, interaction)

    response = await give_back(owner, borrower, listing, interaction)

    assert response.status_code == 409, response.text
    assert response.json()["code"] == "qr_loan_not_handed_over"
    row = await row_of(owner, interaction)
    assert row.status == "accepted"
    assert row.stage is None
    assert await journal(owner, interaction) == before


@pytest.mark.parametrize("repeat", ["replay", "again"])
async def test_the_handover_is_not_repeated(
    owner: Account, borrower: Account, repeat: str
) -> None:
    listing, interaction = await loan(owner, borrower)
    signer = Signer.generate()
    assert (await register_key(owner, signer)).status_code == 200
    body = signer.body(listing["id"], interaction["id"], user_id(owner))
    key = str(uuid4())
    first = await confirm(borrower, "handover", listing, interaction, body, key)
    assert first.status_code == 200, first.text
    before = await journal(owner, interaction)

    if repeat == "replay":
        # The same Idempotency-Key and body replay the stored success.
        second = await confirm(borrower, "handover", listing, interaction, body, key)
        assert second.status_code == 200, second.text
        assert second.json()["stage"] == "issued"
    else:
        other = Signer.generate()
        assert (await register_key(owner, other)).status_code == 200
        second = await confirm(
            borrower,
            "handover",
            listing,
            interaction,
            other.body(listing["id"], interaction["id"], user_id(owner)),
        )
        assert second.status_code == 409, second.text
        assert second.json()["code"] == "qr_loan_already_issued"
    row = await row_of(owner, interaction)
    assert row.stage == "issued"
    assert await journal(owner, interaction) == before


async def test_a_plain_confirmation_does_not_complete_a_loan(
    owner: Account, borrower: Account
) -> None:
    listing, interaction = await loan(owner, borrower)

    plain = await plain_scan(borrower, listing, interaction, owner)
    assert plain.status_code == 409, plain.text
    assert plain.json()["code"] == "qr_loan_action_required"

    code = await borrower.auth.client.post(
        f"{ROOT}/{listing['id']}/interactions/{interaction['id']}/code",
        headers={"Idempotency-Key": str(uuid4()), **borrower.headers},
    )
    assert code.status_code == 409, code.text
    assert code.json()["code"] == "confirmation_code_stage_unavailable"

    row = await row_of(owner, interaction)
    assert row.status == "accepted"
    assert row.stage is None
    assert row.completion_method is None


async def test_only_a_loan_is_handed_over(owner: Account, borrower: Account) -> None:
    giveaway = await request(
        owner,
        "POST",
        "/giveaways",
        {
            "category_id": (await request(owner, "GET", "/categories")).json()["items"][
                0
            ]["id"],
            "title": "A lamp",
            "description": "Works",
        },
    )
    assert giveaway.status_code == 201, giveaway.text
    reservation = await reserve(borrower, giveaway.json())
    assert reservation.status_code == 201
    accepted = await request(
        owner,
        "POST",
        f"/{giveaway.json()['id']}/interactions/{reservation.json()['id']}/transition",
        {"status": "accepted"},
    )
    assert accepted.status_code == 200, accepted.text

    response = await hand_over(owner, borrower, giveaway.json(), accepted.json())

    assert response.status_code == 409, response.text
    assert response.json()["code"] == "qr_unavailable"


async def test_the_handover_belongs_to_the_participants(
    owner: Account, borrower: Account, places: Places
) -> None:
    listing, interaction = await loan(owner, borrower)
    stranger = await new_account(owner.auth, places, "participant4@university.example")
    signer = Signer.generate()
    assert (await register_key(owner, signer)).status_code == 200
    body = signer.body(listing["id"], interaction["id"], user_id(owner))

    response = await confirm(stranger, "handover", listing, interaction, body)

    assert response.status_code == 403, response.text
    row = await row_of(owner, interaction)
    assert row.status == "accepted"
    assert row.stage is None


async def test_parallel_handovers_advance_the_loan_once(
    owner: Account, borrower: Account
) -> None:
    listing, interaction = await loan(owner, borrower)
    signer = Signer.generate()
    assert (await register_key(owner, signer)).status_code == 200
    body = signer.body(listing["id"], interaction["id"], user_id(owner))

    responses = await asyncio.gather(
        confirm(borrower, "handover", listing, interaction, body),
        confirm(borrower, "handover", listing, interaction, body),
    )

    assert sorted(response.status_code for response in responses) == [200, 409]
    assert (responses[0] if responses[0].status_code == 409 else responses[1]).json()[
        "code"
    ] == "qr_nonce_reused"
    row = await row_of(owner, interaction)
    assert row.stage == "issued"
    await owner.auth.db.rollback()
    assert (
        await owner.auth.db.scalar(
            select(func.count())
            .select_from(QrScan)
            .where(QrScan.interaction_id == UUID(interaction["id"]))
        )
        == 1
    )


async def test_not_returned_waits_for_the_configured_delay(
    owner: Account, borrower: Account
) -> None:
    now = clock.now()
    with time_machine.travel(now, tick=False):
        listing, interaction = await loan(owner, borrower, loan_days=3)
        assert (
            await hand_over(owner, borrower, listing, interaction)
        ).status_code == 200
    due_at = now + timedelta(days=3)
    available_at = due_at + timedelta(days=3)

    with time_machine.travel(available_at - timedelta(seconds=1), tick=False):
        early = await not_returned(owner, listing, interaction)
    assert early.status_code == 409, early.text
    assert early.json()["code"] == "loan_not_returned_too_early"
    assert parse_instant(early.json()["available_at"]) == available_at
    assert await marks(owner, interaction) == []

    with time_machine.travel(available_at, tick=False):
        marked = await not_returned(owner, listing, interaction)
        assert marked.status_code == 200, marked.text
        body = marked.json()
        assert body["status"] == "no_show"
        assert body["basis"] == "marked"
        assert body["no_show_at"] == instant(available_at)
        assert len(body["marks"]) == 1
        mark = body["marks"][0]
        assert mark["kind"] == "personal"
        assert mark["status"] == "counted"
        assert mark["reporter_id"] == str(user_id(owner))
        assert mark["subject_id"] == str(user_id(borrower))
        assert mark["reason"] == "loan_not_returned"

        # The borrower can answer the mark within the #66 dispute window.
        read = await borrower.auth.client.get(
            f"{ROOT}/{listing['id']}/interactions/{interaction['id']}/no-show",
            headers=borrower.headers,
        )
        assert read.status_code == 200, read.text
        assert read.json()["basis"] == "marked"
        assert read.json()["can_mark"] is True

        row = await row_of(owner, interaction)
        assert row.status == "no_show"
        assert row.stage is None
        # The item is still out: the deadline stays visible.
        assert row.return_due_at == due_at
        assert row.overdue is True

        kept = await listing_row(owner, listing)
        assert kept.status == "busy"

        await owner.auth.db.rollback()
        reminder = await owner.auth.db.scalar(
            select(Reminder).where(Reminder.key == f"return:{interaction['id']}")
        )
        assert reminder is not None
        assert reminder.active is False


async def test_not_returned_belongs_to_the_owner_only(
    owner: Account, borrower: Account, places: Places
) -> None:
    listing, interaction = await loan(owner, borrower)
    assert (await hand_over(owner, borrower, listing, interaction)).status_code == 200

    borrower_try = await not_returned(borrower, listing, interaction)
    assert borrower_try.status_code == 403, borrower_try.text
    assert borrower_try.json()["code"] == "loan_not_returned_forbidden"

    stranger = await new_account(owner.auth, places, "participant5@university.example")
    stranger_try = await not_returned(stranger, listing, interaction)
    assert stranger_try.status_code == 403, stranger_try.text

    # A loan that was not handed over cannot be marked at all.
    fresh_listing, fresh = await loan(owner, borrower)
    before = await not_returned(owner, fresh_listing, fresh)
    assert before.status_code == 409, before.text
    assert before.json()["code"] == "loan_not_returned_unavailable"

    # Nor can a giveaway: the action belongs to a lent item.
    giveaway = await request(
        owner,
        "POST",
        "/giveaways",
        {
            "category_id": (await request(owner, "GET", "/categories")).json()["items"][
                0
            ]["id"],
            "title": "A kettle",
            "description": "Works",
        },
    )
    assert giveaway.status_code == 201
    reservation = await reserve(borrower, giveaway.json())
    accepted = await request(
        owner,
        "POST",
        f"/{giveaway.json()['id']}/interactions/{reservation.json()['id']}/transition",
        {"status": "accepted"},
    )
    assert accepted.status_code == 200, accepted.text
    wrong_kind = await not_returned(owner, giveaway.json(), accepted.json())
    assert wrong_kind.status_code == 409, wrong_kind.text
    assert wrong_kind.json()["code"] == "loan_not_returned_unavailable"

    assert await marks(owner, interaction) == []


async def test_not_returned_is_repeatable_and_idempotent(
    owner: Account, borrower: Account
) -> None:
    now = clock.now()
    with time_machine.travel(now, tick=False):
        listing, interaction = await loan(owner, borrower, loan_days=1)
        assert (
            await hand_over(owner, borrower, listing, interaction)
        ).status_code == 200
    key = str(uuid4())
    with time_machine.travel(now + timedelta(days=4), tick=False):
        first = await not_returned(owner, listing, interaction, key=key)
        assert first.status_code == 200, first.text
        replay = await not_returned(owner, listing, interaction, key=key)
        assert replay.status_code == 200
        assert replay.json() == first.json()
        repeat = await not_returned(owner, listing, interaction)

    assert repeat.status_code == 200, repeat.text
    assert repeat.json()["status"] == "no_show"
    found = await marks(owner, interaction)
    assert len(found) == 1
    events = await journal(owner, interaction)
    assert [event.action for event in events].count("loan_not_returned") == 1


async def test_parallel_not_returned_marks_once(
    owner: Account, borrower: Account
) -> None:
    now = clock.now()
    with time_machine.travel(now, tick=False):
        listing, interaction = await loan(owner, borrower, loan_days=1)
        assert (
            await hand_over(owner, borrower, listing, interaction)
        ).status_code == 200

    with time_machine.travel(now + timedelta(days=4), tick=False):
        responses = await asyncio.gather(
            not_returned(owner, listing, interaction),
            not_returned(owner, listing, interaction),
        )

    assert [response.status_code for response in responses] == [200, 200]
    assert len(await marks(owner, interaction)) == 1


async def test_the_return_reminder_and_the_overdue_flag(
    owner: Account, borrower: Account
) -> None:
    now = clock.now()
    with time_machine.travel(now, tick=False):
        listing, interaction = await loan(owner, borrower, loan_days=3)
        assert (
            await hand_over(owner, borrower, listing, interaction)
        ).status_code == 200

    remind_at = now + timedelta(days=2)
    with time_machine.travel(remind_at + timedelta(minutes=1), tick=False):
        assert await deadlines(owner) >= 1
        assert await deadlines(owner) == 0
        await owner.auth.db.rollback()
        sends = [
            row
            for row in await owner.auth.db.scalars(
                select(OutboxMessage).where(OutboxMessage.topic == "notifications.send")
            )
            if row.payload.get("type") == "return.reminder"
        ]
    assert len(sends) == 1
    assert sends[0].payload["type"] == "return.reminder"
    assert sends[0].payload["recipients"] == [str(user_id(borrower))]
    assert sends[0].payload["text"]["ru"] == (
        "Срок возврата по вашему займу приближается."
    )

    with time_machine.travel(now + timedelta(days=3, minutes=1), tick=False):
        view = await interaction_view(owner, listing)
        assert view["status"] == "accepted"
        assert view["overdue"] is True
        assert parse_instant(view["return_due_at"]) == now + timedelta(days=3)
        assert (await listing_row(owner, listing)).status == "busy"
        returned = await give_back(owner, borrower, listing, interaction)
        assert returned.status_code == 200, returned.text
        assert returned.json()["status"] == "completed"
        assert returned.json()["return_due_at"] is None

    events = await journal(owner, interaction)
    assert events[-1].action == "loan_returned"
    assert events[-1].details is not None
    assert events[-1].details["overdue"] is True


async def test_a_return_after_the_not_returned_mark_is_refused(
    owner: Account, borrower: Account
) -> None:
    now = clock.now()
    with time_machine.travel(now, tick=False):
        listing, interaction = await loan(owner, borrower, loan_days=1)
        assert (
            await hand_over(owner, borrower, listing, interaction)
        ).status_code == 200

    with time_machine.travel(now + timedelta(days=4), tick=False):
        marked = await not_returned(owner, listing, interaction)
        assert marked.status_code == 200, marked.text
        returned = await give_back(owner, borrower, listing, interaction)

    assert returned.status_code == 409, returned.text
    assert returned.json()["code"] == "qr_loan_return_marked"
    row = await row_of(owner, interaction)
    assert row.status == "no_show"
    assert row.stage is None


async def test_a_loan_without_its_details_fails_closed(
    owner: Account, borrower: Account
) -> None:
    listing, interaction = await loan(owner, borrower)
    db = owner.auth.db
    await db.rollback()
    await db.execute(delete(Item).where(Item.listing_id == UUID(listing["id"])))
    await db.commit()

    response = await hand_over(owner, borrower, listing, interaction)

    assert response.status_code == 409, response.text
    row = await row_of(owner, interaction)
    assert row.status == "accepted"
    assert row.stage is None


async def test_an_issued_loan_cannot_be_cancelled_by_the_borrower(
    owner: Account, borrower: Account
) -> None:
    listing, interaction = await loan(owner, borrower)
    assert (await hand_over(owner, borrower, listing, interaction)).status_code == 200

    response = await request(
        borrower,
        "POST",
        f"/{listing['id']}/interactions/{interaction['id']}/transition",
        {"status": "cancelled"},
    )

    assert response.status_code == 409, response.text
    assert response.json()["code"] == "listing_loan_in_progress"
    row = await row_of(owner, interaction)
    assert row.status == "accepted"
    assert row.stage == "issued"


async def test_the_author_cancellation_keeps_the_loan_evidence(
    owner: Account, borrower: Account
) -> None:
    listing, interaction = await loan(owner, borrower, loan_days=3)
    assert (await hand_over(owner, borrower, listing, interaction)).status_code == 200

    response = await request(
        owner,
        "POST",
        f"/{listing['id']}/cancel",
        {"reason": "The item was stolen"},
    )

    assert response.status_code == 200, response.text
    row = await row_of(owner, interaction)
    assert row.status == "cancelled"
    assert row.stage is None
    events = await journal(owner, interaction)
    assert events[-1].action == "cancelled_by_author"
    assert events[-1].details is not None
    assert events[-1].details["stage"] == "issued"
    assert events[-1].details["return_due_at"] is not None
    await owner.auth.db.rollback()
    reminder = await owner.auth.db.scalar(
        select(Reminder).where(Reminder.key == f"return:{interaction['id']}")
    )
    assert reminder is not None
    assert reminder.active is False
