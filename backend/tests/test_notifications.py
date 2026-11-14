"""Notification inbox acceptance on PostgreSQL, with real HTTP authorization."""

import asyncio
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID, uuid4

import pytest
import time_machine
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncEngine

from campus.core import clock
from campus.core.db import create_session_factory
from campus.core.deadlines import Deadline, process_due_deadlines
from campus.core.jobs import JobInfo
from campus.core.outbox import OutboxMessage, process_outbox
from campus.modules.identity import DocumentKind, publish_document
from campus.modules.listings.service import remind_meeting
from campus.modules.notifications import (
    Inbox,
    Notification,
    cancel_reminders,
    notification_consumers,
    notify,
    register_channel,
    replay_notification_events,
    schedule_reminders,
)
from campus.modules.notifications.delivery import (
    NOTIFICATION_TYPES,
    persist_notifications,
)
from campus.modules.notifications.reminders import remind
from campus.modules.realtime import personal_channel
from tests.test_identity import Auth
from tests.test_listings import auth, borrower, move, owner, places, publish, reserve
from tests.test_listings_meeting import accept, accepted, propose
from tests.test_profile import Account

__all__ = ["auth", "borrower", "owner", "places"]
ROOT = "/api/v1/notifications"


@pytest.fixture(autouse=True)
def long_lived_access(auth: Auth) -> None:
    auth.settings = auth.settings.model_copy(
        update={"access_token_ttl": timedelta(days=365)}
    )
    auth.app.state.settings = auth.settings


async def drain(engine: AsyncEngine, auth: Auth) -> None:
    sessions = create_session_factory(engine)
    # Each stage may enqueue the next stage; the failing delivery is delayed.
    for _ in range(10):
        if not await process_outbox(sessions, auth.settings):
            break


@pytest.fixture
def realtime(
    monkeypatch: pytest.MonkeyPatch,
) -> list[tuple[UUID, dict[str, Any], UUID]]:
    sent: list[tuple[UUID, dict[str, Any], UUID]] = []

    async def publish(user_id: UUID, data: dict[str, Any], delivery_id: UUID) -> None:
        sent.append((user_id, data, delivery_id))

    monkeypatch.setattr("campus.modules.realtime.publish_personal", publish)
    return sent


async def feed(account: Account, **params: Any) -> Any:
    response = await account.auth.client.get(
        ROOT, params=params, headers=account.headers
    )
    assert response.status_code == 200, response.text
    return response.json()


async def enqueue(auth: Auth, account: Account, **kwargs: Any) -> UUID:
    event_id = uuid4()
    notify(
        auth.db,
        {UUID(account.tokens["user"]["id"])},
        "status.changed",
        {"object_id": str(uuid4())},
        event_id=event_id,
        **kwargs,
    )
    await auth.db.commit()
    return event_id


async def test_rollback_replay_reordering_and_channel_failure(
    auth: Auth, owner: Account, engine: AsyncEngine, realtime: list[Any]
) -> None:
    user_id = UUID(owner.tokens["user"]["id"])
    notify(auth.db, {user_id}, "status.changed", {})
    await auth.db.rollback()
    await drain(engine, auth)
    assert (await feed(owner))["items"] == []
    attempts: list[UUID] = []

    @register_channel("test_broken", in_app=True)
    async def broken(_session: Any, _notification: Notification, key: UUID) -> None:
        attempts.append(key)
        raise ConnectionError("provider unavailable")

    try:
        event_id = await enqueue(auth, owner)
        # Same logical event in another source message, with a different order.
        notify(auth.db, {user_id}, "status.changed", {}, event_id=event_id)
        await auth.db.commit()
        await drain(engine, auth)
        items = (await feed(owner))["items"]
        assert len(items) == 1
        assert items[0]["sequence"] == 1
        assert attempts
        assert len(realtime) == 1
        assert set(realtime[0][1]) == {"notification_id", "sequence"}
        await replay_notification_events(auth.db)
        await auth.db.commit()
        await drain(engine, auth)
        assert len((await feed(owner))["items"]) == 1
        assert len(realtime) == 1
        with time_machine.travel(
            clock.now() + auth.settings.job_retry_base_delay, tick=False
        ):
            await drain(engine, auth)
        assert len(attempts) == 2
        assert attempts[0] == attempts[1]
        assert len((await feed(owner))["items"]) == 1
    finally:
        notification_consumers.remove("test_broken")


