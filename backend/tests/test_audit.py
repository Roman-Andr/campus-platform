"""Audit journal of moderator and administrator actions on real PostgreSQL:
atomic records, append-only storage, own-case marks, conversation access,
the administrators-only journal API and retention."""

import asyncio
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Annotated, Any
from uuid import UUID, uuid4

import httpx2
import pytest
import time_machine
from fastapi import Query
from pydantic import BaseModel, SecretStr, ValidationError
from sqlalchemy import func, select, text, update
from sqlalchemy.exc import DBAPIError, IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from campus.core import clock
from campus.core.audit import (
    CONVERSATION_ACCESS,
    RETENTION_ROLE,
    VALUE_MAX_LENGTH,
    AuditPayloadError,
    AuditRecord,
    purge_expired_records,
    record_action,
    record_conversation_access,
)
from campus.core.config import AUDIT_RETENTION_MINIMUM, Settings
from campus.core.i18n import N_
from campus.core.web import DbSession, ProblemError, ProblemType, api_router
from campus.modules.administration import purge_audit_records
from campus.modules.identity import (
    Permissions,
    Role,
    RoleAssignment,
    User,
    admin_router,
)
from tests import test_profile
from tests.test_identity import Auth
from tests.test_profile import Account, Places

auth = test_profile.auth
places = test_profile.places

JOURNAL = "/api/v1/admin/audit"
TEST_ROOT = "/api/v1/admin/audit-test"
TEST_REFUSED = ProblemType("test_refused", 409, N_("Refused"))
APPEND_ONLY = "insufficient_privilege"


@dataclass
class Staff:
    auth: Auth
    accounts: dict[str, Account]
    ids: dict[str, UUID]
    reads: list[UUID]
    cases: dict[str, list[UUID]]

    @property
    def admin(self) -> Account:
        return self.accounts["admin"]

    @property
    def moderator(self) -> Account:
        return self.accounts["moderator"]

    def id(self, name: str) -> UUID:
        return self.ids[name]


async def sign_in(auth: Auth, email: str) -> tuple[Account, UUID]:
    account = Account(auth, await auth.login(email=email))
    return account, UUID(account.tokens["user"]["id"])


class Decision(BaseModel):
    reason: str
    fail: bool = False
    # A client cannot claim or deny an own case: the field is ignored.
    own_case: bool = False


def install_routes(staff: Staff) -> None:
    """Stand-ins of administrative modules: an action and a case reader."""
    nested = api_router(prefix="/audit-test")

    @nested.post("/headmen/{user_id}")
    async def appoint_headman(
        user_id: UUID,
        decision: Decision,
        context: Permissions,
        session: DbSession,
        dormitory_id: UUID,
    ) -> dict[str, str]:
        assignment = RoleAssignment(
            user_id=user_id, role=Role.HEADMAN, dormitory_id=dormitory_id
        )
        session.add(assignment)
        await session.flush()
        record = await record_action(
            session,
            actor_id=context.user_id,
            action="administration.role.assign",
            object_type="user",
            object_id=user_id,
            reason=decision.reason,
            participant_ids=[user_id],
            before={"roles": []},
            after={"roles": [{"role": "headman", "dormitory_id": dormitory_id}]},
        )
        if decision.fail:
            raise ProblemError(TEST_REFUSED)
        return {"record_id": str(record.id)}

    @nested.post("/cases/{case}/decisions")
    async def decide(
        case: str, decision: Decision, context: Permissions, session: DbSession
    ) -> dict[str, Any]:
        # Participants are loaded from the case on the server.
        record = await record_action(
            session,
            actor_id=context.user_id,
            action="moderation.dispute.decide",
            object_type="dispute",
            object_id=uuid4(),
            reason=decision.reason,
            participant_ids=staff.cases[case],
        )
        return {"own_case": record.own_case}

    @nested.get("/cases/{case}/messages")
    async def read_messages(
        case: str,
        context: Permissions,
        session: DbSession,
        broken: Annotated[bool, Query()] = False,
    ) -> dict[str, Any]:
        first, last = uuid4(), uuid4()
        await record_conversation_access(
            session,
            actor_id=context.user_id,
            # Longer than the column: the database rejects the record.
            object_type="dispute" * (20 if broken else 1),
            object_id=UUID(int=len(case)),
            reason="Dispute about a no-show",
            participant_ids=staff.cases[case],
            first_message_id=first,
            last_message_id=last,
            message_count=2,
        )
        staff.reads.append(context.user_id)
        return {"messages": ["hello", "bye"]}

    admin = admin_router()
    admin.include_router(nested)
    staff.auth.app.include_router(admin, prefix="/api/v1")


