"""Consent lifecycle, permissions, database immutability and concurrency."""

import asyncio
from datetime import timedelta
from typing import Any
from uuid import UUID, uuid4

import httpx2
import pytest
import time_machine
from sqlalchemy import func, select, text
from sqlalchemy.exc import IntegrityError

from campus.core import clock
from campus.core.outbox import OutboxMessage
from campus.core.web import CurrentUser, Principal, api_router
from campus.modules.identity import (
    ConsentDecision,
    DocumentKind,
    DocumentVersion,
    User,
    cross_border_allowed,
    publish_document,
    seed_documents,
)
from campus.modules.identity.consents import publication_lock, record_decision
from tests.test_identity import DEVICE, EMAIL, Auth
from tests.test_identity import auth as auth  # noqa: PLC0414 - pytest fixture


async def documents(auth: Auth) -> list[dict[str, Any]]:
    response = await auth.client.get("/api/v1/documents")
    assert response.status_code == 200
    result: list[dict[str, Any]] = response.json()
    return result


async def changed_rules(auth: Auth) -> UUID:
    await auth.db.rollback()
    document = await publish_document(
        auth.db, DocumentKind.RULES, text_ru="Новые правила", text_en="New rules"
    )
    document_id = document.id
    await auth.db.commit()
    return document_id


async def decisions(auth: Auth) -> list[ConsentDecision]:
    auth.db.expire_all()
    result = list(
        (
            await auth.db.scalars(select(ConsentDecision).order_by(ConsentDecision.id))
        ).all()
    )
    auth.db.expunge_all()
    await auth.db.rollback()
    return result


async def mutate(  # noqa: PLR0913 - HTTP request parameters
    auth: Auth,
    path: str,
    data: dict[str, Any],
    headers: dict[str, str],
    *,
    method: str = "POST",
    key: str | None = None,
) -> httpx2.Response:
    return await auth.client.request(
        method,
        "/api/v1" + path,
        json=data,
        headers={"Idempotency-Key": key or str(uuid4()), **headers},
    )


@pytest.mark.parametrize("omitted", list(DocumentKind)[:3])
async def test_registration_requires_each_current_document(
    auth: Auth, omitted: DocumentKind
) -> None:
    docs = await documents(auth)
    code = await auth.code()
    data = {
        "email": EMAIL,
        "code": code,
        "device_id": DEVICE,
        "first_name": "Anna",
        "last_name": "Smith",
        "accepted_document_ids": [
            d["id"] for d in docs if d["required"] and d["kind"] != omitted
        ],
    }
    response = await auth.post("/sign-in", data)
    assert response.status_code == 403
    assert response.json()["code"] == "consent_required"
    assert response.json()["errors"][0]["code"] == omitted
    assert await auth.db.scalar(select(User)) is None
    assert await decisions(auth) == []
    data["accepted_document_ids"] = [d["id"] for d in docs if d["required"]]
    with time_machine.travel(clock.now(), tick=False):
        timestamp = clock.now()
        response = await auth.post("/sign-in", data)
    assert response.status_code == 200
    assert response.json()["user"]["cross_border_transfer_allowed"] is False
    journal = await decisions(auth)
    assert len(journal) == 3
    assert {str(d.document_id) for d in journal} == set(data["accepted_document_ids"])
    assert all(
        d.accepted and d.decided_at == timestamp and d.session_id for d in journal
    )


async def test_registration_without_any_or_with_stale_acceptance(auth: Auth) -> None:
    old = await auth.documents()
    new_id = await changed_rules(auth)
    for accepted in ([], old, [str(new_id), str(uuid4())]):
        response = await auth.post(
            "/sign-in",
            {
                "email": EMAIL,
                "code": await auth.code(),
                "device_id": DEVICE,
                "first_name": "Anna",
                "last_name": "Smith",
                "accepted_document_ids": accepted,
            },
        )
        assert response.status_code == 403
    assert await decisions(auth) == []


