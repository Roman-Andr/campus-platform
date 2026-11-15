"""Assigning and revoking scoped roles on real PostgreSQL (#210).

The API contract, the account-type rules, the last-administrator invariant
(including two genuinely parallel revocations), the audit journal, the
idempotent replay and the reuse of the domain revocation by the annual
status confirmation (#73). Actions go through the real HTTP API and the
real database; the locks are exercised by concurrent requests.
"""

import asyncio
from dataclasses import dataclass
from typing import Any
from uuid import UUID, uuid4

import httpx2
import pytest
from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker

from campus.core import clock
from campus.core.audit import AuditRecord
from campus.core.web import ProblemError, api_router
from campus.modules.administration import roles as roles_api
from campus.modules.identity import (
    LAST_ADMINISTRATOR,
    Permissions,
    Role,
    RoleAssignment,
    admin_router,
    revoke_role,
    revoke_user_roles,
    role_management,
)
from campus.modules.identity.models import User
from tests import test_profile
from tests.test_identity import Auth
from tests.test_profile import Account, Places, moscow_profile

auth = test_profile.auth
places = test_profile.places

ROLES = "/api/v1/admin/users"
AUDIT = "/api/v1/admin/audit"
PROBE = "/api/v1/admin/moderator-probe"
ASSIGN = "administration.role.assign"
REVOKE = "administration.role.revoke"
FORBIDDEN = "forbidden"


@dataclass
class Staff:
    """Accounts of every matrix column and the roles seeded for them."""

    auth: Auth
    accounts: dict[str, Account]
    ids: dict[str, UUID]
    assignments: dict[str, UUID]

    def account(self, name: str) -> Account:
        return self.accounts[name]

    def id(self, name: str) -> UUID:
        return self.ids[name]

    def assignment(self, name: str) -> UUID:
        return self.assignments[name]


async def sign_in(
    auth: Auth, places: Places, email: str, *, kind: str = "student"
) -> tuple[Account, UUID]:
    """An account with a completed profile and, if given, the future type."""
    account = Account(auth, await auth.login(email=email))
    employee = kind in {"employee", "former_employee"}
    profile = moscow_profile(places, course=None if employee else 2)
    assert (await account.put(profile)).status_code == 200
    user_id = UUID(account.tokens["user"]["id"])
    if kind != "student":
        await auth.db.execute(
            update(User).where(User.id == user_id).values(account_type=kind)
        )
        await auth.db.commit()
    return account, user_id


@pytest.fixture
async def staff(auth: Auth, places: Places) -> Staff:
    accounts: dict[str, Account] = {}
    ids: dict[str, UUID] = {}
    for name, email, kind in [
        ("admin", "admin@university.example", "student"),
        ("second_admin", "second-admin@university.example", "student"),
        ("moderator", "moderator@university.example", "student"),
        ("headman", "headman@university.example", "student"),
        ("student", "student@university.example", "student"),
        ("employee", "teacher@staff.example", "employee"),
        ("alumni", "alumni@university.example", "alumni"),
        ("former_employee", "former@staff.example", "former_employee"),
    ]:
        accounts[name], ids[name] = await sign_in(auth, places, email, kind=kind)
    seeded = {
        "admin": RoleAssignment(user_id=ids["admin"], role=Role.ADMINISTRATOR),
        "second_admin": RoleAssignment(
            user_id=ids["second_admin"], role=Role.ADMINISTRATOR
        ),
        "moderator": RoleAssignment(user_id=ids["moderator"], role=Role.MODERATOR),
        "headman": RoleAssignment(
            user_id=ids["headman"], role=Role.HEADMAN, dormitory_id=places.dubki
        ),
    }
    auth.db.add_all(seeded.values())
    await auth.db.commit()
    return Staff(
        auth,
        accounts,
        ids,
        {name: row.id for name, row in seeded.items()},
    )


@pytest.fixture
def moderator_probe(auth: Auth) -> str:
    """A stand-in for the moderator features of later issues (#91, #92).

    The panel prefix accepts moderators, but no moderator-only panel
    function exists in this slice yet; the probe uses the same prefix and
    the same role check, so it proves the revoked role stops working on
    the next request. ``test_roles.py`` uses the same approach.
    """
    nested = api_router()

    @nested.get("/moderator-probe")
    async def probe(context: Permissions) -> dict[str, str]:
        return {"account_type": context.account_type}

    admin = admin_router()
    admin.include_router(nested)
    auth.app.include_router(admin, prefix="/api/v1")
    return PROBE