@pytest.fixture
async def staff(auth: Auth, places: Places) -> Staff:
    ids: dict[str, UUID] = {}
    accounts: dict[str, Account] = {}
    for name, email in [
        ("admin", "admin@university.example"),
        ("moderator", "moderator@university.example"),
        ("student", "student@university.example"),
        ("headman", "headman@university.example"),
        ("alumni", "alumni@university.example"),
        ("employee", "teacher@staff.example"),
    ]:
        accounts[name], ids[name] = await sign_in(auth, email)
    auth.db.add_all(
        [
            RoleAssignment(user_id=ids["admin"], role=Role.ADMINISTRATOR),
            RoleAssignment(user_id=ids["moderator"], role=Role.MODERATOR),
            RoleAssignment(
                user_id=ids["headman"], role=Role.HEADMAN, dormitory_id=places.dubki
            ),
        ]
    )
    await auth.db.execute(
        update(User).where(User.id == ids["alumni"]).values(account_type="alumni")
    )
    await auth.db.commit()
    staff = Staff(
        auth,
        accounts,
        ids,
        reads=[],
        cases={
            "own": [ids["moderator"], ids["student"]],
            "foreign": [ids["student"], ids["employee"]],
        },
    )
    install_routes(staff)
    return staff


async def post(
    account: Account, path: str, data: dict[str, Any], key: str | None = None
) -> httpx2.Response:
    return await account.auth.client.post(
        TEST_ROOT + path,
        json=data,
        headers={"Idempotency-Key": key or str(uuid4()), **account.headers},
    )


async def journal(account: Account, **params: Any) -> httpx2.Response:
    return await account.auth.client.get(
        JOURNAL, params=params, headers=account.headers
    )


async def records(db: AsyncSession) -> list[AuditRecord]:
    db.expire_all()
    rows = (await db.scalars(select(AuditRecord).order_by(AuditRecord.id))).all()
    db.expunge_all()  # keep loaded values after the rollback
    await db.rollback()
    return list(rows)


async def headmen(db: AsyncSession) -> int:
    count = await db.scalar(
        select(func.count())
        .select_from(RoleAssignment)
        .where(RoleAssignment.role == Role.HEADMAN)
    )
    await db.rollback()
    return count or 0


def appoint(staff: Staff, places: Places) -> str:
    return f"/headmen/{staff.id('student')}?dormitory_id={places.dubki}"


# Atomicity and idempotency


async def test_action_and_record_commit_together(staff: Staff, places: Places) -> None:
    response = await post(staff.admin, appoint(staff, places), {"reason": "Elected"})

    assert response.status_code == 200, response.text
    [record] = await records(staff.auth.db)
    assert str(record.id) == response.json()["record_id"]
    assert record.actor_id == staff.id("admin")
    assert record.action == "administration.role.assign"
    assert (record.object_type, record.object_id) == ("user", staff.id("student"))
    assert record.reason == "Elected"
    assert record.participant_ids == [staff.id("student")]
    assert record.own_case is False
    assert record.before == {"roles": []}
    assert record.after == {
        "roles": [{"role": "headman", "dormitory_id": str(places.dubki)}]
    }
    assert record.request_id == response.headers["X-Request-ID"]
    assert record.occurred_at <= clock.now()
    assert await headmen(staff.auth.db) == 2


async def test_failed_action_leaves_no_record(staff: Staff, places: Places) -> None:
    response = await post(
        staff.admin, appoint(staff, places), {"reason": "Elected", "fail": True}
    )

    assert response.status_code == 409
    assert response.headers["content-type"] == "application/problem+json"
    assert await records(staff.auth.db) == []
    assert await headmen(staff.auth.db) == 1


