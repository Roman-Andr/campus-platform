"""Giveaway acceptance and concurrency on real PostgreSQL and HTTP requests."""

import asyncio
from datetime import timedelta
from typing import Any
from uuid import UUID, uuid4

import httpx2
import pytest
import time_machine
from sqlalchemy import func, select, text, update
from sqlalchemy.exc import DBAPIError, IntegrityError
from sqlalchemy.ext.asyncio import AsyncEngine

from campus.core import clock
from campus.core.db import create_session_factory
from campus.core.deadlines import process_due_deadlines
from campus.modules.listings import (
    Interaction,
    InteractionStatus,
    Listing,
    ListingEvent,
    ListingStatus,
)
from campus.modules.university import Dormitory, Faculty
from tests.test_identity import Auth
from tests.test_profile import (
    Account,
    Places,
    auth,
    moscow_profile,
    places,
)

# Reuse the real sign-in/profile fixtures; all domain operations use HTTP.
__all__ = ["auth", "places"]
ROOT = "/api/v1/listings"


async def request(
    account: Account,
    method: str,
    path: str = "",
    data: dict[str, Any] | None = None,
    key: str | None = None,
) -> httpx2.Response:
    return await account.auth.client.request(
        method,
        ROOT + path,
        json=data,
        headers={"Idempotency-Key": key or str(uuid4()), **account.headers},
    )


async def publish(account: Account, **overrides: Any) -> dict[str, Any]:
    response = await request(
        account,
        "POST",
        "/giveaways",
        {
            "title": "A desk",
            "description": "Collect on campus",
            **overrides,
        },
    )
    assert response.status_code == 201, response.text
    result: dict[str, Any] = response.json()
    return result


async def reserve(account: Account, listing: dict[str, Any]) -> httpx2.Response:
    return await request(account, "POST", f"/{listing['id']}/reservations")


async def move(
    account: Account,
    listing: dict[str, Any],
    interaction: dict[str, Any],
    status: str,
) -> httpx2.Response:
    return await request(
        account,
        "POST",
        f"/{listing['id']}/interactions/{interaction['id']}/transition",
        {"status": status},
    )


@pytest.fixture
async def owner(auth: Auth, places: Places) -> Account:
    account = Account(auth, await auth.login())
    assert (await account.put(moscow_profile(places))).status_code == 200
    return account


@pytest.fixture
async def borrower(auth: Auth, places: Places) -> Account:
    account = Account(auth, await auth.login(email="borrower@university.example"))
    assert (await account.put(moscow_profile(places))).status_code == 200
    return account


@pytest.fixture
async def staff(auth: Auth, places: Places) -> Account:
    account = Account(auth, await auth.login(email="staff@staff.example"))
    assert (await account.put(moscow_profile(places, course=None))).status_code == 200
    return account


async def test_parallel_reservations(owner: Account, places: Places) -> None:
    listing = await publish(owner)
    accounts = []
    for i in range(12):
        account = Account(
            owner.auth,
            await owner.auth.login(email=f"participant{i}@university.example"),
        )
        assert (await account.put(moscow_profile(places))).status_code == 200
        accounts.append(account)
    responses = await asyncio.gather(
        *(reserve(account, listing) for account in accounts)
    )
    assert sorted(r.status_code for r in responses) == [201] + [409] * 11
    db = owner.auth.db
    assert await db.scalar(select(func.count()).select_from(Interaction)) == 1
    assert await db.scalar(select(func.count()).select_from(ListingEvent)) == 3


async def test_distinct_users_compete(
    owner: Account, borrower: Account, staff: Account
) -> None:
    listing = await publish(owner, audience="community")
    responses = await asyncio.gather(
        reserve(borrower, listing), reserve(staff, listing)
    )
    assert sorted(r.status_code for r in responses) == [201, 409]