async def test_documents_are_public_localized_and_seed_is_repeatable(
    auth: Auth,
) -> None:
    ru = await documents(auth)
    en = (
        await auth.client.get("/api/v1/documents", headers={"Accept-Language": "en"})
    ).json()
    assert len(ru) == len(en) == 4
    assert {d["kind"] for d in ru} == set(DocumentKind)
    assert all(
        r["id"] == e["id"] and r["text"] != e["text"] and r["published_at"]
        for r, e in zip(ru, en, strict=True)
    )
    await changed_rules(auth)
    await seed_documents(auth.db)
    await auth.db.commit()
    assert await auth.db.scalar(select(func.count()).select_from(DocumentVersion)) == 5
    assert "Новые правила" in [d["text"] for d in await documents(auth)]


async def test_new_required_version_gates_all_requests_and_replays(auth: Auth) -> None:
    tokens = await auth.login()
    headers = {"Authorization": "Bearer " + tokens["access_token"]}
    accepted = await auth.documents()
    # An ordinary mutating route provides an idempotent response before publication.
    router = api_router()

    @router.post("/api/v1/ordinary")
    async def ordinary(principal: CurrentUser) -> dict[str, str]:
        return {"user_id": str(principal.user_id)}

    @router.get("/api/v1/export-test", name="export_my_data")
    async def export_test(principal: CurrentUser) -> dict[str, str]:
        return {"user_id": str(principal.user_id)}

    @router.delete("/api/v1/delete-test", name="delete_my_account")
    async def delete_test(principal: CurrentUser) -> dict[str, str]:
        return {"user_id": str(principal.user_id)}

    auth.app.include_router(router)
    key = str(uuid4())
    assert (await mutate(auth, "/ordinary", {}, headers, key=key)).status_code == 200
    current = await changed_rules(auth)
    for path in ("/me", "/private", "/university/cities"):
        response = await auth.client.get("/api/v1" + path, headers=headers)
        assert response.status_code == 403, response.text
        assert response.json()["code"] == "consent_required"
        assert response.json()["errors"] == [
            {"code": "community_rules", "detail": str(current)}
        ]
    assert (await mutate(auth, "/ordinary", {}, headers, key=key)).status_code == 403
    assert (
        await auth.client.get("/api/v1/documents", headers=headers)
    ).status_code == 200
    assert (
        await auth.client.get("/api/v1/export-test", headers=headers)
    ).status_code == 200
    assert (
        await mutate(auth, "/delete-test", {}, headers, method="DELETE")
    ).status_code == 200
    stale = await mutate(auth, "/me/consents", {"document_ids": accepted}, headers)
    assert stale.status_code == 422
    assert stale.json()["code"] == "consent_invalid"
    key = str(uuid4())
    first = await mutate(
        auth, "/me/consents", {"document_ids": [str(current)]}, headers, key=key
    )
    second = await mutate(
        auth, "/me/consents", {"document_ids": [str(current)]}, headers, key=key
    )
    assert first.status_code == second.status_code == 204
    assert second.headers["Idempotent-Replayed"] == "true"
    assert len(await decisions(auth)) == 4
    assert (
        await auth.client.get("/api/v1/private", headers=headers)
    ).status_code == 200
    await changed_rules(auth)
    assert (await auth.post("/sign-out", **headers)).status_code == 204


@pytest.mark.parametrize("initial", [False, True])
async def test_cross_border_grant_revoke_and_outbox(auth: Auth, initial: bool) -> None:
    docs = await documents(auth)
    cross = next(d for d in docs if d["kind"] == DocumentKind.CROSS_BORDER)
    accepted = [d["id"] for d in docs if d["required"]]
    tokens = await auth.login(
        accepted_document_ids=accepted,
        cross_border_document_id=cross["id"] if initial else None,
    )
    user_id = UUID(tokens["user"]["id"])
    headers = {"Authorization": "Bearer " + tokens["access_token"]}
    assert tokens["user"]["cross_border_transfer_allowed"] == initial
    for allowed in (True, False, True, False):
        with time_machine.travel(clock.now() + timedelta(seconds=1), tick=False):
            now = clock.now()
            response = await mutate(
                auth,
                "/me/consents/cross-border",
                {"document_id": cross["id"], "accepted": allowed},
                headers,
                method="PUT",
            )
        assert response.status_code == 204
        auth.db.expire_all()
        assert await cross_border_allowed(auth.db, user_id) == allowed
        await auth.db.rollback()
        me = await auth.client.get("/api/v1/me", headers=headers)
        assert me.json()["cross_border_transfer_allowed"] == allowed
        journal = await decisions(auth)
        latest = journal[-1]
        assert latest.accepted == allowed
        if not (initial and allowed and len(journal) == 4):
            assert latest.decided_at == now
        event = await auth.db.scalar(
            select(OutboxMessage)
            .where(OutboxMessage.topic == "identity.cross_border_consent_changed")
            .order_by(OutboxMessage.id.desc())
            .limit(1)
        )
        assert event is not None
        assert event.payload == {
            "user_id": str(user_id),
            "document_id": cross["id"],
            "allowed": allowed,
        }
        await auth.db.rollback()
    assert len(await decisions(auth)) == 7
    # Another account's decision does not grant this user's permission.
    other = await auth.login(
        email="other@university.example",
        accepted_document_ids=[d["id"] for d in docs if d["required"]],
        cross_border_document_id=cross["id"],
    )
    assert await cross_border_allowed(auth.db, UUID(other["user"]["id"])) is True
    assert await cross_border_allowed(auth.db, user_id) is False


