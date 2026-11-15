"""Moderation: complaints, disputes, sanctions.

Public interface of the module. Other modules import only this package,
never its submodules (enforced by import-linter).
"""

from campus.modules.moderation.api import admin_router, router
from campus.modules.moderation.models import ComplaintReason

__all__ = ["ComplaintReason", "admin_router", "router"]
