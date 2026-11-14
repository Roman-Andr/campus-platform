"""Server-owned role assignments and reusable authorization dependencies.

Account types never imply elevated permissions. Scoped checks require an
exact role and place match; global roles do not silently bypass them.
Object dependencies must load their object on the server before passing
its author, owner or participant IDs to the context.
"""

from collections.abc import Callable, Iterable
from dataclasses import dataclass
from enum import StrEnum
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends
from pydantic import BaseModel, ConfigDict
from sqlalchemy import (
    CheckConstraint,
    ForeignKey,
    String,
    UniqueConstraint,
    delete,
    select,
)
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import Mapped, mapped_column

from campus.core.db import Entity
from campus.core.i18n import N_
from campus.core.web import (
    CurrentUser,
    DbSession,
    Problem,
    ProblemError,
    ProblemType,
    api_router,
)
from campus.modules.identity.models import User

FORBIDDEN = ProblemType("forbidden", 403, N_("Forbidden"))


class Role(StrEnum):
    HEADMAN = "headman"
    MODERATOR = "moderator"
    ADMINISTRATOR = "administrator"


class RoleAssignment(Entity):
    """A global role or a headman's single dormitory/faculty scope."""

    __tablename__ = "identity_role_assignment"
    __table_args__ = (
        CheckConstraint(
            "(role = 'headman' AND ((dormitory_id IS NOT NULL AND faculty_id IS NULL)"
            " OR (dormitory_id IS NULL AND faculty_id IS NOT NULL)))"
            " OR (role IN ('moderator', 'administrator')"
            " AND dormitory_id IS NULL AND faculty_id IS NULL)",
            name="role_scope",
        ),
        UniqueConstraint(
            "user_id",
            "role",
            "dormitory_id",
            "faculty_id",
            postgresql_nulls_not_distinct=True,
        ),
    )

    user_id: Mapped[UUID] = mapped_column(
        ForeignKey("identity_user.id", ondelete="CASCADE"), index=True
    )
    role: Mapped[str] = mapped_column(String(16))
    dormitory_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("university_dormitory.id", ondelete="RESTRICT")
    )
    faculty_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("university_faculty.id", ondelete="RESTRICT")
    )


async def revoke_headman_roles(session: AsyncSession, user_id: UUID) -> None:
    """Remove every headman scope in the caller's transaction.

    The caller must hold the user's row lock, also required by future role
    assignment operations to serialize them with account type changes.
    Global moderator and administrator assignments are preserved.
    """
    await session.execute(
        delete(RoleAssignment).where(
            RoleAssignment.user_id == user_id, RoleAssignment.role == Role.HEADMAN
        )
    )


class RoleOutput(BaseModel):
    model_config = ConfigDict(from_attributes=True, frozen=True)
    role: Role
    dormitory_id: UUID | None
    faculty_id: UUID | None


async def user_roles(session: DbSession, user_id: UUID) -> tuple[RoleOutput, ...]:
    assignments = await session.scalars(
        select(RoleAssignment)
        .where(RoleAssignment.user_id == user_id)
        .order_by(
            RoleAssignment.role, RoleAssignment.dormitory_id, RoleAssignment.faculty_id
        )
    )
    return tuple(RoleOutput.model_validate(row) for row in assignments)


@dataclass(frozen=True)
class PermissionContext:
    user_id: UUID
    account_type: str
    roles: tuple[RoleOutput, ...]

    def require_role(self, *roles: Role) -> None:
        if not any(assignment.role in roles for assignment in self.roles):
            raise ProblemError(FORBIDDEN)

    def require_scope(
        self, *, dormitory_id: UUID | None = None, faculty_id: UUID | None = None
    ) -> None:
        if (dormitory_id is None) == (faculty_id is None) or not any(
            assignment.role == Role.HEADMAN
            and assignment.dormitory_id == dormitory_id
            and assignment.faculty_id == faculty_id
            for assignment in self.roles
        ):
            raise ProblemError(FORBIDDEN)

    def require_author(self, author_id: UUID) -> None:
        if self.user_id != author_id:
            raise ProblemError(FORBIDDEN)

    def require_owner(self, owner_id: UUID) -> None:
        if self.user_id != owner_id:
            raise ProblemError(FORBIDDEN)

    def require_participant(self, participant_ids: Iterable[UUID]) -> None:
        if self.user_id not in participant_ids:
            raise ProblemError(FORBIDDEN)


async def permission_context(
    session: DbSession, principal: CurrentUser
) -> PermissionContext:
    """Read account type and assignments anew in every request transaction."""
    user = await session.get(User, principal.user_id)
    if user is None:
        raise ProblemError(FORBIDDEN)
    return PermissionContext(
        user.id, user.account_type, await user_roles(session, user.id)
    )


Permissions = Annotated[PermissionContext, Depends(permission_context)]


def require_roles(*roles: Role) -> Callable[..., None]:
    """A FastAPI dependency requiring at least one of the given roles."""

    def check(context: Permissions) -> None:
        context.require_role(*roles)

    return check


def admin_router() -> APIRouter:
    """All panel routes must be included beneath this protected router."""
    return api_router(
        prefix="/admin",
        dependencies=[Depends(require_roles(Role.MODERATOR, Role.ADMINISTRATOR))],
        responses={
            403: {"model": Problem, "description": "Permission denied (forbidden)."}
        },
    )
