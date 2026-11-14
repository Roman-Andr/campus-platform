"""Administrator API of rules versions and complaint reasons on PostgreSQL:
role matrix, immutable versions, consent gates, cross-border revocation,
catalogue history, audit, idempotency and concurrent publication."""

import asyncio
from dataclasses import dataclass
from typing import Any
from uuid import UUID, uuid4

import httpx2
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import func, select, update

from campus.core.audit import AuditRecord
from campus.core.outbox import OutboxMessage
from campus.modules.identity import (
    DocumentKind,
    DocumentVersion,
    Role,
    RoleAssignment,
    User,
    cross_border_allowed,
)
from campus.modules.moderation import ComplaintReason
from campus.modules.moderation import api as moderation_api
from campus.modules.moderation.service import CODE_CONFLICT
from tests.test_identity import Auth
from tests.test_profile import Account, Places, auth, places

__all__ = ["auth", "places"]

RULES = "/admin/documents"
REASONS = "/admin/complaint-reasons"
PUBLIC_REASONS = "/complaint-reasons"
CROSS_BORDER_EVENT = "identity.cross_border_consent_changed"
DOCUMENT_PUBLISHED = "administration.document.publish"


async def sign_in(
    auth: Auth,
    email: str,
    *,
    role: Role | None = None,
    account_type: str | None = None,
    places: Places | None = None,
) -> Account:
    """An account of the given role and type; tokens are enough for roles."""
    tokens = await auth.login(email=email)
    account = Account(auth, tokens)
    user_id = UUID(tokens["user"]["id"])
    changed = False
    if account_type is not None:
        await auth.db.execute(
            update(User).where(User.id == user_id).values(account_type=account_type)
        )
        changed = True
    if role is not None:
        auth.db.add(
            RoleAssignment(
                user_id=user_id,
                role=role,
                dormitory_id=(
                    places.dubki if role == Role.HEADMAN and places else None
                ),
            )
        )
        changed = True
    if changed:
        await auth.db.commit()
    return account


async def call(  # noqa: PLR0913 - request parts of a test probe
    account: Account,
    method: str,
    path: str,
    body: dict[str, Any] | None = None,
    *,
    key: str | None = None,
    headers: dict[str, str] | None = None,
) -> httpx2.Response:
    request_headers = {**account.headers, **(headers or {})}
    if method != "GET":
        request_headers["Idempotency-Key"] = key or str(uuid4())
    return await account.auth.client.request(
        method, "/api/v1" + path, json=body, headers=request_headers
    )


def assert_problem(response: httpx2.Response, status: int, code: str) -> None:
    assert response.status_code == status, response.text
    assert response.headers["content-type"] == "application/problem+json"
    assert response.json()["code"] == code


@dataclass(frozen=True)
class DocumentInfo:
    """Plain values of a document version: the session may expire the row."""

    id: UUID
    version: int


async def latest_document(
    auth: Auth, kind: DocumentKind = DocumentKind.RULES
) -> DocumentInfo:
    await auth.db.rollback()
    document = await auth.db.scalar(
        select(DocumentVersion)
        .where(DocumentVersion.kind == kind)
        .order_by(DocumentVersion.version.desc())
        .limit(1)
    )
    assert document is not None
    return DocumentInfo(document.id, document.version)


async def audit_records(auth: Auth, action: str) -> list[AuditRecord]:
    await auth.db.rollback()
    return list(
        (
            await auth.db.scalars(
                select(AuditRecord)
                .where(AuditRecord.action == action)
                .order_by(AuditRecord.occurred_at, AuditRecord.id)
            )
        ).all()
    )


async def accept(account: Account, document_id: UUID) -> None:
    response = await call(
        account, "POST", "/me/consents", {"document_ids": [str(document_id)]}
    )
    assert response.status_code == 204, response.text


@pytest.fixture
async def admin(auth: Auth) -> Account:
    return await sign_in(auth, "admin@staff.example", role=Role.ADMINISTRATOR)


@pytest.fixture
async def student(auth: Auth) -> Account:
    return await sign_in(auth, "student@university.example")


def reason_body(
    document_id: UUID,
    *,
    code: str = "spam",
    name_ru: str = "Спам",
    name_en: str = "Spam",
    clause: str = "1.1",
) -> dict[str, Any]:
    return {
        "code": code,
        "name_ru": name_ru,
        "name_en": name_en,
        "rules_document_id": str(document_id),
        "rules_clause": clause,
    }


