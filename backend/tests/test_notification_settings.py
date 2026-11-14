"""Notification settings, quiet hours and external delivery policy."""

import asyncio
from collections.abc import Iterator
from dataclasses import replace
from datetime import UTC, datetime, time
from typing import Any
from uuid import UUID, uuid4

import pytest
import time_machine
from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncEngine

from campus.modules.identity import User
from campus.modules.notifications import (
    EffectiveSettings,
    MutedChat,
    Notification,
    NotificationSettings,
    notification_consumers,
    notify,
    quiet_hours_active,
    register_channel,
)
from campus.modules.notifications.delivery import NOTIFICATION_TYPES
from campus.modules.realtime import grant_chat_access, revoke_chat_access
from tests.test_identity import EMAIL, Auth
from tests.test_listings import auth, borrower, owner, places
from tests.test_notifications import drain, feed, realtime
from tests.test_profile import Account, Places, moscow_profile

__all__ = [
    "auth",
    "borrower",
    "owner",
    "places",
    "realtime",
]

ROOT = "/api/v1/notifications/settings"
NIGHT_IN_MOSCOW = datetime(2026, 1, 15, 20, 30, tzinfo=UTC)  # 23:30 MSK
NOON_IN_MOSCOW = datetime(2026, 1, 15, 9, 0, tzinfo=UTC)  # 12:00 MSK


async def get_settings(account: Account) -> Any:
    response = await account.auth.client.get(ROOT, headers=account.headers)
    assert response.status_code == 200, response.text
    return response.json()


async def patch_settings(
    account: Account, body: dict[str, Any], key: str | None = None
) -> Any:
    return await account.auth.client.patch(
        ROOT,
        json=body,
        headers={"Idempotency-Key": key or str(uuid4()), **account.headers},
    )


async def enqueue(
    auth: Auth,
    account: Account,
    kind: str = "status.changed",
    params: dict[str, Any] | None = None,
) -> UUID:
    event_id = uuid4()
    notify(
        auth.db,
        {UUID(account.tokens["user"]["id"])},
        kind,
        params or {},
        event_id=event_id,
    )
    await auth.db.commit()
    return event_id


@pytest.fixture
def external() -> Iterator[list[UUID]]:
    """A registered external channel; its calls are idempotency keys."""
    calls: list[UUID] = []

    @register_channel("test_settings_external")
    async def adapter(_session: Any, _notification: Notification, key: UUID) -> None:
        calls.append(key)

    yield calls
    notification_consumers.remove("test_settings_external")


async def test_defaults_are_all_enabled_with_quiet_hours(
    auth: Auth, owner: Account
) -> None:
    data = await get_settings(owner)

    assert data["version"] == 0
    assert set(data["types"]) == NOTIFICATION_TYPES
    assert all(data["types"].values())
    assert data["quiet_hours"] == {
        "enabled": True,
        "start": "23:00:00",
        "end": "08:00:00",
    }
    assert data["timezone"] == "Europe/Moscow"
    assert data["muted_chat_ids"] == []
    assert (
        await auth.db.scalar(select(func.count()).select_from(NotificationSettings))
        == 0
    )


async def test_patch_changes_only_given_fields_and_persists(
    auth: Auth, owner: Account
) -> None:
    first = await patch_settings(
        owner,
        {
            "types": {"message.received": False},
            "quiet_hours": {"start": "22:30"},
        },
    )
    assert first.status_code == 200, first.text
    data = first.json()
    assert data["version"] == 1
    assert data["types"]["message.received"] is False
    assert data["types"]["status.changed"] is True
    assert data["quiet_hours"] == {
        "enabled": True,
        "start": "22:30:00",
        "end": "08:00:00",
    }

    second = await patch_settings(
        owner, {"version": 1, "quiet_hours": {"end": "07:00"}}
    )
    assert second.status_code == 200, second.text
    data = second.json()
    assert data["version"] == 2
    assert data["quiet_hours"] == {
        "enabled": True,
        "start": "22:30:00",
        "end": "07:00:00",
    }
    # An omitted type keeps the changed value.
    assert data["types"]["message.received"] is False

    other_device = Account(auth, await auth.login(email=EMAIL, device_id=str(uuid4())))
    assert await get_settings(other_device) == data
    assert (
        await auth.db.scalar(select(func.count()).select_from(NotificationSettings))
        == 1
    )


@pytest.mark.parametrize("role", ["student", "employee", "former_employee"])
async def test_each_role_manages_only_own_settings(
    auth: Auth, places: Places, role: str
) -> None:
    if role == "student":
        account = Account(auth, await auth.login())
        profile = moscow_profile(places)
    elif role == "employee":
        account = Account(auth, await auth.login(email="teacher@staff.example"))
        profile = moscow_profile(places, course=None)
    else:
        account = Account(auth, await auth.login())
        profile = moscow_profile(places, course=None)
        await auth.db.execute(
            update(User)
            .where(User.id == UUID(account.tokens["user"]["id"]))
            .values(account_type="former_employee")
        )
        await auth.db.commit()
    assert (await account.put(profile)).status_code == 200

    assert (await get_settings(account))["version"] == 0
    changed = await patch_settings(account, {"quiet_hours": {"start": "21:00"}})
    assert changed.status_code == 200, changed.text
    assert changed.json()["version"] == 1

    other = Account(auth, await auth.login(email="other@university.example"))
    assert (await other.put(moscow_profile(places))).status_code == 200
    untouched = await get_settings(other)
    assert untouched["version"] == 0
    assert untouched["quiet_hours"]["start"] == "23:00:00"


