"""Tables that exist only in the test database, to exercise the base entity."""

from sqlalchemy import MetaData, String
from sqlalchemy.orm import Mapped, mapped_column

from campus.core.db import NAMING_CONVENTION, Entity


class ExampleEntity(Entity):
    """Base of test tables; their own metadata keeps them out of migrations."""

    __abstract__ = True
    metadata = MetaData(naming_convention=NAMING_CONVENTION)


class Note(ExampleEntity):
    __tablename__ = "test_note"

    title: Mapped[str] = mapped_column(String(200))
    body: Mapped[str | None]