async def create_reason(
    admin: Account, document_id: UUID, **overrides: Any
) -> dict[str, Any]:
    response = await call(
        admin,
        "POST",
        REASONS,
        reason_body(document_id, **overrides),
    )
    assert response.status_code == 201, response.text
    body: dict[str, Any] = response.json()
    return body


async def test_versions_are_listed_and_read_in_both_languages(
    admin: Account,
) -> None:
    response = await call(admin, "GET", RULES + "?size=100")
    assert response.status_code == 200, response.text
    items = response.json()["items"]
    assert {item["kind"] for item in items} == {kind.value for kind in DocumentKind}
    assert all("text_ru" not in item and "text_en" not in item for item in items)

    rules = next(item for item in items if item["kind"] == DocumentKind.RULES)
    detail = await call(admin, "GET", f"{RULES}/{rules['id']}")
    assert detail.status_code == 200, detail.text
    body = detail.json()
    assert body["version"] == rules["version"]
    assert body["text_ru"].startswith("Правила сообщества")
    assert body["text_en"].startswith("Campus community rules")
    assert body["required"] is True

    filtered = await call(
        admin, "GET", RULES + f"?kind={DocumentKind.CROSS_BORDER.value}"
    )
    assert filtered.status_code == 200
    cross = filtered.json()["items"]
    assert cross
    assert all(item["kind"] == DocumentKind.CROSS_BORDER for item in cross)
    assert all(item["required"] is False for item in cross)


async def test_publish_adds_a_version_audits_and_is_idempotent(
    admin: Account, auth: Auth
) -> None:
    before = await latest_document(auth)
    body = {
        "kind": DocumentKind.RULES.value,
        "text_ru": "Новые правила",
        "text_en": "New rules",
    }
    key = str(uuid4())
    first = await call(admin, "POST", RULES, body, key=key)
    assert first.status_code == 201, first.text
    published = first.json()
    assert published["version"] == before.version + 1
    assert published["text_ru"] == "Новые правила"
    assert published["text_en"] == "New rules"

    repeated = await call(admin, "POST", RULES, body, key=key)
    assert repeated.status_code == 201
    assert repeated.json() == published
    await auth.db.rollback()
    count = await auth.db.scalar(
        select(func.count())
        .select_from(DocumentVersion)
        .where(DocumentVersion.kind == DocumentKind.RULES)
    )
    assert count == before.version + 1

    reused = await call(admin, "POST", RULES, {**body, "text_en": "Different"}, key=key)
    assert_problem(reused, 422, "idempotency_key_reused")
    await accept(admin, UUID(published["id"]))

    records = await audit_records(auth, DOCUMENT_PUBLISHED)
    assert len(records) == 1
    record = records[0]
    assert record.actor_id == UUID(admin.tokens["user"]["id"])
    assert record.object_id == UUID(published["id"])
    assert record.before == {"version": before.version}
    assert record.after == {
        "kind": DocumentKind.RULES.value,
        "version": published["version"],
        "required": True,
    }

    versions = await call(
        admin, "GET", RULES + f"?kind={DocumentKind.RULES.value}&size=100"
    )
    assert [item["version"] for item in versions.json()["items"]][:2] == [
        published["version"],
        before.version,
    ]


async def test_published_versions_have_no_mutation_routes(client: TestClient) -> None:
    schema = client.get("/api/v1/openapi.json").json()
    methods = set(schema["paths"]["/api/v1/admin/documents"])
    assert {"get", "post"} <= methods
    assert methods.isdisjoint({"put", "patch", "delete"})
    detail = set(schema["paths"]["/api/v1/admin/documents/{document_id}"])
    assert detail == {"get"}


async def test_new_required_version_gates_until_accepted(
    admin: Account, student: Account
) -> None:
    assert (await call(student, "GET", "/me")).status_code == 200
    response = await call(
        admin,
        "POST",
        RULES,
        {
            "kind": DocumentKind.RULES.value,
            "text_ru": "Правила версии 2",
            "text_en": "Rules version 2",
        },
    )
    assert response.status_code == 201, response.text
    document_id = response.json()["id"]

    gated = await call(student, "GET", "/me")
    assert_problem(gated, 403, "consent_required")
    assert any(
        error["code"] == DocumentKind.RULES.value for error in gated.json()["errors"]
    )
    assert (await call(student, "GET", "/documents")).status_code == 200

    await accept(student, UUID(document_id))
    assert (await call(student, "GET", "/me")).status_code == 200


