"""Assigning and revoking scoped roles (specification, 5.1.1, modules 3, 10).

An administrator gives a student the headman role with one dormitory or
faculty scope, or gives a student or an employee the global moderator or
administrator role. A graduate and a former employee hold no roles. The
functions here are the domain operations of the API and of the annual
status confirmation (#73), which revokes every role of a user who did not
confirm the status: it calls :func:`revoke_user_roles` and records the
change in the journal with the system as the actor.

Locking. Every operation locks the target user row first and re-reads the
account type after the lock. A concurrent change of the corporate address
can turn a student into an employee and revokes headman assignments in the
same transaction (#246); without the lock and the re-read, an assignment
that passed the check before that change could reintroduce a headman to an
employee. The lock order is fixed — the user row, then the administrator
assignment rows — so operations on different users do not deadlock.

The last administrator. The service keeps at least one administrator. A
revocation of an administrator counts the administrator assignments under
row locks, so of two concurrent revocations of the last two
administrators exactly one succeeds; the other waits for the first
transaction, sees a single remaining administrator and is rejected.

Audit. Every assignment and revocation adds a record of the global journal
(:mod:`campus.core.audit`) in the caller's transaction: the actor, the
user, the role, its scope and the time. The record and the change commit
together or not at all, and a replayed ``Idempotency-Key`` runs no second
change, so it adds no second record.
"""

from collections.abc import Sequence
from dataclasses import dataclass
from typing import Any
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from campus.core.audit import record_action
from campus.core.config import Locale
from campus.core.i18n import N_, translate
from campus.core.web import FieldError, ProblemError, ProblemType
from campus.core.web.problems import NOT_FOUND, VALIDATION_FAILED
from campus.modules.identity.models import User
from campus.modules.identity.roles import Role, RoleAssignment
from campus.modules.university import AccountType, Dormitory, Faculty

ASSIGN = "administration.role.assign"
REVOKE = "administration.role.revoke"

# Account types that never hold a role; the types themselves arrive in #73.
INACTIVE_ACCOUNT_TYPES = frozenset({"alumni", "former_employee"})

ROLE_ASSIGNMENT_NOT_FOUND = ProblemType(
    "role_assignment_not_found",
    404,
    N_("Role assignment not found"),
    N_("The user has no such role assignment."),
)
ROLE_ALREADY_ASSIGNED = ProblemType(
    "role_already_assigned",
    409,
    N_("Role already assigned"),
    N_("The user already holds this role in this scope."),
)
LAST_ADMINISTRATOR = ProblemType(
    "last_administrator",
    409,
    N_("Last administrator"),
    N_("The service must keep at least one administrator."),
)

ONLY_STUDENT_IS_HEADMAN = N_("Only a student can be the headman.")
INACTIVE_ACCOUNT_HAS_NO_ROLES = N_("A graduate or a former employee has no roles.")
HEADMAN_NEEDS_ONE_SCOPE = N_("A headman needs a dormitory or a faculty.")
HEADMAN_HAS_ONE_SCOPE = N_("A headman has a single scope; both cannot be given.")
GLOBAL_ROLE_HAS_NO_SCOPE = N_("A moderator or an administrator has no scope.")
SCOPE_NOT_FOUND = N_("No such dormitory or faculty.")


def _field(locale: Locale, pointer: str, code: str, message: str) -> FieldError:
    return FieldError(detail=translate(message, locale), code=code, pointer=pointer)


async def _lock_user(session: AsyncSession, user_id: UUID) -> User:
    """Lock the account row for the whole operation and return fresh values.

    ``populate_existing`` replaces the attributes of a user already loaded
    in this transaction (for example the actor) with the row read under the
    lock, so the account type checked below is the one that will hold.
    """
    user = await session.scalar(
        select(User)
        .where(User.id == user_id)
        .with_for_update()
        .execution_options(populate_existing=True)
    )
    if user is None:
        raise ProblemError(NOT_FOUND)
    return user


async def _locked_administrators(session: AsyncSession) -> Sequence[RoleAssignment]:
    """Lock every administrator assignment, ordered, for the invariant."""
    assignments = await session.scalars(
        select(RoleAssignment)
        .where(RoleAssignment.role == Role.ADMINISTRATOR)
        .order_by(RoleAssignment.id)
        .with_for_update()
    )
    return assignments.all()


