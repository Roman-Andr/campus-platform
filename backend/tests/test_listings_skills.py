"""Skill listings and their lessons on real PostgreSQL and HTTP requests."""

from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID, uuid4

import httpx2
import pytest
import time_machine
from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncEngine

from campus.core import clock
from campus.core.db import create_session_factory
from campus.core.deadlines import Deadline, process_due_deadlines
from campus.modules.listings import (
    Interaction,
    InteractionStatus,
    LessonOption,
    Listing,
)
from tests.test_identity import Auth
from tests.test_listings import (
    auth,
    borrower,
    owner,
    places,
    publish,
    request,
    reserve,
    staff,
)
from tests.test_profile import Account, Places, moscow_profile

__all__ = ["auth", "borrower", "owner", "places", "staff"]


@pytest.fixture(autouse=True)
def long_lived_test_access(auth: Auth) -> None:
    """Keep HTTP credentials valid while moving time by days."""
    auth.settings = auth.settings.model_copy(
        update={"access_token_ttl": timedelta(days=365)}
    )
    auth.app.state.settings = auth.settings


def instant(at: datetime) -> str:
    return at.astimezone(UTC).isoformat().replace("+00:00", "Z")


def parse_instant(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def skill_body(**overrides: Any) -> dict[str, Any]:
    return {
        "title": "Python tutoring",
        "description": "I can explain algorithms and help with homework",
        "direction": "teach",
        **overrides,
    }


async def category_id(account: Account) -> str:
    response = await request(account, "GET", "/categories")
    assert response.status_code == 200, response.text
    return str(response.json()["items"][0]["id"])


async def publish_skill(account: Account, **overrides: Any) -> dict[str, Any]:
    body = skill_body(**overrides)
    body.setdefault("category_id", await category_id(account))
    response = await request(account, "POST", "/skills", body)
    assert response.status_code == 201, response.text
    result: dict[str, Any] = response.json()
    return result


def slot(
    at: datetime, location: str = "Main library", online: bool = False
) -> dict[str, Any]:
    result: dict[str, Any] = {"time": instant(at)}
    if online:
        result["online"] = True
    else:
        result["location"] = location
    return result


async def propose(
    account: Account,
    listing: dict[str, Any],
    options: list[dict[str, Any]],
    key: str | None = None,
) -> httpx2.Response:
    return await request(
        account,
        "POST",
        f"/{listing['id']}/lessons",
        {"options": options},
        key=key,
    )


def interaction_path(listing: dict[str, Any], interaction: dict[str, Any]) -> str:
    return f"/{listing['id']}/interactions/{interaction['id']}"


async def accept_option(
    account: Account,
    listing: dict[str, Any],
    interaction: dict[str, Any],
    option_id: str,
    key: str | None = None,
) -> httpx2.Response:
    return await request(
        account,
        "POST",
        interaction_path(listing, interaction) + "/lesson/accept",
        {"option_id": option_id},
        key=key,
    )


async def counter_propose(
    account: Account,
    listing: dict[str, Any],
    interaction: dict[str, Any],
    option: dict[str, Any],
) -> httpx2.Response:
    return await request(
        account,
        "POST",
        interaction_path(listing, interaction) + "/lesson/counter-proposals",
        option,
    )


async def repeat(
    account: Account,
    listing: dict[str, Any],
    interaction: dict[str, Any],
    options: list[dict[str, Any]],
    key: str | None = None,
) -> httpx2.Response:
    return await request(
        account,
        "POST",
        interaction_path(listing, interaction) + "/repeat",
        {"options": options},
        key=key,
    )


async def accepted_lesson(
    owner_account: Account,
    borrower_account: Account,
    **overrides: Any,
) -> tuple[dict[str, Any], dict[str, Any]]:
    listing = await publish_skill(owner_account, **overrides)
    interaction = (
        await propose(
            borrower_account,
            listing,
            [
                slot(clock.now() + timedelta(days=1)),
                slot(clock.now() + timedelta(days=2)),
            ],
        )
    ).json()
    option_id = interaction["options"][0]["id"]
    response = await accept_option(owner_account, listing, interaction, option_id)
    assert response.status_code == 200, response.text
    return listing, response.json()


async def other_account(auth: Auth, places: Places, email: str) -> Account:
    account = Account(auth, await auth.login(email=email))
    assert (await account.put(moscow_profile(places))).status_code == 200
    return account


async def deadlines(account: Account) -> int:
    assert isinstance(account.auth.db.bind, AsyncEngine)
    return await process_due_deadlines(
        create_session_factory(account.auth.db.bind), account.auth.settings
    )


def settings(account: Account, **changes: Any) -> None:
    account.auth.settings = account.auth.settings.model_copy(update=changes)
    account.auth.app.state.settings = account.auth.settings


async def test_skill_listing_is_permanent_and_directional(
    owner: Account, borrower: Account
) -> None:
    listing = await publish_skill(owner, direction="teach")

    assert listing["kind"] == "skill"
    assert listing["status"] == "active"
    assert listing["direction"] == "teach"
    assert listing["expires_at"] is None

    found = (await request(borrower, "GET", "?kind=skill")).json()["items"]
    assert [item["id"] for item in found] == [listing["id"]]
    assert found[0]["direction"] == "teach"

    learn = await publish_skill(owner, title="Learn guitar", direction="learn")
    assert learn["direction"] == "learn"

    detail = (await request(borrower, "GET", f"/{listing['id']}")).json()
    assert detail["kind"] == "skill"
    assert detail["direction"] == "teach"


async def test_skill_creation_permissions(
    owner: Account, borrower: Account, staff: Account
) -> None:
    staff_body = skill_body()
    staff_body["category_id"] = await category_id(staff)
    assert (await request(staff, "POST", "/skills", staff_body)).status_code == 403
    # The author cannot respond to their own offer.
    listing = await publish_skill(owner)
    response = await propose(
        owner,
        listing,
        [slot(clock.now() + timedelta(days=1)), slot(clock.now() + timedelta(days=2))],
    )
    assert response.status_code == 403
    borrower_body = skill_body(direction="learn")
    borrower_body["category_id"] = await category_id(borrower)
    assert (
        await request(borrower, "POST", "/skills", borrower_body)
    ).status_code == 201


async def test_lesson_needs_two_or_three_options(
    owner: Account, borrower: Account
) -> None:
    listing = await publish_skill(owner)
    now = clock.now()
    one = [slot(now + timedelta(days=1))]
    four = [slot(now + timedelta(days=index + 1)) for index in range(4)]
    for options in (one, four):
        response = await propose(borrower, listing, options)
        assert response.status_code == 422, response.text
        assert response.headers["content-type"] == "application/problem+json"
        assert response.json()["code"] == "lesson_options_invalid"

    for options in (
        [slot(now + timedelta(days=1)), slot(now + timedelta(days=2))],
        [
            slot(now + timedelta(days=1)),
            slot(now + timedelta(days=2)),
            slot(now + timedelta(days=3)),
        ],
    ):
        response = await propose(borrower, listing, options)
        assert response.status_code == 201, response.text
        body = response.json()
        assert body["status"] == "pending"
        assert len(body["options"]) == len(options)
        assert body["options"][0]["status"] == "proposed"
        assert (
            now + timedelta(hours=24)
            <= parse_instant(body["response_due_at"])
            <= now + timedelta(hours=24, seconds=5)
        )

    past = [slot(now - timedelta(hours=1)), slot(now + timedelta(days=1))]
    response = await propose(borrower, listing, past)
    assert response.status_code == 422
    assert response.json()["code"] == "meeting_time_invalid"

    mixed = [
        {"time": instant(now + timedelta(days=1)), "location": "Hall", "online": True},
        slot(now + timedelta(days=2)),
    ]
    response = await propose(borrower, listing, mixed)
    assert response.status_code == 422
    assert response.json()["code"] == "validation_failed"


async def test_author_accepts_one_option_and_meeting_is_scheduled(
    owner: Account, borrower: Account, staff: Account, auth: Auth, places: Places
) -> None:
    listing = await publish_skill(owner)
    first_at = clock.now() + timedelta(days=1)
    second_at = clock.now() + timedelta(days=3)
    response = await propose(
        borrower, listing, [slot(first_at), slot(second_at, "Cafe")]
    )
    interaction = response.json()
    first, second = interaction["options"]

    # Only the author answers the responder's options.
    assert (
        await accept_option(borrower, listing, interaction, first["id"])
    ).status_code == 403
    assert (
        await accept_option(staff, listing, interaction, first["id"])
    ).status_code == 403

    response = await accept_option(owner, listing, interaction, first["id"])
    assert response.status_code == 200, response.text
    accepted = response.json()
    assert accepted["status"] == "accepted"
    assert accepted["meeting"]["status"] == "scheduled"
    assert parse_instant(accepted["meeting"]["scheduled_at"]) == first_at
    assert accepted["meeting"]["location"] == "Main library"
    assert accepted["meeting"]["online"] is False
    assert accepted["meeting"]["scheduled_by_id"] == borrower.tokens["user"]["id"]
    statuses = {option["id"]: option["status"] for option in accepted["options"]}
    assert statuses[first["id"]] == "selected"
    assert statuses[second["id"]] == "declined"

    # The permanent listing stays active and takes another participant.
    detail = (await request(owner, "GET", f"/{listing['id']}")).json()
    assert detail["status"] == "active"
    assert detail["expires_at"] is None
    other = await other_account(auth, places, "third@university.example")
    second_lesson = (
        await propose(
            other,
            listing,
            [slot(first_at + timedelta(days=1)), slot(second_at + timedelta(days=1))],
        )
    ).json()
    response = await accept_option(
        owner, listing, second_lesson, second_lesson["options"][0]["id"]
    )
    assert response.status_code == 200, response.text
    assert (await request(owner, "GET", f"/{listing['id']}")).json()[
        "status"
    ] == "active"


def meeting_identity(
    meeting: dict[str, Any],
) -> tuple[str, str, datetime, Any, bool, str]:
    return (
        meeting["id"],
        meeting["status"],
        parse_instant(meeting["scheduled_at"]),
        meeting["location"],
        meeting["online"],
        meeting["scheduled_by_id"],
    )


async def test_three_option_meeting_is_visible_to_both_sides(
    owner: Account, borrower: Account
) -> None:
    listing = await publish_skill(owner)
    first_at = clock.now() + timedelta(days=1)
    second_at = clock.now() + timedelta(days=2)
    third_at = clock.now() + timedelta(days=3)
    interaction = (
        await propose(
            borrower,
            listing,
            [
                slot(first_at),
                slot(second_at, "Cafe"),
                slot(third_at, "Faculty hall"),
            ],
        )
    ).json()
    assert len(interaction["options"]) == 3

    response = await accept_option(
        owner, listing, interaction, interaction["options"][1]["id"]
    )
    assert response.status_code == 200, response.text
    accepted = response.json()
    meeting = accepted["meeting"]
    assert meeting["status"] == "scheduled"
    assert parse_instant(meeting["scheduled_at"]) == second_at
    assert meeting["location"] == "Cafe"
    assert meeting["online"] is False
    assert meeting["scheduled_by_id"] == borrower.tokens["user"]["id"]

    # The author reads the same scheduled meeting in the incoming list.
    incoming = (await request(owner, "GET", f"/{listing['id']}/interactions")).json()
    author_view = next(
        item for item in incoming["items"] if item["id"] == interaction["id"]
    )
    assert author_view["status"] == "accepted"
    assert meeting_identity(author_view["meeting"]) == meeting_identity(meeting)

    # The participant reads the same scheduled meeting in own participation.
    mine = (await request(borrower, "GET", "/reservations/mine")).json()
    participant_view = next(
        item for item in mine["items"] if item["id"] == interaction["id"]
    )
    assert participant_view["status"] == "accepted"
    assert participant_view["listing"]["id"] == listing["id"]
    assert meeting_identity(participant_view["meeting"]) == meeting_identity(meeting)
    selected = next(
        option
        for option in participant_view["options"]
        if option["status"] == "selected"
    )
    assert parse_instant(selected["time"]) == second_at


async def test_online_lesson_has_no_place(owner: Account, borrower: Account) -> None:
    listing = await publish_skill(owner)
    first_at = clock.now() + timedelta(days=1)
    interaction = (
        await propose(
            borrower,
            listing,
            [
                slot(first_at, online=True),
                slot(first_at + timedelta(days=1), online=True),
            ],
        )
    ).json()
    assert interaction["options"][0]["online"] is True
    assert interaction["options"][0]["location"] is None

    response = await accept_option(
        owner, listing, interaction, interaction["options"][0]["id"]
    )
    assert response.status_code == 200, response.text
    meeting = response.json()["meeting"]
    assert meeting["online"] is True
    assert meeting["location"] is None
    assert parse_instant(meeting["scheduled_at"]) == first_at


async def test_author_counter_proposal_and_responder_accepts(
    owner: Account, borrower: Account, staff: Account
) -> None:
    listing = await publish_skill(owner, direction="learn")
    interaction = (
        await propose(
            borrower,
            listing,
            [
                slot(clock.now() + timedelta(days=1)),
                slot(clock.now() + timedelta(days=2)),
            ],
        )
    ).json()
    proposed_at = clock.now() + timedelta(days=5)

    # Only the author may reject the options by offering another time.
    assert (
        await counter_propose(borrower, listing, interaction, slot(proposed_at))
    ).status_code == 403
    assert (
        await counter_propose(staff, listing, interaction, slot(proposed_at))
    ).status_code == 403
    response = await counter_propose(
        owner, listing, interaction, slot(proposed_at, "Faculty hall")
    )
    assert response.status_code == 200, response.text
    countered = response.json()
    assert countered["status"] == "pending"
    assert countered["response_due_at"] is None
    counter = next(
        option
        for option in countered["options"]
        if option["proposed_by_id"] == owner.tokens["user"]["id"]
    )
    assert counter["status"] == "proposed"
    assert parse_instant(counter["time"]) == proposed_at

    # The author cannot accept their own option; the responder can.
    assert (
        await accept_option(owner, listing, countered, counter["id"])
    ).status_code == 403
    assert (
        await accept_option(staff, listing, countered, counter["id"])
    ).status_code == 403
    response = await accept_option(borrower, listing, countered, counter["id"])
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["status"] == "accepted"
    assert parse_instant(body["meeting"]["scheduled_at"]) == proposed_at
    assert body["meeting"]["location"] == "Faculty hall"
    assert body["meeting"]["scheduled_by_id"] == owner.tokens["user"]["id"]


async def test_author_timeout_rejects_lesson(owner: Account, borrower: Account) -> None:
    now = clock.now()
    with time_machine.travel(now, tick=False):
        listing = await publish_skill(owner)
        interaction = (
            await propose(
                borrower,
                listing,
                [
                    slot(now + timedelta(days=1)),
                    slot(now + timedelta(days=2)),
                ],
            )
        ).json()
        assert parse_instant(interaction["response_due_at"]) == now + timedelta(
            hours=24
        )
        assert await deadlines(owner) == 0

    with time_machine.travel(
        now + timedelta(hours=24) - timedelta(seconds=1), tick=False
    ):
        assert await deadlines(owner) == 0

    with time_machine.travel(now + timedelta(hours=24, seconds=1), tick=False):
        assert await deadlines(owner) == 1
        assert await deadlines(owner) == 0
        detail = (await request(owner, "GET", f"/{listing['id']}")).json()
        assert detail["status"] == "active"
        assert detail["expires_at"] is None
        await owner.auth.db.rollback()
        stored = await owner.auth.db.get(Interaction, UUID(interaction["id"]))
        assert stored is not None
        assert stored.status == "rejected"
        events = (
            await request(
                owner,
                "GET",
                f"/{listing['id']}/interactions/{interaction['id']}/events",
            )
        ).json()["items"]
        auto_rejected = [
            event for event in events if event["action"] == "auto_rejected"
        ]
        assert [event["reason"] for event in auto_rejected] == ["author_timeout"]


async def test_timeout_is_configurable(owner: Account, borrower: Account) -> None:
    settings(owner, listing_response_timeout=timedelta(hours=2))
    with time_machine.travel(clock.now(), tick=False):
        listing = await publish_skill(owner)
        now = clock.now()
        interaction = (
            await propose(
                borrower,
                listing,
                [slot(now + timedelta(days=1)), slot(now + timedelta(days=2))],
            )
        ).json()
        assert parse_instant(interaction["response_due_at"]) == now + timedelta(hours=2)


async def test_repeat_lesson_from_accepted_and_completed(
    owner: Account, borrower: Account, staff: Account
) -> None:
    listing = await publish_skill(owner)
    original = (
        await propose(
            borrower,
            listing,
            [
                slot(clock.now() + timedelta(days=1)),
                slot(clock.now() + timedelta(days=2)),
            ],
        )
    ).json()
    accepted = (
        await accept_option(owner, listing, original, original["options"][0]["id"])
    ).json()
    assert accepted["status"] == "accepted"

    options = [
        slot(clock.now() + timedelta(days=7)),
        slot(clock.now() + timedelta(days=8)),
    ]
    assert (await repeat(staff, listing, accepted, options)).status_code == 403
    response = await repeat(borrower, listing, accepted, options)
    assert response.status_code == 201, response.text
    repeated = response.json()
    assert repeated["id"] != accepted["id"]
    assert repeated["listing_id"] == listing["id"]
    assert repeated["participant_id"] == borrower.tokens["user"]["id"]
    assert repeated["status"] == "pending"
    assert len(repeated["options"]) == 2

    # The author may also start the next lesson; no author answer is due then.
    response = await repeat(owner, listing, accepted, options)
    assert response.status_code == 201, response.text
    assert response.json()["participant_id"] == borrower.tokens["user"]["id"]
    assert response.json()["response_due_at"] is None

    await owner.auth.db.execute(
        update(Interaction)
        .where(Interaction.id == UUID(accepted["id"]))
        .values(status=InteractionStatus.COMPLETED)
    )
    await owner.auth.db.commit()
    response = await repeat(borrower, listing, accepted, options)
    assert response.status_code == 201, response.text

    # The same option rule applies to a repeat.
    response = await repeat(borrower, listing, accepted, options[:1])
    assert response.status_code == 422
    assert response.json()["code"] == "lesson_options_invalid"


async def test_repeat_is_idempotent(owner: Account, borrower: Account) -> None:
    listing, accepted = await accepted_lesson(owner, borrower)
    options = [
        slot(clock.now() + timedelta(days=10)),
        slot(clock.now() + timedelta(days=11)),
    ]
    key = str(uuid4())
    first = await repeat(borrower, listing, accepted, options, key=key)
    second = await repeat(borrower, listing, accepted, options, key=key)
    assert first.status_code == 201, first.text
    assert second.status_code == 201, second.text
    assert first.json() == second.json()

    await borrower.auth.db.rollback()
    count = await borrower.auth.db.scalar(
        select(func.count())
        .select_from(Interaction)
        .where(Interaction.listing_id == UUID(listing["id"]))
    )
    assert count == 2


async def test_skill_and_lesson_are_idempotent(
    owner: Account, borrower: Account
) -> None:
    body = skill_body()
    body["category_id"] = await category_id(owner)
    key = str(uuid4())
    first = await request(owner, "POST", "/skills", body, key=key)
    second = await request(owner, "POST", "/skills", body, key=key)
    assert first.status_code == 201, first.text
    assert second.status_code == 201, second.text
    assert first.json() == second.json()

    await owner.auth.db.rollback()
    listings = await owner.auth.db.scalar(
        select(func.count())
        .select_from(Listing)
        .where(
            Listing.kind == "skill",
            Listing.author_id == UUID(owner.tokens["user"]["id"]),
        )
    )
    assert listings == 1

    listing = first.json()
    options = [
        slot(clock.now() + timedelta(days=1)),
        slot(clock.now() + timedelta(days=2)),
    ]
    lesson_key = str(uuid4())
    first_lesson = await propose(borrower, listing, options, key=lesson_key)
    second_lesson = await propose(borrower, listing, options, key=lesson_key)
    assert first_lesson.status_code == 201, first_lesson.text
    assert second_lesson.status_code == 201, second_lesson.text
    assert first_lesson.json() == second_lesson.json()

    await borrower.auth.db.rollback()
    interactions = await borrower.auth.db.scalar(
        select(func.count())
        .select_from(Interaction)
        .where(Interaction.listing_id == UUID(listing["id"]))
    )
    options_count = await borrower.auth.db.scalar(
        select(func.count()).select_from(LessonOption)
    )
    deadlines_count = await borrower.auth.db.scalar(
        select(func.count())
        .select_from(Deadline)
        .where(Deadline.key == f"interaction:{first_lesson.json()['id']}")
    )
    assert (interactions, options_count, deadlines_count) == (1, 2, 1)


async def test_lesson_errors_are_localized(owner: Account, borrower: Account) -> None:
    listing = await publish_skill(owner)
    body = {"options": [slot(clock.now() + timedelta(days=1))]}
    headers = {
        "Idempotency-Key": str(uuid4()),
        "Accept-Language": "ru",
        **borrower.headers,
    }
    response = await borrower.auth.client.post(
        f"/api/v1/listings/{listing['id']}/lessons", json=body, headers=headers
    )
    assert response.status_code == 422
    assert "вариант" in response.json()["detail"]

    headers["Accept-Language"] = "en"
    headers["Idempotency-Key"] = str(uuid4())
    response = await borrower.auth.client.post(
        f"/api/v1/listings/{listing['id']}/lessons", json=body, headers=headers
    )
    assert response.status_code == 422
    assert response.json()["detail"] == "A lesson has from 2 to 3 time options."


async def test_giveaway_cannot_be_booked_as_a_lesson(
    owner: Account, borrower: Account
) -> None:
    listing = await publish(owner)
    response = await propose(
        borrower,
        listing,
        [slot(clock.now() + timedelta(days=1)), slot(clock.now() + timedelta(days=2))],
    )
    assert response.status_code == 409


async def test_reservation_of_skill_listing_is_rejected(
    owner: Account, borrower: Account
) -> None:
    listing = await publish_skill(owner)
    response = await reserve(borrower, listing)
    assert response.status_code == 409


async def test_skill_transitions_and_permanent_listing_rules(
    owner: Account, borrower: Account
) -> None:
    listing = await publish_skill(owner)
    now = clock.now()
    options = [slot(now + timedelta(days=1)), slot(now + timedelta(days=2))]
    interaction = (await propose(borrower, listing, options)).json()

    # A lesson becomes accepted only through a selected time option.
    response = await request(
        owner,
        "POST",
        f"/{listing['id']}/interactions/{interaction['id']}/transition",
        {"status": "accepted"},
    )
    assert response.status_code == 409
    assert (
        await request(
            borrower,
            "POST",
            f"/{listing['id']}/interactions/{interaction['id']}/transition",
            {"status": "cancelled"},
        )
    ).status_code == 200

    interaction = (await propose(borrower, listing, options)).json()
    assert (
        await request(
            owner,
            "POST",
            f"/{listing['id']}/interactions/{interaction['id']}/transition",
            {"status": "rejected"},
        )
    ).status_code == 200

    # A permanent listing cannot be extended or republished.
    assert (await request(owner, "POST", f"/{listing['id']}/extend")).status_code == 409
    assert (
        await request(owner, "POST", f"/{listing['id']}/publish")
    ).status_code == 409

    # An accepted lesson may still be cancelled by the participant.
    accepted = (await propose(borrower, listing, options)).json()
    accepted = (
        await accept_option(owner, listing, accepted, accepted["options"][0]["id"])
    ).json()
    assert (
        await request(
            borrower,
            "POST",
            f"/{listing['id']}/interactions/{accepted['id']}/transition",
            {"status": "cancelled"},
        )
    ).status_code == 200


async def test_employee_responds_only_to_community_skills(
    owner: Account, staff: Account
) -> None:
    now = clock.now()
    options = [slot(now + timedelta(days=1)), slot(now + timedelta(days=2))]
    students = await publish_skill(owner)
    assert (await propose(staff, students, options)).status_code == 403
    community = await publish_skill(owner, audience="community")
    assert (await propose(staff, community, options)).status_code == 201