@pytest.mark.parametrize(
    ("method", "path", "data"),
    [
        ("POST", "/me/consents", {"document_ids": [str(uuid4())]}),
        (
            "PUT",
            "/me/consents/cross-border",
            {"document_id": str(uuid4()), "accepted": False},
        ),
    ],
)
async def test_consent_writes_require_identity_and_current_version(
    auth: Auth, method: str, path: str, data: dict[str, Any]
) -> None:
    assert (await mutate(auth, path, data, {}, method=method)).status_code == 401
    tokens = await auth.login()
    headers = {"Authorization": "Bearer " + tokens["access_token"]}
    response = await mutate(auth, path, data, headers, method=method)
    assert response.status_code == 422
    assert response.json()["code"] == "consent_invalid"
    assert len(await decisions(auth)) == 3


@pytest.mark.parametrize(
    "table", ["identity_consent_decision", "identity_document_version"]
)
@pytest.mark.parametrize(
    "operation",
    [
        "UPDATE {table} SET created_at = created_at",
        "DELETE FROM {table}",
        "TRUNCATE {table} CASCADE",
    ],
)
async def test_legal_history_is_append_only(
    auth: Auth, table: str, operation: str
) -> None:
    await auth.login()
    with pytest.raises(IntegrityError, match="append-only"):
        await auth.db.execute(text(operation.format(table=table)))
    await auth.db.rollback()
    assert len(await decisions(auth)) == 3


async def test_concurrent_acceptance_and_publication(auth: Auth) -> None:
    tokens = await auth.login()
    headers = {"Authorization": "Bearer " + tokens["access_token"]}
    document_id = str(await changed_rules(auth))
    responses = await asyncio.gather(
        *(
            mutate(
                auth,
                "/me/consents",
                {"document_ids": [document_id, document_id]},
                headers,
            )
            for _ in range(5)
        )
    )
    assert all(r.status_code == 204 for r in responses)
    assert len(await decisions(auth)) == 4

    async def publish() -> int:
        async with auth.app.state.session_factory() as session, session.begin():
            document = await publish_document(
                session, DocumentKind.RULES, text_ru="Правила", text_en="Rules"
            )
            return document.version

    assert sorted(await asyncio.gather(publish(), publish())) == [3, 4]
    assert (await auth.client.get("/api/v1/me", headers=headers)).status_code == 403


async def test_outbox_and_decision_rollback_together(auth: Auth) -> None:
    tokens = await auth.login()
    document = await auth.db.scalar(
        select(DocumentVersion).where(DocumentVersion.kind == DocumentKind.CROSS_BORDER)
    )
    assert document is not None
    user_id = UUID(tokens["user"]["id"])
    principal = Principal(user_id, uuid4())
    await record_decision(auth.db, principal, document, accepted=True)
    assert await cross_border_allowed(auth.db, user_id) is True
    await auth.db.rollback()
    assert await cross_border_allowed(auth.db, user_id) is False
    assert (
        await auth.db.scalar(
            select(OutboxMessage).where(
                OutboxMessage.topic == "identity.cross_border_consent_changed"
            )
        )
        is None
    )


