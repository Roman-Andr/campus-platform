"""Authentication acceptance and concurrency tests on PostgreSQL and Redis."""

import asyncio
import re
from collections.abc import AsyncIterator
from dataclasses import dataclass
from datetime import timedelta
from typing import Any
from uuid import UUID, uuid4

import httpx2
import jwt
import pytest
import time_machine
from fastapi import Request
from pydantic import SecretStr, ValidationError
from redis.asyncio import Redis
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from campus.api.app import create_app
from campus.core import clock
from campus.core.config import Settings
from campus.core.db import create_engine, create_session_factory
from campus.core.idempotency import store_response
from campus.core.logging import configure_logging
from campus.core.outbox import OutboxMessage
from campus.core.web import api_router
from campus.core.web.auth import CurrentUser, digest
from campus.modules.identity import RefreshToken, Session, SignInCode, User
from campus.modules.university import AccountType, EmailDomain
from tests.web_app import serve

EMAIL = "student@university.example"
DEVICE = str(uuid4())
SECRET = "testing-sign-in-secret-at-least-32-characters"  # noqa: S105 - test key


@dataclass
class Auth:
    client: httpx2.AsyncClient
    db: AsyncSession
    settings: Settings
    redis: Redis

    async def post(
        self, path: str, data: dict[str, Any] | None = None, **headers: str
    ) -> httpx2.Response:
        return await self.client.post(
            "/api/v1/auth" + path,
            json=data,
            headers={"Idempotency-Key": str(uuid4()), **headers},
        )

    async def code(self, email: str = EMAIL) -> str:
        response = await self.post("/sign-in-codes", {"email": email})
        assert response.status_code == 202, response.text
        self.db.expire_all()
        message = await self.db.scalar(
            select(OutboxMessage).order_by(OutboxMessage.id.desc()).limit(1)
        )
        assert message is not None
        match = re.search(r"\b[0-9]{6}\b", message.payload["text"])
        assert match is not None
        await self.db.rollback()
        return match[0]

    async def login(self, **overrides: Any) -> dict[str, Any]:
        code = await self.code(overrides.get("email", EMAIL))
        response = await self.post(
            "/sign-in",
            {
                "email": EMAIL,
                "code": code,
                "device_id": DEVICE,
                "first_name": "Иван",
                "last_name": "O'Neil",
                **overrides,
            },
        )
        assert response.status_code == 200, response.text
        result: dict[str, Any] = response.json()
        return result