async def test_concurrent_duplicate_and_late_event(
    auth: Auth, owner: Account, engine: AsyncEngine, realtime: list[Any]
) -> None:
    del auth, realtime
    payload = {
        "event_id": str(uuid4()),
        "recipients": [owner.tokens["user"]["id"]],
        "type": "response.created",
        "params": {},
        "text": {"en": "Updated", "ru": "Обновлено"},
    }
    sessions = create_session_factory(engine)

    async def deliver() -> None:
        async with sessions() as session, session.begin():
            await persist_notifications(session, JobInfo(uuid4(), "test", payload, 1))

    await asyncio.gather(deliver(), deliver())
    first = (await feed(owner, ascending=True, size=1))["items"][0]
    # An older source timestamp saved later must remain recoverable.
    payload["event_id"] = str(uuid4())
    payload["occurred_at"] = (clock.now() - timedelta(days=1)).isoformat()
    await deliver()
    recovered = await feed(owner, ascending=True, after_sequence=first["sequence"])
    assert len(recovered["items"]) == 1
    assert recovered["items"][0]["sequence"] == 2


async def test_permissions_pagination_read_cursor_and_idempotency(
    auth: Auth,
    owner: Account,
    borrower: Account,
    engine: AsyncEngine,
    realtime: list[Any],
) -> None:
    del realtime
    for _ in range(3):
        await enqueue(auth, owner)
    await drain(engine, auth)
    page = await feed(owner, size=1, ascending=True)
    assert page["next_page"]
    assert len(page["items"]) == 1
    # The count covers all three pages, not only the returned one.
    assert page["unread_count"] == 3
    second = await feed(owner, size=1, ascending=True, cursor=page["next_page"])
    third = await feed(owner, size=1, ascending=True, cursor=second["next_page"])
    assert [p["items"][0]["sequence"] for p in (page, second, third)] == [1, 2, 3]
    assert [p["unread_count"] for p in (page, second, third)] == [3, 3, 3]
    assert third["next_page"] is None
    assert (await feed(borrower))["items"] == []
    for headers, expected in [({}, 401), (borrower.headers, 404)]:
        response = await auth.client.post(
            ROOT + "/read",
            json={"through_id": second["items"][0]["id"]},
            headers={**headers, "Idempotency-Key": str(uuid4())},
        )
        assert response.status_code == expected
        assert response.headers["content-type"] == "application/problem+json"
    other_cursor = await auth.client.get(
        ROOT,
        params={"cursor": page["next_page"], "ascending": True},
        headers=borrower.headers,
    )
    assert other_cursor.status_code == 400
    key = str(uuid4())
    body = {"through_id": second["items"][0]["id"]}
    headers = {**owner.headers, "Idempotency-Key": key}
    result = await auth.client.post(ROOT + "/read", json=body, headers=headers)
    assert result.status_code == 200
    assert result.json()["unread_count"] == 1
    replay = await auth.client.post(ROOT + "/read", json=body, headers=headers)
    assert replay.json() == result.json()
    assert replay.headers["Idempotent-Replayed"] == "true"
    conflict = await auth.client.post(
        ROOT + "/read", json={"through_id": page["items"][0]["id"]}, headers=headers
    )
    assert conflict.status_code == 422
    await auth.client.post(
        ROOT + "/read",
        json={"through_id": page["items"][0]["id"]},
        headers={**owner.headers, "Idempotency-Key": str(uuid4())},
    )
    final_feed = await feed(owner, ascending=True)
    assert [item["read"] for item in final_feed["items"]] == [True, True, False]
    assert final_feed["unread_count"] == 1


@pytest.mark.parametrize("category", ["event", "return"])
async def test_reminders_repetition_reschedule_cancel(
    auth: Auth, owner: Account, engine: AsyncEngine, realtime: list[Any], category: str
) -> None:
    del realtime
    sessions = create_session_factory(engine)
    now = clock.now()
    starts_at = now + timedelta(days=3)
    settings = auth.settings.model_copy(
        update={
            "meeting_reminder_long": timedelta(hours=24),
            "meeting_reminder_short": timedelta(hours=1),
            "return_reminder_before": timedelta(hours=24),
        }
    )

    async def schedule(at: Any) -> None:
        await schedule_reminders(
            auth.db,
            settings,
            key="test",
            category=category,  # type: ignore[arg-type]
            object_id=UUID(owner.tokens["user"]["id"]),
            recipients={UUID(owner.tokens["user"]["id"])},
            starts_at=at,
        )
        await auth.db.commit()

    await schedule(starts_at)
    with time_machine.travel(starts_at - timedelta(hours=24), tick=False):
        assert await process_due_deadlines(sessions, settings) == 1
        # Repeating the deadline by hand reproduces a retained job replay.
        job = await auth.db.scalar(
            select(OutboxMessage).where(OutboxMessage.topic == "notifications.send")
        )
        assert job is not None
        original = dict(job.payload)
        await auth.db.rollback()
        await schedule(starts_at)
        assert await process_due_deadlines(sessions, settings) == 0
        await drain(engine, auth)
        assert len((await feed(owner))["items"]) == 1
        # A queued old reminder cannot become a new notification after a move.
        await schedule(starts_at + timedelta(days=1))
        original["event_id"] = str(uuid4())
        await persist_notifications(auth.db, JobInfo(uuid4(), "test", original, 1))
        await auth.db.commit()
        assert len((await feed(owner))["items"]) == 1
    with time_machine.travel(starts_at + timedelta(days=1, hours=-1), tick=False):
        await process_due_deadlines(sessions, settings)
        await cancel_reminders(auth.db, "test")
        await auth.db.commit()
        await drain(engine, auth)
        assert len((await feed(owner))["items"]) == 1