async def test_publication_waits_for_acceptance_transaction(auth: Auth) -> None:
    async with auth.app.state.session_factory() as acceptance:
        await publication_lock(acceptance)
        task = asyncio.create_task(changed_rules(auth))
        try:
            with pytest.raises(TimeoutError):
                await asyncio.wait_for(asyncio.shield(task), timeout=0.1)
        finally:
            await acceptance.rollback()
        await asyncio.wait_for(task, timeout=5)


async def test_publish_requires_both_translations(auth: Auth) -> None:
    with pytest.raises(ValueError, match="translations"):
        await publish_document(
            auth.db, DocumentKind.RULES, text_ru=" ", text_en="Rules"
        )


async def test_optional_consent_is_separate_and_version_specific(auth: Auth) -> None:
    docs = await documents(auth)
    cross = next(d for d in docs if d["kind"] == DocumentKind.CROSS_BORDER)
    required = [d["id"] for d in docs if d["required"]]
    code = await auth.code()
    for bundled, separate in (
        (True, None),
        (False, str(uuid4())),
        (False, required[0]),
    ):
        response = await auth.post(
            "/sign-in",
            {
                "email": EMAIL,
                "code": code,
                "device_id": DEVICE,
                "first_name": "Anna",
                "last_name": "Smith",
                "accepted_document_ids": required + ([cross["id"]] if bundled else []),
                "cross_border_document_id": separate,
            },
        )
        assert response.status_code == 422
        assert response.json()["code"] == "consent_invalid"
    tokens = await auth.login(cross_border_document_id=cross["id"])
    headers = {"Authorization": "Bearer " + tokens["access_token"]}
    user_id = UUID(tokens["user"]["id"])
    assert await cross_border_allowed(auth.db, user_id) is True
    await auth.db.rollback()
    document = await publish_document(
        auth.db, DocumentKind.CROSS_BORDER, text_ru="Новые условия", text_en="New terms"
    )
    document_id = str(document.id)
    await auth.db.commit()
    assert await cross_border_allowed(auth.db, user_id) is False
    event = await auth.db.scalar(
        select(OutboxMessage)
        .where(OutboxMessage.topic == "identity.cross_border_consent_changed")
        .order_by(OutboxMessage.id.desc())
        .limit(1)
    )
    assert event is not None
    assert event.payload == {
        "user_id": str(user_id),
        "document_id": document_id,
        "allowed": False,
    }
    await auth.db.rollback()
    assert (await auth.client.get("/api/v1/me", headers=headers)).status_code == 200
    response = await mutate(
        auth,
        "/me/consents/cross-border",
        {"document_id": cross["id"], "accepted": True},
        headers,
        method="PUT",
    )
    assert response.status_code == 422
    response = await mutate(
        auth, "/me/consents", {"document_ids": [document_id]}, headers
    )
    assert response.status_code == 422
    key = str(uuid4())
    for _ in range(2):
        assert (
            await mutate(
                auth,
                "/me/consents/cross-border",
                {"document_id": document_id, "accepted": True},
                headers,
                method="PUT",
                key=key,
            )
        ).status_code == 204
    assert len(await decisions(auth)) == 5
    assert await cross_border_allowed(auth.db, user_id) is True


async def test_cross_border_concurrent_requests_and_missing_key(auth: Auth) -> None:
    tokens = await auth.login()
    headers = {"Authorization": "Bearer " + tokens["access_token"]}
    cross = next(
        d for d in await documents(auth) if d["kind"] == DocumentKind.CROSS_BORDER
    )
    data = {"document_id": cross["id"], "accepted": True}
    response = await auth.client.put(
        "/api/v1/me/consents/cross-border", json=data, headers=headers
    )
    assert response.status_code == 400
    assert response.json()["code"] == "idempotency_key_missing"
    responses = await asyncio.gather(
        *(
            mutate(auth, "/me/consents/cross-border", data, headers, method="PUT")
            for _ in range(5)
        )
    )
    assert all(r.status_code == 204 for r in responses)
    assert len(await decisions(auth)) == 4
    assert (
        await auth.db.scalar(
            select(func.count())
            .select_from(OutboxMessage)
            .where(OutboxMessage.topic == "identity.cross_border_consent_changed")
        )
        == 1
    )
