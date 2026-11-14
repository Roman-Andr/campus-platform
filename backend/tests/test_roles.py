"""Authorization matrix and assignment invariants on real PostgreSQL."""

import asyncio
from typing import Annotated, Any
from uuid import UUID, uuid4

import pytest
from fastapi import Depends
from sqlalchemy import delete, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncEngine, async_sessionmaker

from campus.core.web import api_router
from campus.modules.identity import (
    Permissions,
    Role,
    RoleAssignment,
    User,
    admin_router,
)
from tests import test_profile
from tests.test_identity import Auth
from tests.test_profile import Account, Places

auth = test_profile.auth
places = test_profile.places
student = test_profile.student


@pytest.fixture
async def routes(auth: Auth, student: Account) -> UUID:
    user_id = UUID((await student.me()).json()["id"])
    admin = admin_router()
    nested = api_router()

    @nested.post("/test")
    async def panel(context: Permissions) -> dict[str, str]:
        return {"account_type": context.account_type}

    admin.include_router(nested)
    router = api_router()

    async def check_scope(kind: str, place_id: UUID, context: Permissions) -> None:
        if kind == "dormitory":
            context.require_scope(dormitory_id=place_id)
        else:
            context.require_scope(faculty_id=place_id)

    @router.post("/scope/{kind}/{place_id}")
    async def scoped(_allowed: Annotated[None, Depends(check_scope)]) -> None:
        pass

    # The object was loaded on the server. Client-supplied IDs must never
    # stand in for an object's actual author, owner or membership list.
    object_ids = {"author": user_id, "owner": user_id, "participant": user_id}
    auth.app.state.test_object_ids = object_ids

    async def check_object(action: str, context: Permissions) -> None:
        if action == "author":
            context.require_author(object_ids[action])
        elif action == "owner":
            context.require_owner(object_ids[action])
        else:
            context.require_participant([object_ids[action]])

    @router.post("/object/{action}")
    async def object_action(_allowed: Annotated[None, Depends(check_object)]) -> None:
        pass

    auth.app.include_router(admin, prefix="/api/v1")
    auth.app.include_router(router, prefix="/api/v1")
    return user_id


async def action(student: Account, path: str) -> Any:
    return await student.auth.client.post(
        "/api/v1" + path,
        headers={**student.headers, "Idempotency-Key": str(uuid4())},
    )


def denied(response: Any) -> None:
    assert response.status_code == 403, response.text
    assert response.headers["content-type"] == "application/problem+json"
    assert response.json()["code"] == "forbidden"


@pytest.mark.parametrize(
    ("account_type", "role", "allowed"),
    [
        ("student", None, False),
        ("employee", None, False),
        ("alumni", None, False),
        ("student", Role.HEADMAN, False),
        ("student", Role.MODERATOR, True),
        ("student", Role.ADMINISTRATOR, True),
    ],
)
async def test_admin_matrix(  # noqa: PLR0913, PLR0917 - matrix axes and fixtures
    auth: Auth,
    places: Places,
    student: Account,
    routes: UUID,
    account_type: str,
    role: Role | None,
    allowed: bool,
) -> None:
    await auth.db.execute(
        update(User).where(User.id == routes).values(account_type=account_type)
    )
    if role:
        auth.db.add(
            RoleAssignment(
                user_id=routes,
                role=role,
                dormitory_id=places.dubki if role == Role.HEADMAN else None,
            )
        )
    await auth.db.commit()
    response = await action(student, "/admin/test")
    if allowed:
        assert response.status_code == 200, response.text
        assert response.json()["account_type"] == account_type
    else:
        denied(response)


@pytest.mark.parametrize("role", [None, *Role])
@pytest.mark.parametrize("target", ["own_dormitory", "other_dormitory", "faculty"])
async def test_scope_matrix(  # noqa: PLR0913, PLR0917 - matrix axes and fixtures
    auth: Auth,
    places: Places,
    student: Account,
    routes: UUID,
    role: Role | None,
    target: str,
) -> None:
    if role:
        auth.db.add(
            RoleAssignment(
                user_id=routes,
                role=role,
                dormitory_id=places.dubki if role == Role.HEADMAN else None,
            )
        )
        await auth.db.commit()
    kind, place = {
        "own_dormitory": ("dormitory", places.dubki),
        "other_dormitory": ("dormitory", places.perm_dormitory),
        "faculty": ("faculty", places.economics),
    }[target]
    response = await action(student, f"/scope/{kind}/{place}")
    if role == Role.HEADMAN and target == "own_dormitory":
        assert response.status_code == 200, response.text
    else:
        denied(response)


async def test_faculty_scope_and_me(
    auth: Auth,
    places: Places,
    student: Account,
    routes: UUID,
) -> None:
    auth.db.add(
        RoleAssignment(user_id=routes, role=Role.HEADMAN, faculty_id=places.economics)
    )
    await auth.db.commit()
    assert (
        await action(student, f"/scope/faculty/{places.economics}")
    ).status_code == 200
    denied(await action(student, f"/scope/faculty/{places.perm_faculty}"))
    denied(await action(student, f"/scope/dormitory/{places.dubki}"))
    assert (await student.me()).json()["roles"] == [
        {
            "role": "headman",
            "dormitory_id": None,
            "faculty_id": str(places.economics),
        }
    ]


