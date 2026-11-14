"""University structure: campus cities, dormitories, faculties, e-mail domains.

Public interface of the module. Other modules import only this package,
never its submodules (enforced by import-linter).
"""

from campus.modules.university.api import router
from campus.modules.university.models import (
    CODE_MAX_LENGTH,
    CODE_PATTERN,
    AccountType,
    City,
    Dormitory,
    EmailDomain,
    Faculty,
    InvalidTimezoneError,
    check_timezone,
)
from campus.modules.university.seed import (
    DEFAULT_SEED_FILE,
    ReferenceData,
    SeedReport,
    read_seed_file,
    seed_reference_data,
)

__all__ = [
    "CODE_MAX_LENGTH",
    "CODE_PATTERN",
    "DEFAULT_SEED_FILE",
    "AccountType",
    "City",
    "Dormitory",
    "EmailDomain",
    "Faculty",
    "InvalidTimezoneError",
    "ReferenceData",
    "SeedReport",
    "check_timezone",
    "read_seed_file",
    "router",
    "seed_reference_data",
]