async def test_repeated_key_adds_no_record(staff: Staff, places: Places) -> None:
    key = str(uuid4())
    body = {"reason": "Elected"}

    first = await post(staff.admin, appoint(staff, places), body, key)
    second = await post(staff.admin, appoint(staff, places), body, key)
    other = await post(staff.admin, appoint(staff, places), {"reason": "No"}, key)

    assert first.status_code == second.status_code == 200
    assert second.content == first.content
    assert second.headers["Idempotent-Replayed"] == "true"
    assert other.status_code == 422
    assert other.json()["code"] == "idempotency_key_reused"
    assert len(await records(staff.auth.db)) == 1


async def test_concurrent_repeats_add_one_record(staff: Staff, places: Places) -> None:
    key = str(uuid4())

    responses = await asyncio.gather(
        *(
            post(staff.admin, appoint(staff, places), {"reason": "Elected"}, key)
            for _ in range(5)
        )
    )

    assert {r.status_code for r in responses} == {200}
    assert len({r.json()["record_id"] for r in responses}) == 1
    assert len(await records(staff.auth.db)) == 1
    assert await headmen(staff.auth.db) == 2


# Own case


@pytest.mark.parametrize(
    ("case", "claimed", "own"),
    [("own", False, True), ("foreign", True, False), ("foreign", False, False)],
)
async def test_own_case_comes_from_participants(
    staff: Staff, case: str, claimed: bool, own: bool
) -> None:
    response = await post(
        staff.moderator,
        f"/cases/{case}/decisions",
        {"reason": "Payment confirmed", "own_case": claimed},
    )

    assert response.status_code == 200, response.text
    assert response.json() == {"own_case": own}
    [record] = await records(staff.auth.db)
    assert record.own_case is own


async def test_journal_filters_own_cases(staff: Staff) -> None:
    for case in ("own", "foreign", "own"):
        response = await post(
            staff.moderator, f"/cases/{case}/decisions", {"reason": "Decided"}
        )
        assert response.status_code == 200

    own = await journal(staff.admin, own_case="true")
    other = await journal(staff.admin, own_case="false")

    assert own.status_code == 200, own.text
    assert len(own.json()["items"]) == 2
    assert all(item["own_case"] for item in own.json()["items"])
    assert [item["own_case"] for item in other.json()["items"]] == [False]


async def test_database_enforces_own_case(staff: Staff) -> None:
    db = staff.auth.db
    db.add(
        AuditRecord(
            actor_id=staff.id("moderator"),
            action="moderation.dispute.decide",
            object_type="dispute",
            participant_ids=[staff.id("moderator")],
            own_case=False,
        )
    )
    with pytest.raises(IntegrityError, match="own_case_by_participants"):
        await db.commit()
    await db.rollback()


# Append-only storage and retention


async def add_record(db: AsyncSession, actor_id: UUID | None = None) -> AuditRecord:
    record = await record_action(
        db,
        actor_id=actor_id,
        action="administration.domain.add",
        object_type="email_domain",
        object_id=uuid4(),
    )
    await db.commit()
    return record


@pytest.mark.parametrize(
    "statement",
    [
        "UPDATE audit_record SET reason = 'forged'",
        "UPDATE audit_record SET own_case = own_case",
        "DELETE FROM audit_record",
        "TRUNCATE audit_record",
    ],
)
@pytest.mark.parametrize("replica", [False, True])
async def test_records_cannot_change(
    staff: Staff, statement: str, replica: bool
) -> None:
    db = staff.auth.db
    await add_record(db, staff.id("admin"))
    if replica:
        # Ordinary triggers do not fire in this mode; these fire always.
        await db.execute(text("SET LOCAL session_replication_role = replica"))

    with pytest.raises(DBAPIError, match="append-only") as error:
        await db.execute(text(statement))
    assert error.value.orig.sqlstate == "42501"  # type: ignore[union-attr]
    await db.rollback()

    assert len(await records(db)) == 1
    await add_record(db, staff.id("admin"))
    assert len(await records(db)) == 2


async def test_application_has_no_direct_purge(staff: Staff) -> None:
    db = staff.auth.db
    owner = await db.scalar(
        text(
            "SELECT pg_get_userbyid(proowner) FROM pg_proc"
            " WHERE proname = 'audit_purge_expired'"
        )
    )
    assert owner == RETENTION_ROLE
    privileges = await db.scalar(
        text(
            "SELECT has_table_privilege(:role, 'audit_record', 'UPDATE')"
            " OR has_table_privilege(:role, 'audit_record', 'INSERT')"
        ),
        {"role": RETENTION_ROLE},
    )
    assert privileges is False
    can_login = await db.scalar(
        text("SELECT rolcanlogin FROM pg_roles WHERE rolname = :role"),
        {"role": RETENTION_ROLE},
    )
    assert can_login is False
    await db.rollback()