@pytest.mark.parametrize("role", [None, *Role])
@pytest.mark.parametrize("relation", ["author", "owner", "participant"])
@pytest.mark.parametrize("belongs", [False, True])
async def test_object_matrix(  # noqa: PLR0913, PLR0917 - matrix axes and fixtures
    auth: Auth,
    places: Places,
    student: Account,
    routes: UUID,
    role: Role | None,
    relation: str,
    belongs: bool,
) -> None:
    if role:
        auth.db.add(
            RoleAssignment(
                user_id=routes,
                role=role,
                dormitory_id=places.dubki if role == Role.HEADMAN else None,
            )
        )
        await auth.db.commit()
    auth.app.state.test_object_ids[relation] = routes if belongs else uuid4()
    response = await action(student, f"/object/{relation}")
    if belongs:
        assert response.status_code == 200, response.text
    else:
        denied(response)


async def test_role_removal_takes_effect_with_same_token(
    auth: Auth,
    student: Account,
    routes: UUID,
) -> None:
    auth.db.add(RoleAssignment(user_id=routes, role=Role.MODERATOR))
    await auth.db.commit()
    assert (await action(student, "/admin/test")).status_code == 200
    await auth.db.execute(
        delete(RoleAssignment).where(RoleAssignment.user_id == routes)
    )
    await auth.db.commit()
    denied(await action(student, "/admin/test"))
    assert (await student.me()).json()["roles"] == []


@pytest.mark.parametrize(
    ("role", "dormitory", "faculty"),
    [
        (Role.HEADMAN, False, False),
        (Role.HEADMAN, True, True),
        (Role.MODERATOR, True, False),
        (Role.MODERATOR, False, True),
        (Role.MODERATOR, True, True),
        (Role.ADMINISTRATOR, True, False),
        (Role.ADMINISTRATOR, False, True),
        (Role.ADMINISTRATOR, True, True),
        ("unknown", False, False),
    ],
)
async def test_invalid_assignment_rejected(  # noqa: PLR0913, PLR0917 - matrix axes and fixtures
    auth: Auth,
    places: Places,
    student: Account,
    role: str,
    dormitory: bool,
    faculty: bool,
) -> None:
    user_id = UUID((await student.me()).json()["id"])
    auth.db.add(
        RoleAssignment(
            user_id=user_id,
            role=role,
            dormitory_id=places.dubki if dormitory else None,
            faculty_id=places.economics if faculty else None,
        )
    )
    with pytest.raises(IntegrityError):
        await auth.db.commit()
    await auth.db.rollback()


@pytest.mark.parametrize(
    "scope", ["dormitory", "faculty", "moderator", "administrator"]
)
async def test_duplicate_assignment_rejected(
    auth: Auth,
    places: Places,
    student: Account,
    scope: str,
) -> None:
    user_id = UUID((await student.me()).json()["id"])
    values = {
        "user_id": user_id,
        "role": Role.HEADMAN if scope in {"dormitory", "faculty"} else scope,
        "dormitory_id": places.dubki if scope == "dormitory" else None,
        "faculty_id": places.economics if scope == "faculty" else None,
    }
    auth.db.add(RoleAssignment(**values))
    await auth.db.commit()
    auth.db.add(RoleAssignment(**values))
    with pytest.raises(IntegrityError):
        await auth.db.commit()
    await auth.db.rollback()
    assert len(list(await auth.db.scalars(select(RoleAssignment)))) == 1


async def test_replay_rechecks_roles(
    auth: Auth, student: Account, routes: UUID
) -> None:
    auth.db.add(RoleAssignment(user_id=routes, role=Role.MODERATOR))
    await auth.db.commit()
    headers = {**student.headers, "Idempotency-Key": str(uuid4())}
    first = await auth.client.post("/api/v1/admin/test", headers=headers)
    assert first.status_code == 200
    replay = await auth.client.post("/api/v1/admin/test", headers=headers)
    assert replay.status_code == 200
    assert replay.headers["Idempotent-Replayed"] == "true"
    await auth.db.execute(
        delete(RoleAssignment).where(RoleAssignment.user_id == routes)
    )
    await auth.db.commit()
    denied(await auth.client.post("/api/v1/admin/test", headers=headers))


@pytest.mark.usefixtures("routes")
async def test_replay_rechecks_object_permissions(
    auth: Auth,
    student: Account,
) -> None:
    headers = {**student.headers, "Idempotency-Key": str(uuid4())}
    first = await auth.client.post("/api/v1/object/owner", headers=headers)
    assert first.status_code == 200
    auth.app.state.test_object_ids["owner"] = uuid4()
    denied(await auth.client.post("/api/v1/object/owner", headers=headers))


@pytest.mark.parametrize("role", list(Role))
async def test_concurrent_duplicate_assignments(
    engine: AsyncEngine,
    student: Account,
    places: Places,
    role: Role,
) -> None:
    user_id = UUID((await student.me()).json()["id"])

    async def assign() -> bool:
        async with async_sessionmaker(engine)() as session:
            session.add(
                RoleAssignment(
                    user_id=user_id,
                    role=role,
                    dormitory_id=places.dubki if role == Role.HEADMAN else None,
                )
            )
            try:
                await session.commit()
            except IntegrityError:
                return False
            return True

    assert sorted(await asyncio.gather(assign(), assign())) == [False, True]