async def test_only_member_can_mute_chat(
    auth: Auth, owner: Account, borrower: Account
) -> None:
    owner_id = UUID(owner.tokens["user"]["id"])
    borrower_id = UUID(borrower.tokens["user"]["id"])
    own_chat, foreign_chat = uuid4(), uuid4()
    await grant_chat_access(auth.db, own_chat, owner_id)
    await grant_chat_access(auth.db, foreign_chat, borrower_id)
    await auth.db.commit()

    muted = await patch_settings(owner, {"muted_chat_ids": [str(own_chat)]})
    assert muted.status_code == 200, muted.text
    assert muted.json()["muted_chat_ids"] == [str(own_chat)]

    forbidden = await patch_settings(owner, {"muted_chat_ids": [str(foreign_chat)]})
    assert forbidden.status_code == 403
    assert forbidden.headers["content-type"] == "application/problem+json"
    assert forbidden.json()["code"] == "notification_chat_forbidden"

    foreign_attempt = await patch_settings(
        borrower, {"muted_chat_ids": [str(own_chat)]}
    )
    assert foreign_attempt.status_code == 403

    assert (await patch_settings(owner, {"muted_chat_ids": []})).status_code == 200
    assert await auth.db.scalar(select(func.count()).select_from(MutedChat)) == 0
    await revoke_chat_access(auth.db, own_chat, owner_id)
    await auth.db.commit()
    revoked = await patch_settings(owner, {"muted_chat_ids": [str(own_chat)]})
    assert revoked.status_code == 403


async def test_unknown_type_and_invalid_quiet_hours(
    owner: Account,
) -> None:
    unknown = await patch_settings(owner, {"types": {"not.a.type": False}})
    assert unknown.status_code == 422
    assert unknown.headers["content-type"] == "application/problem+json"
    assert unknown.json()["code"] == "notification_type_unknown"

    assert (
        await patch_settings(owner, {"quiet_hours": {"start": "22:00"}})
    ).status_code == 200
    empty = await patch_settings(owner, {"quiet_hours": {"end": "22:00"}})
    assert empty.status_code == 422
    assert empty.json()["code"] == "notification_quiet_hours_invalid"
    data = await get_settings(owner)
    assert data["quiet_hours"]["start"] == "22:00:00"
    assert data["quiet_hours"]["end"] == "08:00:00"

    aware = await patch_settings(owner, {"quiet_hours": {"start": "22:00:00+03:00"}})
    assert aware.status_code == 422
    assert aware.json()["code"] == "validation_failed"


async def test_idempotent_repeat_and_concurrent_stale_edit(
    auth: Auth, owner: Account
) -> None:
    key = str(uuid4())
    body = {"types": {"status.changed": False}}
    first = await patch_settings(owner, body, key=key)
    assert first.status_code == 200, first.text
    assert first.json()["version"] == 1

    replay = await patch_settings(owner, body, key=key)
    assert replay.status_code == 200
    assert replay.json() == first.json()
    assert replay.headers["Idempotent-Replayed"] == "true"

    reused = await patch_settings(owner, {"quiet_hours": {"enabled": False}}, key=key)
    assert reused.status_code == 422
    assert reused.json()["code"] == "idempotency_key_reused"

    async def change(payload: dict[str, Any]) -> Any:
        return await patch_settings(owner, {"version": 1, **payload})

    results = await asyncio.gather(
        change({"types": {"message.received": False}}),
        change({"quiet_hours": {"start": "22:00"}}),
    )
    assert sorted(result.status_code for result in results) == [200, 409]
    loser = next(result for result in results if result.status_code == 409)
    assert loser.headers["content-type"] == "application/problem+json"
    assert loser.json()["code"] == "notification_settings_version_conflict"
    assert loser.json()["current_version"] == 2

    data = await get_settings(owner)
    assert data["version"] == 2
    assert (
        sum(
            [
                data["types"]["message.received"] is False,
                data["quiet_hours"]["start"] == "22:00:00",
            ]
        )
        == 1
    )
    assert (
        await auth.db.scalar(select(func.count()).select_from(NotificationSettings))
        == 1
    )

    # Repeating equal settings with a new key is not a new version.
    unchanged = await patch_settings(
        owner,
        {"types": {"message.received": data["types"]["message.received"]}},
    )
    assert unchanged.status_code == 200
    assert unchanged.json()["version"] == 2


QUIET = EffectiveSettings(
    version=1,
    disabled_types=frozenset(),
    quiet_hours_enabled=True,
    quiet_hours_start=time(23, 0),
    quiet_hours_end=time(8, 0),
    muted_chats=frozenset(),
)


