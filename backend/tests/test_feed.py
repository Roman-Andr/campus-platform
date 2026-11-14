"""Pinned publication permissions, visibility and stable filtered feed pages."""

from datetime import timedelta
from typing import Any
from uuid import UUID, uuid4

import pytest
import time_machine
from sqlalchemy import update

from campus.core import clock
from campus.modules.identity import Role, RoleAssignment, User
from campus.modules.listings import Item
from campus.modules.publications import Publication
from tests.test_listings import borrower, owner, publish, request, reserve
from tests.test_profile import Account, Places, auth, places

__all__ = ["auth", "borrower", "owner", "places"]


async def grant(account: Account, role: Role, **scope: Any) -> None:
    account.auth.db.add(
        RoleAssignment(
            user_id=UUID(account.tokens["user"]["id"]),
            role=role,
            **scope,
        )
    )
    await account.auth.db.commit()


def content(**overrides: Any) -> dict[str, Any]:
    return {
        "title": "Campus notice",
        "description": "Information only",
        "visibility": "city",
        "pinned_until": (clock.now() + timedelta(seconds=10)).isoformat(),
        **overrides,
    }


async def notice(account: Account, **overrides: Any) -> dict[str, Any]:
    response = await request(account, "POST", "/publications", content(**overrides))
    assert response.status_code == 201, response.text
    result: dict[str, Any] = response.json()
    return result


@pytest.mark.parametrize(
    ("account_type", "role"),
    [
        ("student", None),
        ("employee", None),
        ("alumni", None),
        ("student", Role.MODERATOR),
    ],
)
async def test_denied_publish_roles(
    owner: Account, account_type: str, role: Role | None
) -> None:
    if role:
        await grant(owner, role)
    await owner.auth.db.execute(
        update(User)
        .where(User.id == UUID(owner.tokens["user"]["id"]))
        .values(account_type=account_type)
    )
    await owner.auth.db.commit()
    for scope in ("city", "university", "faculty", "dormitory"):
        response = await request(
            owner, "POST", "/publications", content(visibility=scope)
        )
        assert response.status_code == 403, response.text


@pytest.mark.parametrize("scope", ["faculty", "dormitory"])
async def test_headman_scope(owner: Account, places: Places, scope: str) -> None:
    own = places.dubki if scope == "dormitory" else places.economics
    other = places.perm_dormitory if scope == "dormitory" else places.perm_faculty
    await grant(owner, Role.HEADMAN, **{f"{scope}_id": own})
    await notice(owner, visibility=scope, **{f"{scope}_id": str(own)})
    for data in [
        content(visibility=scope, **{f"{scope}_id": str(other)}),
        content(visibility="city"),
        content(visibility="university"),
        content(visibility="faculty" if scope == "dormitory" else "dormitory"),
    ]:
        assert (await request(owner, "POST", "/publications", data)).status_code == 403


@pytest.mark.parametrize("scope", ["city", "university"])
async def test_administrator_publish(
    owner: Account, places: Places, scope: str
) -> None:
    await grant(owner, Role.ADMINISTRATOR)
    listing = await notice(owner, visibility=scope, city_id=str(places.perm))
    assert listing["city_id"] == str(places.perm)
    assert (
        await request(
            owner,
            "POST",
            "/publications",
            content(visibility="dormitory", dormitory_id=str(places.dubki)),
        )
    ).status_code == 403


async def test_pins_visibility_expiry_and_interactions(
    owner: Account,
    borrower: Account,
    places: Places,
) -> None:
    await grant(owner, Role.HEADMAN, dormitory_id=places.dubki)
    await grant(owner, Role.HEADMAN, dormitory_id=places.perm_dormitory)
    await grant(owner, Role.ADMINISTRATOR)
    with time_machine.travel(clock.now(), tick=False) as traveller:
        pin = await notice(
            owner, visibility="dormitory", dormitory_id=str(places.dubki)
        )
        foreign = await notice(
            owner, visibility="dormitory", dormitory_id=str(places.perm_dormitory)
        )
        university = await notice(
            owner, visibility="university", city_id=str(places.perm)
        )
        traveller.shift(timedelta(seconds=1))
        ordinary = await publish(owner)
        items = (await request(borrower, "GET")).json()["items"]
        assert [i["id"] for i in items] == [university["id"], pin["id"], ordinary["id"]]
        assert foreign["id"] not in [i["id"] for i in items]
        assert (await request(borrower, "GET", f"/{foreign['id']}")).status_code == 404
        assert (
            await request(borrower, "GET", f"/{university['id']}")
        ).status_code == 200
        assert (await reserve(borrower, pin)).status_code == 409
        traveller.shift(timedelta(seconds=10))
        items = (await request(borrower, "GET")).json()["items"]
        assert [i["id"] for i in items] == [ordinary["id"], university["id"], pin["id"]]