@pytest.mark.parametrize("attempt", range(5))
async def test_cancel_races_reserve(
    owner: Account, borrower: Account, attempt: int
) -> None:
    listing = await publish(owner, title=f"Desk {attempt}")
    responses = await asyncio.gather(
        request(owner, "POST", f"/{listing['id']}/cancel"), reserve(borrower, listing)
    )
    assert sorted(r.status_code for r in responses) in ([200, 409], [201, 409])
    current = (await request(owner, "GET", f"/{listing['id']}")).json()
    assert current["status"] == (
        "cancelled" if responses[0].status_code == 200 else "busy"
    )


@pytest.mark.parametrize("source", list(InteractionStatus))
@pytest.mark.parametrize("target", list(InteractionStatus))
async def test_every_interaction_edge(
    owner: Account,
    borrower: Account,
    source: InteractionStatus,
    target: InteractionStatus,
) -> None:
    listing = await publish(owner)
    interaction = (await reserve(borrower, listing)).json()
    await owner.auth.db.execute(update(Interaction).values(status=source))
    await owner.auth.db.commit()
    allowed = {
        ("pending", "accepted"),
        ("pending", "rejected"),
        ("pending", "cancelled"),
        ("accepted", "cancelled"),
    }
    actor = borrower if target == "cancelled" else owner
    response = await move(actor, listing, interaction, target)
    assert response.status_code == (200 if (source, target) in allowed else 409)
    events = (await request(owner, "GET", f"/{listing['id']}/events")).json()["items"]
    if response.status_code == 200:
        assert events[-1]["previous_status"] == source
        assert events[-1]["status"] == target
        assert events[-1]["actor_id"] == actor.tokens["user"]["id"]
    else:
        assert len(events) == 3


@pytest.mark.parametrize("status", list(ListingStatus))
@pytest.mark.parametrize("action", ["reserve", "cancel", "edit"])
async def test_listing_states(
    owner: Account,
    borrower: Account,
    status: ListingStatus,
    action: str,
) -> None:
    listing = await publish(owner)
    await owner.auth.db.execute(update(Listing).values(status=status))
    await owner.auth.db.commit()
    if action == "reserve":
        response = await reserve(borrower, listing)
    elif action == "cancel":
        response = await request(owner, "POST", f"/{listing['id']}/cancel")
    else:
        response = await request(
            owner,
            "PATCH",
            f"/{listing['id']}",
            {"version": 1, "title": "New", "description": "New description"},
        )
    allowed = status == "active" or (status == "busy" and action == "edit")
    expected = (201 if action == "reserve" else 200) if allowed else 409
    assert response.status_code == expected


async def test_stale_parallel_edit(owner: Account) -> None:
    listing = await publish(owner)
    body = {"version": 1, "title": "New", "description": "Updated"}
    responses = await asyncio.gather(
        *(request(owner, "PATCH", f"/{listing['id']}", body) for _ in range(5))
    )
    assert sorted(r.status_code for r in responses) == [200] + [409] * 4
    for response in responses:
        if response.status_code == 409:
            assert response.headers["content-type"] == "application/problem+json"
            assert response.json()["current_version"] == 2


async def test_visibility_and_area_switch(
    owner: Account,
    borrower: Account,
    staff: Account,
    places: Places,
) -> None:
    city = await publish(owner, audience="community")
    students = await publish(owner)
    dorm = await publish(owner, visibility="dormitory", audience="community")
    faculty = await publish(owner, visibility="faculty", audience="community")
    response = await request(staff, "GET")
    assert {x["id"] for x in response.json()["items"]} == {city["id"], faculty["id"]}
    for hidden in (students, dorm):
        assert (await request(staff, "GET", f"/{hidden['id']}")).status_code == 404
        assert (await reserve(staff, hidden)).status_code == 404
    assert [
        x["id"]
        for x in (await request(borrower, "GET", "?area=dormitory")).json()["items"]
    ] == [dorm["id"]]
    await borrower.put(moscow_profile(places, dormitory_id=None))
    assert (await request(borrower, "GET", f"/{dorm['id']}")).status_code == 404
    await borrower.put(
        {
            "city_id": str(places.perm),
            "faculty_id": str(places.perm_faculty),
            "course": 1,
        }
    )
    assert (await request(borrower, "GET")).json()["items"] == []
    for hidden in (city, faculty):
        assert (await reserve(borrower, hidden)).status_code == 404


