"""Initial reference data: cities, dormitories, faculties, e-mail domains.

The data is a TOML file (``seed.toml`` next to this module by default),
validated before anything is written. Loading is idempotent: rows are
matched by their natural keys (``code``, ``(city, code)``, ``domain``) with
``INSERT ... ON CONFLICT DO NOTHING``, so a repeated or concurrent load
adds only missing rows and never overwrites rows edited by administrators.
"""

import tomllib
from dataclasses import dataclass, field
from pathlib import Path
from typing import Annotated, Any

from pydantic import AfterValidator, BaseModel, ConfigDict, Field, StringConstraints
from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from campus.core import clock
from campus.core.db import NAME_MAX_LENGTH, Entity
from campus.modules.university.models import (
    CODE_MAX_LENGTH,
    CODE_PATTERN,
    DOMAIN_MAX_LENGTH,
    DOMAIN_PATTERN,
    AccountType,
    City,
    Dormitory,
    EmailDomain,
    Faculty,
    check_timezone,
)

DEFAULT_SEED_FILE = Path(__file__).with_name("seed.toml")

Code = Annotated[
    str, StringConstraints(pattern=CODE_PATTERN, max_length=CODE_MAX_LENGTH)
]
Name = Annotated[
    str,
    StringConstraints(strip_whitespace=True, min_length=1, max_length=NAME_MAX_LENGTH),
]


class _Strict(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)


class PlaceSeed(_Strict):
    """A dormitory or faculty; its code is unique within the city."""

    code: Code
    name_ru: Name
    name_en: Name


def _unique_codes(places: list[PlaceSeed]) -> list[PlaceSeed]:
    codes = [place.code for place in places]
    if len(codes) != len(set(codes)):
        msg = "codes must be unique within a city"
        raise ValueError(msg)
    return places


Places = Annotated[list[PlaceSeed], AfterValidator(_unique_codes)]


class CitySeed(_Strict):
    code: Code
    name_ru: Name
    name_en: Name
    timezone: Annotated[str, AfterValidator(check_timezone)]
    dormitories: Places = []
    faculties: Places = []


class EmailDomainSeed(_Strict):
    domain: Annotated[
        str,
        StringConstraints(pattern=DOMAIN_PATTERN, max_length=DOMAIN_MAX_LENGTH),
    ]
    account_type: AccountType


class ReferenceData(_Strict):
    """Contents of a seed file."""

    cities: list[CitySeed] = Field(default_factory=list)
    email_domains: list[EmailDomainSeed] = Field(default_factory=list)


def read_seed_file(path: Path = DEFAULT_SEED_FILE) -> ReferenceData:
    """Parse and validate a seed file; raises ``ValueError`` if invalid."""
    with path.open("rb") as seed_file:
        return ReferenceData.model_validate(tomllib.load(seed_file))


@dataclass(slots=True)
class SeedReport:
    """Rows created by a load, per table; existing rows are not counted."""

    created: dict[str, int] = field(default_factory=dict)

    def add(self, table: str, count: int) -> None:
        self.created[table] = self.created.get(table, 0) + count


async def _insert_missing(
    session: AsyncSession,
    model: type[Entity],
    key: list[str],
    values: dict[str, Any],
    report: SeedReport,
) -> None:
    now = clock.now()
    statement = (
        insert(model)
        .values(**values, created_at=now, updated_at=now)
        .on_conflict_do_nothing(index_elements=key)
        .returning(model.id)
    )
    created = (await session.execute(statement)).scalar_one_or_none()
    report.add(model.__tablename__, int(created is not None))


async def seed_reference_data(
    session: AsyncSession, data: ReferenceData | None = None
) -> SeedReport:
    """Add the missing rows of ``data`` (the default seed file if omitted).

    Flushes but does not commit: the caller owns the transaction.
    """
    data = data if data is not None else read_seed_file()
    report = SeedReport()
    for city in data.cities:
        await _insert_missing(
            session,
            City,
            ["code"],
            {
                "code": city.code,
                "name_ru": city.name_ru,
                "name_en": city.name_en,
                "timezone": city.timezone,
            },
            report,
        )
        city_id = (
            await session.execute(select(City.id).where(City.code == city.code))
        ).scalar_one()
        for model, places in ((Dormitory, city.dormitories), (Faculty, city.faculties)):
            for place in places:
                await _insert_missing(
                    session,
                    model,
                    ["city_id", "code"],
                    {"city_id": city_id, **place.model_dump()},
                    report,
                )
    for domain in data.email_domains:
        await _insert_missing(
            session, EmailDomain, ["domain"], domain.model_dump(), report
        )
    return report
