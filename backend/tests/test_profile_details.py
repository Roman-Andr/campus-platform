"""Skills and name changes of the profile, on PostgreSQL and Redis."""

import asyncio
from datetime import datetime, timedelta
from typing import Any
from uuid import UUID, uuid4

import httpx2
import pytest
import time_machine
from sqlalchemy import delete, func, select, text, update
from sqlalchemy.exc import DBAPIError
from sqlalchemy.sql.expression import Executable

from campus.core import clock
from campus.modules.identity import NameChange, SkillTag, seed_skill_tags
from tests.test_identity import Auth
from tests.test_profile import Account, auth, employee, student

__all__ = ["auth", "employee", "student"]


async def call(  # noqa: PLR0913 - request parts
    account: Account,
    method: str,
    path: str,
    data: dict[str, Any] | None = None,
    *,
    language: str = "en",
    key: str | None = None,
) -> httpx2.Response:
    headers = {"Accept-Language": language, **account.headers}
    if method != "GET":
        headers["Idempotency-Key"] = key or str(uuid4())
    return await account.auth.client.request(
        method, "/api/v1" + path, json=data, headers=headers
    )


@pytest.fixture
async def tags(auth: Auth) -> dict[str, str]:
    """Seeded skill tags by code."""
    assert await seed_skill_tags(auth.db) > 0
    assert await seed_skill_tags(auth.db) == 0
    await auth.db.commit()
    rows = await auth.db.execute(select(SkillTag.code, SkillTag.id))
    return {code: str(tag_id) for code, tag_id in rows}


async def rename(
    account: Account, first: str, last: str, **kwargs: Any
) -> httpx2.Response:
    return await call(
        account, "PUT", "/me/name", {"first_name": first, "last_name": last}, **kwargs
    )


def instant(value: str) -> datetime:
    return datetime.fromisoformat(value)


# Skill tags


async def test_tags_are_named_and_searched_in_request_language(
    student: Account, tags: dict[str, str]
) -> None:
    response = await call(student, "GET", "/skill-tags?q=гит", language="ru")
    assert response.status_code == 200, response.text
    assert response.headers["Content-Language"] == "ru"
    assert response.json()["items"] == [
        {"id": tags["guitar"], "code": "guitar", "name": "Гитара"}
    ]
    response = await call(student, "GET", "/skill-tags?q=GUI", language="en")
    assert response.json()["items"] == [
        {"id": tags["guitar"], "code": "guitar", "name": "Guitar"}
    ]
    # A prefix of the other language's name does not match.
    assert (await call(student, "GET", "/skill-tags?q=gui", language="ru")).json()[
        "items"
    ] == []
    # Only prefixes match, and LIKE wildcards are literal.
    assert (await call(student, "GET", "/skill-tags?q=itar")).json()["items"] == []
    assert (await call(student, "GET", "/skill-tags?q=%25")).json()["items"] == []


async def test_tags_are_listed_by_name_with_a_limit(
    student: Account, tags: dict[str, str]
) -> None:
    response = await call(student, "GET", "/skill-tags?limit=500")
    names = [tag["name"] for tag in response.json()["items"]]
    assert len(names) == len(tags)
    assert names == sorted(names, key=str.lower)
    response = await call(student, "GET", "/skill-tags?limit=3")
    assert len(response.json()["items"]) == 3
    assert (await call(student, "GET", "/skill-tags?limit=0")).status_code == 422


async def test_tags_require_sign_in(auth: Auth) -> None:
    assert (await auth.client.get("/api/v1/skill-tags")).status_code == 401
    assert (await auth.client.get("/api/v1/me/skills")).status_code == 401


# Skills of the profile


async def test_set_and_replace_skills(student: Account, tags: dict[str, str]) -> None:
    empty = await call(student, "GET", "/me/skills")
    assert empty.json() == {"can": [], "wants": []}
    data = {
        "can": [tags["python"], tags["guitar"], tags["python"]],
        "wants": [tags["chess"]],
    }
    response = await call(student, "PUT", "/me/skills", data, language="ru")
    assert response.status_code == 200, response.text
    skills = response.json()
    assert [tag["name"] for tag in skills["can"]] == ["Python", "Гитара"]
    assert [tag["code"] for tag in skills["wants"]] == ["chess"]
    assert (await call(student, "GET", "/me/skills", language="ru")).json() == skills
    response = await call(
        student, "PUT", "/me/skills", {"can": [], "wants": [tags["guitar"]]}
    )
    assert response.json() == {
        "can": [],
        "wants": [{"id": tags["guitar"], "code": "guitar", "name": "Guitar"}],
    }


