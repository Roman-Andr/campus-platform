"""Secondary address acceptance tests against real PostgreSQL and Redis."""

import asyncio
import re
from typing import Any
from uuid import uuid4

import httpx2
import pytest
from sqlalchemy import select

from campus.core.outbox import OutboxMessage
from campus.modules.identity import User, UserEmail
from tests.database import run_alembic
from tests.test_identity import Auth

pytest_plugins = ["tests.test_identity"]


async def call(  # noqa: PLR0913 - HTTP test helper
    auth: Auth,
    tokens: dict[str, Any],
    method: str,
    path: str = "",
    data: dict[str, Any] | None = None,
    *,
    key: str | None = None,
) -> httpx2.Response:
    return await auth.client.request(
        method,
        "/api/v1/me/emails" + path,
        json=data,
        headers={
            "Authorization": "Bearer " + tokens["access_token"],
            "Idempotency-Key": key or str(uuid4()),
        },
    )


async def code(
    auth: Auth, tokens: dict[str, Any], email: str, kind: str = "corporate"
) -> str:
    response = await call(
        auth, tokens, "POST", "/codes", {"email": email, "kind": kind}
    )
    assert response.status_code == 202, response.text
    auth.db.expire_all()
    message = await auth.db.scalar(
        select(OutboxMessage).order_by(OutboxMessage.id.desc()).limit(1)
    )
    assert message is not None
    match = re.search(r"\b[0-9]{6}\b", message.payload["text"])
    assert match is not None
    await auth.db.rollback()
    return match[0]


async def add(
    auth: Auth, tokens: dict[str, Any], email: str, kind: str = "corporate"
) -> httpx2.Response:
    challenge = await code(auth, tokens, email, kind)
    return await call(
        auth, tokens, "POST", data={"email": email, "kind": kind, "code": challenge}
    )


async def test_corporate_type_and_all_addresses_sign_in(auth: Auth) -> None:
    tokens = await auth.login(email="teacher@staff.example")
    response = await add(auth, tokens, "student@university.example")
    assert response.status_code == 201, response.text
    for email in ("teacher@staff.example", "student@university.example"):
        signed_in = await auth.login(email=email)
        assert signed_in["user"]["id"] == tokens["user"]["id"]
        assert signed_in["user"]["account_type"] == "student"
    # Use the latest device token: login replaces the previous one.
    tokens = signed_in
    assert (
        await call(auth, tokens, "DELETE", "/" + response.json()["id"])
    ).status_code == 204
    me = await auth.client.get(
        "/api/v1/me", headers={"Authorization": "Bearer " + tokens["access_token"]}
    )
    assert me.json()["account_type"] == "employee"
    addresses = (await call(auth, tokens, "GET")).json()
    assert len(addresses) == 1
    assert (
        await call(auth, tokens, "DELETE", "/" + addresses[0]["id"])
    ).status_code == 409


async def test_backup_replace_remove_and_notifications(auth: Auth) -> None:
    tokens = await auth.login()
    assert (
        await add(auth, tokens, "first@personal.example", "backup")
    ).status_code == 201
    response = await add(auth, tokens, "second@personal.example", "backup")
    assert response.status_code == 201
    addresses = (await call(auth, tokens, "GET")).json()
    assert {a["email"] for a in addresses} == {
        "student@university.example",
        "second@personal.example",
    }
    messages = (await auth.db.scalars(select(OutboxMessage))).all()
    corporate_notices = [
        m
        for m in messages
        if m.payload["to"] == "student@university.example"
        and "изменены" in m.payload["text"]
    ]
    assert len(corporate_notices) == 2
    await auth.db.rollback()
    signed_in = await auth.login(email="second@personal.example")
    assert signed_in["user"]["id"] == tokens["user"]["id"]
    assert signed_in["user"]["account_type"] == "student"
    assert (
        await call(auth, signed_in, "DELETE", "/" + response.json()["id"])
    ).status_code == 204
    unknown = await auth.post("/sign-in-codes", {"email": "second@personal.example"})
    assert unknown.status_code == 202
    assert len((await call(auth, signed_in, "GET")).json()) == 1


