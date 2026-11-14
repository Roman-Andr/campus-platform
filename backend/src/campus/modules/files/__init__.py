"""Private reusable files and photo upload API."""

from campus.modules.files.api import router
from campus.modules.files.models import File
from campus.modules.files.profile import router as profile_router

__all__ = ["File", "profile_router", "router"]