async def test_skills_only_from_the_reference(
    student: Account, tags: dict[str, str]
) -> None:
    await call(student, "PUT", "/me/skills", {"can": [tags["chess"]], "wants": []})
    response = await call(
        student,
        "PUT",
        "/me/skills",
        {"can": [tags["python"], str(uuid4())], "wants": [str(uuid4())]},
        language="ru",
    )
    assert response.status_code == 422, response.text
    body = response.json()
    assert body["code"] == "validation_failed"
    assert {(e["pointer"], e["code"]) for e in body["errors"]} == {
        ("#/can/1", "not_found"),
        ("#/wants/0", "not_found"),
    }
    assert body["errors"][0]["detail"] == "Такого навыка нет в справочнике."
    # Nothing changed.
    skills = (await call(student, "GET", "/me/skills")).json()
    assert [tag["code"] for tag in skills["can"]] == ["chess"]
    response = await call(student, "PUT", "/me/skills", {"can": ["guitar"]})
    assert response.status_code == 422


async def test_skill_lists_are_limited(
    auth: Auth, student: Account, tags: dict[str, str]
) -> None:
    auth.app.state.settings = auth.settings.model_copy(update={"profile_skills_max": 2})
    ids = list(tags.values())
    response = await call(student, "PUT", "/me/skills", {"can": ids[:3], "wants": []})
    assert response.status_code == 422
    assert response.json()["errors"][0]["pointer"] == "#/can"
    response = await call(
        student, "PUT", "/me/skills", {"can": ids[:2], "wants": ids[:2]}
    )
    assert response.status_code == 200, response.text


async def test_skills_are_per_user(
    student: Account, employee: Account, tags: dict[str, str]
) -> None:
    await call(student, "PUT", "/me/skills", {"can": [tags["chess"]], "wants": []})
    await call(employee, "PUT", "/me/skills", {"can": [], "wants": [tags["yoga"]]})
    assert [
        t["code"] for t in (await call(student, "GET", "/me/skills")).json()["can"]
    ] == ["chess"]
    assert (await call(employee, "GET", "/me/skills")).json()["can"] == []


async def test_parallel_replacements_keep_one_whole_set(
    student: Account, tags: dict[str, str]
) -> None:
    first = {"can": [tags["chess"], tags["yoga"]], "wants": [tags["python"]]}
    second = {"can": [tags["guitar"]], "wants": [tags["sql"], tags["excel"]]}
    responses = await asyncio.gather(
        *(call(student, "PUT", "/me/skills", data) for data in [first, second] * 5)
    )
    assert {response.status_code for response in responses} == {200}
    skills = (await call(student, "GET", "/me/skills")).json()
    result = {
        "can": sorted(tag["id"] for tag in skills["can"]),
        "wants": sorted(tag["id"] for tag in skills["wants"]),
    }
    assert result in (
        {key: sorted(value) for key, value in first.items()},
        {key: sorted(value) for key, value in second.items()},
    )


async def test_idempotent_skill_replacement(
    student: Account, tags: dict[str, str]
) -> None:
    key = str(uuid4())
    data = {"can": [tags["chess"]], "wants": []}
    first = await call(student, "PUT", "/me/skills", data, key=key)
    replay = await call(student, "PUT", "/me/skills", data, key=key)
    assert replay.headers["Idempotent-Replayed"] == "true"
    assert replay.json() == first.json()


# Name changes


async def test_name_change_is_recorded(auth: Auth, student: Account) -> None:
    me = (await student.me()).json()
    assert me["name_change_available_at"] is None
    response = await rename(student, " Пётр ", "Сидоров-Иванов")
    assert response.status_code == 200, response.text
    user = response.json()
    assert (user["first_name"], user["last_name"]) == ("Пётр", "Сидоров-Иванов")
    available_at = instant(user["name_change_available_at"])
    assert available_at - clock.now() > timedelta(days=89, hours=23)
    changes = (
        await auth.db.scalars(
            select(NameChange).where(NameChange.user_id == UUID(user["id"]))
        )
    ).all()
    assert [
        (c.old_first_name, c.old_last_name, c.new_first_name, c.new_last_name)
        for c in changes
    ] == [("Иван", "O'Neil", "Пётр", "Сидоров-Иванов")]
    assert changes[0].created_at + timedelta(days=90) == available_at