async def test_cross_border_version_revokes_grants_and_emits_event(
    admin: Account, student: Account, auth: Auth
) -> None:
    cross = await latest_document(auth, DocumentKind.CROSS_BORDER)
    consent = await call(
        student,
        "PUT",
        "/me/consents/cross-border",
        {"document_id": str(cross.id), "accepted": True},
    )
    assert consent.status_code == 204, consent.text
    await auth.db.rollback()
    assert await cross_border_allowed(auth.db, UUID(student.tokens["user"]["id"]))

    response = await call(
        admin,
        "POST",
        RULES,
        {
            "kind": DocumentKind.CROSS_BORDER.value,
            "text_ru": "Новое трансграничное согласие",
            "text_en": "New cross-border consent",
        },
    )
    assert response.status_code == 201, response.text
    new_id = UUID(response.json()["id"])
    await auth.db.rollback()
    assert not await cross_border_allowed(auth.db, UUID(student.tokens["user"]["id"]))
    event = await auth.db.scalar(
        select(OutboxMessage)
        .where(OutboxMessage.topic == CROSS_BORDER_EVENT)
        .order_by(OutboxMessage.id.desc())
        .limit(1)
    )
    assert event is not None
    assert event.payload == {
        "user_id": student.tokens["user"]["id"],
        "document_id": str(new_id),
        "allowed": False,
    }


async def test_reason_crud_keeps_history_and_hides_inactive(
    admin: Account, student: Account, auth: Auth
) -> None:
    rules = await latest_document(auth)
    created = await create_reason(admin, rules.id, clause="3.1")
    reason_id = created["id"]
    assert created["active"] is True
    assert created["version"] == 1
    assert created["rules_document_id"] == str(rules.id)
    assert created["rules_version"] == rules.version
    assert created["rules_clause"] == "3.1"

    public = await call(
        student, "GET", PUBLIC_REASONS, headers={"Accept-Language": "ru"}
    )
    assert public.status_code == 200
    assert public.headers["content-language"] == "ru"
    assert public.json()["items"] == [
        {
            "id": reason_id,
            "code": "spam",
            "name": "Спам",
            "rules_version": rules.version,
            "rules_clause": "3.1",
        }
    ]
    english = await call(
        student, "GET", PUBLIC_REASONS, headers={"Accept-Language": "en"}
    )
    assert english.json()["items"][0]["name"] == "Spam"

    updated = await call(
        admin,
        "PATCH",
        f"{REASONS}/{reason_id}",
        {"version": 1, "name_ru": "Спам и реклама", "rules_clause": "3.2"},
    )
    assert updated.status_code == 200, updated.text
    assert updated.json()["version"] == 2
    assert updated.json()["name_ru"] == "Спам и реклама"
    assert updated.json()["rules_clause"] == "3.2"

    stale = await call(
        admin,
        "PATCH",
        f"{REASONS}/{reason_id}",
        {"version": 1, "name_en": "Old"},
    )
    assert_problem(stale, 409, "complaint_reason_version_conflict")
    assert stale.json()["current_version"] == 2

    deleted = await call(admin, "DELETE", f"{REASONS}/{reason_id}")
    assert deleted.status_code == 204, deleted.text
    detail = await call(admin, "GET", f"{REASONS}/{reason_id}")
    assert detail.status_code == 200, detail.text
    stored = detail.json()
    assert stored["active"] is False
    assert stored["version"] == 3
    assert stored["name_ru"] == "Спам и реклама"
    assert stored["rules_clause"] == "3.2"
    assert stored["rules_document_id"] == str(rules.id)

    await auth.db.rollback()
    row = await auth.db.get(ComplaintReason, UUID(reason_id))
    assert row is not None
    assert row.active is False
    assert (await call(student, "GET", PUBLIC_REASONS)).json()["items"] == []

    repeated = await call(admin, "DELETE", f"{REASONS}/{reason_id}")
    assert repeated.status_code == 204
    assert len(await audit_records(auth, "moderation.complaint_reason.create")) == 1
    assert len(await audit_records(auth, "moderation.complaint_reason.update")) == 1
    assert len(await audit_records(auth, "moderation.complaint_reason.deactivate")) == 1