@pytest.mark.parametrize("days", [0, 1, 1095])
async def test_purge_refuses_short_retention(staff: Staff, days: int) -> None:
    db = staff.auth.db
    await add_record(db)
    with pytest.raises(DBAPIError, match="at least 1096 days"):
        await purge_expired_records(db, timedelta(days=days))
    await db.rollback()
    assert len(await records(db)) == 1


def test_configured_retention_has_a_floor() -> None:
    assert Settings().audit_retention == AUDIT_RETENTION_MINIMUM
    assert Settings(audit_retention=timedelta(days=2000)).audit_retention.days == 2000
    with pytest.raises(ValidationError):
        Settings(audit_retention=timedelta(days=1095))


async def test_purge_deletes_only_expired_records(
    staff: Staff, database_url: str
) -> None:
    db = staff.auth.db
    now = datetime.now(UTC)  # noqa: TID251 - the database clock decides
    ages = {"expired": 1097, "kept": 1095, "fresh": 0}
    for age in ages.values():
        with time_machine.travel(now - timedelta(days=age), tick=False):
            await add_record(db, staff.id("admin"))
    settings = Settings(database_url=SecretStr(database_url))
    sessions = async_sessionmaker(db.bind, expire_on_commit=False)

    assert await purge_audit_records(sessions, settings) == {"records": 1}
    assert await purge_audit_records(sessions, settings) == {"records": 0}

    left = sorted((now - r.occurred_at).days for r in await records(db))
    assert left == [0, 1095]


# Conversation access


async def test_conversation_access_is_recorded(staff: Staff) -> None:
    response = await staff.auth.client.get(
        TEST_ROOT + "/cases/foreign/messages", headers=staff.moderator.headers
    )

    assert response.status_code == 200, response.text
    assert staff.reads == [staff.id("moderator")]
    [record] = await records(staff.auth.db)
    assert record.action == CONVERSATION_ACCESS
    assert record.reason == "Dispute about a no-show"
    assert record.details is not None
    assert record.details["message_count"] == 2
    assert {"first_message_id", "last_message_id"} <= set(record.details)
    assert record.request_id == response.headers["X-Request-ID"]


async def test_failed_access_record_blocks_the_read(staff: Staff) -> None:
    response = await staff.auth.client.get(
        TEST_ROOT + "/cases/foreign/messages",
        params={"broken": "true"},
        headers=staff.moderator.headers,
    )

    assert response.status_code == 500
    assert response.headers["content-type"] == "application/problem+json"
    assert "hello" not in response.text
    assert staff.reads == []
    assert await records(staff.auth.db) == []


async def test_access_needs_a_reason(staff: Staff) -> None:
    db = staff.auth.db
    with pytest.raises(AuditPayloadError, match="reason"):
        await record_conversation_access(
            db,
            actor_id=staff.id("moderator"),
            object_type="complaint",
            object_id=uuid4(),
            reason="  ",
            participant_ids=[],
            first_message_id=None,
            last_message_id=None,
            message_count=0,
        )
    await db.rollback()


# No secrets or texts


@pytest.mark.parametrize(
    "payload",
    [
        {"before": {"refresh_token": "x"}},
        {"after": {"totp_secret": "x"}},
        {"details": {"Password": "x"}},
        {"details": {"access": {"accessToken": "x"}}},
        {"details": {"code": "123456"}},
        {"details": {"text": "Full message"}},
        {"after": {"messages": [{"id": 1}]}},
        {"details": {"items": [{"body": "x"}]}},
        {"details": {"note": "x" * (VALUE_MAX_LENGTH + 1)}},
    ],
)
async def test_secrets_and_texts_are_rejected(
    staff: Staff, payload: dict[str, Any]
) -> None:
    db = staff.auth.db
    with pytest.raises(AuditPayloadError):
        await record_action(
            db,
            actor_id=staff.id("admin"),
            action="administration.user.recover",
            object_type="user",
            **payload,
        )
    await db.rollback()
    assert await records(db) == []


