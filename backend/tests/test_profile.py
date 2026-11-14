"""Profile of the signed-in user: filling in, reference checks and the
"filled profile" requirement, on PostgreSQL and Redis."""

import asyncio
from collections.abc import AsyncIterator
from dataclasses import dataclass
from typing import Any
from uuid import UUID, uuid4

import httpx2
import pytest
from pydantic import SecretStr
from redis.asyncio import Redis
from sqlalchemy import update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from campus.api.app import create_app
from campus.core.config import Settings
from campus.core.db import create_engine, create_session_factory
from campus.core.web import api_router
from campus.modules.identity import ProfiledUser, User, seed_documents
from campus.modules.university import (
    AccountType,
    City,
    Dormitory,
    EmailDomain,
    Faculty,
)
from tests.test_identity import EMAIL, SECRET, Auth
from tests.web_app import serve

STAFF_EMAIL = "teacher@staff.example"


@dataclass
class Places:
    """Reference data of two cities."""

    moscow: UUID
    dubki: UUID
    economics: UUID
    perm: UUID
    perm_dormitory: UUID
    perm_faculty: UUID


@dataclass
class Account:
    auth: Auth
    tokens: dict[str, Any]

    @property
    def headers(self) -> dict[str, str]:
        return {"Authorization": "Bearer " + self.tokens["access_token"]}

    async def me(self) -> httpx2.Response:
        return await self.auth.client.get("/api/v1/me", headers=self.headers)

    async def put(
        self, data: dict[str, Any], key: str | None = None
    ) -> httpx2.Response:
        return await self.auth.client.put(
            "/api/v1/me/profile",
            json=data,
            headers={"Idempotency-Key": key or str(uuid4()), **self.headers},
        )

    async def publish(self) -> httpx2.Response:
        return await publish(self.auth, self.headers)


async def publish(auth: Auth, headers: dict[str, str] | None = None) -> httpx2.Response:
    return await auth.client.post(
        "/api/v1/listings-test",
        headers={"Idempotency-Key": str(uuid4()), **(headers or {})},
    )


@pytest.fixture
async def auth(database_url: str, redis_url: str) -> AsyncIterator[Auth]:
    settings = Settings(
        database_url=SecretStr(database_url),
        redis_url=SecretStr(redis_url),
        auth_secret_key=SecretStr(SECRET),
        profile_max_course=6,
    )
    engine = create_engine(settings)
    async with (
        create_session_factory(engine)() as db,
        Redis.from_url(redis_url) as redis,
    ):
        await redis.flushdb()
        db.add_all(
            [
                EmailDomain(
                    domain="university.example", account_type=AccountType.STUDENT
                ),
                EmailDomain(domain="staff.example", account_type=AccountType.EMPLOYEE),
            ]
        )
        await seed_documents(db)
        await db.commit()
        app = create_app(settings)
        router = api_router()

        # Stands in for publishing and responding, which take ProfiledUser.
        @router.post("/api/v1/listings-test", status_code=201)
        async def create_listing(principal: ProfiledUser) -> dict[str, str]:
            return {"author_id": str(principal.user_id)}

        app.include_router(router)
        async with serve(app) as client:
            yield Auth(client, db, settings, redis, app)
    await engine.dispose()


@pytest.fixture
async def places(auth: Auth) -> Places:
    db = auth.db
    moscow = City(
        code="moscow", name_ru="Москва", name_en="Moscow", timezone="Europe/Moscow"
    )
    perm = City(
        code="perm", name_ru="Пермь", name_en="Perm", timezone="Asia/Yekaterinburg"
    )
    db.add_all([moscow, perm])
    await db.flush()
    dubki = Dormitory(city_id=moscow.id, code="dubki", name_ru="Дубки", name_en="Dubki")
    economics = Faculty(
        city_id=moscow.id, code="economics", name_ru="Экономика", name_en="Economics"
    )
    perm_dormitory = Dormitory(
        city_id=perm.id, code="perm-1", name_ru="Общежитие 1", name_en="Dormitory 1"
    )
    perm_faculty = Faculty(city_id=perm.id, code="law", name_ru="Право", name_en="Law")
    db.add_all([dubki, economics, perm_dormitory, perm_faculty])
    await db.commit()
    return Places(
        moscow=moscow.id,
        dubki=dubki.id,
        economics=economics.id,
        perm=perm.id,
        perm_dormitory=perm_dormitory.id,
        perm_faculty=perm_faculty.id,
    )


@pytest.fixture
async def student(auth: Auth) -> Account:
    return Account(auth, await auth.login())