async def test_reason_code_and_rules_basis_are_validated(
    admin: Account, auth: Auth
) -> None:
    rules = await latest_document(auth)
    await create_reason(admin, rules.id, code="duplicate")
    duplicate = await call(
        admin, "POST", REASONS, reason_body(rules.id, code="duplicate")
    )
    assert_problem(duplicate, 409, CODE_CONFLICT.code)
    assert "duplicate" in duplicate.json()["detail"]

    policy = await latest_document(auth, DocumentKind.POLICY)
    wrong_kind = await call(
        admin, "POST", REASONS, reason_body(policy.id, code="wrong_kind")
    )
    assert_problem(wrong_kind, 422, "complaint_reason_rules_invalid")

    missing = await call(
        admin, "POST", REASONS, reason_body(uuid4(), code="missing_document")
    )
    assert_problem(missing, 422, "complaint_reason_rules_invalid")

    unknown = await call(admin, "GET", f"{REASONS}/{uuid4()}")
    assert_problem(unknown, 404, "not_found")


async def test_reason_edit_rebinds_the_rules_basis(admin: Account, auth: Auth) -> None:
    first = await latest_document(auth)
    reason = await create_reason(admin, first.id)
    response = await call(
        admin,
        "POST",
        RULES,
        {
            "kind": DocumentKind.RULES.value,
            "text_ru": "Правила версии 2",
            "text_en": "Rules version 2",
        },
    )
    assert response.status_code == 201, response.text
    second_id = UUID(response.json()["id"])
    await accept(admin, second_id)

    patched = await call(
        admin,
        "PATCH",
        f"{REASONS}/{reason['id']}",
        {"version": 1, "rules_document_id": str(second_id)},
    )
    assert patched.status_code == 200, patched.text
    assert patched.json()["rules_version"] == first.version + 1
    assert patched.json()["rules_document_id"] == str(second_id)


async def test_validation_filters_and_noop_edit(admin: Account, auth: Auth) -> None:
    rules = await latest_document(auth)
    reason = await create_reason(admin, rules.id)
    same = await call(
        admin,
        "PATCH",
        f"{REASONS}/{reason['id']}",
        {"version": 1, "name_ru": "Спам"},
    )
    assert same.status_code == 200, same.text
    assert same.json()["version"] == 1

    empty_name = await call(
        admin, "POST", REASONS, {**reason_body(rules.id, code="empty"), "name_en": " "}
    )
    assert_problem(empty_name, 422, "validation_failed")
    empty_text = await call(
        admin,
        "POST",
        RULES,
        {
            "kind": DocumentKind.RULES.value,
            "text_ru": "Правила",
            "text_en": " ",
        },
    )
    assert_problem(empty_text, 422, "validation_failed")
    missing_document = await call(admin, "GET", f"{RULES}/{uuid4()}")
    assert_problem(missing_document, 404, "not_found")

    active = await call(admin, "GET", REASONS + "?active=true")
    assert [item["id"] for item in active.json()["items"]] == [reason["id"]]
    inactive = await call(admin, "GET", REASONS + "?active=false")
    assert inactive.json()["items"] == []


async def test_reason_edit_is_idempotent(admin: Account, auth: Auth) -> None:
    rules = await latest_document(auth)
    reason = await create_reason(admin, rules.id)
    key = str(uuid4())
    body = {"version": 1, "name_en": "Unsolicited messages"}
    first = await call(admin, "PATCH", f"{REASONS}/{reason['id']}", body, key=key)
    assert first.status_code == 200, first.text
    repeated = await call(admin, "PATCH", f"{REASONS}/{reason['id']}", body, key=key)
    assert repeated.status_code == 200
    assert repeated.json() == first.json()
    await auth.db.rollback()
    assert (
        await auth.db.scalar(
            select(ComplaintReason.version).where(
                ComplaintReason.id == UUID(reason["id"])
            )
        )
        == 2
    )


