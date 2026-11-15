"""Administrator API of role assignments (specification, 5.1.1, modules 3, 10).

The panel lists the roles of a user, assigns a role with its scope and
revokes a role. Only an administrator may do so: the panel prefix itself
accepts moderators (their own features live there), so these routes add the
stricter check, and a moderator, headman, student, employee or graduate
gets ``forbidden``.

The domain rules live in :mod:`campus.modules.identity.role_management`:
they lock the user row, re-read the account type, keep at least one
administrator and write the audit journal in the same transaction. Records
here only translate HTTP to those operations; the request transaction and
the ``Idempotency-Key`` replay cover the change and its audit record.
"""

from uuid import UUID

from fastapi import Depends, Request, Response
from pydantic import BaseModel, ConfigDict, Field

from campus.core.web import DbSession, Instant, Problem, api_router, request_locale
from campus.modules.identity import (
    Permissions,
    Role,
    assign_role,
    require_roles,
    revoke_role,
    user_role_assignments,
)

router = api_router(
    prefix="/users",
    tags=["administration"],
    dependencies=[Depends(require_roles(Role.ADMINISTRATOR))],
    responses={
        403: {
            "model": Problem,
            "description": "Administrator role required (forbidden).",
        }
    },
)


class RoleAssignmentOut(BaseModel):
    """One role of a user with its scope."""

    model_config = ConfigDict(from_attributes=True, frozen=True)

    id: UUID
    user_id: UUID
    role: Role = Field(
        description="Headman, moderator or administrator.",
        examples=["headman"],
    )
    dormitory_id: UUID | None = Field(
        description="Scope of a headman; empty for global roles."
    )
    faculty_id: UUID | None = Field(
        description="Scope of a headman; empty for global roles."
    )
    created_at: Instant


class RoleAssignmentInput(BaseModel):
    """The role to assign and its scope.

    A headman has exactly one scope, ``dormitory_id`` or ``faculty_id``;
    a moderator and an administrator have none. The account type rules of
    the target user are checked on the server.
    """

    model_config = ConfigDict(extra="forbid")

    role: Role = Field(examples=["headman"])
    dormitory_id: UUID | None = Field(
        default=None, description="Scope of a headman; not for global roles."
    )
    faculty_id: UUID | None = Field(
        default=None, description="Scope of a headman; not for global roles."
    )


class RoleAssignmentList(BaseModel):
    items: list[RoleAssignmentOut]


@router.get(
    "/{user_id}/roles",
    responses={404: {"model": Problem, "description": "No such user."}},
)
async def list_user_roles(user_id: UUID, session: DbSession) -> RoleAssignmentList:
    """Roles of the user with their scopes; empty for a user without roles."""
    assignments = await user_role_assignments(session, user_id)
    return RoleAssignmentList(
        items=[RoleAssignmentOut.model_validate(row) for row in assignments]
    )


@router.post(
    "/{user_id}/roles",
    status_code=201,
    responses={
        404: {"model": Problem, "description": "No such user."},
        409: {
            "model": Problem,
            "description": "The user already holds this role in this scope.",
        },
        422: {
            "model": Problem,
            "description": "Invalid request (validation_failed: the role is not"
            " allowed for the account type, or the scope is missing or unknown)"
            " or Idempotency-Key used for a different request"
            " (idempotency_key_reused).",
        },
    },
)
async def create_user_role(
    user_id: UUID,
    data: RoleAssignmentInput,
    request: Request,
    session: DbSession,
    permissions: Permissions,
) -> RoleAssignmentOut:
    """Assign the role with its scope to the user.

    A headman must be a student with exactly one existing dormitory or
    faculty; a moderator or an administrator is a student or an employee
    without a scope; a graduate and a former employee hold no roles.
    """
    assignment = await assign_role(
        session,
        actor_id=permissions.user_id,
        user_id=user_id,
        role=data.role,
        dormitory_id=data.dormitory_id,
        faculty_id=data.faculty_id,
        locale=request_locale(request),
    )
    return RoleAssignmentOut.model_validate(assignment)


@router.delete(
    "/{user_id}/roles/{assignment_id}",
    status_code=204,
    responses={
        404: {
            "model": Problem,
            "description": "No such user, or the assignment is not theirs.",
        },
        409: {
            "model": Problem,
            "description": "The last administrator cannot be revoked.",
        },
    },
)
async def delete_user_role(
    user_id: UUID,
    assignment_id: UUID,
    session: DbSession,
    permissions: Permissions,
) -> Response:
    """Revoke one assignment of the user; the last administrator stays."""
    await revoke_role(
        session,
        actor_id=permissions.user_id,
        user_id=user_id,
        assignment_id=assignment_id,
    )
    return Response(status_code=204)


__all__ = ["RoleAssignmentOut", "router"]
