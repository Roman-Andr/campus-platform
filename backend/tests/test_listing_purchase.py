"""Group purchases: shares, volume invariants, deadline and fixation."""

import asyncio
from datetime import UTC, datetime, timedelta
from decimal import Decimal
from typing import Any
from uuid import UUID

import httpx2
import pytest
from sqlalchemy import func, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncEngine

from campus.core import clock
from campus.core.db import create_session_factory
from campus.core.deadlines import Deadline, process_due_deadlines
from campus.core.outbox import OutboxMessage
from campus.modules.listings import (
    Interaction,
    InteractionStatus,
    Listing,
    WaitlistEntry,
    WaitlistStatus,
)
from tests.test_identity import Auth
from tests.test_listings import (
    auth,
    borrower,
    move,
    owner,
    places,
    request,
    staff,
)
from tests.test_photos import at
from tests.test_profile import Account, Places, moscow_profile

__all__ = ["auth", "borrower", "owner", "places", "staff"]

ROOT = "/api/v1/listings"


@pytest.fixture(autouse=True)
def long_lived_test_access(auth: Auth) -> None:
    """Keep HTTP credentials valid while moving time to collection deadlines."""
    auth.settings = auth.settings.model_copy(
        update={"access_token_ttl": timedelta(days=365)}
    )
    auth.app.state.settings = auth.settings


def instant(value: datetime) -> str:
    return value.astimezone(UTC).isoformat().replace("+00:00", "Z")


def money(value: Any) -> Decimal:
    return Decimal(str(value))


async def participant(auth: Auth, places: Places, number: int) -> Account:
    account = Account(auth, await auth.login(email=f"buyer{number}@university.example"))
    assert (await account.put(moscow_profile(places))).status_code == 200
    return account


async def publish_purchase(account: Account, **overrides: Any) -> dict[str, Any]:
    category = (await request(account, "GET", "/categories")).json()["items"][0]["id"]
    response = await request(
        account,
        "POST",
        "/purchases",
        {
            "category_id": category,
            "title": "A bag of rice",
            "description": "Bulk order from the market",
            "price_per_unit": "12.50",
            "min_units": 2,
            "max_units": 10,
            "collection_deadline": instant(clock.now() + timedelta(days=3)),
            **overrides,
        },
    )
    assert response.status_code == 201, response.text
    result: dict[str, Any] = response.json()
    assert result["kind"] == "purchase"
    assert result["purchase_stage"] == "collecting"
    return result


async def join(
    account: Account, listing: dict[str, Any], units: int
) -> httpx2.Response:
    return await request(account, "POST", f"/{listing['id']}/shares", {"units": units})


async def my_share(account: Account, listing: dict[str, Any]) -> httpx2.Response:
    return await request(account, "GET", f"/{listing['id']}/shares/me")


async def change(
    account: Account, listing: dict[str, Any], units: int
) -> httpx2.Response:
    return await request(
        account, "PATCH", f"/{listing['id']}/shares/me", {"units": units}
    )


async def leave(account: Account, listing: dict[str, Any]) -> httpx2.Response:
    return await request(account, "DELETE", f"/{listing['id']}/shares/me")


async def withdrawal(
    account: Account, listing: dict[str, Any], **body: Any
) -> httpx2.Response:
    return await request(
        account, "POST", f"/{listing['id']}/shares/me/withdrawal", body
    )


async def cancel_withdrawal(
    account: Account, listing: dict[str, Any]
) -> httpx2.Response:
    return await request(account, "DELETE", f"/{listing['id']}/shares/me/withdrawal")


async def decide(
    account: Account,
    listing: dict[str, Any],
    interaction_id: str,
    approve: bool,
) -> httpx2.Response:
    return await request(
        account,
        "POST",
        f"/{listing['id']}/shares/{interaction_id}/withdrawal/decision",
        {"approve": approve},
    )


async def composition(account: Account, listing: dict[str, Any]) -> dict[str, Any]:
    response = await request(account, "GET", f"/{listing['id']}/shares")
    assert response.status_code == 200, response.text
    result: dict[str, Any] = response.json()
    return result


async def queue_join(
    account: Account, listing: dict[str, Any], units: int
) -> httpx2.Response:
    return await request(
        account, "POST", f"/{listing['id']}/waitlist", {"units": units}
    )


