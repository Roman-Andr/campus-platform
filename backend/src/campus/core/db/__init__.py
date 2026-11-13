"""Database access: declarative base, base entity, engine and sessions."""

from campus.core.db.base import NAMING_CONVENTION, Base, Entity
from campus.core.db.engine import (
    DatabaseNotConfiguredError,
    create_engine,
    create_session_factory,
)
from campus.core.db.localized import NAME_MAX_LENGTH, LocalizedName

__all__ = [
    "NAME_MAX_LENGTH",
    "NAMING_CONVENTION",
    "Base",
    "DatabaseNotConfiguredError",
    "Entity",
    "LocalizedName",
    "create_engine",
    "create_session_factory",
]
