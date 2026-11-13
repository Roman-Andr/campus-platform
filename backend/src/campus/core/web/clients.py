"""Client platform and version headers (specification, 4.6).

Every API request names the client: ``X-Client-Platform`` (one of
:class:`~campus.core.config.ClientPlatform`) and ``X-Client-Version`` (PEP
440 / semantic version, e.g. ``1.4.0``). A client older than the minimum
configured for its platform gets ``426 client_update_required`` with the
minimum version, so the app can offer an update.
"""

from fastapi import Request
from packaging.version import Version

from campus.core.config import ClientPlatform, Settings
from campus.core.i18n import N_
from campus.core.web.problems import ProblemError, ProblemType

PLATFORM_HEADER = "X-Client-Platform"
VERSION_HEADER = "X-Client-Version"

CLIENT_VERSION_MISSING = ProblemType(
    "client_version_missing",
    400,
    N_("Client version missing"),
    N_("The X-Client-Platform and X-Client-Version headers are required."),
)
CLIENT_VERSION_INVALID = ProblemType(
    "client_version_invalid",
    400,
    N_("Invalid client version"),
    N_("The client platform or version is not recognized."),
)
CLIENT_UPDATE_REQUIRED = ProblemType(
    "client_update_required",
    426,
    N_("Update required"),
    N_(
        "This version of the app is no longer supported."
        " Please update to {version} or newer."
    ),
)


def check_client_version(request: Request, settings: Settings) -> None:
    """Reject requests without client headers or from outdated clients."""
    platform_value = request.headers.get(PLATFORM_HEADER)
    version_value = request.headers.get(VERSION_HEADER)
    if not platform_value or not version_value:
        raise ProblemError(CLIENT_VERSION_MISSING)
    try:
        platform = ClientPlatform(platform_value)
        version = Version(version_value)
    except ValueError:  # InvalidVersion is a ValueError too
        raise ProblemError(CLIENT_VERSION_INVALID) from None

    minimum = settings.client_min_version(platform)
    if minimum is not None and version < minimum:
        raise ProblemError(
            CLIENT_UPDATE_REQUIRED, min_version=str(minimum), version=str(minimum)
        )