async def test_concurrent_publication_numbers_versions_once(
    admin: Account, auth: Auth
) -> None:
    before = await latest_document(auth)

    async def publish(text: str) -> httpx2.Response:
        return await call(
            admin,
            "POST",
            RULES,
            {
                "kind": DocumentKind.RULES.value,
                "text_ru": f"Правила {text}",
                "text_en": f"Rules {text}",
            },
        )

    responses = await asyncio.gather(publish("A"), publish("B"))
    assert [response.status_code for response in responses] == [201, 201]
    versions = sorted(response.json()["version"] for response in responses)
    assert versions == [before.version + 1, before.version + 2]
    await auth.db.rollback()
    assert (
        await auth.db.scalar(
            select(func.count())
            .select_from(DocumentVersion)
            .where(DocumentVersion.kind == DocumentKind.RULES)
        )
        == before.version + 2
    )
    assert len(await audit_records(auth, DOCUMENT_PUBLISHED)) == 2


async def test_failed_audit_rolls_back_publication_and_event(
    admin: Account, student: Account, auth: Auth, monkeypatch: pytest.MonkeyPatch
) -> None:
    cross = await latest_document(auth, DocumentKind.CROSS_BORDER)
    assert (
        await call(
            student,
            "PUT",
            "/me/consents/cross-border",
            {"document_id": str(cross.id), "accepted": True},
        )
    ).status_code == 204
    await auth.db.rollback()
    events_before = await auth.db.scalar(
        select(func.count())
        .select_from(OutboxMessage)
        .where(OutboxMessage.topic == CROSS_BORDER_EVENT)
    )

    async def fail(*_args: Any, **_kwargs: Any) -> None:
        raise RuntimeError("audit unavailable")

    monkeypatch.setattr(moderation_api, "record_action", fail)
    response = await call(
        admin,
        "POST",
        RULES,
        {
            "kind": DocumentKind.CROSS_BORDER.value,
            "text_ru": "Черновик",
            "text_en": "Not published",
        },
    )
    assert_problem(response, 500, "internal_error")

    after = await latest_document(auth, DocumentKind.CROSS_BORDER)
    assert after.id == cross.id
    assert after.version == cross.version
    await auth.db.rollback()
    assert (
        await auth.db.scalar(
            select(func.count())
            .select_from(OutboxMessage)
            .where(OutboxMessage.topic == CROSS_BORDER_EVENT)
        )
        == events_before
    )
    assert await audit_records(auth, DOCUMENT_PUBLISHED) == []


ROLES = ("student", "employee", "alumni", "headman", "moderator", "administrator")


@pytest.mark.parametrize("column", ROLES)
async def test_admin_api_role_matrix(column: str, auth: Auth, places: Places) -> None:
    """Only the administrator passes every admin probe; all roles see reasons."""
    setup = await sign_in(auth, "matrix-admin@staff.example", role=Role.ADMINISTRATOR)
    rules = await latest_document(auth)
    reason = await create_reason(setup, rules.id, code=f"matrix_{column}")

    if column == "administrator":
        actor = setup
    else:
        actor = await sign_in(
            auth,
            "matrix@staff.example"
            if column == "employee"
            else "matrix@university.example",
            role={
                "headman": Role.HEADMAN,
                "moderator": Role.MODERATOR,
            }.get(column),
            account_type="alumni" if column == "alumni" else None,
            places=places,
        )

    probes: list[tuple[str, str, dict[str, Any] | None, int]] = [
        ("GET", RULES, None, 200),
        ("GET", f"{RULES}/{rules.id}", None, 200),
        ("GET", REASONS, None, 200),
        ("GET", f"{REASONS}/{reason['id']}", None, 200),
        ("POST", REASONS, reason_body(rules.id, code=f"created_{column}"), 201),
        (
            "PATCH",
            f"{REASONS}/{reason['id']}",
            {"version": 1, "name_en": "Updated"},
            200,
        ),
        ("DELETE", f"{REASONS}/{reason['id']}", None, 204),
        ("GET", PUBLIC_REASONS, None, 200),
        (
            "POST",
            RULES,
            {
                "kind": DocumentKind.RULES.value,
                "text_ru": f"Правила {column}",
                "text_en": f"Rules {column}",
            },
            201,
        ),
    ]
    for method, path, body, allowed in probes:
        response = await call(actor, method, path, body)
        if path == PUBLIC_REASONS:
            assert response.status_code == 200, response.text
            assert response.json()["items"]
        elif column == "administrator":
            assert response.status_code == allowed, f"{method} {path}: {response.text}"
        else:
            assert_problem(response, 403, "forbidden")
