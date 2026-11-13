"""Database access: declarative base, base entity, engine and sessions."""

from campus.core.db.base import NAMING_CONVENTION, Base, Entity
from campus.core.db.engine import (
    DatabaseNotConfiguredError,
    create_engine,
    create_session_factory,
)

__all__ = [
    "NAMING_CONVENTION",
    "Base",
    "DatabaseNotConfiguredError",
    "Entity",
    "create_engine",
    "create_session_factory",
]
