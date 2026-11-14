"""Public interface of the identity module."""

from campus.modules.identity.api import router
from campus.modules.identity.bootstrap import FirstAdminInput, create_first_admin
from campus.modules.identity.models import RefreshToken, Session, SignInCode, User
from campus.modules.identity.profile import ProfiledUser
from campus.modules.identity.profile import router as profile_router
from campus.modules.identity.retention import delete_expired_credentials
from campus.modules.identity.roles import (
    PermissionContext,
    Permissions,
    Role,
    RoleAssignment,
    admin_router,
    require_roles,
)

__all__ = [
    "FirstAdminInput",
    "PermissionContext",
    "Permissions",
    "ProfiledUser",
    "RefreshToken",
    "Role",
    "RoleAssignment",
    "Session",
    "SignInCode",
    "User",
    "admin_router",
    "create_first_admin",
    "delete_expired_credentials",
    "profile_router",
    "require_roles",
    "router",
]