async def queue_entry(account: Account, listing: dict[str, Any]) -> dict[str, Any]:
    response = await request(account, "GET", f"/{listing['id']}/waitlist/me")
    assert response.status_code == 200, response.text
    result: dict[str, Any] = response.json()
    return result


async def deadlines(account: Account) -> int:
    assert isinstance(account.auth.db.bind, AsyncEngine)
    return await process_due_deadlines(
        create_session_factory(account.auth.db.bind), account.auth.settings
    )


def settings(account: Account, **changes: Any) -> None:
    account.auth.settings = account.auth.settings.model_copy(update=changes)
    account.auth.app.state.settings = account.auth.settings


async def notifications(account: Account) -> list[OutboxMessage]:
    await account.auth.db.rollback()
    return list(
        await account.auth.db.scalars(select(OutboxMessage).order_by(OutboxMessage.id))
    )


async def events(account: Account, listing: dict[str, Any]) -> list[dict[str, Any]]:
    response = await request(account, "GET", f"/{listing['id']}/events")
    assert response.status_code == 200, response.text
    items: list[dict[str, Any]] = response.json()["items"]
    return items


async def test_purchase_share_amount_and_composition(
    owner: Account, borrower: Account
) -> None:
    listing = await publish_purchase(owner)
    assert money(listing["purchase_unit_price"]) == Decimal("12.50")
    assert listing["purchase_max_units"] == 10
    assert listing["purchase_taken_units"] == 0

    response = await join(borrower, listing, 3)
    assert response.status_code == 201, response.text
    share = response.json()
    assert share["status"] == "accepted"
    assert share["stage"] == "collecting"
    assert share["units"] == 3
    assert money(share["amount"]) == Decimal("37.50")
    assert money(share["unit_price"]) == Decimal("12.50")

    own = await my_share(borrower, listing)
    assert own.status_code == 200
    assert money(own.json()["amount"]) == Decimal("37.50")

    result = await composition(owner, listing)
    assert result["stage"] == "collecting"
    assert result["total_units"] == 3
    assert money(result["total_amount"]) == Decimal("37.50")
    assert len(result["items"]) == 1

    # One share per participant, and the author cannot join.
    assert (await join(borrower, listing, 1)).json()["code"] == (
        "listing_purchase_share_exists"
    )
    assert (await join(owner, listing, 1)).status_code == 403
    forbidden = await request(borrower, "GET", f"/{listing['id']}/shares")
    assert forbidden.status_code == 403


async def test_change_units_and_leave_while_collecting(
    owner: Account, borrower: Account
) -> None:
    listing = await publish_purchase(owner)
    assert (await join(borrower, listing, 4)).status_code == 201

    changed = await change(borrower, listing, 6)
    assert changed.status_code == 200, changed.text
    assert changed.json()["units"] == 6
    assert money(changed.json()["amount"]) == Decimal("75.00")
    assert (await composition(owner, listing))["total_units"] == 6

    unavailable = await change(borrower, listing, 11)
    assert unavailable.status_code == 409
    assert unavailable.json()["code"] == "listing_purchase_units_unavailable"

    assert (await leave(borrower, listing)).status_code == 204
    assert (await composition(owner, listing))["total_units"] == 0
    assert (await my_share(borrower, listing)).status_code == 404
    assert (await change(borrower, listing, 2)).status_code == 404


async def test_parallel_shares_never_exceed_maximum(
    owner: Account, auth: Auth, places: Places
) -> None:
    listing = await publish_purchase(owner, min_units=1, max_units=10)
    buyers = [await participant(auth, places, index) for index in range(6)]
    responses = await asyncio.gather(*(join(buyer, listing, 3) for buyer in buyers))

    codes = sorted(response.status_code for response in responses)
    assert codes == [201] * 3 + [409] * 3
    assert {
        response.json()["code"] for response in responses if response.status_code == 409
    } == {"listing_purchase_units_unavailable"}
    result = await composition(owner, listing)
    assert result["total_units"] == 9
    assert result["taken_units"] == 9
    total = await owner.auth.db.scalar(
        select(func.coalesce(func.sum(Interaction.units), 0)).where(
            Interaction.listing_id == UUID(listing["id"]),
            Interaction.status == InteractionStatus.ACCEPTED,
        )
    )
    assert total == 9

    # The database itself refuses a counter above the maximum.
    db = owner.auth.db
    with pytest.raises(IntegrityError):
        await db.execute(
            update(Listing)
            .where(Listing.id == UUID(listing["id"]))
            .values(purchase_taken_units=11)
        )
    await db.rollback()