# The journal API


@pytest.mark.parametrize(
    ("name", "allowed"),
    [
        ("student", False),
        ("employee", False),
        ("alumni", False),
        ("headman", False),
        ("moderator", False),
        ("admin", True),
    ],
)
async def test_only_administrators_read_the_journal(
    staff: Staff, name: str, allowed: bool
) -> None:
    await add_record(staff.auth.db, staff.id("admin"))
    response = await journal(staff.accounts[name])

    if allowed:
        assert response.status_code == 200, response.text
        assert len(response.json()["items"]) == 1
    else:
        assert response.status_code == 403, response.text
        assert response.headers["content-type"] == "application/problem+json"
        assert response.json()["code"] == "forbidden"
        assert "administration.domain.add" not in response.text


async def test_case_access_does_not_open_the_journal(staff: Staff) -> None:
    read = await staff.auth.client.get(
        TEST_ROOT + "/cases/own/messages", headers=staff.moderator.headers
    )
    assert read.status_code == 200

    response = await journal(staff.moderator, object_type="dispute")

    assert response.status_code == 403


async def test_journal_requires_sign_in(staff: Staff) -> None:
    response = await staff.auth.client.get(JOURNAL)

    assert response.status_code == 401


async def test_journal_filters_and_pages(staff: Staff) -> None:
    db = staff.auth.db
    start = datetime(2026, 1, 1, tzinfo=UTC)
    target = uuid4()
    for day, (actor, action, participants) in enumerate(
        [
            ("admin", "administration.role.assign", ["student"]),
            ("moderator", "moderation.complaint.resolve", ["student", "employee"]),
            ("moderator", "moderation.dispute.decide", ["moderator", "employee"]),
            ("admin", "administration.domain.add", []),
            ("admin", "administration.role.assign", ["headman"]),
        ]
    ):
        with time_machine.travel(start + timedelta(days=day), tick=False):
            await record_action(
                db,
                actor_id=staff.id(actor),
                action=action,
                object_type="user",
                object_id=target if day == 1 else uuid4(),
                participant_ids=[staff.id(p) for p in participants],
            )
    await db.commit()

    async def actions(**params: Any) -> list[str]:
        response = await journal(staff.admin, **params)
        assert response.status_code == 200, response.text
        return [item["action"].split(".")[-1] for item in response.json()["items"]]

    assert await actions() == ["assign", "add", "decide", "resolve", "assign"]
    assert await actions(order_by="occurred_at") == [
        "assign",
        "resolve",
        "decide",
        "add",
        "assign",
    ]
    assert await actions(actor_id=str(staff.id("moderator"))) == ["decide", "resolve"]
    assert await actions(action="administration.role.assign") == ["assign", "assign"]
    assert await actions(object_type="user", object_id=str(target)) == ["resolve"]
    assert await actions(participant_id=str(staff.id("employee"))) == [
        "decide",
        "resolve",
    ]
    assert await actions(own_case="true") == ["decide"]
    assert await actions(
        occurred_from="2026-01-02T00:00:00Z", occurred_to="2026-01-04T00:00:00+00:00"
    ) == ["decide", "resolve"]

    seen: list[str] = []
    cursor = None
    while True:
        params: dict[str, Any] = {"size": 2}
        if cursor:
            params["cursor"] = cursor
        page = (await journal(staff.admin, **params)).json()
        seen.extend(item["id"] for item in page["items"])
        cursor = page["next_page"]
        if cursor is None:
            break
    assert len(seen) == len(set(seen)) == 5

    invalid = await journal(staff.admin, occurred_from="2026-01-02")
    assert invalid.status_code == 422
    assert invalid.headers["content-type"] == "application/problem+json"


async def test_journal_is_in_openapi(staff: Staff) -> None:
    schema = (await staff.auth.client.get("/api/v1/openapi.json")).json()
    operation = schema["paths"][JOURNAL]["get"]
    assert operation["operationId"] == "list_audit_records"
    names = {parameter["name"] for parameter in operation["parameters"]}
    assert {"own_case", "participant_id", "actor_id", "cursor", "size"} <= names
    assert "403" in operation["responses"]
