"""Private reusable files and photo upload API."""

from campus.modules.files.api import router
from campus.modules.files.models import File
from campus.modules.files.profile import router as profile_router
from campus.modules.files.service import expire_later, locked_file

__all__ = ["File", "expire_later", "locked_file", "profile_router", "router"]