async def test_parallel_increases_never_exceed_maximum(
    owner: Account, borrower: Account, auth: Auth, places: Places
) -> None:
    second = await participant(auth, places, 5)
    listing = await publish_purchase(owner, min_units=1, max_units=10)
    assert (await join(borrower, listing, 5)).status_code == 201
    assert (await join(second, listing, 4)).status_code == 201

    # One free unit: each increase is valid against the current state, but
    # only one of them can commit.
    responses = await asyncio.gather(
        change(borrower, listing, 6),
        change(second, listing, 5),
    )
    assert sorted(response.status_code for response in responses) == [200, 409]
    result = await composition(owner, listing)
    assert result["total_units"] == 10
    assert result["taken_units"] == 10
    assert {item["units"] for item in result["items"]} <= {4, 5, 6}


async def test_participant_with_share_cannot_also_queue(
    owner: Account, borrower: Account
) -> None:
    listing = await publish_purchase(owner, min_units=1, max_units=2)
    assert (await join(borrower, listing, 2)).status_code == 201
    queued = await queue_join(borrower, listing, 1)
    assert queued.status_code == 409
    assert queued.json()["code"] == "listing_purchase_share_exists"
    assert (await join(borrower, listing, 1)).json()["code"] == (
        "listing_purchase_share_exists"
    )


async def test_edit_cannot_lower_maximum_below_taken(
    owner: Account, borrower: Account
) -> None:
    listing = await publish_purchase(owner, min_units=2, max_units=10)
    assert (await join(borrower, listing, 6)).status_code == 201
    current = (await request(owner, "GET", f"/{listing['id']}")).json()

    refused = await request(
        owner,
        "PATCH",
        f"/{listing['id']}/purchase",
        {"version": current["version"], "max_units": 5},
    )
    assert refused.status_code == 409
    assert refused.json()["code"] == "listing_purchase_capacity_conflict"

    deadline = clock.now() + timedelta(days=2)
    changed = await request(
        owner,
        "PATCH",
        f"/{listing['id']}/purchase",
        {
            "version": current["version"],
            "min_units": 2,
            "max_units": 8,
            "collection_deadline": instant(deadline),
        },
    )
    assert changed.status_code == 200, changed.text
    assert changed.json()["purchase_max_units"] == 8
    assert changed.json()["purchase_collection_deadline"] == instant(deadline)


async def test_author_cancels_collecting_purchase(
    owner: Account, borrower: Account, auth: Auth, places: Places
) -> None:
    queue_member = await participant(auth, places, 6)
    listing = await publish_purchase(owner, min_units=1, max_units=2)
    share = (await join(borrower, listing, 2)).json()
    assert (await queue_join(queue_member, listing, 1)).status_code == 201

    cancelled = await request(
        owner,
        "POST",
        f"/{listing['id']}/cancel",
        {"reason": "Supplier is out of stock"},
    )
    assert cancelled.status_code == 200, cancelled.text
    assert cancelled.json()["status"] == "cancelled"
    assert cancelled.json()["purchase_stage"] == "cancelled"
    assert cancelled.json()["purchase_taken_units"] == 0

    await owner.auth.db.rollback()
    stored_share = await owner.auth.db.get(Interaction, UUID(share["id"]))
    assert stored_share is not None
    assert stored_share.status == InteractionStatus.CANCELLED
    assert stored_share.cancelled_by == "author"
    assert stored_share.cancellation_reason == "Supplier is out of stock"
    entry = await owner.auth.db.scalar(
        select(WaitlistEntry).where(
            WaitlistEntry.listing_id == UUID(listing["id"]),
            WaitlistEntry.participant_id == UUID(queue_member.tokens["user"]["id"]),
        )
    )
    assert entry is not None
    assert entry.status == WaitlistStatus.REMOVED
    history = await events(owner, listing)
    assert any(item["action"] == "purchase_cancelled" for item in history)
    messages = await notifications(borrower)
    assert any(
        message.payload.get("type") == "listing.purchase.cancelled"
        for message in messages
    )

    version = cancelled.json()["version"]
    later = [
        await join(borrower, listing, 1),
        await request(owner, "POST", f"/{listing['id']}/cancel"),
        await request(
            owner,
            "PATCH",
            f"/{listing['id']}/purchase",
            {"version": version, "price_per_unit": "1.00"},
        ),
    ]
    assert [response.status_code for response in later] == [409, 409, 409]


