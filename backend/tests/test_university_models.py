"""University reference data: integrity rules enforced by the model and DB."""

from uuid import UUID, uuid4

import pytest
from sqlalchemy import insert, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from campus.core import clock
from campus.modules.university import (
    AccountType,
    City,
    Dormitory,
    EmailDomain,
    Faculty,
    InvalidTimezoneError,
    check_timezone,
)
from tests.factories import CityFactory

MISSING_CITY = UUID("0192f0c4-0000-7000-8000-000000000000")


@pytest.mark.parametrize("model", [Dormitory, Faculty])
async def test_place_of_missing_city_is_rejected(
    session: AsyncSession, model: type[Dormitory | Faculty]
) -> None:
    session.add(
        model(city_id=MISSING_CITY, code="dorm-1", name_ru="Корпус", name_en="Hall")
    )

    with pytest.raises(IntegrityError, match="fk_university_"):
        await session.flush()


@pytest.mark.parametrize("model", [Dormitory, Faculty])
async def test_place_belongs_to_existing_city(
    session: AsyncSession, model: type[Dormitory | Faculty]
) -> None:
    city = await CityFactory.create_async()
    session.add(model(city_id=city.id, code="main", name_ru="Главное", name_en="Main"))
    await session.commit()

    place = await session.scalar(select(model))
    assert place is not None
    assert place.city_id == city.id
    assert place.name_in("ru") == "Главное"
    assert place.name_in("en") == "Main"


@pytest.mark.parametrize("model", [Dormitory, Faculty])
async def test_city_with_places_cannot_be_deleted(
    session: AsyncSession, model: type[Dormitory | Faculty]
) -> None:
    city = await CityFactory.create_async()
    session.add(model(city_id=city.id, code="main", name_ru="Корпус", name_en="Hall"))
    await session.flush()

    await session.delete(city)
    with pytest.raises(IntegrityError, match="fk_university_"):
        await session.flush()


@pytest.mark.parametrize(
    "timezone", ["Europe/Moscow", "Asia/Yekaterinburg", "UTC", "America/New_York"]
)
def test_iana_timezone_is_accepted(timezone: str) -> None:
    assert check_timezone(timezone) == timezone
    city = City(code="c", name_ru="Г", name_en="C", timezone=timezone)
    assert city.timezone == timezone


@pytest.mark.parametrize(
    "timezone",
    ["", "Moscow", "europe/moscow", "UTC+3", "MSK", "+03:00", "Europe/Atlantis"],
)
def test_non_iana_timezone_is_rejected(timezone: str) -> None:
    with pytest.raises(InvalidTimezoneError, match="IANA"):
        check_timezone(timezone)
    with pytest.raises(InvalidTimezoneError):
        City(code="c", name_ru="Г", name_en="C", timezone=timezone)


@pytest.mark.usefixtures("session")
async def test_timezone_change_is_checked() -> None:
    city = await CityFactory.create_async()

    with pytest.raises(InvalidTimezoneError):
        city.timezone = "Mars/Olympus"
    assert city.timezone == "Europe/Moscow"


@pytest.mark.parametrize("code", ["Moscow", "moscow city", "-moscow", "a--b", ""])
async def test_code_format_is_checked_by_database(
    session: AsyncSession, code: str
) -> None:
    statement = insert(City).values(
        id=uuid4(),
        code=code,
        name_ru="Корпус",
        name_en="A",
        timezone="Europe/Moscow",
        **_timestamps(),
    )

    with pytest.raises(IntegrityError, match="ck_university_city_code_format"):
        await session.execute(statement)


@pytest.mark.usefixtures("session")
async def test_city_code_is_unique() -> None:
    await CityFactory.create_async(code="moscow")

    with pytest.raises(IntegrityError, match="uq_university_city_code"):
        await CityFactory.create_async(code="moscow")


async def test_place_code_is_unique_within_city(session: AsyncSession) -> None:
    moscow, perm = await CityFactory.create_batch_async(2)
    for city in (moscow, perm):
        session.add(
            Dormitory(city_id=city.id, code="dorm-1", name_ru="Корпус", name_en="Hall")
        )
    await session.flush()

    session.add(Dormitory(city_id=perm.id, code="dorm-1", name_ru="Б", name_en="B"))
    with pytest.raises(IntegrityError, match="uq_university_dormitory_city_id_code"):
        await session.flush()


@pytest.mark.parametrize(
    ("domain", "constraint"),
    [
        ("HSE.ru", "ck_university_email_domain_domain_format"),
        ("hse", "ck_university_email_domain_domain_format"),
        ("@hse.ru", "ck_university_email_domain_domain_format"),
        ("-hse.ru", "ck_university_email_domain_domain_format"),
    ],
)
async def test_domain_format_is_checked_by_database(
    session: AsyncSession, domain: str, constraint: str
) -> None:
    session.add(EmailDomain(domain=domain, account_type=AccountType.STUDENT))

    with pytest.raises(IntegrityError, match=constraint):
        await session.flush()


async def test_domain_is_unique(session: AsyncSession) -> None:
    session.add(EmailDomain(domain="hse.ru", account_type=AccountType.EMPLOYEE))
    await session.flush()

    session.add(EmailDomain(domain="hse.ru", account_type=AccountType.STUDENT))
    with pytest.raises(IntegrityError, match="uq_university_email_domain_domain"):
        await session.flush()


async def test_account_type_is_checked_by_database(session: AsyncSession) -> None:
    statement = insert(EmailDomain).values(
        id=uuid4(), domain="hse.ru", account_type="graduate", **_timestamps()
    )

    with pytest.raises(IntegrityError, match="ck_university_email_domain_account"):
        await session.execute(statement)


def _timestamps() -> dict[str, object]:
    now = clock.now()
    return {"created_at": now, "updated_at": now}