@pytest.fixture
async def auth(database_url: str, redis_url: str) -> AsyncIterator[Auth]:
    settings = Settings(
        database_url=SecretStr(database_url),
        redis_url=SecretStr(redis_url),
        auth_secret_key=SecretStr(SECRET),
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
        await db.commit()
        app = create_app(settings)
        router = api_router()

        @router.get("/api/v1/private")
        async def private(principal: CurrentUser, request: Request) -> dict[str, str]:
            assert request.state.principal == principal
            return {"user_id": str(principal.user_id)}

        app.include_router(router)
        async with serve(app) as client:
            yield Auth(client, db, settings, redis)
    await engine.dispose()


@pytest.mark.parametrize(
    ("email", "account_type"),
    [(EMAIL.upper(), "student"), ("teacher@staff.example", "employee")],
)
async def test_registration_and_token_hashes(
    auth: Auth, email: str, account_type: str
) -> None:
    tokens = await auth.login(email=email)
    assert tokens["user"]["email"] == email.lower()
    assert tokens["user"]["account_type"] == account_type
    assert tokens["expires_in"] == 900
    payload = jwt.decode(tokens["access_token"], SECRET, algorithms=["HS256"])
    assert payload["sub"] == tokens["user"]["id"]
    assert payload["sid"]
    challenge = await auth.db.scalar(select(SignInCode))
    assert challenge is not None
    assert challenge.consumed_at
    token = await auth.db.scalar(select(RefreshToken))
    assert token is not None
    assert token.token_hash != tokens["refresh_token"]
    assert (
        timedelta(days=30) - timedelta(seconds=1)
        < (token.expires_at - token.created_at)
        <= timedelta(days=30)
    )
    device = await auth.db.get(Session, UUID(payload["sid"]))
    assert device is not None
    assert device.platform == "android"


@pytest.mark.parametrize(
    "email",
    [
        "a@external.example",
        "a@sub.university.example",
        "a@university.example.evil.example",
    ],
)
async def test_domain_exact_match(auth: Auth, email: str) -> None:
    response = await auth.post("/sign-in-codes", {"email": email})
    assert response.status_code == 422
    assert response.json()["code"] == "email_domain_not_allowed"
    response = await auth.post(
        "/sign-in", {"email": email, "code": "123456", "device_id": DEVICE}
    )
    assert response.status_code == 422
    assert await auth.db.scalar(select(User)) is None
    assert await auth.db.scalar(select(OutboxMessage)) is None


async def test_registration_required_does_not_consume_code(auth: Auth) -> None:
    code = await auth.code()
    data = {"email": EMAIL, "code": code, "device_id": DEVICE}
    response = await auth.post("/sign-in", data)
    assert response.json()["code"] == "registration_required"
    response = await auth.post(
        "/sign-in", {**data, "first_name": "Anna-Maria", "last_name": "Smith"}
    )
    assert response.status_code == 200
    assert (await auth.post("/sign-in", data)).json()["code"] == "sign_in_code_expired"


@pytest.mark.parametrize("name", ["123", "a@example.com", "   ", "<script>", "--"])
async def test_names_are_real_name_characters(auth: Auth, name: str) -> None:
    response = await auth.post(
        "/sign-in",
        {"email": EMAIL, "code": "123456", "device_id": DEVICE, "first_name": name},
    )
    assert response.status_code == 422
    assert response.json()["code"] == "validation_failed"
    assert response.json()["errors"][0]["detail"] == "Неверный формат."


async def test_unknown_and_expired_code(auth: Auth) -> None:
    data = {"email": EMAIL, "code": "123456", "device_id": DEVICE}
    assert (await auth.post("/sign-in", data)).json()["code"] == "sign_in_code_expired"
    with time_machine.travel(clock.now(), tick=False) as travel:
        code = await auth.code()
        travel.shift(timedelta(minutes=10))
        response = await auth.post("/sign-in", {**data, "code": code})
        assert response.json()["code"] == "sign_in_code_expired"


async def test_parallel_attempts_are_bounded_and_resend_resets(auth: Auth) -> None:
    code = await auth.code()
    wrong = "000000" if code != "000000" else "111111"
    responses = await asyncio.gather(
        *(
            auth.post("/sign-in", {"email": EMAIL, "code": wrong, "device_id": DEVICE})
            for _ in range(10)
        )
    )
    codes = [r.json()["code"] for r in responses]
    assert codes.count("sign_in_code_invalid") == 5
    assert codes.count("sign_in_code_attempts_exceeded") == 5
    challenge = await auth.db.scalar(select(SignInCode))
    assert challenge is not None
    assert challenge.attempts == 5
    await auth.db.rollback()
    assert (
        await auth.post("/sign-in", {"email": EMAIL, "code": code, "device_id": DEVICE})
    ).json()["code"] == "sign_in_code_attempts_exceeded"
    assert (await auth.login())["user"]["email"] == EMAIL


async def test_parallel_code_consumption(auth: Auth) -> None:
    code = await auth.code()
    data = {
        "email": EMAIL,
        "code": code,
        "device_id": DEVICE,
        "first_name": "John",
        "last_name": "Smith",
    }
    responses = await asyncio.gather(*(auth.post("/sign-in", data) for _ in range(2)))
    assert sorted(r.status_code for r in responses) == [200, 401]
    assert len((await auth.db.scalars(select(User))).all()) == 1
    assert len((await auth.db.scalars(select(Session))).all()) == 1


async def test_resend_invalidates_previous_code(auth: Auth) -> None:
    old = await auth.code()
    new = await auth.code()
    challenge = await auth.db.scalar(select(SignInCode))
    assert challenge is not None
    assert challenge.code_hash == digest(auth.settings, EMAIL + ":" + new)
    assert challenge.code_hash != new
    if old != new:
        response = await auth.post(
            "/sign-in", {"email": EMAIL, "code": old, "device_id": DEVICE}
        )
        assert response.json()["code"] == "sign_in_code_invalid"


async def test_refresh_rotation_and_reuse_revokes_entire_chain(auth: Auth) -> None:
    first = await auth.login()
    second_response = await auth.post(
        "/token/refresh", {"refresh_token": first["refresh_token"], "device_id": DEVICE}
    )
    assert second_response.status_code == 200
    second = second_response.json()
    assert second["refresh_token"] != first["refresh_token"]
    third = (
        await auth.post(
            "/token/refresh",
            {"refresh_token": second["refresh_token"], "device_id": DEVICE},
        )
    ).json()
    assert "access_token" in third
    replay = await auth.post(
        "/token/refresh", {"refresh_token": first["refresh_token"], "device_id": DEVICE}
    )
    assert replay.status_code == 401
    for tokens in (first, second, third):
        response = await auth.client.get(
            "/api/v1/private",
            headers={"Authorization": "Bearer " + tokens["access_token"]},
        )
        assert response.status_code == 401
        response = await auth.post(
            "/token/refresh",
            {"refresh_token": tokens["refresh_token"], "device_id": DEVICE},
        )
        assert response.status_code == 401
    device = await auth.db.scalar(select(Session))
    assert device is not None
    assert device.revoked_at
    assert await auth.redis.exists(f"auth:revoked:{device.id}")


async def test_parallel_refresh_revokes_winning_descendant(auth: Auth) -> None:
    tokens = await auth.login()
    data = {"refresh_token": tokens["refresh_token"], "device_id": DEVICE}
    responses = await asyncio.gather(
        auth.post("/token/refresh", data), auth.post("/token/refresh", data)
    )
    assert sorted(r.status_code for r in responses) == [200, 401]
    winner = next(r.json() for r in responses if r.status_code == 200)
    assert (
        await auth.post(
            "/token/refresh", {**data, "refresh_token": winner["refresh_token"]}
        )
    ).status_code == 401


async def test_wrong_device_revokes_session(auth: Auth) -> None:
    tokens = await auth.login()
    response = await auth.post(
        "/token/refresh",
        {"refresh_token": tokens["refresh_token"], "device_id": str(uuid4())},
    )
    assert response.status_code == 401
    assert (
        await auth.client.get(
            "/api/v1/private",
            headers={"Authorization": "Bearer " + tokens["access_token"]},
        )
    ).status_code == 401


async def test_refresh_expiration(auth: Auth) -> None:
    with time_machine.travel(clock.now(), tick=False) as travel:
        tokens = await auth.login()
        travel.shift(timedelta(days=30))
        response = await auth.post(
            "/token/refresh",
            {"refresh_token": tokens["refresh_token"], "device_id": DEVICE},
        )
        assert response.status_code == 401
    assert (
        await auth.post(
            "/token/refresh", {"refresh_token": "unknown", "device_id": DEVICE}
        )
    ).status_code == 401


async def test_same_device_sign_in_revokes_previous_session(auth: Auth) -> None:
    first = await auth.login()
    second = await auth.login(first_name=None, last_name=None)
    assert second["user"] == first["user"]
    assert (
        await auth.client.get(
            "/api/v1/private",
            headers={"Authorization": "Bearer " + first["access_token"]},
        )
    ).status_code == 401
    assert (
        await auth.client.get(
            "/api/v1/private",
            headers={"Authorization": "Bearer " + second["access_token"]},
        )
    ).status_code == 200
    assert (
        await auth.post(
            "/token/refresh",
            {"refresh_token": first["refresh_token"], "device_id": DEVICE},
        )
    ).status_code == 401


async def test_access_matrix_and_logout(auth: Auth) -> None:
    assert (await auth.client.get("/api/v1/private")).status_code == 401
    assert (await auth.post("/sign-out")).status_code == 401
    tokens = await auth.login()
    headers = {"Authorization": "Bearer " + tokens["access_token"]}
    response = await auth.client.get("/api/v1/private", headers=headers)
    assert response.json() == {"user_id": tokens["user"]["id"]}
    assert (await auth.post("/sign-out", **headers)).status_code == 204
    assert (await auth.post("/sign-out", **headers)).status_code == 401
    assert (
        await auth.client.get("/api/v1/private", headers=headers)
    ).status_code == 401
    assert (
        await auth.post(
            "/token/refresh",
            {"refresh_token": tokens["refresh_token"], "device_id": DEVICE},
        )
    ).status_code == 401


@pytest.mark.parametrize(
    "authorization",
    [
        "Basic secret",
        "Bearer invalid",
        "Bearer",
        "Bearer "
        + jwt.encode(
            {"sub": str(uuid4()), "sid": str(uuid4()), "exp": 9999999999},
            "wrong-signing-key-at-least-32-characters",
            algorithm="HS256",
        ),
    ],
)
async def test_invalid_access_token(auth: Auth, authorization: str) -> None:
    response = await auth.client.get(
        "/api/v1/private", headers={"Authorization": authorization}
    )
    assert response.status_code == 401
    assert response.headers["WWW-Authenticate"] == "Bearer"


async def test_access_expiration(auth: Auth) -> None:
    with time_machine.travel(clock.now(), tick=False) as travel:
        tokens = await auth.login()
        travel.shift(timedelta(minutes=15))
        response = await auth.client.get(
            "/api/v1/private",
            headers={"Authorization": "Bearer " + tokens["access_token"]},
        )
        assert response.status_code == 401


async def test_email_rate_limits_and_private_redis_keys(auth: Auth) -> None:
    for _ in range(3):
        assert (await auth.post("/sign-in-codes", {"email": EMAIL})).status_code == 202
    response = await auth.post("/sign-in-codes", {"email": EMAIL.upper()})
    assert response.status_code == 429
    assert 1 <= int(response.headers["Retry-After"]) <= 900
    assert response.json()["code"] == "rate_limited"
    keys = await auth.redis.keys("*")
    assert keys
    assert all(EMAIL.encode() not in key and b"127.0.0.1" not in key for key in keys)


async def test_ip_rate_limit_on_requests_and_attempts(auth: Auth) -> None:
    # Different addresses cannot bypass the shared IP budget.
    for index in range(60):
        path = "/sign-in-codes" if index % 2 else "/sign-in"
        data = {"email": f"user{index}@university.example"}
        if path == "/sign-in":
            data.update(code="123456", device_id=DEVICE)
        assert (await auth.post(path, data)).status_code in (202, 401)
    response = await auth.post("/sign-in-codes", {"email": EMAIL})
    assert response.status_code == 429
    assert 1 <= int(response.headers["Retry-After"]) <= 60


async def test_idempotent_sign_in(auth: Auth) -> None:
    code = await auth.code()
    data = {
        "email": EMAIL,
        "code": code,
        "device_id": DEVICE,
        "first_name": "John",
        "last_name": "Smith",
    }
    key = str(uuid4())
    first = await auth.post("/sign-in", data, **{"Idempotency-Key": key})
    second = await auth.post("/sign-in", data, **{"Idempotency-Key": key})
    assert first.status_code == 200
    assert second.json() == first.json()
    assert second.headers["Idempotent-Replayed"] == "true"


async def test_no_sensitive_data_in_logs(
    auth: Auth, capsys: pytest.CaptureFixture[str]
) -> None:
    configure_logging(auth.settings, process="api")
    code = await auth.code()
    response = await auth.post(
        "/sign-in",
        {
            "email": EMAIL,
            "code": code,
            "device_id": DEVICE,
            "first_name": "John",
            "last_name": "Smith",
        },
    )
    tokens = response.json()
    assert response.status_code == 200
    await auth.post(
        "/token/refresh",
        {"refresh_token": tokens["refresh_token"], "device_id": DEVICE},
    )
    await auth.post("/sign-out", Authorization="Bearer " + tokens["access_token"])
    logs = capsys.readouterr().out
    assert logs
    for sensitive in (
        EMAIL,
        code,
        tokens["access_token"],
        tokens["refresh_token"],
        "John",
        "Smith",
    ):
        assert sensitive not in logs


async def test_mail_localization_and_non_disclosure(auth: Auth) -> None:
    responses = []
    for locale in ("ru", "en"):
        response = await auth.post(
            "/sign-in-codes", {"email": EMAIL}, **{"Accept-Language": locale}
        )
        responses.append(response.json())
        message = await auth.db.scalar(
            select(OutboxMessage).order_by(OutboxMessage.id.desc()).limit(1)
        )
        assert message is not None
        assert ("Your" if locale == "en" else "Ваш") in message.payload["subject"]
        await auth.db.rollback()
    assert responses[0] == responses[1]


def test_openapi_authentication() -> None:
    schema = create_app(Settings()).openapi()
    assert schema["paths"]["/api/v1/auth/sign-out"]["post"]["security"] == [
        {"HTTPBearer": []}
    ]
    assert "429" in schema["paths"]["/api/v1/auth/sign-in"]["post"]["responses"]
    assert schema["components"]["securitySchemes"]["HTTPBearer"]["scheme"] == "bearer"


@pytest.mark.parametrize(
    "overrides",
    [
        {"sign_in_email_limits": "nonsense"},
        {"sign_in_ip_limits": ""},
        {"auth_secret_key": SecretStr("short")},
        {"sign_in_code_max_attempts": 0},
        {"access_token_ttl": timedelta(0)},
    ],
)
def test_invalid_auth_settings(overrides: dict[str, Any]) -> None:
    with pytest.raises(ValidationError):
        Settings(**overrides)


async def test_refresh_is_idempotent(auth: Auth) -> None:
    tokens = await auth.login()
    data = {"refresh_token": tokens["refresh_token"], "device_id": DEVICE}
    headers = {"Idempotency-Key": str(uuid4())}
    first = await auth.post("/token/refresh", data, **headers)
    second = await auth.post("/token/refresh", data, **headers)
    assert first.status_code == 200
    assert second.json() == first.json()
    assert second.headers["Idempotent-Replayed"] == "true"
    assert (
        await auth.client.get(
            "/api/v1/private",
            headers={"Authorization": "Bearer " + first.json()["access_token"]},
        )
    ).status_code == 200


async def test_refresh_rollback_preserves_token(
    auth: Auth, monkeypatch: pytest.MonkeyPatch
) -> None:
    tokens = await auth.login()
    data = {"refresh_token": tokens["refresh_token"], "device_id": DEVICE}

    async def fail_to_store(*args: Any, **kwargs: Any) -> None:
        del args, kwargs
        raise RuntimeError("Simulated response storage failure")

    monkeypatch.setattr("campus.core.web.routing.store_response", fail_to_store)
    response = await auth.post("/token/refresh", data)
    assert response.status_code == 500
    monkeypatch.setattr("campus.core.web.routing.store_response", store_response)
    response = await auth.post("/token/refresh", data)
    assert response.status_code == 200
    assert len((await auth.db.scalars(select(RefreshToken))).all()) == 2


async def test_logout_preserves_other_device_and_user_scopes(auth: Auth) -> None:
    first = await auth.login()
    other_device = await auth.login(device_id=str(uuid4()))
    other_user = await auth.login(email="other@staff.example")
    key = str(uuid4())
    for tokens in (first, other_user):
        response = await auth.post(
            "/sign-out",
            **{
                "Authorization": "Bearer " + tokens["access_token"],
                "Idempotency-Key": key,
            },
        )
        assert response.status_code == 204
        assert "Idempotent-Replayed" not in response.headers
    response = await auth.client.get(
        "/api/v1/private",
        headers={"Authorization": "Bearer " + other_device["access_token"]},
    )
    assert response.status_code == 200


async def test_new_and_existing_email_responses_match(auth: Auth) -> None:
    first = await auth.post("/sign-in-codes", {"email": EMAIL})
    await auth.login()
    existing = await auth.post("/sign-in-codes", {"email": EMAIL})
    assert first.status_code == existing.status_code == 202
    assert first.json() == existing.json()


async def test_correct_code_on_last_attempt(auth: Auth) -> None:
    code = await auth.code()
    wrong = "000000" if code != "000000" else "111111"
    data = {"email": EMAIL, "code": wrong, "device_id": DEVICE}
    for _ in range(4):
        assert (await auth.post("/sign-in", data)).json()[
            "code"
        ] == "sign_in_code_invalid"
    response = await auth.post(
        "/sign-in", {**data, "code": code, "first_name": "John", "last_name": "Smith"}
    )
    assert response.status_code == 200