@pytest.mark.parametrize(
    ("utc_hour", "utc_minute", "expected"),
    [
        (19, 59, False),  # 22:59
        (20, 0, True),  # 23:00
        (23, 59, True),  # 02:59, across midnight
        (4, 59, True),  # 07:59
        (5, 0, False),  # 08:00
        (12, 0, False),
    ],
)
def test_quiet_hours_boundaries_in_city_time(
    utc_hour: int, utc_minute: int, expected: bool
) -> None:
    moment = datetime(2026, 1, 15, utc_hour, utc_minute, tzinfo=UTC)

    assert quiet_hours_active(moment, QUIET, "Europe/Moscow") is expected


def test_disabled_quiet_hours_are_never_active() -> None:
    current = replace(QUIET, quiet_hours_enabled=False)

    assert not quiet_hours_active(NIGHT_IN_MOSCOW, current, "Europe/Moscow")


async def test_quiet_hours_suppress_external_but_keep_feed(
    auth: Auth,
    owner: Account,
    engine: AsyncEngine,
    realtime: list[Any],
    external: list[UUID],
) -> None:
    with time_machine.travel(NIGHT_IN_MOSCOW, tick=False):
        await enqueue(auth, owner)
        await drain(engine, auth)
    assert external == []
    assert len(realtime) == 1
    assert len((await feed(owner))["items"]) == 1

    with time_machine.travel(NOON_IN_MOSCOW, tick=False):
        await enqueue(auth, owner)
        await drain(engine, auth)
    assert len(external) == 1
    assert len(realtime) == 2
    assert len((await feed(owner))["items"]) == 2


async def test_disabled_quiet_hours_deliver_at_night(
    auth: Auth, owner: Account, engine: AsyncEngine, external: list[UUID]
) -> None:
    with time_machine.travel(NIGHT_IN_MOSCOW, tick=False):
        changed = await patch_settings(owner, {"quiet_hours": {"enabled": False}})
        assert changed.status_code == 200, changed.text
        await enqueue(auth, owner)
        await drain(engine, auth)

    assert len(external) == 1


async def test_important_event_passes_quiet_hours(
    auth: Auth, owner: Account, engine: AsyncEngine, external: list[UUID]
) -> None:
    with time_machine.travel(NIGHT_IN_MOSCOW, tick=False):
        await enqueue(auth, owner, kind="listing.offer")
        await drain(engine, auth)

    assert len(external) == 1
    important = await auth.db.scalar(select(Notification.important))
    assert important is True


async def test_disabled_type_and_muted_chat_suppress_external(
    auth: Auth,
    owner: Account,
    engine: AsyncEngine,
    external: list[UUID],
) -> None:
    chat_id = uuid4()
    await grant_chat_access(auth.db, chat_id, UUID(owner.tokens["user"]["id"]))
    await auth.db.commit()

    with time_machine.travel(NOON_IN_MOSCOW, tick=False):
        disabled = await patch_settings(owner, {"types": {"status.changed": False}})
        assert disabled.status_code == 200, disabled.text
        await enqueue(auth, owner)
        await drain(engine, auth)
        assert external == []
        assert len((await feed(owner))["items"]) == 1

        muted = await patch_settings(owner, {"muted_chat_ids": [str(chat_id)]})
        assert muted.status_code == 200, muted.text
        await enqueue(
            auth, owner, kind="message.received", params={"chat_id": str(chat_id)}
        )
        await drain(engine, auth)
        assert external == []
        assert len((await feed(owner))["items"]) == 2

        unmuted = await patch_settings(owner, {"muted_chat_ids": []})
        assert unmuted.status_code == 200, unmuted.text
        await enqueue(
            auth, owner, kind="message.received", params={"chat_id": str(chat_id)}
        )
        await drain(engine, auth)

    assert len(external) == 1


async def test_quiet_hours_follow_city_timezone_change(
    auth: Auth,
    owner: Account,
    places: Places,
    engine: AsyncEngine,
    external: list[UUID],
) -> None:
    # 19:30 UTC is 22:30 in Moscow but 00:30 in Perm.
    evening = datetime(2026, 1, 15, 19, 30, tzinfo=UTC)
    with time_machine.travel(evening, tick=False):
        await enqueue(auth, owner)
        await drain(engine, auth)
        assert len(external) == 1

        moved = await owner.put(
            {
                "city_id": str(places.perm),
                "dormitory_id": str(places.perm_dormitory),
                "faculty_id": str(places.perm_faculty),
                "course": 2,
            }
        )
        assert moved.status_code == 200, moved.text
        await enqueue(auth, owner)
        await drain(engine, auth)

    assert len(external) == 1
    assert (await get_settings(owner))["timezone"] == "Asia/Yekaterinburg"


async def test_timezone_falls_back_until_profile_has_a_city(auth: Auth) -> None:
    account = Account(auth, await auth.login())

    assert (await get_settings(account))["timezone"] == "Europe/Moscow"
