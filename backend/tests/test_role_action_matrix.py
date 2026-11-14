"""Each specification cell is an HTTP probe or an explicit feature skip."""

from uuid import UUID

import httpx2
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select, update

from campus.modules.identity import Role, RoleAssignment, User
from tests.role_action_matrix import (
    ALIASES,
    COLUMNS,
    KNOWN_FAILURES,
    LIVE,
    MATRIX,
    PENDING,
    USER_ACTIONS,
    Case,
    Grant,
    cases,
)
from tests.test_identity import Auth
from tests.test_listings import move, owner, publish, request, reserve
from tests.test_profile import Account, Places, auth, moscow_profile, places

__all__ = ["auth", "owner", "places"]


def test_matrix_is_complete() -> None:
    # Independent inventory: dropping a row/column must fail, not silently
    # reduce the generated test suite. Expectations live only in test data.
    assert set(MATRIX) == {
        "publish_respond",
        "finish_review",
        "complain_dispute_appeal",
        "student_feed",
        "message",
        "create_club",
        "forum_comment_react",
        "vote",
        "book",
        "ai",
        "follow_personal_page",
        "pin",
        "hide",
        "manage_resources",
        "moderate",
        "review_appeal",
        "administrate",
        "audit_dashboard_export",
    }
    assert COLUMNS == (
        "student",
        "employee",
        "alumni",
        "headman",
        "moderator",
        "administrator",
    )
    assert len(MATRIX) == 18
    assert all(len(row) == 6 for row in MATRIX.values())
    assert all(isinstance(grant, Grant) for row in MATRIX.values() for grant in row)
    assert set(LIVE) | set(PENDING) == set(MATRIX)
    inventory = cases()
    for action in MATRIX:
        for column in COLUMNS:
            cell = [c for c in inventory if c.action == action and c.actor == column]
            assert cell
            assert all(c.probe in LIVE.get(action, ()) or c.issue for c in cell)
    assert len({c.id for c in inventory}) == len(inventory)
    assert set(KNOWN_FAILURES) <= {c.id for c in inventory}
    assert all(c.issue is None or c.issue > 0 for c in inventory)
    for action in USER_ACTIONS:
        for actor, column in ALIASES.items():
            assert any(
                c.action == action and c.actor == actor and c.column == column
                for c in inventory
            )


@pytest.mark.parametrize(
    ("probe", "resources"),
    [
        (
            "reference_data",
            {
                "cities",
                "dormitories",
                "faculties",
                "categories",
                "skills",
                "skill-tags",
                "reference-data",
            },
        ),
        ("domains", {"domains", "email-domains"}),
    ],
)
def test_pending_reference_admin_api_is_absent(
    client: TestClient, probe: str, resources: set[str]
) -> None:
    if PENDING.get("administrate", {}).get(probe) != 99:
        return
    response = client.get("/api/v1/openapi.json")
    assert response.status_code == 200
    # Public lookup GETs do not implement reference-data administration,
    # nor do the user's own lists (e.g. /me/skills). Once an administrative
    # read or any write exists, activate API probes.
    implemented = {
        f"{method.upper()} {path}"
        for path, operations in response.json()["paths"].items()
        if resources.intersection(path.split("/"))
        and not path.startswith("/api/v1/me/")
        for method in operations
        if method in {"post", "put", "patch", "delete"}
        or (path.startswith("/api/v1/admin/") and method == "get")
    }
    assert not implemented, (
        f"Replace the #99 {probe} skips with API assertions: {sorted(implemented)}"
    )


@pytest.fixture
async def actor(case: Case, auth: Auth, places: Places) -> Account:
    staff = case.actor in {
        "employee",
        "employee_moderator",
        "employee_administrator",
        "former_employee",
    }
    email = "matrix@staff.example" if staff else "matrix@university.example"
    account = Account(auth, await auth.login(email=email))
    assert (
        await account.put(moscow_profile(places, course=None if staff else 2))
    ).status_code == 200
    user_id = UUID(account.tokens["user"]["id"])
    if case.actor in {"alumni", "former_employee"}:
        # Simulate the future #73 transition after a complete profile.
        # Preserve the employee profile without a student course.
        await auth.db.execute(
            update(User)
            .where(User.id == user_id)
            .values(account_type="former_employee" if staff else "alumni")
        )
    role = {
        "headman": Role.HEADMAN,
        "moderator": Role.MODERATOR,
        "administrator": Role.ADMINISTRATOR,
        "employee_moderator": Role.MODERATOR,
        "employee_administrator": Role.ADMINISTRATOR,
    }.get(case.actor)
    if role:
        auth.db.add(
            RoleAssignment(
                user_id=user_id,
                role=role,
                dormitory_id=places.dubki if role == Role.HEADMAN else None,
            )
        )
    await auth.db.commit()
    return account