async def test_name_change_at_most_once_in_90_days(
    auth: Auth, student: Account
) -> None:
    start = clock.now()
    with time_machine.travel(start, tick=False):
        assert (await rename(student, "Пётр", "Петров")).status_code == 200
    with time_machine.travel(start + timedelta(days=90, seconds=-1), tick=False):
        student.tokens = await auth.login()
        response = await rename(student, "Павел", "Павлов", language="ru")
        assert response.status_code == 409, response.text
        problem = response.json()
        assert problem["code"] == "name_change_too_soon"
        assert instant(problem["available_at"]) == start + timedelta(days=90)
        assert "90" in problem["detail"]
        assert (await student.me()).json()["first_name"] == "Пётр"
    with time_machine.travel(start + timedelta(days=90), tick=False):
        student.tokens = await auth.login()
        assert (await student.me()).json()["name_change_available_at"] is None
        response = await rename(student, "Павел", "Павлов")
        assert response.status_code == 200, response.text
    count = await auth.db.scalar(select(func.count()).select_from(NameChange))
    assert count == 2


async def test_interval_is_configured(auth: Auth, student: Account) -> None:
    auth.app.state.settings = auth.settings.model_copy(
        update={"name_change_interval": timedelta(0)}
    )
    assert (await rename(student, "Пётр", "Петров")).status_code == 200
    assert (await rename(student, "Павел", "Павлов")).status_code == 200


async def test_same_name_changes_nothing(auth: Auth, student: Account) -> None:
    response = await rename(student, "Иван", "O'Neil")
    assert response.status_code == 200
    assert response.json()["name_change_available_at"] is None
    assert await auth.db.scalar(select(func.count()).select_from(NameChange)) == 0


@pytest.mark.parametrize(
    "data",
    [
        {"first_name": "", "last_name": "Петров"},
        {"first_name": "R2-D2", "last_name": "Петров"},
        {"first_name": "Пётр"},
        {"first_name": "Пётр", "last_name": "Петров", "email": "x@y.z"},
        {"first_name": "П" * 101, "last_name": "Петров"},
    ],
)
async def test_invalid_names_are_rejected(
    auth: Auth, student: Account, data: dict[str, Any]
) -> None:
    response = await call(student, "PUT", "/me/name", data)
    assert response.status_code == 422, response.text
    assert await auth.db.scalar(select(func.count()).select_from(NameChange)) == 0


async def test_name_change_requires_sign_in(auth: Auth) -> None:
    response = await auth.client.put(
        "/api/v1/me/name",
        json={"first_name": "Пётр", "last_name": "Петров"},
        headers={"Idempotency-Key": str(uuid4())},
    )
    assert response.status_code == 401


async def test_parallel_name_changes_record_one(auth: Auth, student: Account) -> None:
    responses = await asyncio.gather(
        *(
            rename(student, name, "Петров")
            for name in ["Пётр", "Павел", "Олег", "Анна", "Мария", "Ольга"]
        )
    )
    assert sorted(r.status_code for r in responses).count(200) == 1
    assert {r.status_code for r in responses} == {200, 409}
    change = await auth.db.scalar(select(NameChange))
    assert change is not None
    assert (await student.me()).json()["first_name"] == change.new_first_name


async def test_name_history_cannot_be_changed_or_deleted(
    auth: Auth, student: Account
) -> None:
    await rename(student, "Пётр", "Петров")
    statements: list[Executable] = [
        update(NameChange).values(new_first_name="Подделка"),
        delete(NameChange),
        text("TRUNCATE identity_name_change"),
    ]
    for statement in statements:
        with pytest.raises(DBAPIError, match="append-only"):
            await auth.db.execute(statement)
        await auth.db.rollback()
    change = await auth.db.scalar(select(NameChange))
    assert change is not None
    assert change.new_first_name == "Пётр"
