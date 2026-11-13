"""Initial reference data: the default seed file and the campus-seed command."""

import asyncio
from pathlib import Path
from typing import Any

import pytest
from pydantic import ValidationError
from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession

from campus.core.db import DatabaseNotConfiguredError, create_session_factory
from campus.modules.university import (
    AccountType,
    City,
    Dormitory,
    EmailDomain,
    Faculty,
    ReferenceData,
    read_seed_file,
    seed_reference_data,
)
from campus.seed.__main__ import main

TABLES = [City, Dormitory, Faculty, EmailDomain]


async def row_counts(session: AsyncSession) -> dict[str, int]:
    return {
        model.__tablename__: await session.scalar(
            select(func.count()).select_from(model)
        )
        or 0
        for model in TABLES
    }


async def test_default_data_has_hse_campuses(session: AsyncSession) -> None:
    await seed_reference_data(session)
    await session.commit()

    cities = {city.code: city for city in await session.scalars(select(City))}
    assert {code: city.timezone for code, city in cities.items()} == {
        "moscow": "Europe/Moscow",
        "saint-petersburg": "Europe/Moscow",
        "nizhny-novgorod": "Europe/Moscow",
        "perm": "Asia/Yekaterinburg",
    }
    assert cities["perm"].name_ru == "Пермь"
    assert cities["perm"].name_en == "Perm"
    domains = await session.scalars(select(EmailDomain))
    assert {(d.domain, d.account_type) for d in domains} == {
        ("edu.hse.ru", AccountType.STUDENT),
        ("hse.ru", AccountType.EMPLOYEE),
    }
    for model in (Dormitory, Faculty):
        city_ids = set(await session.scalars(select(model.city_id)))
        assert city_ids == {city.id for city in cities.values()}


async def test_first_load_reports_created_rows(session: AsyncSession) -> None:
    report = await seed_reference_data(session)

    assert report.created == await row_counts(session)
    assert report.created["university_city"] == 4


async def test_repeated_load_creates_no_duplicates(session: AsyncSession) -> None:
    await seed_reference_data(session)
    await session.commit()
    counts = await row_counts(session)

    report = await seed_reference_data(session)
    await session.commit()

    assert set(report.created.values()) == {0}
    assert await row_counts(session) == counts


async def test_concurrent_loads_create_no_duplicates(engine: AsyncEngine) -> None:
    sessions = create_session_factory(engine)

    async def load() -> dict[str, int]:
        async with sessions() as session, session.begin():
            return (await seed_reference_data(session)).created

    reports = await asyncio.gather(*(load() for _ in range(4)))

    async with sessions() as session:
        counts = await row_counts(session)
    for table, count in counts.items():
        assert sum(report[table] for report in reports) == count


async def test_repeated_load_keeps_edited_rows(session: AsyncSession) -> None:
    await seed_reference_data(session)
    await session.execute(
        update(City).where(City.code == "perm").values(name_en="Perm Campus")
    )
    await session.commit()

    await seed_reference_data(session)
    await session.commit()

    name = await session.scalar(select(City.name_en).where(City.code == "perm"))
    assert name == "Perm Campus"


async def test_load_adds_new_rows_of_changed_file(session: AsyncSession) -> None:
    await seed_reference_data(session)
    await session.commit()
    data = read_seed_file().model_dump()
    data["cities"][0]["dormitories"].append(
        {"code": "new-dorm", "name_ru": "Новое", "name_en": "New"}
    )

    report = await seed_reference_data(session, ReferenceData.model_validate(data))

    assert report.created["university_dormitory"] == 1
    assert report.created["university_city"] == 0


def city(**changes: Any) -> dict[str, Any]:
    return {
        "code": "moscow",
        "name_ru": "Москва",
        "name_en": "Moscow",
        "timezone": "Europe/Moscow",
    } | changes


DORM = {"code": "dorm-1", "name_ru": "Общежитие", "name_en": "Dormitory"}


@pytest.mark.parametrize(
    ("data", "location"),
    [
        ({"cities": [city(timezone="UTC+3")]}, ("cities", 0, "timezone")),
        ({"cities": [city(timezone="Moscow")]}, ("cities", 0, "timezone")),
        ({"cities": [city(code="Moscow")]}, ("cities", 0, "code")),
        ({"cities": [city(name_en=" ")]}, ("cities", 0, "name_en")),
        ({"cities": [city(name_ru=None)]}, ("cities", 0, "name_ru")),
        ({"cities": [city(dormitories=[DORM, DORM])]}, ("cities", 0, "dormitories")),
        ({"cities": [city(faculties=[DORM | {"code": "A"}])]}, ("cities", 0)),
        ({"cities": [city(region="msk")]}, ("cities", 0, "region")),
        ({"email_domains": [{"domain": "@hse.ru", "account_type": "student"}]}, ()),
        ({"email_domains": [{"domain": "hse.ru", "account_type": "graduate"}]}, ()),
    ],
)
def test_invalid_data_is_rejected(
    data: dict[str, Any], location: tuple[str | int, ...]
) -> None:
    with pytest.raises(ValidationError) as error:
        ReferenceData.model_validate(data)

    assert error.value.errors()[0]["loc"][: len(location)] == location


def test_domain_must_be_lowercase() -> None:
    with pytest.raises(ValidationError, match="pattern"):
        ReferenceData.model_validate(
            {"email_domains": [{"domain": "Edu.HSE.ru", "account_type": "student"}]}
        )


async def test_command_loads_default_data(
    monkeypatch: pytest.MonkeyPatch, database_url: str, session: AsyncSession
) -> None:
    monkeypatch.setenv("CAMPUS_DATABASE_URL", database_url)

    await asyncio.to_thread(main, [])
    await asyncio.to_thread(main, [])

    counts = await row_counts(session)
    assert counts["university_city"] == 4
    assert counts["university_email_domain"] == 2


async def test_command_loads_given_file(
    monkeypatch: pytest.MonkeyPatch,
    database_url: str,
    session: AsyncSession,
    tmp_path: Path,
) -> None:
    monkeypatch.setenv("CAMPUS_DATABASE_URL", database_url)
    seed_file = tmp_path / "university.toml"
    seed_file.write_text(
        '[[cities]]\ncode = "tomsk"\nname_ru = "Томск"\nname_en = "Tomsk"\n'
        'timezone = "Asia/Tomsk"\n',
        encoding="utf-8",
    )

    await asyncio.to_thread(main, ["--university", str(seed_file)])

    assert list(await session.scalars(select(City.code))) == ["tomsk"]


def test_command_rejects_invalid_file(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    monkeypatch.setenv("CAMPUS_DATABASE_URL", "postgresql://u:p@unreachable.invalid/db")
    seed_file = tmp_path / "university.toml"
    seed_file.write_text("[[cities]]\ncode = 'x'\ntimezone = 'Mars/Base'\n")

    with pytest.raises(ValidationError, match="IANA"):
        main(["--university", str(seed_file)])


def test_command_needs_database() -> None:
    with pytest.raises(DatabaseNotConfiguredError):
        main([])