async def user_role_assignments(
    session: AsyncSession, user_id: UUID
) -> tuple[RoleAssignment, ...]:
    """All role assignments of the user, by role and scope.

    A user without roles answers an empty list; an unknown user is
    ``not_found``. The panel needs the assignment IDs to revoke a role.
    """
    if await session.scalar(select(User.id).where(User.id == user_id)) is None:
        raise ProblemError(NOT_FOUND)
    assignments = await session.scalars(
        select(RoleAssignment)
        .where(RoleAssignment.user_id == user_id)
        .order_by(
            RoleAssignment.role,
            RoleAssignment.dormitory_id,
            RoleAssignment.faculty_id,
            RoleAssignment.id,
        )
    )
    return tuple(assignments)


@dataclass(frozen=True, slots=True)
class RemovedRole:
    """A role that was just revoked; safe to use after the commit."""

    user_id: UUID
    role: Role
    dormitory_id: UUID | None
    faculty_id: UUID | None


def _removed(assignment: RoleAssignment) -> RemovedRole:
    return RemovedRole(
        user_id=assignment.user_id,
        role=Role(assignment.role),
        dormitory_id=assignment.dormitory_id,
        faculty_id=assignment.faculty_id,
    )


def _state(assignment: RoleAssignment) -> dict[str, Any]:
    """The audited fields of an assignment: its role and its scope."""
    return {
        "role": assignment.role,
        "dormitory_id": assignment.dormitory_id,
        "faculty_id": assignment.faculty_id,
    }


def _account_errors(user: User, role: Role, locale: Locale) -> list[FieldError]:
    """Why the account type cannot hold the role; empty if it can."""
    if user.account_type in INACTIVE_ACCOUNT_TYPES:
        return [_field(locale, "#/role", "not_allowed", INACTIVE_ACCOUNT_HAS_NO_ROLES)]
    if role == Role.HEADMAN and user.account_type != AccountType.STUDENT:
        return [_field(locale, "#/role", "not_allowed", ONLY_STUDENT_IS_HEADMAN)]
    return []


def _scope_form_errors(
    role: Role, dormitory_id: UUID | None, faculty_id: UUID | None, locale: Locale
) -> list[FieldError]:
    """Why the scope form is wrong for the role; empty if it is right."""
    if role == Role.HEADMAN:
        if dormitory_id is None and faculty_id is None:
            return [
                _field(locale, "#/dormitory_id", "missing", HEADMAN_NEEDS_ONE_SCOPE)
            ]
        if dormitory_id is not None and faculty_id is not None:
            return [
                _field(locale, "#/faculty_id", "not_allowed", HEADMAN_HAS_ONE_SCOPE)
            ]
        return []
    errors: list[FieldError] = []
    if dormitory_id is not None:
        errors.append(
            _field(locale, "#/dormitory_id", "not_allowed", GLOBAL_ROLE_HAS_NO_SCOPE)
        )
    if faculty_id is not None:
        errors.append(
            _field(locale, "#/faculty_id", "not_allowed", GLOBAL_ROLE_HAS_NO_SCOPE)
        )
    return errors


async def _scope_exists_errors(
    session: AsyncSession,
    role: Role,
    dormitory_id: UUID | None,
    faculty_id: UUID | None,
    locale: Locale,
) -> list[FieldError]:
    """Why the single headman scope does not exist; empty if it does.

    The form is validated separately, so here exactly one scope is set or
    the assignment is global.
    """
    if role != Role.HEADMAN or (dormitory_id is None) == (faculty_id is None):
        return []
    if dormitory_id is not None:
        known = await session.scalar(
            select(Dormitory.id).where(Dormitory.id == dormitory_id)
        )
        pointer = "#/dormitory_id"
    else:
        known = await session.scalar(select(Faculty.id).where(Faculty.id == faculty_id))
        pointer = "#/faculty_id"
    if known is not None:
        return []
    return [_field(locale, pointer, "not_found", SCOPE_NOT_FOUND)]


async def _assignment_errors(  # noqa: PLR0913 - the fields of an assignment
    session: AsyncSession,
    *,
    user: User,
    role: Role,
    dormitory_id: UUID | None,
    faculty_id: UUID | None,
    locale: Locale,
) -> list[FieldError]:
    """Why the assignment is not allowed for the user; empty if it is."""
    return [
        *_account_errors(user, role, locale),
        *_scope_form_errors(role, dormitory_id, faculty_id, locale),
        *await _scope_exists_errors(session, role, dormitory_id, faculty_id, locale),
    ]


