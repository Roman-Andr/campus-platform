"""Read API of the university reference data."""

from typing import Any

import httpx2
import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from campus.api.app import API_PREFIX
from campus.modules.university import seed_reference_data

URL = f"{API_PREFIX}/university"


@pytest.fixture
async def seeded(session: AsyncSession) -> None:
    await seed_reference_data(session)
    await session.commit()


async def get_items(
    api: httpx2.AsyncClient, path: str, language: str | None = None, **params: Any
) -> list[dict[str, Any]]:
    headers = {"Accept-Language": language} if language else {}
    response = await api.get(f"{URL}/{path}", headers=headers, params=params)
    assert response.status_code == 200, response.text
    items: list[dict[str, Any]] = response.json()["items"]
    return items


@pytest.mark.usefixtures("seeded")
@pytest.mark.parametrize(
    ("language", "names"),
    [
        ("en", ["Moscow", "Nizhny Novgorod", "Perm", "Saint Petersburg"]),
        ("en-US,ru;q=0.5", ["Moscow", "Nizhny Novgorod", "Perm", "Saint Petersburg"]),
        ("ru", ["Москва", "Нижний Новгород", "Пермь", "Санкт-Петербург"]),
        (None, ["Москва", "Нижний Новгород", "Пермь", "Санкт-Петербург"]),
        ("de", ["Москва", "Нижний Новгород", "Пермь", "Санкт-Петербург"]),
    ],
)
async def test_cities_are_named_in_request_language(
    api: httpx2.AsyncClient, language: str | None, names: list[str]
) -> None:
    cities = await get_items(api, "cities", language)

    assert [city["name"] for city in cities] == names


@pytest.mark.usefixtures("seeded")
async def test_city_has_code_and_timezone(api: httpx2.AsyncClient) -> None:
    cities = await get_items(api, "cities", "en")

    perm = next(city for city in cities if city["code"] == "perm")
    assert perm["timezone"] == "Asia/Yekaterinburg"
    assert set(perm) == {"id", "code", "name", "timezone"}


@pytest.mark.usefixtures("seeded")
@pytest.mark.parametrize("language", ["ru", "en"])
async def test_response_states_its_language(
    api: httpx2.AsyncClient, language: str
) -> None:
    for path in ("cities", "dormitories", "faculties"):
        response = await api.get(f"{URL}/{path}", headers={"Accept-Language": language})

        assert response.headers["Content-Language"] == language
        assert response.headers["Vary"] == "Accept-Language"


@pytest.mark.usefixtures("seeded")
@pytest.mark.parametrize(
    ("path", "language", "name"),
    [
        ("dormitories", "ru", "Общежитие «Дубки»"),
        ("dormitories", "en", "Dubki Dormitory"),
        ("faculties", "ru", "Факультет компьютерных наук"),
        ("faculties", "en", "Faculty of Computer Science"),
    ],
)
async def test_places_are_named_in_request_language(
    api: httpx2.AsyncClient, path: str, language: str, name: str
) -> None:
    places = await get_items(api, path, language)

    assert name in [place["name"] for place in places]


@pytest.mark.usefixtures("seeded")
@pytest.mark.parametrize("path", ["dormitories", "faculties"])
async def test_places_are_filtered_by_city(api: httpx2.AsyncClient, path: str) -> None:
    cities = {city["code"]: city["id"] for city in await get_items(api, "cities")}
    everything = await get_items(api, path)

    by_city = {
        code: await get_items(api, path, city_id=city_id)
        for code, city_id in cities.items()
    }

    assert sum(len(places) for places in by_city.values()) == len(everything)
    for code, places in by_city.items():
        assert places
        assert {place["city_id"] for place in places} == {cities[code]}
        expected_zone = "Asia/Yekaterinburg" if code == "perm" else "Europe/Moscow"
        assert {place["city_timezone"] for place in places} == {expected_zone}


@pytest.mark.usefixtures("seeded")
async def test_places_of_unknown_city_are_empty(api: httpx2.AsyncClient) -> None:
    places = await get_items(
        api, "dormitories", city_id="0192f0c4-0000-7000-8000-000000000000"
    )

    assert places == []


async def test_invalid_city_filter_is_a_problem(api: httpx2.AsyncClient) -> None:
    response = await api.get(
        f"{URL}/faculties",
        params={"city_id": "moscow"},
        headers={"Accept-Language": "en"},
    )

    assert response.status_code == 422
    problem = response.json()
    assert problem["code"] == "validation_failed"
    assert problem["errors"] == [
        {"detail": "Must be a UUID.", "code": "uuid_parsing", "parameter": "city_id"}
    ]


@pytest.mark.usefixtures("seeded")
async def test_email_domains_have_account_types(api: httpx2.AsyncClient) -> None:
    domains = await get_items(api, "email-domains")

    assert domains == [
        {"domain": "edu.hse.ru", "account_type": "student"},
        {"domain": "hse.ru", "account_type": "employee"},
    ]


@pytest.mark.parametrize(
    "path", ["cities", "dormitories", "faculties", "email-domains"]
)
async def test_empty_reference_data(api: httpx2.AsyncClient, path: str) -> None:
    assert await get_items(api, path) == []


@pytest.mark.parametrize(
    "path", ["cities", "dormitories", "faculties", "email-domains"]
)
async def test_client_headers_are_required(api: httpx2.AsyncClient, path: str) -> None:
    response = await api.get(
        f"{URL}/{path}",
        headers={"X-Client-Platform": "", "X-Client-Version": ""},
    )

    assert response.status_code == 400
    assert response.json()["code"] == "client_version_missing"
