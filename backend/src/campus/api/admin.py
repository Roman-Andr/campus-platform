"""Panel features attach their routers here to inherit the role check."""

from campus.modules import administration, moderation
from campus.modules.identity import admin_router

router = admin_router()
router.include_router(administration.audit_router)
router.include_router(administration.roles_router)
router.include_router(moderation.admin_router)
router.include_router(moderation.disputes_admin_router)
