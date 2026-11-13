"""Test data factories (polyfactory) persisted through the test session."""

from typing import Any
from uuid import uuid4

from polyfactory import Use
from polyfactory.factories.sqlalchemy_factory import (
    SQLAlchemyFactory,
    SQLAlchemyPersistenceMethod,
)

from campus.core.db import Entity
from campus.modules.university import City
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


class CityFactory(EntityFactory[City]):
    code = Use(lambda: f"city-{uuid4().hex[:8]}")
    timezone = "Europe/Moscow"
    name_ru = "Город"
    name_en = "City"