@pytest.fixture
async def employee(auth: Auth) -> Account:
    return Account(auth, await auth.login(email=STAFF_EMAIL))


def moscow_profile(places: Places, **overrides: Any) -> dict[str, Any]:
    return {
        "city_id": str(places.moscow),
        "dormitory_id": str(places.dubki),
        "faculty_id": str(places.economics),
        "course": 2,
        **overrides,
    }


def pointers(response: httpx2.Response) -> dict[str, str]:
    assert response.status_code == 422, response.text
    body = response.json()
    assert body["code"] == "validation_failed"
    return {error["pointer"]: error["code"] for error in body["errors"]}


async def test_new_account_has_empty_profile(student: Account) -> None:
    assert student.tokens["user"]["profile_complete"] is False
    response = await student.me()
    assert response.status_code == 200
    me = response.json()
    assert me["email"] == EMAIL
    assert me["profile_complete"] is False
    assert [me[f] for f in ("city_id", "dormitory_id", "faculty_id", "course")] == [
        None
    ] * 4


async def test_profile_requires_sign_in(auth: Auth) -> None:
    assert (await auth.client.get("/api/v1/me")).status_code == 401
    response = await auth.client.put(
        "/api/v1/me/profile", json={}, headers={"Idempotency-Key": str(uuid4())}
    )
    assert response.status_code == 401


async def test_fill_in_profile(student: Account, places: Places) -> None:
    response = await student.put(moscow_profile(places))
    assert response.status_code == 200, response.text
    assert response.json()["profile_complete"] is True
    me = (await student.me()).json()
    assert me["city_id"] == str(places.moscow)
    assert me["city_timezone"] == "Europe/Moscow"
    assert me["dormitory_id"] == str(places.dubki)
    assert me["faculty_id"] == str(places.economics)
    assert me["course"] == 2


async def test_no_dormitory(student: Account, places: Places) -> None:
    await student.put(moscow_profile(places))
    response = await student.put(moscow_profile(places, dormitory_id=None))
    assert response.status_code == 200, response.text
    assert response.json()["dormitory_id"] is None
    assert response.json()["profile_complete"] is True
    omitted = moscow_profile(places)
    del omitted["dormitory_id"]
    assert (await student.put(omitted)).json()["dormitory_id"] is None


async def test_change_city(student: Account, places: Places) -> None:
    await student.put(moscow_profile(places))
    response = await student.put(
        {
            "city_id": str(places.perm),
            "dormitory_id": str(places.perm_dormitory),
            "faculty_id": str(places.perm_faculty),
            "course": 3,
        }
    )
    assert response.status_code == 200, response.text
    assert response.json()["city_id"] == str(places.perm)
    assert response.json()["city_timezone"] == "Asia/Yekaterinburg"


@pytest.mark.parametrize(
    ("overrides", "expected"),
    [
        pytest.param(
            {"dormitory_id": "perm_dormitory"},
            {"#/dormitory_id": "not_of_city"},
            id="dormitory-of-other-city",
        ),
        pytest.param(
            {"faculty_id": "perm_faculty"},
            {"#/faculty_id": "not_of_city"},
            id="faculty-of-other-city",
        ),
        pytest.param(
            {"dormitory_id": "perm_dormitory", "faculty_id": "perm_faculty"},
            {"#/dormitory_id": "not_of_city", "#/faculty_id": "not_of_city"},
            id="both-of-other-city",
        ),
        pytest.param(
            {"faculty_id": "unknown"},
            {"#/faculty_id": "not_of_city"},
            id="unknown-faculty",
        ),
        pytest.param(
            {"dormitory_id": "unknown"},
            {"#/dormitory_id": "not_of_city"},
            id="unknown-dormitory",
        ),
        pytest.param(
            {"city_id": "unknown"}, {"#/city_id": "not_found"}, id="unknown-city"
        ),
        pytest.param(
            {"city_id": "perm"},
            {"#/dormitory_id": "not_of_city", "#/faculty_id": "not_of_city"},
            id="places-of-other-city",
        ),
    ],
)
async def test_places_only_of_the_city(
    student: Account,
    places: Places,
    overrides: dict[str, str],
    expected: dict[str, str],
) -> None:
    values = {
        field: str(uuid4()) if name == "unknown" else str(getattr(places, name))
        for field, name in overrides.items()
    }
    response = await student.put(moscow_profile(places, **values))
    assert pointers(response) == expected
    assert (await student.me()).json()["profile_complete"] is False