def roles_url(user_id: UUID) -> str:
    return f"{ROLES}/{user_id}/roles"


def assignment_url(user_id: UUID, assignment_id: UUID) -> str:
    return f"{roles_url(user_id)}/{assignment_id}"


async def post(
    account: Account,
    target: UUID,
    data: dict[str, Any],
    key: str | None = None,
) -> httpx2.Response:
    return await account.auth.client.post(
        roles_url(target),
        json=data,
        headers={"Idempotency-Key": key or str(uuid4()), **account.headers},
    )


async def delete(
    account: Account,
    target: UUID,
    assignment_id: UUID,
    key: str | None = None,
) -> httpx2.Response:
    return await account.auth.client.delete(
        assignment_url(target, assignment_id),
        headers={"Idempotency-Key": key or str(uuid4()), **account.headers},
    )


async def assignments(db: AsyncSession) -> list[RoleAssignment]:
    db.expire_all()
    rows = list(await db.scalars(select(RoleAssignment).order_by(RoleAssignment.id)))
    db.expunge_all()  # keep loaded values after the rollback
    await db.rollback()
    return rows


async def administrator_count(db: AsyncSession) -> int:
    count = await db.scalar(
        select(func.count())
        .select_from(RoleAssignment)
        .where(RoleAssignment.role == Role.ADMINISTRATOR)
    )
    await db.rollback()
    return count or 0


async def records(db: AsyncSession, action: str | None = None) -> list[AuditRecord]:
    db.expire_all()
    query = select(AuditRecord).order_by(AuditRecord.id)
    if action is not None:
        query = query.where(AuditRecord.action == action)
    rows = list(await db.scalars(query))
    db.expunge_all()
    await db.rollback()
    return rows


def error_codes(response: httpx2.Response) -> dict[str, str]:
    assert response.status_code == 422, response.text
    body = response.json()
    assert body["code"] == "validation_failed"
    return {error["pointer"]: error["code"] for error in body["errors"]}


def scope_payload(role: str, scope: str | None, places: Places) -> dict[str, Any]:
    payload: dict[str, Any] = {"role": role}
    if scope == "dormitory":
        payload["dormitory_id"] = str(places.dubki)
    elif scope == "faculty":
        payload["faculty_id"] = str(places.economics)
    return payload


# The account type x role matrix


async def test_headman_and_global_roles_are_assigned(
    staff: Staff, places: Places
) -> None:
    admin = staff.account("admin")
    student = staff.id("student")
    responses = [
        await post(admin, student, scope_payload("headman", "dormitory", places)),
        await post(admin, student, scope_payload("headman", "faculty", places)),
        await post(admin, student, scope_payload("moderator", None, places)),
    ]
    assert [response.status_code for response in responses] == [201, 201, 201]
    headman = responses[0].json()
    assert headman["role"] == "headman"
    assert headman["dormitory_id"] == str(places.dubki)
    assert headman["faculty_id"] is None
    assert headman["user_id"] == str(student)
    assert headman["id"]
    assert headman["created_at"]

    listed = await admin.auth.client.get(roles_url(student), headers=admin.headers)
    assert listed.status_code == 200, listed.text
    assert [item["role"] for item in listed.json()["items"]] == [
        "headman",
        "headman",
        "moderator",
    ]
    # The client sees the roles on its next request, scopes included.
    me = (await staff.account("student").me()).json()
    assert me["roles"] == [
        {
            "role": "headman",
            "dormitory_id": str(places.dubki),
            "faculty_id": None,
        },
        {
            "role": "headman",
            "dormitory_id": None,
            "faculty_id": str(places.economics),
        },
        {"role": "moderator", "dormitory_id": None, "faculty_id": None},
    ]


