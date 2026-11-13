"""Test data factories (polyfactory) persisted through the test session."""

from typing import Any

from polyfactory.factories.sqlalchemy_factory import (
    SQLAlchemyFactory,
    SQLAlchemyPersistenceMethod,
)

from campus.core.db import Entity
from tests.models import Note

# Columns filled by the database or the application clock, never randomly.
GENERATED_COLUMNS = frozenset({"id", "created_at", "updated_at"})


class EntityFactory[T: Entity](SQLAlchemyFactory[T]):
    """Base factory: ``await Factory.create_async()`` adds and flushes a row.

    The ``session`` fixture binds all factories to the test session; the test
    decides when to commit.
    """

    __is_base_factory__ = True
    __persistence_method__ = SQLAlchemyPersistenceMethod.FLUSH
    __check_model__ = True

    @classmethod
    def should_column_be_set(cls, column: Any) -> bool:
        if getattr(column, "name", None) in GENERATED_COLUMNS:
            return False
        return super().should_column_be_set(column)


class NoteFactory(EntityFactory[Note]):
    pass