async def test_available_listing_producer_contract(
    auth: Auth,
    owner: Account,
    borrower: Account,
    engine: AsyncEngine,
    realtime: list[Any],
) -> None:
    del realtime
    listing = await publish(owner)
    interaction = (await reserve(borrower, listing)).json()
    assert (await move(owner, listing, interaction, "accepted")).status_code == 200
    await drain(engine, auth)
    items = (await feed(borrower))["items"]
    assert items
    assert {item["type"] for item in items} == {"listing.activity"}
    assert all(item["object_id"] == listing["id"] for item in items)


@pytest.mark.parametrize(
    "kind", sorted(NOTIFICATION_TYPES - {"listing.meeting.reminder"})
)
async def test_registered_contracts(auth: Auth, owner: Account, kind: str) -> None:
    job = JobInfo(
        uuid4(),
        "test",
        {
            "event_id": str(uuid4()),
            "recipients": [owner.tokens["user"]["id"]],
            "type": kind,
            "params": {"object_id": str(uuid4())},
            "text": {"ru": "Обновлено", "en": "Updated"},
        },
        1,
    )
    await persist_notifications(auth.db, job)
    await auth.db.commit()
    assert await auth.db.scalar(select(func.count()).select_from(Notification)) == 1
    inbox = await auth.db.get(Inbox, UUID(owner.tokens["user"]["id"]))
    assert inbox is not None
    assert inbox.sequence == 1
    assert inbox.read_sequence == 0


async def test_unknown_contract_rejected(auth: Auth, owner: Account) -> None:
    with pytest.raises(ValueError, match="Unknown notification type"):
        await persist_notifications(
            auth.db,
            JobInfo(
                uuid4(),
                "test",
                {
                    "recipients": [owner.tokens["user"]["id"]],
                    "type": "unknown",
                    "params": {},
                    "text": {},
                },
                1,
            ),
        )
    await auth.db.rollback()
    # An obsolete reminder is harmless even if a deadline job is replayed.
    await remind(
        auth.db,
        JobInfo(
            uuid4(),
            "test",
            {
                "key": "missing",
                "revision": str(uuid4()),
                "kind": "long",
            },
            1,
        ),
    )


async def test_meeting_reminders_persist_once_and_discard_stale_delivery(
    auth: Auth,
    owner: Account,
    borrower: Account,
    engine: AsyncEngine,
    realtime: list[Any],
) -> None:
    del realtime

    sessions = create_session_factory(engine)
    now = clock.now()
    meeting_at = now + timedelta(days=2)
    listing, interaction = await accepted(owner, borrower)
    proposal = (await propose(owner, listing, interaction, meeting_at)).json()
    assert (
        await accept(borrower, listing, interaction, proposal["version"])
    ).status_code == 200
    await drain(engine, auth)
    with time_machine.travel(meeting_at - timedelta(hours=24), tick=False):
        await process_due_deadlines(sessions, auth.settings)
        deadline = await auth.db.scalar(
            select(Deadline).where(
                Deadline.topic == "listing.meeting_reminder",
                Deadline.payload["kind"].astext == "long",
            )
        )
        assert deadline is not None
        await remind_meeting(
            auth.db, JobInfo(deadline.id, deadline.topic, deadline.payload, 1)
        )
        await auth.db.commit()
        await drain(engine, auth)
        reminders = [
            item
            for item in (await feed(owner))["items"]
            if item["type"] == "listing.meeting.reminder"
        ]
        assert len(reminders) == 1
    with time_machine.travel(meeting_at - timedelta(hours=1), tick=False):
        await process_due_deadlines(sessions, auth.settings)
        # Move after the deadline fired, before its outbox delivery.
        proposal = (
            await propose(owner, listing, interaction, meeting_at + timedelta(days=1))
        ).json()
        assert (
            await accept(borrower, listing, interaction, proposal["version"])
        ).status_code == 200
        await drain(engine, auth)
        reminders = [
            item
            for item in (await feed(owner))["items"]
            if item["type"] == "listing.meeting.reminder"
        ]
        assert len(reminders) == 1


