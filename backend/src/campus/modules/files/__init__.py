"""Private reusable files and photo upload API."""

from campus.modules.files.api import router
from campus.modules.files.models import File

__all__ = ["File", "router"]