async def test_keyset_feed(owner: Account) -> None:
    with time_machine.travel(clock.now() - timedelta(seconds=1), tick=False):
        listings = [await publish(owner, title=str(i)) for i in range(5)]
    # The clock must remain before their expiry when fetching.
    first = (await request(owner, "GET", "?size=2")).json()
    assert [x["id"] for x in first["items"]] == [
        x["id"] for x in reversed(listings[-2:])
    ]
    await publish(owner)
    second = (
        await request(owner, "GET", "?size=2&cursor=" + first["next_page"])
    ).json()
    third = (
        await request(owner, "GET", "?size=2&cursor=" + second["next_page"])
    ).json()
    assert [x["id"] for x in first["items"] + second["items"] + third["items"]] == [
        x["id"] for x in reversed(listings)
    ]
    assert third["next_page"] is None


@pytest.mark.parametrize("actor", ["owner", "borrower", "staff"])
async def test_object_permissions(
    owner: Account,
    borrower: Account,
    staff: Account,
    actor: str,
) -> None:
    listing = await publish(owner, audience="community")
    interaction = (await reserve(borrower, listing)).json()
    account = {"owner": owner, "borrower": borrower, "staff": staff}[actor]
    accept = await move(account, listing, interaction, "accepted")
    assert accept.status_code == (200 if actor == "owner" else 403)
    if actor == "owner":
        # Only the participant may cancel their interaction.
        assert (await move(owner, listing, interaction, "cancelled")).status_code == 403
    else:
        assert (
            await request(
                account,
                "PATCH",
                f"/{listing['id']}",
                {"title": "x", "description": "y", "version": 2},
            )
        ).status_code == 403
        assert (
            await request(account, "POST", f"/{listing['id']}/cancel")
        ).status_code == 403
    history = await request(account, "GET", f"/{listing['id']}/events")
    assert history.status_code == (403 if actor == "staff" else 200)


async def test_profile_and_sign_in_required(auth: Auth, owner: Account) -> None:
    account = Account(auth, await auth.login(email="empty@university.example"))
    listing = await publish(owner)
    response = await request(
        account, "POST", "/giveaways", {"title": "x", "description": "y"}
    )
    assert response.json()["code"] == "profile_incomplete"
    assert (await reserve(account, listing)).json()["code"] == "profile_incomplete"
    for method, path in [
        ("GET", ""),
        ("GET", f"/{listing['id']}"),
        ("POST", "/giveaways"),
        ("POST", f"/{listing['id']}/reservations"),
        ("PATCH", f"/{listing['id']}"),
        ("POST", f"/{listing['id']}/cancel"),
        ("GET", f"/{listing['id']}/events"),
    ]:
        response = await auth.client.request(
            method, ROOT + path, headers={"Idempotency-Key": str(uuid4())}
        )
        assert response.status_code == 401
    assert (await reserve(owner, listing)).status_code == 403


async def test_employee_publishes_and_participates(
    owner: Account, staff: Account
) -> None:
    listing = await publish(staff, audience="community")
    assert (await reserve(owner, listing)).status_code == 201
    forbidden = await request(
        staff,
        "POST",
        "/giveaways",
        {"title": "x", "description": "y", "visibility": "dormitory"},
    )
    assert forbidden.status_code == 403