async def test_author_cancel_purchase_requires_reason(
    owner: Account, borrower: Account
) -> None:
    listing = await publish_purchase(owner, min_units=1, max_units=2)
    share = (await join(borrower, listing, 1)).json()

    preview = await request(owner, "GET", f"/{listing['id']}/cancellation")
    assert preview.status_code == 200
    assert preview.json()["accepted_interactions"] == 1
    assert preview.json()["reason_required"] is True

    refused = await request(owner, "POST", f"/{listing['id']}/cancel")
    assert refused.status_code == 422
    assert refused.json()["code"] == "listing_cancel_reason_required"

    cancelled = await request(
        owner,
        "POST",
        f"/{listing['id']}/cancel",
        {"reason": "Supplier is out of stock"},
    )
    assert cancelled.status_code == 200, cancelled.text
    await owner.auth.db.rollback()
    stored = await owner.auth.db.get(Interaction, UUID(share["id"]))
    assert stored is not None
    assert stored.status == InteractionStatus.CANCELLED
    assert stored.cancelled_by == "author"
    assert stored.cancellation_reason == "Supplier is out of stock"
    messages = [
        message
        for message in await notifications(borrower)
        if message.payload.get("type") == "listing.purchase.cancelled"
    ]
    assert "Supplier is out of stock" in messages[-1].payload["text"]["en"]


async def test_collecting_leave_is_not_late(owner: Account, borrower: Account) -> None:
    listing = await publish_purchase(owner, min_units=1, max_units=2)
    share = (await join(borrower, listing, 1)).json()
    assert (await leave(borrower, listing)).status_code == 204

    await owner.auth.db.rollback()
    stored = await owner.auth.db.get(Interaction, UUID(share["id"]))
    assert stored is not None
    assert stored.status == InteractionStatus.CANCELLED
    assert stored.cancelled_by == "participant"
    assert stored.late_cancelled is False


async def test_fixed_purchase_leave_is_late(owner: Account, borrower: Account) -> None:
    deadline = clock.now() + timedelta(hours=2)
    listing = await publish_purchase(
        owner, min_units=1, max_units=5, collection_deadline=instant(deadline)
    )
    share = (await join(borrower, listing, 2)).json()
    with at(deadline + timedelta(seconds=1)):
        assert await deadlines(owner) >= 1

    preview = await request(
        borrower,
        "GET",
        f"/{listing['id']}/interactions/{share['id']}/cancellation",
    )
    assert preview.status_code == 200, preview.text
    assert preview.json()["late"] is True
    assert preview.json()["requires_approval"] is True

    requested = await withdrawal(borrower, listing, reason="Changed plans")
    assert requested.status_code == 201
    decided = await decide(owner, listing, share["id"], True)
    assert decided.status_code == 200, decided.text
    assert decided.json()["late_cancelled"] is True

    await owner.auth.db.rollback()
    stored = await owner.auth.db.get(Interaction, UUID(share["id"]))
    assert stored is not None
    assert stored.cancelled_by == "participant"
    assert stored.late_cancelled is True
    history = await events(owner, listing)
    approved = next(item for item in history if item["action"] == "leave_approved")
    assert approved["details"]["late"] is True


async def test_price_change_exempts_fixed_leave(
    owner: Account, borrower: Account
) -> None:
    deadline = clock.now() + timedelta(hours=2)
    listing = await publish_purchase(
        owner, min_units=1, max_units=5, collection_deadline=instant(deadline)
    )
    share = (await join(borrower, listing, 2)).json()
    current = (await request(owner, "GET", f"/{listing['id']}")).json()
    changed = await request(
        owner,
        "PATCH",
        f"/{listing['id']}/purchase",
        {"version": current["version"], "price_per_unit": "15.00"},
    )
    assert changed.status_code == 200, changed.text

    with at(deadline + timedelta(seconds=1)):
        assert await deadlines(owner) >= 1

    preview = await request(
        borrower,
        "GET",
        f"/{listing['id']}/interactions/{share['id']}/cancellation",
    )
    assert preview.status_code == 200, preview.text
    assert preview.json()["late"] is False
    requested = await withdrawal(borrower, listing, reason="Price changed")
    assert requested.status_code == 201
    decided = await decide(owner, listing, share["id"], True)
    assert decided.status_code == 200, decided.text
    assert decided.json()["late_cancelled"] is False

    await owner.auth.db.rollback()
    stored = await owner.auth.db.get(Interaction, UUID(share["id"]))
    assert stored is not None
    assert stored.late_cancelled is False