async def test_domains_ownership_authentication_and_idempotency(auth: Auth) -> None:
    first = await auth.login()
    second = await auth.login(email="other@staff.example")
    for email, kind in (
        ("a@personal.example", "corporate"),
        ("a@staff.example", "backup"),
    ):
        response = await call(
            auth, first, "POST", "/codes", {"email": email, "kind": kind}
        )
        assert response.status_code == 422
    assert (
        await call(
            auth,
            first,
            "POST",
            "/codes",
            {"email": "other@staff.example", "kind": "corporate"},
        )
    ).status_code == 409
    other_addresses = (await call(auth, second, "GET")).json()
    assert (
        await call(auth, first, "DELETE", "/" + other_addresses[0]["id"])
    ).status_code == 404
    for method, path, data in (
        ("GET", "", None),
        ("POST", "/codes", {"email": "a@staff.example", "kind": "corporate"}),
        (
            "POST",
            "",
            {"email": "a@staff.example", "kind": "corporate", "code": "123456"},
        ),
        ("DELETE", "/" + str(uuid4()), None),
    ):
        assert (
            await auth.client.request(
                method,
                "/api/v1/me/emails" + path,
                json=data,
                headers={"Idempotency-Key": str(uuid4())},
            )
        ).status_code == 401
    email = "second@staff.example"
    challenge = await code(auth, first, email)
    data = {"email": email, "kind": "corporate", "code": challenge}
    assert (await call(auth, second, "POST", data=data)).status_code == 401
    assert (
        await auth.post(
            "/sign-in", {"email": email, "code": challenge, "device_id": str(uuid4())}
        )
    ).status_code == 401
    key = str(uuid4())
    added = await call(auth, first, "POST", data=data, key=key)
    replay = await call(auth, first, "POST", data=data, key=key)
    assert added.status_code == replay.status_code == 201
    assert replay.json() == added.json()
    assert replay.headers["Idempotent-Replayed"] == "true"


async def test_parallel_claims_have_exactly_one_winner(auth: Auth) -> None:
    first = await auth.login()
    second = await auth.login(email="other@staff.example")
    email = "shared@university.example"
    codes = [await code(auth, tokens, email) for tokens in (first, second)]
    results = await asyncio.gather(
        *(
            call(
                auth,
                tokens,
                "POST",
                data={"email": email, "kind": "corporate", "code": challenge},
            )
            for tokens, challenge in zip((first, second), codes, strict=True)
        )
    )
    assert sorted(r.status_code for r in results) == [201, 409]
    assert (
        len(
            (
                await auth.db.scalars(select(UserEmail).where(UserEmail.email == email))
            ).all()
        )
        == 1
    )


async def test_confirmation_attempts_and_request_limits(auth: Auth) -> None:
    tokens = await auth.login()
    email = "second@staff.example"
    challenge = await code(auth, tokens, email)
    wrong = "000000" if challenge != "000000" else "111111"
    for _ in range(5):
        assert (
            await call(
                auth,
                tokens,
                "POST",
                data={"email": email, "kind": "corporate", "code": wrong},
            )
        ).status_code == 401
    response = await call(
        auth,
        tokens,
        "POST",
        data={"email": email, "kind": "corporate", "code": challenge},
    )
    assert response.status_code == 429
    assert int(response.headers["Retry-After"]) > 0
    await code(auth, tokens, email)
    await code(auth, tokens, email)
    response = await call(
        auth, tokens, "POST", "/codes", {"email": email, "kind": "corporate"}
    )
    assert response.status_code == 429
    assert int(response.headers["Retry-After"]) > 0


async def test_unconfirmed_backup_replacement_keeps_old_address(auth: Auth) -> None:
    tokens = await auth.login()
    assert (
        await add(auth, tokens, "old@personal.example", "backup")
    ).status_code == 201
    email = "new@personal.example"
    challenge = await code(auth, tokens, email, "backup")
    data = {
        "email": email,
        "kind": "backup",
        "code": "000000" if challenge != "000000" else "111111",
    }
    assert (await call(auth, tokens, "POST", data=data)).status_code == 401
    addresses = (await call(auth, tokens, "GET")).json()
    assert {a["email"] for a in addresses} == {
        "student@university.example",
        "old@personal.example",
    }
    # Confirmation does not change the account until it commits.
    assert (
        await call(auth, tokens, "POST", data={**data, "code": challenge})
    ).status_code == 201


async def test_parallel_removals_preserve_one_corporate_address(auth: Auth) -> None:
    tokens = await auth.login()
    assert (await add(auth, tokens, "second@staff.example")).status_code == 201
    addresses = (await call(auth, tokens, "GET")).json()
    results = await asyncio.gather(
        *(call(auth, tokens, "DELETE", "/" + row["id"]) for row in addresses)
    )
    assert sorted(r.status_code for r in results) == [204, 409]
    remaining = (await call(auth, tokens, "GET")).json()
    assert len(remaining) == 1
    # The compatible primary email follows deletion of the initial address.
    me = await auth.client.get(
        "/api/v1/me", headers={"Authorization": "Bearer " + tokens["access_token"]}
    )
    assert me.json()["email"] == remaining[0]["email"]


async def test_parallel_confirmation_attempts_are_bounded(auth: Auth) -> None:
    tokens = await auth.login()
    email = "parallel@staff.example"
    challenge = await code(auth, tokens, email)
    data = {
        "email": email,
        "kind": "corporate",
        "code": "000000" if challenge != "000000" else "111111",
    }
    results = await asyncio.gather(
        *(call(auth, tokens, "POST", data=data) for _ in range(10))
    )
    assert sorted(r.status_code for r in results) == [401] * 5 + [429] * 5
    assert all("Retry-After" in r.headers for r in results if r.status_code == 429)