@pytest.mark.parametrize(
    ("kind", "role", "scope", "allowed"),
    [
        ("student", "headman", "dormitory", True),
        ("student", "headman", "faculty", True),
        ("student", "moderator", None, True),
        ("student", "administrator", None, True),
        ("employee", "headman", "dormitory", False),
        ("employee", "moderator", None, True),
        ("employee", "administrator", None, True),
        ("alumni", "headman", "dormitory", False),
        ("alumni", "moderator", None, False),
        ("alumni", "administrator", None, False),
        ("former_employee", "headman", "dormitory", False),
        ("former_employee", "moderator", None, False),
        ("former_employee", "administrator", None, False),
    ],
)
async def test_account_type_role_matrix(  # noqa: PLR0913, PLR0917
    staff: Staff,
    places: Places,
    kind: str,
    role: str,
    scope: str | None,
    allowed: bool,
) -> None:
    before = len(await assignments(staff.auth.db))
    response = await post(
        staff.account("admin"), staff.id(kind), scope_payload(role, scope, places)
    )
    if allowed:
        assert response.status_code == 201, response.text
        assert len(await assignments(staff.auth.db)) == before + 1
    else:
        assert error_codes(response) == {"#/role": "not_allowed"}
        assert len(await assignments(staff.auth.db)) == before
    # The account itself is unchanged: the refusal touched no role row.
    account_type = await staff.auth.db.scalar(
        select(User.account_type).where(User.id == staff.id(kind))
    )
    await staff.auth.db.rollback()
    assert account_type == kind


@pytest.mark.parametrize(
    ("payload", "expected"),
    [
        ({"role": "headman"}, {"#/dormitory_id": "missing"}),
        (
            {"role": "headman", "dormitory_id": "dubki", "faculty_id": "economics"},
            {"#/faculty_id": "not_allowed"},
        ),
        (
            {"role": "headman", "dormitory_id": "unknown"},
            {"#/dormitory_id": "not_found"},
        ),
        (
            {"role": "headman", "faculty_id": "unknown"},
            {"#/faculty_id": "not_found"},
        ),
        (
            {"role": "moderator", "dormitory_id": "dubki"},
            {"#/dormitory_id": "not_allowed"},
        ),
        (
            {"role": "administrator", "faculty_id": "economics"},
            {"#/faculty_id": "not_allowed"},
        ),
        (
            {"role": "moderator", "dormitory_id": "dubki", "faculty_id": "economics"},
            {"#/dormitory_id": "not_allowed", "#/faculty_id": "not_allowed"},
        ),
    ],
)
async def test_scope_rules(
    staff: Staff,
    places: Places,
    payload: dict[str, str],
    expected: dict[str, str],
) -> None:
    known = {
        "dubki": str(places.dubki),
        "economics": str(places.economics),
        "unknown": str(uuid4()),
    }
    body = {
        **payload,
        **{key: known[value] for key, value in payload.items() if value in known},
    }
    response = await post(staff.account("admin"), staff.id("student"), body)
    assert error_codes(response) == expected
    assert len(await assignments(staff.auth.db)) == 4


async def test_unknown_role_is_a_problem(staff: Staff) -> None:
    response = await post(
        staff.account("admin"), staff.id("student"), {"role": "superuser"}
    )
    assert response.status_code == 422
    assert response.headers["content-type"] == "application/problem+json"
    assert response.json()["code"] == "validation_failed"


async def test_unknown_user_is_not_found(staff: Staff, places: Places) -> None:
    admin = staff.account("admin")
    missing = uuid4()
    listed = await admin.auth.client.get(roles_url(missing), headers=admin.headers)
    assert listed.status_code == 404
    assert listed.headers["content-type"] == "application/problem+json"
    assert listed.json()["code"] == "not_found"
    created = await post(admin, missing, scope_payload("moderator", None, places))
    assert created.status_code == 404
    assert created.json()["code"] == "not_found"


# Only an administrator manages roles


@pytest.mark.parametrize(
    "name", ["student", "employee", "alumni", "headman", "moderator"]
)
async def test_only_an_administrator_manages_roles(
    staff: Staff, places: Places, name: str
) -> None:
    account = staff.account(name)
    target = staff.id("student")
    calls = [
        await account.auth.client.get(roles_url(target), headers=account.headers),
        await post(account, target, scope_payload("moderator", None, places)),
        await delete(account, staff.id("moderator"), staff.assignment("moderator")),
    ]
    for response in calls:
        assert response.status_code == 403, response.text
        assert response.headers["content-type"] == "application/problem+json"
        assert response.json()["code"] == FORBIDDEN
    # The refusals changed nothing.
    assert len(await assignments(staff.auth.db)) == 4