async def test_pending_offer_expires_when_composition_freezes(
    owner: Account,
    borrower: Account,
    auth: Auth,
    places: Places,
) -> None:
    queue_member = await participant(auth, places, 7)
    deadline = clock.now() + timedelta(hours=2)
    listing = await publish_purchase(
        owner, min_units=1, max_units=5, collection_deadline=instant(deadline)
    )
    assert (await join(borrower, listing, 5)).status_code == 201
    assert (await queue_join(queue_member, listing, 2)).status_code == 201
    assert (await change(borrower, listing, 3)).status_code == 200
    assert (await queue_entry(queue_member, listing))["status"] == "offered"

    with at(deadline + timedelta(seconds=1)):
        assert await deadlines(owner) >= 1

    result = (await request(owner, "GET", f"/{listing['id']}")).json()
    assert result["purchase_stage"] == "fixed"
    assert result["purchase_fixed_units"] == 3
    await owner.auth.db.rollback()
    entry = await owner.auth.db.scalar(
        select(WaitlistEntry).where(
            WaitlistEntry.listing_id == UUID(listing["id"]),
            WaitlistEntry.participant_id == UUID(queue_member.tokens["user"]["id"]),
        )
    )
    assert entry is not None
    assert entry.status == WaitlistStatus.EXPIRED
    expired = await request(
        queue_member, "POST", f"/{listing['id']}/waitlist/offer/accept"
    )
    assert expired.status_code == 409
    assert (await composition(owner, listing))["total_units"] == 3


async def test_price_change_recalculates_and_notifies(
    owner: Account, borrower: Account
) -> None:
    listing = await publish_purchase(owner)
    assert (await join(borrower, listing, 2)).status_code == 201
    current = (await request(owner, "GET", f"/{listing['id']}")).json()

    changed = await request(
        owner,
        "PATCH",
        f"/{listing['id']}/purchase",
        {"version": current["version"], "price_per_unit": "15.00"},
    )
    assert changed.status_code == 200, changed.text
    assert money(changed.json()["purchase_unit_price"]) == Decimal("15.00")
    assert money((await my_share(borrower, listing)).json()["amount"]) == Decimal(
        "30.00"
    )
    history = await events(owner, listing)
    assert history[-1]["action"] == "conditions_changed"
    assert money(history[-1]["details"]["price_per_unit"]) == Decimal("15.00")
    assert money(history[-1]["details"]["previous"]["price_per_unit"]) == Decimal(
        "12.50"
    )
    messages = await notifications(borrower)
    condition_messages = [
        message
        for message in messages
        if message.payload.get("type") == "listing.purchase.conditions_changed"
    ]
    assert condition_messages
    assert borrower.tokens["user"]["id"] in condition_messages[-1].payload["recipients"]

    version = (await request(owner, "GET", f"/{listing['id']}")).json()["version"]
    stale = await request(
        owner,
        "PATCH",
        f"/{listing['id']}/purchase",
        {"version": version - 1, "min_units": 1},
    )
    assert stale.status_code == 409
    assert stale.json()["code"] == "listing_version_conflict"