def assert_status(response: httpx2.Response, expected: int) -> None:
    assert response.status_code == expected, response.text
    if expected in {403, 404}:
        assert response.headers["content-type"] == "application/problem+json"


async def publish_respond(case: Case, actor: Account, owner: Account) -> None:
    audience = "students" if case.probe.endswith("students") else "community"
    allowed = case.grant != Grant.NO and not (
        case.grant == Grant.COMMUNITY
        and (audience == "students" or case.probe == "publish_dormitory")
    )
    if case.probe.startswith("publish"):
        category = (await request(actor, "GET", "/categories")).json()["items"][0]["id"]
        response = await request(
            actor,
            "POST",
            "/giveaways",
            {
                "title": "Matrix desk",
                "description": "Collect on campus",
                "category_id": category,
                "audience": audience,
                "visibility": "dormitory"
                if case.probe == "publish_dormitory"
                else "city",
            },
        )
    else:
        listing = await publish(owner, audience=audience)
        response = await reserve(actor, listing)
    assert_status(response, 201 if allowed else 403)


async def student_feed(case: Case, actor: Account, owner: Account) -> None:
    dormitory = "dormitory" in case.probe
    listing = await publish(
        owner,
        audience="community" if case.probe.endswith("community") else "students",
        visibility="dormitory" if dormitory else "city",
    )
    assert listing["audience"] == (
        "community" if case.probe.endswith("community") else "students"
    )
    assert listing["visibility"] == ("dormitory" if dormitory else "city")
    allowed = case.grant in {Grant.YES, Grant.COMPLAINT}
    if case.probe.startswith("feed"):
        control = await publish(owner, audience="community")
        response = await request(actor, "GET", "?area=dormitory" if dormitory else "")
        assert_status(response, 200)
        ids = {item["id"] for item in response.json()["items"]}
        assert (listing["id"] in ids) == allowed
        if not dormitory:
            assert control["id"] in ids
    else:
        response = await request(actor, "GET", f"/{listing['id']}")
        # Hidden resources use 404, and feeds omit them instead of 403.
        assert_status(response, 200 if allowed else 404)


async def continue_interaction(case: Case, actor: Account, owner: Account) -> None:
    # Start while eligible, then restore the matrix type using the same token.
    db = actor.auth.db
    user_id = UUID(actor.tokens["user"]["id"])
    account_type = await db.scalar(select(User.account_type).where(User.id == user_id))
    course = await db.scalar(select(User.course).where(User.id == user_id))
    await db.execute(
        update(User).where(User.id == user_id).values(account_type="student", course=2)
    )
    await db.commit()
    listing = await publish(owner, audience="community")
    response = await reserve(actor, listing)
    assert_status(response, 201)
    interaction = response.json()
    assert_status(await move(owner, listing, interaction, "accepted"), 200)
    await db.execute(
        update(User)
        .where(User.id == user_id)
        .values(account_type=account_type, course=course)
    )
    await db.commit()
    assert case.grant == Grant.YES
    response = await move(actor, listing, interaction, "cancelled")
    assert_status(response, 200)
    assert response.json()["status"] == "cancelled"


@pytest.mark.parametrize(
    "case",
    [
        pytest.param(
            case,
            id=case.id,
            marks=pytest.mark.skip(
                reason=f"Not implemented: #{case.issue} ({case.probe})"
            )
            if case.issue
            else pytest.mark.xfail(
                strict=True,
                raises=AssertionError,
                reason=f"Permission regression: #{KNOWN_FAILURES[case.id]}",
            )
            if case.id in KNOWN_FAILURES
            else (),
        )
        for case in cases()
    ],
)
async def test_role_action(case: Case, actor: Account, owner: Account) -> None:
    probes = {
        "publish_respond": publish_respond,
        "student_feed": student_feed,
        "finish_review": continue_interaction,
    }
    await probes[case.action](case, actor, owner)
