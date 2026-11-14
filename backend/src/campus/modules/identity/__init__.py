"""Public interface of the identity module."""

from campus.modules.identity.api import router
from campus.modules.identity.bootstrap import FirstAdminInput, create_first_admin
from campus.modules.identity.consent_events import (
    ConsentChange,
    consent_consumers,
    replay_consent_events,
)
from campus.modules.identity.consent_seed import seed_documents
from campus.modules.identity.consents import (
    ConsentDecision,
    DocumentKind,
    DocumentVersion,
    check_consents,
    cross_border_allowed,
    publish_document,
)
from campus.modules.identity.consents import router as consent_router
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
from campus.modules.identity.sessions import router as sessions_router

__all__ = [
    "ConsentChange",
    "ConsentDecision",
    "DocumentKind",
    "DocumentVersion",
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
    "check_consents",
    "consent_consumers",
    "consent_router",
    "create_first_admin",
    "cross_border_allowed",
    "delete_expired_credentials",
    "profile_router",
    "publish_document",
    "replay_consent_events",
    "require_roles",
    "router",
    "seed_documents",
    "sessions_router",
]