async def test_purchase_validation(owner: Account, borrower: Account) -> None:
    listing = await publish_purchase(owner, min_units=2, max_units=4)
    past = instant(clock.now() - timedelta(hours=1))
    too_far = instant(clock.now() + timedelta(days=60))
    base = {
        "price_per_unit": "10.00",
        "min_units": 1,
        "max_units": 5,
        "collection_deadline": instant(clock.now() + timedelta(days=1)),
    }
    cases = [
        ({**base, "price_per_unit": "0"}, "validation_failed"),
        ({**base, "min_units": 0}, "validation_failed"),
        ({**base, "min_units": 5, "max_units": 2}, "listing_purchase_volume_invalid"),
        ({**base, "collection_deadline": past}, "listing_purchase_deadline_invalid"),
        ({**base, "collection_deadline": too_far}, "listing_purchase_deadline_invalid"),
    ]
    category = (await request(owner, "GET", "/categories")).json()["items"][0]["id"]
    for body, code in cases:
        response = await request(
            owner,
            "POST",
            "/purchases",
            {
                "category_id": category,
                "title": "A case",
                "description": "Validated",
                **body,
            },
        )
        assert response.status_code == 422, response.text
        assert response.json()["code"] == code

    too_many = await join(borrower, listing, 5)
    assert too_many.status_code == 409
    assert too_many.json()["code"] == "listing_purchase_units_unavailable"
    zero = await request(borrower, "POST", f"/{listing['id']}/shares", {"units": 0})
    assert zero.status_code == 422
    assert (await join(owner, listing, 1)).status_code == 403


async def test_deadline_cancels_below_minimum(
    owner: Account, borrower: Account
) -> None:
    deadline = clock.now() + timedelta(hours=2)
    listing = await publish_purchase(
        owner, min_units=3, max_units=10, collection_deadline=instant(deadline)
    )
    joined = await join(borrower, listing, 2)
    assert joined.status_code == 201
    share_id = UUID(joined.json()["id"])

    with at(deadline + timedelta(seconds=1)):
        assert await deadlines(owner) == 1

    result = (await request(owner, "GET", f"/{listing['id']}")).json()
    assert result["status"] == "cancelled"
    assert result["purchase_stage"] == "cancelled"
    assert result["purchase_taken_units"] == 0
    await owner.auth.db.rollback()
    cancelled_share = await owner.auth.db.get(Interaction, share_id)
    assert cancelled_share is not None
    assert cancelled_share.status == InteractionStatus.CANCELLED
    history = await events(owner, listing)
    cancelled = [item for item in history if item["action"] == "purchase_cancelled"]
    assert cancelled
    assert cancelled[-1]["reason"] == "min_units_not_reached"
    messages = await notifications(borrower)
    assert any(
        message.payload.get("type") == "listing.purchase.cancelled"
        for message in messages
    )


async def test_deadline_fixes_composition(
    owner: Account, borrower: Account, auth: Auth, places: Places
) -> None:
    second = await participant(auth, places, 2)
    deadline = clock.now() + timedelta(hours=2)
    listing = await publish_purchase(
        owner, min_units=2, max_units=10, collection_deadline=instant(deadline)
    )
    assert (await join(borrower, listing, 3)).status_code == 201
    assert (await join(second, listing, 2)).status_code == 201

    with at(deadline + timedelta(seconds=1)):
        assert await deadlines(owner) == 1

    result = (await request(owner, "GET", f"/{listing['id']}")).json()
    assert result["purchase_stage"] == "fixed"
    assert result["purchase_fixed_units"] == 5
    assert result["purchase_taken_units"] == 5
    assert (await my_share(borrower, listing)).json()["stage"] == "fixed"
    fixed_composition = await composition(owner, listing)
    assert fixed_composition["stage"] == "fixed"
    assert fixed_composition["total_units"] == 5
    assert money(fixed_composition["total_amount"]) == Decimal("62.50")
    messages = await notifications(borrower)
    assert any(
        message.payload.get("type") == "listing.purchase.fixed" for message in messages
    )

    # The composition is closed for joins and free changes.
    assert (await join(second, listing, 1)).json()["code"] in (
        "listing_purchase_share_exists",
        "listing_purchase_closed",
    )
    assert (await change(borrower, listing, 4)).status_code == 409
    assert (await change(borrower, listing, 4)).json()["code"] == (
        "listing_purchase_closed"
    )
    refused = await leave(borrower, listing)
    assert refused.status_code == 409
    assert refused.json()["code"] == "listing_purchase_leave_requires_approval"

    # The generic interaction transition cannot bypass the purchase rules.
    share = (await my_share(borrower, listing)).json()
    assert (await move(borrower, listing, share, "cancelled")).status_code == 409


