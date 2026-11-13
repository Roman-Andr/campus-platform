"""Reference data named in every supported language (specification, 5.1.1).

Reference entities (cities, dormitories, categories, ...) carry their name
in each language of :data:`campus.core.config.Locale`; the API returns the
name in the language of the request.
"""

from typing import Any

from sqlalchemy import String
from sqlalchemy.orm import InstrumentedAttribute, Mapped, mapped_column

from campus.core.config import Locale

NAME_MAX_LENGTH = 200


class LocalizedName:
    """Mixin: ``name_ru`` and ``name_en`` columns of a reference entity."""

    name_ru: Mapped[str] = mapped_column(String(NAME_MAX_LENGTH))
    name_en: Mapped[str] = mapped_column(String(NAME_MAX_LENGTH))

    def name_in(self, locale: Locale) -> str:
        """The name in ``locale``."""
        name: str = getattr(self, f"name_{locale}")
        return name

    @classmethod
    def name_column(cls, locale: Locale) -> InstrumentedAttribute[Any]:
        """The column holding names in ``locale``, e.g. for sorting."""
        column: InstrumentedAttribute[Any] = getattr(cls, f"name_{locale}")
        return column
