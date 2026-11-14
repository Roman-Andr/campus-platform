"""Panel features attach their routers here to inherit the role check."""

from campus.modules.identity import admin_router

router = admin_router()