async def test_reminder_before_deadline_notifies_participants(
    owner: Account, borrower: Account
) -> None:
    settings(owner, listing_purchase_reminder_before=timedelta(hours=1))
    deadline = clock.now() + timedelta(days=2)
    listing = await publish_purchase(owner, collection_deadline=instant(deadline))
    assert (await join(borrower, listing, 1)).status_code == 201

    rows = list(await owner.auth.db.scalars(select(Deadline)))
    topics = {row.topic for row in rows}
    assert "listing.purchase_deadline" in topics
    assert "listing.purchase_reminder" in topics
    reminder = next(row for row in rows if row.topic == "listing.purchase_reminder")
    assert reminder.available_at == deadline - timedelta(hours=1)

    with at(deadline - timedelta(hours=1) + timedelta(seconds=1)):
        assert await deadlines(owner) == 1
    messages = await notifications(borrower)
    assert any(
        message.payload.get("type") == "listing.purchase.reminder"
        for message in messages
    )
    # The deadline itself has not closed the collection yet.
    assert (await request(owner, "GET", f"/{listing['id']}")).json()[
        "purchase_stage"
    ] == "collecting"


async def test_withdrawal_after_fixation_and_queue_offer(
    owner: Account, borrower: Account, auth: Auth, places: Places
) -> None:
    queue_member = await participant(auth, places, 3)
    deadline = clock.now() + timedelta(hours=2)
    listing = await publish_purchase(
        owner, min_units=1, max_units=10, collection_deadline=instant(deadline)
    )
    assert (await join(borrower, listing, 2)).status_code == 201
    with at(deadline + timedelta(seconds=1)):
        assert await deadlines(owner) >= 1
    assert (await request(owner, "GET", f"/{listing['id']}")).json()[
        "purchase_stage"
    ] == "fixed"

    queued = await queue_join(queue_member, listing, 2)
    assert queued.status_code == 201, queued.text

    requested = await withdrawal(borrower, listing, reason="changed plans")
    assert requested.status_code == 201, requested.text
    assert requested.json()["leave_requested_at"] is not None
    assert (await withdrawal(borrower, listing)).status_code == 409
    assert (await withdrawal(borrower, listing)).json()["code"] == (
        "listing_purchase_withdrawal_exists"
    )

    share = requested.json()
    assert (await decide(borrower, listing, share["id"], True)).status_code == 403
    approved = await decide(owner, listing, share["id"], True)
    assert approved.status_code == 200, approved.text
    assert approved.json()["status"] == "cancelled"
    assert approved.json()["leave_requested_at"] is None
    result = (await request(owner, "GET", f"/{listing['id']}")).json()
    assert result["purchase_taken_units"] == 0
    history = await events(owner, listing)
    assert any(item["action"] == "leave_approved" for item in history)

    entry = await queue_entry(queue_member, listing)
    assert entry["status"] == "offered"
    assert entry["offer_units"] == 2
    accepted = await request(
        queue_member, "POST", f"/{listing['id']}/waitlist/offer/accept"
    )
    assert accepted.status_code == 201, accepted.text
    assert accepted.json()["units"] == 2
    assert (await composition(owner, listing))["total_units"] == 2


async def test_withdrawal_rejected_and_cancelled(
    owner: Account, borrower: Account
) -> None:
    deadline = clock.now() + timedelta(hours=2)
    listing = await publish_purchase(
        owner, min_units=1, max_units=10, collection_deadline=instant(deadline)
    )
    assert (await join(borrower, listing, 2)).status_code == 201
    with at(deadline + timedelta(seconds=1)):
        await deadlines(owner)

    # No request before fixation, and no decision without a request.
    fresh = await publish_purchase(
        owner, min_units=1, collection_deadline=instant(clock.now() + timedelta(days=1))
    )
    assert (await join(borrower, fresh, 1)).status_code == 201
    assert (await withdrawal(borrower, fresh)).json()["code"] == (
        "listing_purchase_not_fixed"
    )

    requested = await withdrawal(borrower, listing)
    assert requested.status_code == 201
    share = requested.json()
    assert (await cancel_withdrawal(borrower, listing)).status_code == 204
    assert (await decide(owner, listing, share["id"], True)).json()["code"] == (
        "listing_purchase_withdrawal_missing"
    )

    again = await withdrawal(borrower, listing)
    assert again.status_code == 201
    rejected = await decide(owner, listing, share["id"], False)
    assert rejected.status_code == 200
    assert rejected.json()["status"] == "accepted"
    assert rejected.json()["leave_requested_at"] is None
    history = await events(owner, listing)
    assert any(item["action"] == "leave_rejected" for item in history)


