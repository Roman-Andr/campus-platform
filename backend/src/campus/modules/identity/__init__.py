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
    lock_consent_state,
    publish_document,
)
from campus.modules.identity.consents import router as consent_router
from campus.modules.identity.emails import notify_account_security
from campus.modules.identity.emails import router as email_router
from campus.modules.identity.models import (
    Block,
    NameChange,
    RefreshToken,
    Session,
    SignInCode,
    SkillTag,
    User,
    UserEmail,
    UserSkill,
)
from campus.modules.identity.privacy import blocked_between, serialize_contact_pair
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
from campus.modules.identity.session_events import (
    SessionsRevoked,
    replay_session_events,
    session_consumers,
)
from campus.modules.identity.sessions import router as sessions_router
from campus.modules.identity.skill_seed import seed_skill_tags
from campus.modules.identity.skills import router as skills_router

__all__ = [
    "Block",
    "ConsentChange",
    "ConsentDecision",
    "DocumentKind",
    "DocumentVersion",
    "FirstAdminInput",
    "NameChange",
    "PermissionContext",
    "Permissions",
    "ProfiledUser",
    "RefreshToken",
    "Role",
    "RoleAssignment",
    "Session",
    "SessionsRevoked",
    "SignInCode",
    "SkillTag",
    "User",
    "UserEmail",
    "UserSkill",
    "admin_router",
    "blocked_between",
    "check_consents",
    "consent_consumers",
    "consent_router",
    "create_first_admin",
    "cross_border_allowed",
    "delete_expired_credentials",
    "email_router",
    "lock_consent_state",
    "notify_account_security",
    "profile_router",
    "publish_document",
    "replay_consent_events",
    "replay_session_events",
    "require_roles",
    "router",
    "seed_documents",
    "seed_skill_tags",
    "serialize_contact_pair",
    "session_consumers",
    "sessions_router",
    "skills_router",
]