async def test_unknown_personal_matches_known_without_mail_or_registration(
    auth: Auth,
) -> None:
    tokens = await auth.login()
    assert (
        await add(auth, tokens, "known@personal.example", "backup")
    ).status_code == 201
    known = await auth.post("/sign-in-codes", {"email": "known@personal.example"})
    messages = list((await auth.db.scalars(select(OutboxMessage.id))).all())
    await auth.db.rollback()
    unknown = await auth.post("/sign-in-codes", {"email": "unknown@personal.example"})
    assert known.status_code == unknown.status_code == 202
    assert known.content == unknown.content
    assert list((await auth.db.scalars(select(OutboxMessage.id))).all()) == messages
    await auth.db.rollback()
    response = await auth.post(
        "/sign-in",
        {
            "email": "unknown@personal.example",
            "code": "123456",
            "device_id": str(uuid4()),
            "first_name": "Some",
            "last_name": "Name",
        },
    )
    assert response.status_code == 401


async def test_existing_account_signs_in_after_address_migration(auth: Auth) -> None:
    original = await auth.login()
    assert auth.settings.database_url is not None
    url = auth.settings.database_url.get_secret_value()
    await asyncio.to_thread(run_alembic, url, "downgrade", "90fb233ce001")
    await asyncio.to_thread(run_alembic, url, "upgrade", "head")
    signed_in = await auth.login()
    assert signed_in["user"]["id"] == original["user"]["id"]
    assert signed_in["user"]["email"] == original["user"]["email"]


async def test_registration_racing_address_claim_returns_conflict(auth: Auth) -> None:
    tokens = await auth.login()
    email = "racing@staff.example"
    confirmation = await code(auth, tokens, email)
    sign_in_code = await auth.code(email)
    documents = await auth.documents()
    claimed, registered = await asyncio.gather(
        call(
            auth,
            tokens,
            "POST",
            data={"email": email, "kind": "corporate", "code": confirmation},
        ),
        auth.post(
            "/sign-in",
            {
                "email": email,
                "code": sign_in_code,
                "device_id": str(uuid4()),
                "first_name": "Some",
                "last_name": "Name",
                "accepted_document_ids": documents,
            },
        ),
    )
    assert sorted((claimed.status_code, registered.status_code)) in (
        [200, 409],
        [201, 409],
    )
    assert (
        len(
            (
                await auth.db.scalars(select(UserEmail).where(UserEmail.email == email))
            ).all()
        )
        == 1
    )


async def test_security_notices_reach_all_corporate_addresses(auth: Auth) -> None:
    tokens = await auth.login()
    assert (await add(auth, tokens, "second@staff.example")).status_code == 201
    auth.db.expire_all()
    before = set((await auth.db.scalars(select(OutboxMessage.id))).all())
    await auth.db.rollback()
    backup = await add(auth, tokens, "backup@personal.example", "backup")
    assert backup.status_code == 201
    messages = (
        await auth.db.scalars(
            select(OutboxMessage).where(OutboxMessage.id.not_in(before))
        )
    ).all()
    notices = [row for row in messages if "изменены" in row.payload["text"]]
    assert {row.payload["to"] for row in notices} == {
        "student@university.example",
        "second@staff.example",
        "backup@personal.example",
    }
    before.update(row.id for row in messages)
    await auth.db.rollback()
    assert (
        await call(auth, tokens, "DELETE", "/" + backup.json()["id"])
    ).status_code == 204
    messages = (
        await auth.db.scalars(
            select(OutboxMessage).where(OutboxMessage.id.not_in(before))
        )
    ).all()
    assert {row.payload["to"] for row in messages} == {
        "student@university.example",
        "second@staff.example",
    }


@pytest.mark.parametrize("account_type", ["alumni", "former_employee"])
async def test_backup_changes_preserve_restricted_account_type(
    auth: Auth, account_type: str
) -> None:
    tokens = await auth.login()
    user = await auth.db.scalar(select(User))
    assert user is not None
    user.account_type = account_type
    await auth.db.commit()
    for email in ("first@personal.example", "replacement@personal.example"):
        response = await add(auth, tokens, email, "backup")
        assert response.status_code == 201, response.text
        auth.db.expire_all()
        assert await auth.db.scalar(select(User.account_type)) == account_type
        await auth.db.rollback()
    response = await call(auth, tokens, "DELETE", "/" + response.json()["id"])
    assert response.status_code == 204
    auth.db.expire_all()
    assert await auth.db.scalar(select(User.account_type)) == account_type