async def test_queue_offers_partial_units(
    owner: Account, borrower: Account, auth: Auth, places: Places
) -> None:
    first = await participant(auth, places, 4)
    # While units are free, joining the queue is rejected: take a share.
    spare = await publish_purchase(owner, min_units=1, max_units=5)
    assert (await join(borrower, spare, 1)).status_code == 201
    rejected = await queue_join(first, spare, 1)
    assert rejected.status_code == 409
    assert rejected.json()["code"] == "listing_waitlist_free"

    listing = await publish_purchase(owner, min_units=1, max_units=5)
    assert (await join(borrower, listing, 5)).status_code == 201
    queued = await queue_join(first, listing, 2)
    assert queued.status_code == 201, queued.text
    assert (await queue_entry(first, listing))["status"] == "waiting"

    # Free units appear only when the participant reduces the share.
    assert (await change(borrower, listing, 3)).status_code == 200
    entry = await queue_entry(first, listing)
    assert entry["status"] == "offered"
    assert entry["offer_units"] == 2

    accepted = await request(first, "POST", f"/{listing['id']}/waitlist/offer/accept")
    assert accepted.status_code == 201
    assert accepted.json()["units"] == 2
    result = await composition(owner, listing)
    assert result["taken_units"] == 5
    assert result["total_units"] == 5


async def test_mutations_are_closed_at_the_deadline_before_the_job(
    owner: Account, borrower: Account
) -> None:
    deadline = clock.now() + timedelta(hours=1)
    listing = await publish_purchase(
        owner, min_units=1, max_units=10, collection_deadline=instant(deadline)
    )
    assert (await join(borrower, listing, 1)).status_code == 201
    current = (await request(owner, "GET", f"/{listing['id']}")).json()

    with at(deadline + timedelta(seconds=1)):
        responses = [
            await join(borrower, listing, 1),
            await change(borrower, listing, 2),
            await leave(borrower, listing),
            await queue_join(borrower, listing, 1),
            await request(
                owner,
                "PATCH",
                f"/{listing['id']}/purchase",
                {"version": current["version"], "price_per_unit": "9.00"},
            ),
        ]
    assert [response.status_code for response in responses] == [409] * 5
    assert {response.json()["code"] for response in responses} == {
        "listing_purchase_closed",
        "listing_purchase_share_exists",
    }

    with at(deadline + timedelta(seconds=2)):
        assert await deadlines(owner) >= 1
    assert (await request(owner, "GET", f"/{listing['id']}")).json()[
        "purchase_stage"
    ] == "fixed"


async def test_forbidden_stage_transitions(owner: Account, borrower: Account) -> None:
    deadline = clock.now() + timedelta(hours=1)
    listing = await publish_purchase(
        owner, min_units=1, max_units=10, collection_deadline=instant(deadline)
    )
    assert (await join(borrower, listing, 1)).status_code == 201
    with at(deadline + timedelta(seconds=1)):
        await deadlines(owner)
    assert (await request(owner, "GET", f"/{listing['id']}")).json()[
        "purchase_stage"
    ] == "fixed"

    version = (await request(owner, "GET", f"/{listing['id']}")).json()["version"]
    actions = [
        await join(borrower, listing, 1),
        await change(borrower, listing, 2),
        await leave(borrower, listing),
        await request(owner, "POST", f"/{listing['id']}/cancel"),
        await request(
            owner,
            "PATCH",
            f"/{listing['id']}/purchase",
            {"version": version, "price_per_unit": "1.00"},
        ),
    ]
    assert all(response.status_code == 409 for response in actions), [
        response.text for response in actions
    ]

    # A cancelled purchase never returns to collecting.
    closed = await publish_purchase(
        owner, min_units=5, max_units=5, collection_deadline=instant(deadline)
    )
    with at(deadline + timedelta(seconds=1)):
        await deadlines(owner)
    version = (await request(owner, "GET", f"/{closed['id']}")).json()["version"]
    refused = await request(
        owner,
        "PATCH",
        f"/{closed['id']}/purchase",
        {"version": version, "price_per_unit": "1.00"},
    )
    assert refused.status_code == 409
    assert refused.json()["code"] == "listing_purchase_closed"