async def test_release_reopens_item(owner: Account, borrower: Account) -> None:
    listing = await publish(owner)
    first = (await reserve(borrower, listing)).json()
    assert (await move(owner, listing, first, "rejected")).status_code == 200
    second = (await reserve(borrower, listing)).json()
    assert (await move(owner, listing, second, "accepted")).status_code == 200
    assert (await move(borrower, listing, second, "cancelled")).status_code == 200
    assert (await reserve(borrower, listing)).status_code == 201


async def test_idempotency(owner: Account, borrower: Account) -> None:
    key = str(uuid4())
    data = {"title": "x", "description": "y"}
    first = await request(owner, "POST", "/giveaways", data, key)
    replay = await request(owner, "POST", "/giveaways", data, key)
    assert replay.json() == first.json()
    assert replay.headers["Idempotent-Replayed"] == "true"
    path = f"/{first.json()['id']}/reservations"
    key = str(uuid4())
    responses = await asyncio.gather(
        *(request(borrower, "POST", path, key=key) for _ in range(4))
    )
    assert {r.status_code for r in responses} == {201}
    assert len({r.json()["id"] for r in responses}) == 1


@pytest.mark.parametrize("state", ["active", "pending", "accepted", "cancelled"])
async def test_deadline_catch_up(owner: Account, borrower: Account, state: str) -> None:
    now = clock.now()
    listing = await publish(owner)
    interaction = None
    if state in ("pending", "accepted"):
        interaction = (await reserve(borrower, listing)).json()
        if state == "accepted":
            await move(owner, listing, interaction, "accepted")
    elif state == "cancelled":
        await request(owner, "POST", f"/{listing['id']}/cancel")
    assert isinstance(owner.auth.db.bind, AsyncEngine)
    sessions = create_session_factory(owner.auth.db.bind)
    with time_machine.travel(
        now + owner.auth.settings.listing_lifetime + timedelta(days=2), tick=False
    ):
        assert await process_due_deadlines(sessions, owner.auth.settings) == 1
        assert await process_due_deadlines(sessions, owner.auth.settings) == 0
        owner.auth.db.expire_all()
        row = await owner.auth.db.get(Listing, UUID(listing["id"]))
        assert row is not None
        assert row.status == ("cancelled" if state == "cancelled" else "expired")
        if interaction:
            item = await owner.auth.db.get(Interaction, UUID(interaction["id"]))
            assert item is not None
            assert item.status == ("rejected" if state == "pending" else "accepted")
        events = list(
            await owner.auth.db.scalars(
                select(ListingEvent).where(ListingEvent.action == "expired")
            )
        )
        assert len(events) == (
            0 if state == "cancelled" else 2 if state == "pending" else 1
        )


async def test_database_invariants(owner: Account, borrower: Account) -> None:
    listing = await publish(owner)
    interaction = (await reserve(borrower, listing)).json()
    db = owner.auth.db
    db.add(
        Interaction(
            listing_id=UUID(listing["id"]),
            participant_id=UUID(interaction["participant_id"]),
        )
    )
    with pytest.raises(IntegrityError):
        await db.commit()
    await db.rollback()
    for statement in (
        "UPDATE listing_event SET action = 'tampered'",
        "DELETE FROM listing_event",
        "TRUNCATE listing_event",
    ):
        with pytest.raises(DBAPIError):
            await db.execute(text(statement))
        await db.rollback()


async def test_validation_and_missing_objects(
    owner: Account, borrower: Account
) -> None:
    for data in (
        {"title": " ", "description": "x"},
        {"title": "x" * 101, "description": "y"},
        {"title": "x", "description": "y" * 5001},
    ):
        assert (await request(owner, "POST", "/giveaways", data)).status_code == 422
    assert (await request(owner, "GET", f"/{uuid4()}")).status_code == 404
    assert (await request(owner, "POST", f"/{uuid4()}/reservations")).status_code == 404
    listing = await publish(owner)
    assert (
        await request(
            borrower,
            "POST",
            f"/{listing['id']}/interactions/{uuid4()}/transition",
            {"status": "accepted"},
        )
    ).status_code == 404


