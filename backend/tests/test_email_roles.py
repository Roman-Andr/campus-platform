"""Corporate type transitions revoke headman scopes atomically on PostgreSQL."""

from typing import Literal
from uuid import UUID

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from campus.core.outbox import OutboxMessage
from campus.modules.identity import Role, RoleAssignment, emails
from tests.test_identity import Auth
from tests.test_profile import Account, Places, moscow_profile
from tests.test_roles import action, auth, denied, places, routes, student
from tests.test_secondary_emails import add, call

__all__ = ["auth", "places", "routes", "student"]


async def grant_roles(auth: Auth, user_id: UUID, places: Places) -> set[UUID]:
    assignments = [
        RoleAssignment(user_id=user_id, role=Role.HEADMAN, dormitory_id=places.dubki),
        RoleAssignment(
            user_id=user_id, role=Role.HEADMAN, dormitory_id=places.perm_dormitory
        ),
        RoleAssignment(user_id=user_id, role=Role.HEADMAN, faculty_id=places.economics),
        RoleAssignment(user_id=user_id, role=Role.MODERATOR),
        RoleAssignment(user_id=user_id, role=Role.ADMINISTRATOR),
    ]
    auth.db.add_all(assignments)
    await auth.db.commit()
    return {row.id for row in assignments}


@pytest.mark.parametrize("rollback", [False, True])
async def test_corporate_deletion_revokes_headman_atomically(  # noqa: PLR0913, PLR0917
    auth: Auth,
    student: Account,
    places: Places,
    routes: UUID,
    monkeypatch: pytest.MonkeyPatch,
    rollback: bool,
) -> None:
    assert (await add(auth, student.tokens, "teacher@staff.example")).status_code == 201
    assert (await student.put(moscow_profile(places))).status_code == 200
    original_roles = await grant_roles(auth, routes, places)
    addresses = (await call(auth, student.tokens, "GET")).json()
    student_address = next(
        a for a in addresses if a["email"].endswith("@university.example")
    )
    scope = f"/scope/dormitory/{places.dubki}"
    assert (await action(student, scope)).status_code == 200
    notices = set(await auth.db.scalars(select(OutboxMessage.id)))
    await auth.db.rollback()

    roles_before_failure: set[str] | None = None
    if rollback:
        original_notify = emails.notify_account_security

        async def fail_after_notice(
            session: AsyncSession, user_id: UUID, *, locale: Literal["ru", "en"]
        ) -> None:
            nonlocal roles_before_failure
            await original_notify(session, user_id, locale=locale)
            roles_before_failure = set(
                await session.scalars(
                    select(RoleAssignment.role).where(RoleAssignment.user_id == user_id)
                )
            )
            raise RuntimeError("Fail after account and role updates")

        monkeypatch.setattr(emails, "notify_account_security", fail_after_notice)

    response = await call(auth, student.tokens, "DELETE", "/" + student_address["id"])
    assert response.status_code == (500 if rollback else 204), response.text
    me = (await student.me()).json()
    assert me["account_type"] == ("student" if rollback else "employee")
    assert me["course"] == (2 if rollback else None)
    remaining = (await call(auth, student.tokens, "GET")).json()
    assert len(remaining) == (2 if rollback else 1)
    auth.db.expire_all()
    assignments = list(await auth.db.scalars(select(RoleAssignment)))
    if rollback:
        assert roles_before_failure == {Role.MODERATOR, Role.ADMINISTRATOR}
        assert {row.id for row in assignments} == original_roles
        assert set(await auth.db.scalars(select(OutboxMessage.id))) == notices
        assert (await action(student, scope)).status_code == 200
    else:
        assert {row.role for row in assignments} == {Role.MODERATOR, Role.ADMINISTRATOR}
        assert {row.id for row in assignments} < original_roles
        denied(await action(student, scope))
        denied(await action(student, f"/scope/faculty/{places.economics}"))
        assert (await action(student, "/admin/test")).status_code == 200


async def test_backup_changes_preserve_type_and_all_assignments(
    auth: Auth, student: Account, places: Places, routes: UUID
) -> None:
    assert (await add(auth, student.tokens, "teacher@staff.example")).status_code == 201
    assert (await student.put(moscow_profile(places))).status_code == 200
    original_roles = await grant_roles(auth, routes, places)
    for email in ("first@personal.example", "replacement@personal.example"):
        response = await add(auth, student.tokens, email, "backup")
        assert response.status_code == 201, response.text
        assert (await student.me()).json()["account_type"] == "student"
        auth.db.expire_all()
        assert set(await auth.db.scalars(select(RoleAssignment.id))) == original_roles
        await auth.db.rollback()
    assert (
        await call(auth, student.tokens, "DELETE", "/" + response.json()["id"])
    ).status_code == 204
    assert (await student.me()).json()["account_type"] == "student"
    auth.db.expire_all()
    assert set(await auth.db.scalars(select(RoleAssignment.id))) == original_roles


async def test_removing_staff_address_preserves_student_roles(
    auth: Auth, student: Account, places: Places, routes: UUID
) -> None:
    staff = await add(auth, student.tokens, "teacher@staff.example")
    assert staff.status_code == 201
    original_roles = await grant_roles(auth, routes, places)
    assert (
        await call(auth, student.tokens, "DELETE", "/" + staff.json()["id"])
    ).status_code == 204
    assert (await student.me()).json()["account_type"] == "student"
    auth.db.expire_all()
    assert set(await auth.db.scalars(select(RoleAssignment.id))) == original_roles