async def assign_role(  # noqa: PLR0913 - the fields of an assignment
    session: AsyncSession,
    *,
    actor_id: UUID,
    user_id: UUID,
    role: Role,
    dormitory_id: UUID | None,
    faculty_id: UUID | None,
    locale: Locale,
) -> RoleAssignment:
    """Give the user the role in the scope; the caller owns the transaction.

    The rules of the account type and the scope form are checked under the
    user row lock; a duplicate assignment is a conflict, and the change and
    its audit record commit together.
    """
    user = await _lock_user(session, user_id)
    errors = await _assignment_errors(
        session,
        user=user,
        role=role,
        dormitory_id=dormitory_id,
        faculty_id=faculty_id,
        locale=locale,
    )
    if errors:
        raise ProblemError(VALIDATION_FAILED, errors=errors)
    assignment = RoleAssignment(
        user_id=user.id,
        role=role,
        dormitory_id=dormitory_id,
        faculty_id=faculty_id,
    )
    try:
        async with session.begin_nested():
            session.add(assignment)
            await session.flush()
    except IntegrityError:
        # Only the unique constraint can fail here: the form is checked.
        raise ProblemError(ROLE_ALREADY_ASSIGNED) from None
    await record_action(
        session,
        actor_id=actor_id,
        action=ASSIGN,
        object_type="user",
        object_id=user.id,
        participant_ids=[user.id],
        after=_state(assignment),
    )
    return assignment


async def _revoke(
    session: AsyncSession,
    assignment: RoleAssignment,
    *,
    actor_id: UUID | None,
    reason: str | None,
) -> RemovedRole:
    removed = _removed(assignment)
    before = _state(assignment)
    await session.delete(assignment)
    await session.flush()
    await record_action(
        session,
        actor_id=actor_id,
        action=REVOKE,
        object_type="user",
        object_id=removed.user_id,
        reason=reason,
        participant_ids=[removed.user_id],
        before=before,
    )
    return removed


async def revoke_role(
    session: AsyncSession,
    *,
    actor_id: UUID | None,
    user_id: UUID,
    assignment_id: UUID,
    reason: str | None = None,
) -> RemovedRole:
    """Revoke one assignment of the user; the caller owns the transaction.

    An assignment of another user is indistinguishable from a missing one.
    Revoking the last administrator is rejected, including by the
    administrator themselves: the count and the deletion are serialized by
    the administrator assignment row locks. ``actor_id`` is empty when the
    system revokes roles itself (#73), which still writes the journal.
    """
    user = await _lock_user(session, user_id)
    assignment = await session.scalar(
        select(RoleAssignment).where(
            RoleAssignment.id == assignment_id,
            RoleAssignment.user_id == user.id,
        )
    )
    if assignment is None:
        raise ProblemError(ROLE_ASSIGNMENT_NOT_FOUND)
    if assignment.role == Role.ADMINISTRATOR:
        administrators = await _locked_administrators(session)
        # The locks awaited the concurrent revocation: the row may be gone.
        if all(row.id != assignment.id for row in administrators):
            raise ProblemError(ROLE_ASSIGNMENT_NOT_FOUND)
        if len(administrators) == 1:
            raise ProblemError(LAST_ADMINISTRATOR)
    return await _revoke(session, assignment, actor_id=actor_id, reason=reason)


async def revoke_user_roles(
    session: AsyncSession,
    *,
    user_id: UUID,
    actor_id: UUID | None = None,
    reason: str | None = None,
) -> tuple[RemovedRole, ...]:
    """Revoke every role of the user; the annual confirmation (#73) uses it.

    The last administrator is rejected before anything is deleted, so the
    caller can postpone the transition of that account (#209) and retry
    later. The returned roles are snapshots, usable after the commit.
    """
    user = await _lock_user(session, user_id)
    assignments = (
        await session.scalars(
            select(RoleAssignment)
            .where(RoleAssignment.user_id == user.id)
            .order_by(RoleAssignment.id)
        )
    ).all()
    if any(assignment.role == Role.ADMINISTRATOR for assignment in assignments):
        administrators = await _locked_administrators(session)
        if len(administrators) == 1:
            raise ProblemError(LAST_ADMINISTRATOR)
    return tuple(
        [
            await _revoke(session, assignment, actor_id=actor_id, reason=reason)
            for assignment in assignments
        ]
    )


__all__ = [
    "ASSIGN",
    "LAST_ADMINISTRATOR",
    "REVOKE",
    "ROLE_ALREADY_ASSIGNED",
    "ROLE_ASSIGNMENT_NOT_FOUND",
    "RemovedRole",
    "assign_role",
    "revoke_role",
    "revoke_user_roles",
    "user_role_assignments",
]