async def test_different_dormitory_and_faculty(
    owner: Account,
    borrower: Account,
    places: Places,
) -> None:
    db = owner.auth.db
    other_dorm = Dormitory(
        city_id=places.moscow, code="other", name_ru="Другое", name_en="Other"
    )
    other_faculty = Faculty(
        city_id=places.moscow, code="other", name_ru="Другой", name_en="Other"
    )
    db.add_all([other_dorm, other_faculty])
    await db.flush()
    profile = moscow_profile(
        places, dormitory_id=str(other_dorm.id), faculty_id=str(other_faculty.id)
    )
    await db.commit()
    dorm = await publish(owner, visibility="dormitory")
    faculty = await publish(owner, visibility="faculty")
    assert (await borrower.put(profile)).status_code == 200
    assert (await request(borrower, "GET")).json()["items"] == []
    for listing in (dorm, faculty):
        assert (await request(borrower, "GET", f"/{listing['id']}")).status_code == 404
        assert (await reserve(borrower, listing)).status_code == 404
    await borrower.put(moscow_profile(places, dormitory_id=None))
    response = await request(
        borrower,
        "POST",
        "/giveaways",
        {"title": "x", "description": "y", "visibility": "dormitory"},
    )
    assert response.status_code == 403


async def test_expiry_is_enforced_before_scheduler(
    owner: Account, borrower: Account
) -> None:
    owner.auth.app.state.settings = owner.auth.settings.model_copy(
        update={"listing_lifetime": timedelta(seconds=30)}
    )
    listing = await publish(owner)
    interaction = (await reserve(borrower, listing)).json()
    with time_machine.travel(clock.now() + timedelta(seconds=31), tick=False):
        assert (await reserve(borrower, listing)).status_code == 409
        assert (await move(owner, listing, interaction, "accepted")).status_code == 409
        assert (await request(owner, "GET")).json()["items"] == []
        assert (
            await request(
                owner,
                "PATCH",
                f"/{listing['id']}",
                {"version": 2, "title": "Updated", "description": "Updated"},
            )
        ).status_code == 409
        assert (
            await request(owner, "POST", f"/{listing['id']}/cancel")
        ).status_code == 409


async def test_all_mutations_replay(owner: Account, borrower: Account) -> None:
    listing = await publish(owner)
    key = str(uuid4())
    body = {"version": 1, "title": "Updated", "description": "Updated"}
    edited = await request(owner, "PATCH", f"/{listing['id']}", body, key)
    assert edited.status_code == 200
    assert (
        await request(owner, "PATCH", f"/{listing['id']}", body, key)
    ).json() == edited.json()
    interaction = (await reserve(borrower, listing)).json()
    path = f"/{listing['id']}/interactions/{interaction['id']}/transition"
    key = str(uuid4())
    accepted = await request(owner, "POST", path, {"status": "accepted"}, key)
    assert accepted.status_code == 200
    replay = await request(owner, "POST", path, {"status": "accepted"}, key)
    assert replay.headers["Idempotent-Replayed"] == "true"
    assert replay.json() == accepted.json()
    assert (await move(borrower, listing, interaction, "cancelled")).status_code == 200
    key = str(uuid4())
    cancelled = await request(owner, "POST", f"/{listing['id']}/cancel", key=key)
    assert cancelled.status_code == 200
    replay = await request(owner, "POST", f"/{listing['id']}/cancel", key=key)
    assert replay.headers["Idempotent-Replayed"] == "true"
    assert replay.json() == cancelled.json()


async def test_wrong_transition_actor(owner: Account, borrower: Account) -> None:
    listing = await publish(owner)
    interaction = (await reserve(borrower, listing)).json()
    assert (await move(borrower, listing, interaction, "rejected")).status_code == 403
    assert (await move(owner, listing, interaction, "cancelled")).status_code == 403
    assert (await request(owner, "GET", f"/{uuid4()}/events")).status_code == 404