async def test_consent_forbidden_and_missing_key(auth: Auth, owner: Account) -> None:
    response = await auth.client.post(
        ROOT + "/read", json={"through_id": str(uuid4())}, headers=owner.headers
    )
    assert response.status_code == 400
    await publish_document(
        auth.db, DocumentKind.RULES, text_ru="Новые правила", text_en="New rules"
    )
    await auth.db.commit()
    for method, path, body in [
        ("GET", ROOT, None),
        ("POST", ROOT + "/read", {"through_id": str(uuid4())}),
    ]:
        response = await auth.client.request(
            method,
            path,
            headers={**owner.headers, "Idempotency-Key": str(uuid4())},
            json=body,
        )
        assert response.status_code == 403
        assert response.json()["code"] == "consent_required"


async def test_external_adapter_checks_live_consent(
    auth: Auth, owner: Account, engine: AsyncEngine, realtime: list[Any]
) -> None:
    del realtime
    calls: list[UUID] = []

    @register_channel("test_foreign", cross_border=True)
    async def foreign(
        _session: Any, _notification: Notification, delivery: UUID
    ) -> None:
        calls.append(delivery)

    docs = (await auth.client.get("/api/v1/documents")).json()
    document = next(doc for doc in docs if doc["kind"] == "cross_border_transfer")
    try:
        # Midday in the user's city: the default quiet hours do not apply.
        with time_machine.travel(datetime(2026, 6, 1, 9, 0, tzinfo=UTC), tick=False):
            for allowed in (False, True, False):
                response = await auth.client.put(
                    "/api/v1/me/consents/cross-border",
                    json={"document_id": document["id"], "accepted": allowed},
                    headers={**owner.headers, "Idempotency-Key": str(uuid4())},
                )
                assert response.status_code == 204
                await enqueue(auth, owner)
                await drain(engine, auth)
        assert len(calls) == 1
        assert len((await feed(owner))["items"]) == 3
    finally:
        notification_consumers.remove("test_foreign")


async def test_real_realtime_adapter_sends_private_reference(
    auth: Auth, owner: Account, engine: AsyncEngine, monkeypatch: pytest.MonkeyPatch
) -> None:
    sent: list[dict[str, Any]] = []

    class Client:
        async def publish(self, **kwargs: Any) -> None:
            sent.append(kwargs)

    @asynccontextmanager
    async def client(_settings: Any) -> AsyncIterator[Client]:
        yield Client()

    monkeypatch.setattr("campus.modules.realtime.publish.centrifugo_client", client)
    await enqueue(auth, owner)
    await drain(engine, auth)
    assert len(sent) == 1
    item = (await feed(owner))["items"][0]
    assert sent[0]["channel"] == personal_channel(UUID(owner.tokens["user"]["id"])).name
    assert sent[0]["data"] == {
        "notification_id": item["id"],
        "sequence": item["sequence"],
    }
    assert UUID(sent[0]["idempotency_key"])


@pytest.mark.parametrize(("category", "expected"), [("event", 2), ("return", 1)])
async def test_each_reminder_offset_and_deadline_replay(  # noqa: PLR0913, PLR0917
    auth: Auth,
    owner: Account,
    engine: AsyncEngine,
    realtime: list[Any],
    category: str,
    expected: int,
) -> None:
    del realtime
    starts_at = clock.now() + timedelta(days=3)
    await schedule_reminders(
        auth.db,
        auth.settings,
        key="offsets",
        category=category,  # type: ignore[arg-type]
        object_id=uuid4(),
        recipients={UUID(owner.tokens["user"]["id"])},
        starts_at=starts_at,
    )
    await auth.db.commit()
    with time_machine.travel(starts_at - timedelta(hours=1), tick=False):
        assert (
            await process_due_deadlines(create_session_factory(engine), auth.settings)
            == expected
        )
        jobs = list(
            await auth.db.scalars(
                select(Deadline).where(Deadline.topic == "notifications.remind")
            )
        )
        assert len(jobs) == expected
        for job in jobs:
            await remind(auth.db, JobInfo(job.id, job.topic, job.payload, 1))
        await auth.db.commit()
        await drain(engine, auth)
        assert len((await feed(owner))["items"]) == expected