async def test_administrator_is_not_a_moderator_shortcut(staff: Staff) -> None:
    target = staff.id("student")
    moderator = staff.account("moderator")
    denied = await moderator.auth.client.get(
        roles_url(target), headers=moderator.headers
    )
    assert denied.status_code == 403
    admin = staff.account("admin")
    allowed = await admin.auth.client.get(roles_url(target), headers=admin.headers)
    assert allowed.status_code == 200


# The last administrator


async def test_last_administrator_cannot_be_revoked(staff: Staff) -> None:
    admin = staff.account("admin")
    removed = await delete(
        admin, staff.id("second_admin"), staff.assignment("second_admin")
    )
    assert removed.status_code == 204, removed.text
    assert await administrator_count(staff.auth.db) == 1

    # The administrator cannot revoke themselves either: it would leave the
    # service without an administrator.
    denied = await delete(admin, staff.id("admin"), staff.assignment("admin"))
    assert denied.status_code == 409
    assert denied.headers["content-type"] == "application/problem+json"
    assert denied.json()["code"] == "last_administrator"
    assert await administrator_count(staff.auth.db) == 1
    assert len(await records(staff.auth.db, REVOKE)) == 1


async def test_parallel_revocations_keep_one_administrator(
    staff: Staff, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Of two parallel revocations of the last two administrators one wins."""
    barrier = asyncio.Barrier(2)
    revoke = revoke_role

    async def gated(*args: Any, **kwargs: Any) -> Any:
        # Both requests have passed the role check; let them enter the
        # domain together so the row locks, not the event loop, decide.
        async with asyncio.timeout(10):
            await barrier.wait()
        return await revoke(*args, **kwargs)

    monkeypatch.setattr(roles_api, "revoke_role", gated)
    responses = await asyncio.wait_for(
        asyncio.gather(
            delete(
                staff.account("admin"), staff.id("admin"), staff.assignment("admin")
            ),
            delete(
                staff.account("second_admin"),
                staff.id("second_admin"),
                staff.assignment("second_admin"),
            ),
        ),
        timeout=20,
    )
    assert sorted(response.status_code for response in responses) == [204, 409], [
        response.text for response in responses
    ]
    rejected = next(r for r in responses if r.status_code == 409)
    assert rejected.json()["code"] == "last_administrator"
    assert await administrator_count(staff.auth.db) == 1
    assert len(await records(staff.auth.db, REVOKE)) == 1


async def test_annual_confirmation_keeps_the_last_administrator(
    staff: Staff, engine: AsyncEngine
) -> None:
    """#73 postpones the transition instead of leaving no administrator."""
    admin = staff.id("admin")
    assert (
        await delete(
            staff.account("admin"),
            staff.id("second_admin"),
            staff.assignment("second_admin"),
        )
    ).status_code == 204
    sessions = async_sessionmaker(engine)

    async def revoke_all() -> None:
        async with sessions() as session:
            await revoke_user_roles(session, user_id=admin)
            await session.commit()

    with pytest.raises(ProblemError) as error:
        await revoke_all()
    assert error.value.problem_type == LAST_ADMINISTRATOR
    assert await administrator_count(staff.auth.db) == 1
    [revoked] = await records(staff.auth.db, REVOKE)
    assert revoked.actor_id == staff.id("admin")
    assert revoked.object_id == staff.id("second_admin")


async def test_annual_confirmation_revokes_every_role(
    staff: Staff, places: Places, engine: AsyncEngine
) -> None:
    student = staff.id("student")
    moderator = await post(staff.account("admin"), student, {"role": "moderator"})
    assert moderator.status_code == 201
    headman = await post(
        staff.account("admin"),
        student,
        {"role": "headman", "dormitory_id": str(places.dubki)},
    )
    assert headman.status_code == 201
    sessions = async_sessionmaker(engine)
    async with sessions() as session:
        revoked = await revoke_user_roles(
            session, user_id=student, reason="Annual status confirmation"
        )
        await session.commit()
    assert {row.role for row in revoked} == {Role.MODERATOR, Role.HEADMAN}
    remaining = [
        row for row in await assignments(staff.auth.db) if row.user_id == student
    ]
    assert remaining == []
    revoked_records = await records(staff.auth.db, REVOKE)
    assert len(revoked_records) == 2
    for record in revoked_records:
        assert record.actor_id is None
        assert record.reason == "Annual status confirmation"
        assert record.object_id == student
        assert record.before is not None
    # Nothing is revoked twice.
    async with sessions() as session:
        assert await revoke_user_roles(session, user_id=student) == ()
        await session.commit()
    assert len(await records(staff.auth.db, REVOKE)) == 2


# The journal


async def test_assignment_and_revocation_are_audited(
    staff: Staff, places: Places
) -> None:
    admin = staff.account("admin")
    student = staff.id("student")
    started = clock.now()
    created = await post(
        admin,
        student,
        {"role": "headman", "dormitory_id": str(places.dubki)},
    )
    finished = clock.now()
    assert created.status_code == 201, created.text
    [assigned] = await records(staff.auth.db, ASSIGN)
    assert assigned.actor_id == staff.id("admin")
    assert (assigned.object_type, assigned.object_id) == ("user", student)
    assert assigned.participant_ids == [student]
    assert assigned.own_case is False
    assert assigned.before is None
    assert assigned.after == {
        "role": "headman",
        "dormitory_id": str(places.dubki),
        "faculty_id": None,
    }
    assert started <= assigned.occurred_at <= finished
    assert assigned.request_id == created.headers["X-Request-ID"]

    revoked_at = clock.now()
    removed = await delete(admin, student, created.json()["id"])
    assert removed.status_code == 204
    [revoked] = await records(staff.auth.db, REVOKE)
    assert revoked.actor_id == staff.id("admin")
    assert revoked.object_id == student
    assert revoked.before == assigned.after
    assert revoked.after is None
    assert revoked_at <= revoked.occurred_at <= clock.now()

    journal = await admin.auth.client.get(
        AUDIT, params={"action": ASSIGN}, headers=admin.headers
    )
    assert journal.status_code == 200, journal.text
    [item] = journal.json()["items"]
    assert item["action"] == ASSIGN
    assert item["object_id"] == str(student)


async def test_audit_failure_rolls_back_the_assignment(
    staff: Staff, places: Places, monkeypatch: pytest.MonkeyPatch
) -> None:
    async def unavailable(*_args: Any, **_kwargs: Any) -> None:
        msg = "the journal is unavailable"
        raise RuntimeError(msg)

    monkeypatch.setattr(role_management, "record_action", unavailable)
    response = await post(
        staff.account("admin"),
        staff.id("student"),
        {"role": "headman", "dormitory_id": str(places.dubki)},
    )
    assert response.status_code == 500
    assert response.json()["code"] == "internal_error"
    assert len(await assignments(staff.auth.db)) == 4
    assert await records(staff.auth.db) == []


# Idempotency and duplicates


async def test_idempotent_assignment_and_revocation(staff: Staff) -> None:
    admin = staff.account("admin")
    student = staff.id("student")
    key = str(uuid4())
    first = await post(admin, student, {"role": "moderator"}, key)
    second = await post(admin, student, {"role": "moderator"}, key)
    assert first.status_code == second.status_code == 201, second.text
    assert first.json()["id"] == second.json()["id"]
    assert second.headers["Idempotent-Replayed"] == "true"
    assert [row.user_id for row in await assignments(staff.auth.db)].count(student) == 1
    assert len(await records(staff.auth.db, ASSIGN)) == 1

    reused = await post(admin, student, {"role": "administrator"}, key)
    assert reused.status_code == 422
    assert reused.json()["code"] == "idempotency_key_reused"

    assignment_id = UUID(first.json()["id"])
    delete_key = str(uuid4())
    removed = await delete(admin, student, assignment_id, delete_key)
    replayed = await delete(admin, student, assignment_id, delete_key)
    assert removed.status_code == replayed.status_code == 204
    assert replayed.headers["Idempotent-Replayed"] == "true"
    assert len(await records(staff.auth.db, REVOKE)) == 1


async def test_duplicate_assignment_with_another_key_conflicts(staff: Staff) -> None:
    admin = staff.account("admin")
    student = staff.id("student")
    assert (await post(admin, student, {"role": "moderator"})).status_code == 201
    duplicate = await post(admin, student, {"role": "moderator"})
    assert duplicate.status_code == 409
    assert duplicate.headers["content-type"] == "application/problem+json"
    assert duplicate.json()["code"] == "role_already_assigned"
    assert [row.user_id for row in await assignments(staff.auth.db)].count(student) == 1
    assert len(await records(staff.auth.db, ASSIGN)) == 1


async def test_parallel_duplicate_assignments(staff: Staff) -> None:
    admin = staff.account("admin")
    student = staff.id("student")
    responses = await asyncio.wait_for(
        asyncio.gather(
            *(post(admin, student, {"role": "moderator"}) for _ in range(4))
        ),
        timeout=20,
    )
    assert sorted(response.status_code for response in responses) == [
        201,
        409,
        409,
        409,
    ]
    assert [row.user_id for row in await assignments(staff.auth.db)].count(student) == 1
    assert len(await records(staff.auth.db, ASSIGN)) == 1


# A role change is serialized with an account type change


async def concurrent_type_change(
    engine: AsyncEngine,
    user_id: UUID,
    account_type: str,
    request: Any,
) -> httpx2.Response:
    """Change the type under the user row lock while ``request`` waits.

    The request reads the account type before the lock as part of its role
    check; after the lock it must read the type again, or a headman could
    be assigned to an account that has just become an employee or a
    graduate.
    """
    sessions = async_sessionmaker(engine)
    async with sessions() as blocker:
        await blocker.execute(
            select(User.id).where(User.id == user_id).with_for_update()
        )
        await blocker.execute(
            update(User).where(User.id == user_id).values(account_type=account_type)
        )
        await blocker.flush()
        task = asyncio.create_task(request)
        await asyncio.sleep(0.2)
        await blocker.commit()
    return await asyncio.wait_for(task, timeout=20)


async def test_assignment_reads_the_type_after_the_lock(
    staff: Staff, engine: AsyncEngine
) -> None:
    # The actor's own row is already in the request's identity map; the
    # fresh read under the lock must still win.
    response = await concurrent_type_change(
        engine,
        staff.id("admin"),
        "alumni",
        post(staff.account("admin"), staff.id("admin"), {"role": "administrator"}),
    )
    assert error_codes(response) == {"#/role": "not_allowed"}
    assert len(await assignments(staff.auth.db)) == 4


async def test_headman_assignment_loses_to_a_concurrent_type_change(
    staff: Staff, places: Places, engine: AsyncEngine
) -> None:
    response = await concurrent_type_change(
        engine,
        staff.id("student"),
        "employee",
        post(
            staff.account("admin"),
            staff.id("student"),
            {"role": "headman", "dormitory_id": str(places.dubki)},
        ),
    )
    assert error_codes(response) == {"#/role": "not_allowed"}
    assert len(await assignments(staff.auth.db)) == 4


# A revoked role stops working immediately


async def test_revoked_role_is_forbidden_on_the_next_request(
    staff: Staff, moderator_probe: str
) -> None:
    admin = staff.account("admin")
    student = staff.account("student")
    target = staff.id("student")

    administrator = await post(admin, target, {"role": "administrator"})
    assert administrator.status_code == 201
    assert (
        await student.auth.client.get(AUDIT, headers=student.headers)
    ).status_code == 200
    assert (
        await delete(admin, target, UUID(administrator.json()["id"]))
    ).status_code == 204
    denied = await student.auth.client.get(AUDIT, headers=student.headers)
    assert denied.status_code == 403
    assert denied.json()["code"] == FORBIDDEN

    moderator = await post(admin, target, {"role": "moderator"})
    assert moderator.status_code == 201
    assert (
        await student.auth.client.get(moderator_probe, headers=student.headers)
    ).status_code == 200
    assert (
        await delete(admin, target, UUID(moderator.json()["id"]))
    ).status_code == 204
    denied = await student.auth.client.get(moderator_probe, headers=student.headers)
    assert denied.status_code == 403
    assert denied.json()["code"] == FORBIDDEN


async def test_foreign_assignment_is_not_found(staff: Staff) -> None:
    admin = staff.account("admin")
    foreign = await delete(admin, staff.id("student"), staff.assignment("moderator"))
    assert foreign.status_code == 404
    assert foreign.json()["code"] == "role_assignment_not_found"
    missing = await delete(admin, staff.id("student"), uuid4())
    assert missing.status_code == 404
    assert missing.json()["code"] == "role_assignment_not_found"
    assert len(await assignments(staff.auth.db)) == 4