@pytest.mark.parametrize(
    ("course", "expected"),
    [
        (None, {"#/course": "missing"}),
        (7, {"#/course": "less_than_equal"}),
        (0, {"#/course": "greater_than_equal"}),
    ],
)
async def test_student_course(
    student: Account, places: Places, course: int | None, expected: dict[str, str]
) -> None:
    response = await student.put(moscow_profile(places, course=course))
    assert pointers(response) == expected


async def test_highest_course(student: Account, places: Places) -> None:
    response = await student.put(moscow_profile(places, course=6))
    assert response.status_code == 200, response.text


async def test_employee_has_no_course(employee: Account, places: Places) -> None:
    response = await employee.put(moscow_profile(places, course=1))
    assert pointers(response) == {"#/course": "not_allowed"}
    response = await employee.put(moscow_profile(places, course=None))
    assert response.status_code == 200, response.text
    assert response.json()["profile_complete"] is True


async def test_errors_are_localized(student: Account, places: Places) -> None:
    response = await student.auth.client.put(
        "/api/v1/me/profile",
        json=moscow_profile(places, faculty_id=str(places.perm_faculty)),
        headers={
            "Idempotency-Key": str(uuid4()),
            "Accept-Language": "ru",
            **student.headers,
        },
    )
    assert response.json()["errors"][0]["detail"] == (
        "Должно относиться к выбранному городу."
    )


async def test_unknown_fields_are_rejected(student: Account, places: Places) -> None:
    response = await student.put(moscow_profile(places, photo="x"))
    assert pointers(response) == {"#/photo": "extra_forbidden"}


async def test_publishing_requires_filled_profile(
    auth: Auth, student: Account, employee: Account, places: Places
) -> None:
    """Who may publish: anonymous, without profile, with profile."""
    assert (await publish(auth)).status_code == 401
    response = await student.publish()
    assert response.status_code == 403
    assert response.json()["code"] == "profile_incomplete"
    await student.put(moscow_profile(places))
    response = await student.publish()
    assert response.status_code == 201, response.text
    assert response.json() == {"author_id": student.tokens["user"]["id"]}
    assert (await employee.publish()).status_code == 403
    await employee.put(moscow_profile(places, course=None))
    assert (await employee.publish()).status_code == 201


async def test_same_profile_on_another_device(auth: Auth, places: Places) -> None:
    first = Account(auth, await auth.login())
    await first.put(moscow_profile(places, dormitory_id=None, course=4))
    second = Account(auth, await auth.login(device_id=str(uuid4())))
    assert second.tokens["user"] == (await first.me()).json()
    assert (await second.me()).json() == (await first.me()).json()
    assert second.tokens["user"]["profile_complete"] is True
    assert (await second.publish()).status_code == 201


async def test_idempotent_update(student: Account, places: Places) -> None:
    key = str(uuid4())
    first = await student.put(moscow_profile(places), key)
    await student.put(moscow_profile(places, course=5))
    replay = await student.put(moscow_profile(places), key)
    assert replay.headers["Idempotent-Replayed"] == "true"
    assert replay.json() == first.json()
    assert (await student.me()).json()["course"] == 5


async def test_parallel_updates_keep_places_of_one_city(
    student: Account, places: Places
) -> None:
    moscow = moscow_profile(places)
    perm = {
        "city_id": str(places.perm),
        "dormitory_id": str(places.perm_dormitory),
        "faculty_id": str(places.perm_faculty),
        "course": 1,
    }
    responses = await asyncio.gather(
        *(student.put(profile) for profile in [moscow, perm] * 5)
    )
    assert {response.status_code for response in responses} == {200}
    me = (await student.me()).json()
    assert {key: me[key] for key in moscow} in (moscow, perm)


async def test_database_rejects_places_of_other_city(
    auth: Auth, student: Account, places: Places
) -> None:
    db: AsyncSession = auth.db
    user_id = UUID(student.tokens["user"]["id"])
    statements: list[dict[str, Any]] = [
        {"city_id": places.moscow, "faculty_id": places.perm_faculty},
        {
            "city_id": places.moscow,
            "faculty_id": places.economics,
            "dormitory_id": places.perm_dormitory,
        },
        {"dormitory_id": places.dubki},
        {"city_id": places.moscow},
        {"city_id": places.moscow, "faculty_id": places.economics, "course": 0},
    ]
    for values in statements:
        with pytest.raises(IntegrityError):
            await db.execute(update(User).where(User.id == user_id).values(**values))
        await db.rollback()
