"""The common API instant type: explicit RFC 3339 offset in, UTC out."""

import re
from datetime import datetime
from typing import Annotated

from pydantic import AfterValidator, AwareDatetime, BeforeValidator, Field
from pydantic_core import PydanticCustomError

from campus.core.timezones import as_utc

_RFC3339 = re.compile(
    r"^\d{4}-\d{2}-\d{2}[Tt]\d{2}:\d{2}:\d{2}(?:\.\d+)?"
    r"(?:[Zz]|[+-]\d{2}:\d{2})$"
)


def _explicit_offset(value: object) -> object:
    if isinstance(value, datetime):
        return value
    if not isinstance(value, str) or not _RFC3339.fullmatch(value):
        raise PydanticCustomError(
            "datetime_offset", "Use RFC 3339 with an explicit UTC offset."
        )
    return value


Instant = Annotated[
    AwareDatetime,
    BeforeValidator(_explicit_offset),
    AfterValidator(as_utc),
    Field(description="RFC 3339 instant with an explicit offset; returned in UTC."),
]