@pytest.mark.parametrize("admin", [False, True])
async def test_edit_unpin_and_cancel(
    owner: Account,
    borrower: Account,
    places: Places,
    admin: bool,
) -> None:
    await grant(owner, Role.HEADMAN, dormitory_id=places.dubki)
    pin = await notice(owner, visibility="dormitory", dormitory_id=str(places.dubki))
    for path, data in [
        (f"/{pin['id']}", {"title": "Changed", "description": "Notice", "version": 1}),
        (f"/{pin['id']}/unpin", None),
        (f"/{pin['id']}/cancel", None),
    ]:
        assert (
            await request(borrower, "PATCH" if data else "POST", path, data)
        ).status_code == 403
    if admin:
        await grant(borrower, Role.ADMINISTRATOR)
    actor = borrower if admin else owner
    edited = await request(
        actor,
        "PATCH",
        f"/{pin['id']}",
        {
            "title": "Changed",
            "description": "Notice",
            "version": 1,
        },
    )
    assert edited.status_code == 200, edited.text
    stale = await request(
        actor,
        "PATCH",
        f"/{pin['id']}",
        {
            "title": "Stale",
            "description": "Notice",
            "version": 1,
        },
    )
    assert stale.status_code == 409
    unpinned = await request(actor, "POST", f"/{pin['id']}/unpin")
    assert unpinned.status_code == 200
    assert unpinned.json()["pinned_until"] is None
    assert pin["id"] in [i["id"] for i in (await request(owner, "GET")).json()["items"]]
    assert (await request(actor, "POST", f"/{pin['id']}/cancel")).status_code == 200
    assert (await request(owner, "GET")).json()["items"] == []


async def test_filters_and_snapshot_pages(owner: Account, places: Places) -> None:
    await grant(owner, Role.ADMINISTRATOR)
    with time_machine.travel(clock.now(), tick=False) as traveller:
        pin = await notice(owner)
        expected = [pin["id"]]
        for n in range(4):
            traveller.shift(timedelta(seconds=1))
            item = await publish(owner, title=f"Item {n}")
            expected.insert(1, item["id"])
        category = item["category_id"]
        for suffix in [
            "kind=giveaway",
            f"category_id={category}",
            f"dormitory_id={places.dubki}",
            f"kind=giveaway&category_id={category}&dormitory_id={places.dubki}",
        ]:
            items = (await request(owner, "GET", "?" + suffix)).json()["items"]
            assert len(items) == (5 if suffix.startswith("dormitory") else 4)
        assert (
            await request(owner, "GET", f"?dormitory_id={places.perm_dormitory}")
        ).json()["items"] == []
        first = (await request(owner, "GET", "?size=2")).json()
        cursor = first["next_page"]
        seen = [i["id"] for i in first["items"]]
        traveller.shift(timedelta(minutes=2))
        await publish(owner, title="Inserted during scrolling")
        assert (
            await request(owner, "GET", f"?size=2&kind=giveaway&cursor={cursor}")
        ).status_code == 400
        while cursor:
            response = await request(owner, "GET", f"?size=2&cursor={cursor}")
            assert response.status_code == 200, response.text
            result = response.json()
            seen += [i["id"] for i in result["items"]]
            cursor = result["next_page"]
        assert seen == expected


@pytest.mark.parametrize(
    "overrides",
    [
        {"pinned_until": "2020-01-01T00:00:00Z"},
        {"title": " "},
        {"description": " "},
    ],
)
async def test_invalid_publication(owner: Account, overrides: dict[str, Any]) -> None:
    await grant(owner, Role.ADMINISTRATOR)
    response = await request(owner, "POST", "/publications", content(**overrides))
    assert response.status_code == 422


async def test_publication_mutations_replay(owner: Account) -> None:
    await grant(owner, Role.ADMINISTRATOR)
    payload = content()
    create_key = str(uuid4())
    first = await request(owner, "POST", "/publications", payload, key=create_key)
    replay = await request(owner, "POST", "/publications", payload, key=create_key)
    assert replay.status_code == first.status_code == 201
    assert replay.json() == first.json()
    listing = first.json()
    assert await owner.auth.db.get(Publication, UUID(listing["id"])) is not None
    assert await owner.auth.db.get(Item, UUID(listing["id"])) is None
    for method, suffix, data in [
        (
            "PATCH",
            "",
            {
                "title": "Updated",
                "description": "Notice",
                "version": 1,
                "pinned_until": (clock.now() + timedelta(days=1)).isoformat(),
            },
        ),
        ("POST", "/unpin", None),
        ("POST", "/cancel", None),
    ]:
        key = str(uuid4())
        first = await request(owner, method, f"/{listing['id']}{suffix}", data, key=key)
        replay = await request(
            owner, method, f"/{listing['id']}{suffix}", data, key=key
        )
        assert first.status_code == replay.status_code == 200, first.text
        assert first.json() == replay.json()


async def test_filter_combinations_and_scope(
    owner: Account,
    borrower: Account,
    places: Places,
) -> None:
    categories = (await request(owner, "GET", "/categories")).json()["items"]
    wanted, other = categories[0]["id"], categories[1]["id"]
    city = await publish(owner, category_id=wanted)
    faculty = await publish(owner, category_id=wanted, visibility="faculty")
    await publish(owner, category_id=other)
    await grant(owner, Role.ADMINISTRATOR)
    await notice(owner)
    for area in ("city", "faculty"):
        expected = [faculty["id"], city["id"]] if area == "city" else [faculty["id"]]
        response = await request(
            owner,
            "GET",
            f"?area={area}&kind=giveaway&category_id={wanted}&dormitory_id={places.dubki}",
        )
        assert [i["id"] for i in response.json()["items"]] == expected
    # Filter metadata is a snapshot, independent of subsequent profile moves.
    await owner.auth.db.execute(
        update(User)
        .where(User.id == UUID(owner.tokens["user"]["id"]))
        .values(dormitory_id=None)
    )
    await owner.auth.db.commit()
    response = await request(
        borrower,
        "GET",
        f"?kind=giveaway&category_id={wanted}&dormitory_id={places.dubki}",
    )
    assert {i["id"] for i in response.json()["items"]} == {city["id"], faculty["id"]}
