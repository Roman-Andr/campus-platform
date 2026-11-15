"""Reviews: mutual reveal, editing, one answer and moderation hiding.

The tests run on a real PostgreSQL with controlled time and cover the
window counted from the completion, the reveal of both reviews or by the
durable deadline with its catch-up, the single answer, the event one-way
rule, the purchase pair, the hidden review, races and idempotency.
"""

import asyncio
from datetime import UTC, datetime, timedelta
from typing import Any, NamedTuple
from uuid import UUID, uuid4

import httpx2
import pytest
import time_machine
from sqlalchemy import func, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker

from campus.core import clock
from campus.core.db import create_session_factory
from campus.core.deadlines import Deadline, process_due_deadlines
from campus.core.outbox import process_outbox
from campus.modules.listings import (
    CompletionMethod,
    Interaction,
    InteractionStatus,
    ListingEvent,
)
from campus.modules.reputation import Review, ReviewReply, ReviewTag, reveal_key
from campus.modules.reputation.reviews import REVIEW_REVEAL_TOPIC
from tests.test_confirmation_code import confirm, issue
from tests.test_event_attendance import event_at, signup
from tests.test_identity import Auth
from tests.test_listing_purchase import join, publish_purchase
from tests.test_listings import (
    auth,
    borrower,
    move,
    owner,
    places,
    publish,
    request,
    reserve,
    staff,
)
from tests.test_profile import Account, Places, moscow_profile
from tests.test_qr import accepted, user_id

__all__ = ["auth", "borrower", "owner", "places", "staff"]

ROOT = "/api/v1/listings"


@pytest.fixture(autouse=True)
def long_lived_access(auth: Auth) -> None:
    """Keep access tokens valid while tests move time by days."""
    auth.settings = auth.settings.model_copy(
        update={"access_token_ttl": timedelta(days=365)}
    )
    auth.app.state.settings = auth.settings


@pytest.fixture
async def sessions(engine: AsyncEngine) -> async_sessionmaker[AsyncSession]:
    return create_session_factory(engine)


def parse_instant(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def review_path(listing: dict[str, Any], interaction: dict[str, Any]) -> str:
    return f"/{listing['id']}/interactions/{interaction['id']}/review"


async def review(  # noqa: PLR0913, PLR0917 - a request builder
    account: Account,
    listing: dict[str, Any],
    interaction: dict[str, Any],
    rating: int = 5,
    tags: list[str] | None = None,
    text: str | None = None,
    key: str | None = None,
) -> httpx2.Response:
    body: dict[str, Any] = {"rating": rating}
    if tags is not None:
        body["tags"] = tags
    if text is not None:
        body["text"] = text
    return await request(
        account, "POST", review_path(listing, interaction), body, key=key
    )


async def edit(  # noqa: PLR0913, PLR0917 - a request builder
    account: Account,
    listing: dict[str, Any],
    interaction: dict[str, Any],
    rating: int,
    tags: list[str] | None = None,
    text: str | None = None,
    key: str | None = None,
) -> httpx2.Response:
    body: dict[str, Any] = {"rating": rating}
    if tags is not None:
        body["tags"] = tags
    if text is not None:
        body["text"] = text
    return await request(
        account, "PATCH", review_path(listing, interaction), body, key=key
    )


async def state(
    account: Account, listing: dict[str, Any], interaction: dict[str, Any]
) -> httpx2.Response:
    return await request(account, "GET", review_path(listing, interaction))


async def reply(
    account: Account,
    listing: dict[str, Any],
    interaction: dict[str, Any],
    text: str,
    key: str | None = None,
) -> httpx2.Response:
    return await request(
        account,
        "POST",
        review_path(listing, interaction) + "/reply",
        {"text": text},
        key=key,
    )


async def public_reviews(
    account: Account, subject_id: UUID, cursor: str | None = None
) -> httpx2.Response:
    params = {} if cursor is None else {"cursor": cursor}
    return await account.auth.client.get(
        f"/api/v1/users/{subject_id}/reviews",
        params=params,
        headers=account.headers,
    )


async def completed(
    author: Account, participant: Account, at: datetime | None = None
) -> tuple[dict[str, Any], dict[str, Any]]:
    """An accepted giveaway completed by a server-issued code."""
    if at is not None:
        with time_machine.travel(at, tick=False):
            return await _complete(author, participant)
    return await _complete(author, participant)


async def _complete(
    author: Account, participant: Account
) -> tuple[dict[str, Any], dict[str, Any]]:
    listing, interaction = await accepted(author, participant)
    code = (await issue(author, listing, interaction)).json()["code"]
    response = await confirm(participant, listing, interaction, code)
    assert response.status_code == 200, response.text
    assert response.json()["completed"] is True
    return listing, interaction


async def run_deadlines(account: Account) -> int:
    assert isinstance(account.auth.db.bind, AsyncEngine)
    return await process_due_deadlines(
        create_session_factory(account.auth.db.bind), account.auth.settings
    )


async def run_outbox(account: Account) -> int:
    assert isinstance(account.auth.db.bind, AsyncEngine)
    return await process_outbox(
        create_session_factory(account.auth.db.bind), account.auth.settings
    )


async def new_student(auth: Auth, places: Places, number: int) -> Account:
    account = Account(
        auth, await auth.login(email=f"review-{number}@university.example")
    )
    assert (await account.put(moscow_profile(places))).status_code == 200
    return account


class StoredReview(NamedTuple):
    id: UUID
    author_id: UUID
    subject_id: UUID
    rating: int
    text: str | None
    published_at: datetime | None
    hidden_at: datetime | None
    tags: tuple[str, ...]


async def stored(
    account: Account, *, subject_id: UUID | None = None
) -> list[StoredReview]:
    await account.auth.db.rollback()
    query = select(Review).order_by(Review.created_at, Review.id)
    if subject_id is not None:
        query = query.where(Review.subject_id == subject_id)
    rows = list(await account.auth.db.scalars(query))
    return [
        StoredReview(
            id=row.id,
            author_id=row.author_id,
            subject_id=row.subject_id,
            rating=row.rating,
            text=row.text,
            published_at=row.published_at,
            hidden_at=row.hidden_at,
            tags=tuple(tag.tag for tag in row.tags),
        )
        for row in rows
    ]


async def count(account: Account) -> int:
    await account.auth.db.rollback()
    return await account.auth.db.scalar(select(func.count()).select_from(Review)) or 0


async def pending_deadlines(account: Account) -> list[Deadline]:
    await account.auth.db.rollback()
    return list(
        await account.auth.db.scalars(
            select(Deadline).where(Deadline.topic == REVIEW_REVEAL_TOPIC)
        )
    )


async def test_review_needs_a_completed_interaction_and_participation(
    owner: Account, borrower: Account, auth: Auth, places: Places
) -> None:
    outsider = await new_student(auth, places, 1)
    listing = await publish(owner, audience="community")
    response = await reserve(borrower, listing)
    pending = response.json()
    assert (await review(owner, listing, pending)).status_code == 409
    assert (await review(owner, listing, pending)).json()[
        "code"
    ] == "review_unavailable"

    assert (await move(owner, listing, pending, "accepted")).status_code == 200
    refused = await review(borrower, listing, pending)
    assert refused.status_code == 409, refused.text
    assert refused.json()["code"] == "review_unavailable"

    hiding = await request(outsider, "GET", review_path(listing, pending))
    assert hiding.status_code == 403, hiding.text
    assert hiding.json()["code"] == "review_forbidden"
    assert (await review(outsider, listing, pending)).status_code == 403

    listing, interaction = await completed(owner, borrower)
    created = await review(borrower, listing, interaction, 5, ["punctual"], "Thanks")
    assert created.status_code == 201, created.text
    body = created.json()
    assert body["mine"]["rating"] == 5
    assert body["mine"]["tags"] == ["punctual"]
    assert body["mine"]["text"] == "Thanks"
    assert body["revealed"] is False
    assert body["can_edit"] is True

    nowhere = await request(
        owner, "GET", f"/{uuid4()}/interactions/{interaction['id']}/review"
    )
    assert nowhere.status_code == 404
    assert (
        await state(owner, listing, {**interaction, "id": str(uuid4())})
    ).status_code == 404


async def test_rating_tags_and_text_are_validated(
    owner: Account, borrower: Account
) -> None:
    listing, interaction = await completed(owner, borrower)

    for bad in (0, 6):
        refused = await review(borrower, listing, interaction, bad)
        assert refused.status_code == 422, refused.text

    foreign = await review(borrower, listing, interaction, 5, ["clear_explanation"])
    assert foreign.status_code == 422, foreign.text
    assert foreign.json()["code"] == "review_tags_invalid"

    unknown = await review(borrower, listing, interaction, 5, ["not_a_tag"])
    assert unknown.json()["code"] == "review_tags_invalid"

    duplicated = await review(
        borrower, listing, interaction, 5, ["punctual", "punctual"]
    )
    assert duplicated.json()["code"] == "review_tags_invalid"

    many = await review(
        borrower,
        listing,
        interaction,
        5,
        ["punctual", "friendly", "item_as_described"] * 4,
    )
    assert many.json()["code"] == "review_tags_invalid"

    long_text = await review(borrower, listing, interaction, 5, text="x" * 2001)
    assert long_text.status_code == 422, long_text.text
    assert long_text.json()["code"] == "review_text_invalid"

    empty = await review(borrower, listing, interaction, 5, text="   ")
    assert empty.status_code == 201, empty.text
    assert empty.json()["mine"]["text"] is None


async def test_mutual_reviews_are_hidden_until_both_exist(
    owner: Account, borrower: Account
) -> None:
    listing, interaction = await completed(owner, borrower)
    owner_id, borrower_id = user_id(owner), user_id(borrower)

    first = await review(owner, listing, interaction, 4, ["punctual"], "Smooth")
    assert first.status_code == 201, first.text
    assert first.json()["mine"]["rating"] == 4
    assert first.json()["theirs"] is None
    assert first.json()["can_edit"] is True

    as_borrower = (await state(borrower, listing, interaction)).json()
    assert as_borrower["mine"] is None
    assert as_borrower["theirs"] is None
    assert as_borrower["revealed"] is False
    assert as_borrower["can_review"] is True

    for subject in (owner_id, borrower_id):
        listed = (await public_reviews(owner, subject)).json()
        assert listed["items"] == []

    second = await review(borrower, listing, interaction, 5, ["item_as_described"])
    assert second.status_code == 201, second.text
    revealed = second.json()
    assert revealed["revealed"] is True
    assert revealed["theirs"]["rating"] == 4
    assert revealed["theirs"]["text"] == "Smooth"
    assert revealed["mine"]["rating"] == 5
    assert revealed["can_edit"] is False

    as_owner = (await state(owner, listing, interaction)).json()
    assert as_owner["revealed"] is True
    assert as_owner["theirs"]["rating"] == 5
    assert as_owner["can_edit"] is False

    refused = await edit(owner, listing, interaction, 1)
    assert refused.status_code == 409, refused.text
    assert refused.json()["code"] == "review_published"

    listed_borrower = (await public_reviews(owner, borrower_id)).json()["items"]
    assert [(item["rating"], item["author_id"]) for item in listed_borrower] == [
        (4, str(owner_id))
    ]
    listed_owner = (await public_reviews(owner, owner_id)).json()["items"]
    assert [(item["rating"], item["author_id"]) for item in listed_owner] == [
        (5, str(borrower_id))
    ]

    assert await pending_deadlines(owner) == []


async def test_deadline_reveals_one_sided_review_and_catches_up(
    owner: Account, borrower: Account
) -> None:
    completed_at = clock.now()
    listing, interaction = await completed(owner, borrower, at=completed_at)
    created = await review(owner, listing, interaction, 3, ["punctual"])
    body = created.json()
    assert parse_instant(body["window_closes_at"]) == (
        completed_at + timedelta(days=14)
    ).astimezone(UTC)
    assert (await state(borrower, listing, interaction)).json()["theirs"] is None

    with time_machine.travel(completed_at + timedelta(days=13), tick=False):
        await run_deadlines(owner)
        assert (await state(owner, listing, interaction)).json()["revealed"] is False

    # The scheduler was down past the window: the deadline is simply due.
    with time_machine.travel(completed_at + timedelta(days=20), tick=False):
        assert await run_deadlines(owner) >= 1
        await run_deadlines(owner)
        mine = (await state(owner, listing, interaction)).json()
        assert mine["revealed"] is True
        assert mine["mine"]["published_at"] is not None
        theirs = (await state(borrower, listing, interaction)).json()
        assert theirs["revealed"] is True
        assert theirs["theirs"]["rating"] == 3
        assert (await public_reviews(owner, user_id(borrower))).json()["items"][0][
            "rating"
        ] == 3


async def test_edit_is_open_only_until_the_reveal(
    owner: Account, borrower: Account
) -> None:
    listing, interaction = await completed(owner, borrower)
    assert (
        await review(owner, listing, interaction, 2, [], "First")
    ).status_code == 201

    changed = await edit(
        owner, listing, interaction, 5, ["item_as_described"], "Second"
    )
    assert changed.status_code == 200, changed.text
    assert changed.json()["mine"]["rating"] == 5
    assert changed.json()["mine"]["tags"] == ["item_as_described"]
    assert changed.json()["mine"]["text"] == "Second"

    refused = await edit(borrower, listing, interaction, 5)
    assert refused.status_code == 404

    hidden_at = clock.now()
    await owner.auth.db.execute(
        update(Review)
        .where(Review.author_id == user_id(owner))
        .values(hidden_at=hidden_at, hidden_by_id=user_id(borrower))
    )
    await owner.auth.db.commit()
    hidden = await edit(owner, listing, interaction, 1)
    assert hidden.status_code == 409, hidden.text
    assert hidden.json()["code"] == "review_hidden"


async def test_edit_is_closed_when_the_window_closes(
    owner: Account, borrower: Account
) -> None:
    completed_at = clock.now()
    listing, interaction = await completed(owner, borrower, at=completed_at)
    assert (await review(owner, listing, interaction, 2)).status_code == 201

    with time_machine.travel(completed_at + timedelta(days=14, seconds=1), tick=False):
        refused = await edit(owner, listing, interaction, 5)
        assert refused.status_code == 409, refused.text
        assert refused.json()["code"] == "review_published"
        # The deadline has not run yet; the review must still not be shown.
        assert (await state(borrower, listing, interaction)).json()["theirs"] is None
        assert await run_deadlines(owner) == 1
        assert (await state(borrower, listing, interaction)).json()["theirs"][
            "rating"
        ] == 2


async def test_one_answer_only_by_the_addressee(
    owner: Account, borrower: Account, auth: Auth, places: Places
) -> None:
    outsider = await new_student(auth, places, 2)
    listing, interaction = await completed(owner, borrower)
    assert (await review(owner, listing, interaction, 5)).status_code == 201

    before = await reply(borrower, listing, interaction, "Thanks")
    assert before.status_code == 404, before.text

    assert (await review(borrower, listing, interaction, 4)).status_code == 201
    outsider_reply = await reply(outsider, listing, interaction, "Not mine")
    assert outsider_reply.status_code == 403, outsider_reply.text

    answered = await reply(borrower, listing, interaction, "Pleasure")
    assert answered.status_code == 201, answered.text
    assert answered.json()["theirs"]["reply"]["text"] == "Pleasure"
    assert answered.json()["can_reply"] is False

    owner_view = (await state(owner, listing, interaction)).json()
    assert owner_view["mine"]["reply"]["text"] == "Pleasure"
    assert owner_view["theirs"]["reply"] is None

    repeated = await reply(borrower, listing, interaction, "Again")
    assert repeated.status_code == 409, repeated.text
    assert repeated.json()["code"] == "review_reply_exists"

    assert (await reply(owner, listing, interaction, "  ")).status_code == 422

    listed = (await public_reviews(outsider, user_id(borrower))).json()["items"]
    assert [item["reply"]["text"] for item in listed] == ["Pleasure"]


async def test_event_review_is_one_way_and_published_at_once(
    owner: Account, borrower: Account, auth: Auth, places: Places
) -> None:
    outsider = await new_student(auth, places, 3)
    starts_at = clock.now() + timedelta(hours=2)
    ends_at = starts_at + timedelta(hours=2)
    with time_machine.travel(starts_at - timedelta(hours=1), tick=False):
        listing = await event_at(owner, starts_at, ends_at)
        interaction = await signup(borrower, listing)
        early = await review(borrower, listing, interaction, 5)
        assert early.status_code == 409, early.text
        assert early.json()["code"] == "review_unavailable"

    with time_machine.travel(ends_at + timedelta(minutes=1), tick=False):
        created = await review(borrower, listing, interaction, 5, ["interesting"])
        assert created.status_code == 201, created.text
        body = created.json()
        assert body["one_way"] is True
        assert body["revealed"] is True
        assert body["mine"]["published_at"] is not None
        assert body["can_edit"] is False

        listener = (await state(owner, listing, interaction)).json()
        assert listener["can_review"] is False
        assert listener["revealed"] is True
        assert listener["theirs"]["rating"] == 5
        assert listener["can_reply"] is True

        reverse = await review(owner, listing, interaction, 1)
        assert reverse.status_code == 403, reverse.text
        assert reverse.json()["code"] == "review_one_way"

        answered = await reply(owner, listing, interaction, "See you again")
        assert answered.status_code == 201, answered.text
        participant_view = (await state(borrower, listing, interaction)).json()
        assert participant_view["mine"]["reply"]["text"] == "See you again"
        assert participant_view["can_reply"] is False
        assert (await reply(borrower, listing, interaction, "No")).status_code == 404

        published = (await public_reviews(outsider, user_id(owner))).json()["items"]
        assert [(item["rating"], item["kind"]) for item in published] == [(5, "event")]


async def test_event_interaction_that_did_not_take_place_is_not_reviewable(
    owner: Account, borrower: Account
) -> None:
    starts_at = clock.now() + timedelta(hours=1)
    ends_at = starts_at + timedelta(hours=1)
    with time_machine.travel(starts_at - timedelta(minutes=30), tick=False):
        listing = await event_at(owner, starts_at, ends_at)
        interaction = await signup(borrower, listing)

    with time_machine.travel(ends_at + timedelta(hours=25), tick=False):
        assert await run_deadlines(owner) >= 1
        refused = await review(borrower, listing, interaction, 5)
        assert refused.status_code == 409, refused.text
        assert refused.json()["code"] == "review_unavailable"


async def test_hidden_review_is_not_public_but_keeps_primary_data(
    owner: Account, borrower: Account, auth: Auth, places: Places
) -> None:
    outsider = await new_student(auth, places, 4)
    listing, interaction = await completed(owner, borrower)
    assert (
        await review(owner, listing, interaction, 2, ["punctual"], "Late")
    ).status_code == 201
    assert (
        await review(borrower, listing, interaction, 4, ["item_as_described"], "Fine")
    ).status_code == 201
    before = (await state(owner, listing, interaction)).json()
    hidden_id = UUID(before["theirs"]["id"])
    moderator_id = user_id(owner)

    await borrower.auth.db.execute(
        update(Review)
        .where(Review.id == hidden_id)
        .values(hidden_at=clock.now(), hidden_by_id=moderator_id)
    )
    await borrower.auth.db.commit()

    theirs = (await state(owner, listing, interaction)).json()
    assert theirs["theirs"] is None
    assert theirs["can_reply"] is False
    assert theirs["revealed"] is True

    author_view = (await state(borrower, listing, interaction)).json()
    assert author_view["mine"]["hidden"] is True
    assert author_view["mine"]["rating"] == 4
    assert author_view["mine"]["text"] == "Fine"

    published = (await public_reviews(outsider, user_id(owner))).json()["items"]
    assert published == []
    other_side = (await public_reviews(outsider, user_id(borrower))).json()["items"]
    assert [item["rating"] for item in other_side] == [2]

    rows = await stored(borrower, subject_id=user_id(owner))
    assert [(row.rating, row.text, row.tags) for row in rows] == [
        (4, "Fine", ("item_as_described",))
    ]

    reply_refused = await reply(owner, listing, interaction, "Answer")
    assert reply_refused.status_code == 404


async def test_concurrent_first_reviews_reveal_each_other(
    owner: Account, borrower: Account
) -> None:
    listing, interaction = await completed(owner, borrower)
    first, second = await asyncio.gather(
        review(owner, listing, interaction, 5),
        review(borrower, listing, interaction, 4),
    )
    assert first.status_code == 201, first.text
    assert second.status_code == 201, second.text
    # The response of the first request was formed before the second one
    # committed, so each participant sees the reveal on the next read.
    for account in (owner, borrower):
        read = (await state(account, listing, interaction)).json()
        assert read["revealed"] is True
        assert read["theirs"] is not None
    rows = await stored(owner)
    assert [row.published_at is not None for row in rows] == [True, True]
    assert await pending_deadlines(owner) == []


async def test_concurrent_duplicate_review_is_refused_once(
    owner: Account, borrower: Account
) -> None:
    listing, interaction = await completed(owner, borrower)
    results = await asyncio.gather(
        review(owner, listing, interaction, 5),
        review(owner, listing, interaction, 4),
    )
    statuses = sorted(result.status_code for result in results)
    assert statuses == [201, 409]
    assert await count(owner) == 1


async def test_deadline_and_second_review_are_consistent(
    owner: Account, borrower: Account
) -> None:
    completed_at = clock.now()
    listing, interaction = await completed(owner, borrower, at=completed_at)
    assert (await review(owner, listing, interaction, 5)).status_code == 201

    with time_machine.travel(completed_at + timedelta(days=15), tick=False):
        late = await review(borrower, listing, interaction, 4)
        assert late.status_code == 409, late.text
        assert late.json()["code"] == "review_window_closed"
        assert await run_deadlines(owner) == 1
        assert (await state(owner, listing, interaction)).json()["theirs"] is None
        rows = await stored(owner)
        assert [row.published_at is not None for row in rows] == [True]
        published = (await public_reviews(owner, user_id(borrower))).json()["items"]
        assert [item["rating"] for item in published] == [5]


async def test_idempotency_key_replays_and_other_body_conflicts(
    owner: Account, borrower: Account
) -> None:
    listing, interaction = await completed(owner, borrower)
    key = str(uuid4())
    first = await review(owner, listing, interaction, 5, ["punctual"], "A", key)
    assert first.status_code == 201, first.text
    repeated = await review(owner, listing, interaction, 5, ["punctual"], "A", key)
    assert repeated.status_code == 201, repeated.text
    assert repeated.headers.get("Idempotent-Replayed") == "true"
    assert repeated.json()["mine"]["id"] == first.json()["mine"]["id"]
    assert await count(owner) == 1

    conflicting = await review(owner, listing, interaction, 4, ["punctual"], "A", key)
    assert conflicting.status_code == 422, conflicting.text
    assert conflicting.json()["code"] == "idempotency_key_reused"


async def test_idempotency_covers_edit_and_reply(
    owner: Account, borrower: Account
) -> None:
    listing, interaction = await completed(owner, borrower)
    assert (
        await review(owner, listing, interaction, 3, text="Draft")
    ).status_code == 201

    edit_key = str(uuid4())
    first = await edit(owner, listing, interaction, 5, text="Final", key=edit_key)
    assert first.status_code == 200, first.text
    replay = await edit(owner, listing, interaction, 5, text="Final", key=edit_key)
    assert replay.status_code == 200, replay.text
    assert replay.headers.get("Idempotent-Replayed") == "true"
    assert replay.json()["mine"]["rating"] == 5
    conflict = await edit(owner, listing, interaction, 4, text="Final", key=edit_key)
    assert conflict.status_code == 422, conflict.text
    assert conflict.json()["code"] == "idempotency_key_reused"

    assert (await review(borrower, listing, interaction, 4)).status_code == 201
    reply_key = str(uuid4())
    answered = await reply(borrower, listing, interaction, "Thanks", key=reply_key)
    assert answered.status_code == 201, answered.text
    repeated = await reply(borrower, listing, interaction, "Thanks", key=reply_key)
    assert repeated.status_code == 201, repeated.text
    assert repeated.headers.get("Idempotent-Replayed") == "true"
    refused = await reply(borrower, listing, interaction, "Other", key=reply_key)
    assert refused.status_code == 422, refused.text
    assert refused.json()["code"] == "idempotency_key_reused"

    await owner.auth.db.rollback()
    replies = list(await owner.auth.db.scalars(select(ReviewReply)))
    assert len(replies) == 1


async def test_edit_race_with_the_reveal_deadline_is_consistent(
    owner: Account, borrower: Account
) -> None:
    completed_at = clock.now()
    listing, interaction = await completed(owner, borrower, at=completed_at)
    assert (await review(owner, listing, interaction, 2, text="Old")).status_code == 201

    with time_machine.travel(completed_at + timedelta(days=14), tick=False):
        edited, processed = await asyncio.gather(
            edit(owner, listing, interaction, 5, text="New"),
            run_deadlines(owner),
        )
        assert edited.status_code == 409, edited.text
        assert edited.json()["code"] == "review_published"
        assert processed >= 1
        rows = await stored(owner)
        assert len(rows) == 1
        assert rows[0].published_at is not None
        assert (rows[0].rating, rows[0].text) == (2, "Old")
        published = (await public_reviews(owner, user_id(borrower))).json()["items"]
        assert [(item["rating"], item["text"]) for item in published] == [(2, "Old")]


async def test_realtime_wakeup_carries_metadata_only(
    owner: Account, borrower: Account, monkeypatch: pytest.MonkeyPatch
) -> None:
    listing, interaction = await completed(owner, borrower)
    published: list[tuple[UUID, dict[str, Any]]] = []

    async def fake(user_id: UUID, data: dict[str, Any], _delivery: UUID) -> None:
        published.append((user_id, data))

    monkeypatch.setattr("campus.modules.realtime.publish_personal", fake)
    assert (
        await review(owner, listing, interaction, 5, ["punctual"], "Secret text")
    ).status_code == 201
    assert (await review(borrower, listing, interaction, 4)).status_code == 201
    assert published == []
    assert await run_outbox(owner) >= 1
    wakeups = [
        (recipient, data)
        for recipient, data in published
        if data.get("kind") == "published"
    ]
    assert {recipient for recipient, _ in wakeups} == {
        user_id(owner),
        user_id(borrower),
    }
    assert len(wakeups) == 2
    for _, data in wakeups:
        assert data["listing_id"] == listing["id"]
        for key in ("rating", "tags", "text", "review", "author_id"):
            assert key not in data


async def test_purchase_pair_is_mutual_and_unique(
    owner: Account, borrower: Account
) -> None:
    listing = await publish_purchase(owner)
    interaction = (await join(borrower, listing, 2)).json()
    assert interaction["status"] == "accepted"
    await borrower.auth.db.rollback()
    await borrower.auth.db.execute(
        update(Interaction)
        .where(Interaction.id == UUID(str(interaction["id"])))
        .values(
            status=InteractionStatus.COMPLETED.value,
            completion_method=CompletionMethod.QR.value,
            completed_at=clock.now(),
            completion_weight=1.0,
        )
    )
    await borrower.auth.db.commit()

    first = await review(owner, listing, interaction, 4, ["punctual"])
    assert first.status_code == 201, first.text
    assert first.json()["revealed"] is False

    second = await review(borrower, listing, interaction, 5, ["transparent_terms"])
    assert second.status_code == 201, second.text
    assert second.json()["revealed"] is True
    assert second.json()["theirs"]["rating"] == 4

    again = await review(owner, listing, interaction, 1)
    assert again.status_code == 409, again.text
    assert again.json()["code"] == "review_exists"

    await owner.auth.db.rollback()

    def duplicate_pair_review() -> Review:
        return Review(
            listing_id=UUID(listing["id"]),
            interaction_id=UUID(str(interaction["id"])),
            kind="purchase",
            author_id=user_id(owner),
            subject_id=user_id(borrower),
            rating=3,
            text=None,
            reveal_at=clock.now() + timedelta(days=1),
        )

    async def insert_duplicate() -> None:
        owner.auth.db.add(duplicate_pair_review())
        await owner.auth.db.commit()

    with pytest.raises(IntegrityError):
        await insert_duplicate()
    await owner.auth.db.rollback()


async def test_review_of_another_listing_interaction_is_not_found(
    owner: Account, borrower: Account
) -> None:
    _listing, interaction = await completed(owner, borrower)
    other = await publish(owner, audience="community")
    stranger = (await reserve(borrower, other)).json()
    response = await request(borrower, "GET", review_path(other, interaction))
    assert response.status_code == 404
    assert response.json()["code"] == "not_found"
    assert (await review(borrower, other, stranger)).status_code == 409


async def test_journal_keeps_the_reveal_and_the_answer_without_contents(
    owner: Account, borrower: Account
) -> None:
    listing, interaction = await completed(owner, borrower)
    identifier = UUID(str(interaction["id"]))
    assert (
        await review(owner, listing, interaction, 5, ["punctual"], "Hidden text")
    ).status_code == 201
    assert (await review(borrower, listing, interaction, 4)).status_code == 201
    assert (await reply(borrower, listing, interaction, "Thanks")).status_code == 201

    await owner.auth.db.rollback()
    events = list(
        await owner.auth.db.scalars(
            select(ListingEvent)
            .where(ListingEvent.interaction_id == identifier)
            .order_by(ListingEvent.created_at, ListingEvent.id)
        )
    )
    actions = [event.action for event in events]
    assert actions.count("review_published") == 1
    assert actions.count("review_replied") == 1
    for event in events:
        if event.action.startswith("review_"):
            assert event.reason is None
            assert "Hidden text" not in str(event.details)


async def test_public_reviews_are_paginated(
    owner: Account, borrower: Account, auth: Auth, places: Places
) -> None:
    outsider = await new_student(auth, places, 5)
    for expected in (5, 4, 3):
        listing, interaction = await completed(owner, borrower)
        assert (await review(owner, listing, interaction, expected)).status_code == 201
        assert (await review(borrower, listing, interaction, 5)).status_code == 201
    page = (await public_reviews(outsider, user_id(borrower))).json()
    assert [item["rating"] for item in page["items"]] == [3, 4, 5]
    assert page["next_page"] is None

    response = await outsider.auth.client.get(
        f"/api/v1/users/{user_id(borrower)}/reviews",
        params={"size": 2},
        headers=outsider.headers,
    )
    assert response.status_code == 200, response.text
    first = response.json()
    assert len(first["items"]) == 2
    assert first["next_page"] is not None
    rest = (
        await public_reviews(outsider, user_id(borrower), first["next_page"])
    ).json()
    assert [item["rating"] for item in rest["items"]] == [5]


async def test_review_tag_rows_are_replaced_not_duplicated(
    owner: Account, borrower: Account
) -> None:
    listing, interaction = await completed(owner, borrower)
    assert (
        await review(owner, listing, interaction, 5, ["punctual", "friendly"])
    ).status_code == 201
    changed = await edit(owner, listing, interaction, 4, ["item_as_described"])
    assert changed.status_code == 200, changed.text
    assert changed.json()["mine"]["tags"] == ["item_as_described"]
    await owner.auth.db.rollback()
    tags = list(await owner.auth.db.scalars(select(ReviewTag.tag)))
    assert tags == ["item_as_described"]
    replies = list(await owner.auth.db.scalars(select(ReviewReply)))
    assert replies == []
    assert await owner.auth.db.scalar(select(func.count()).select_from(Review)) == 1
    assert reveal_key(UUID(str(interaction["id"]))) == (
        f"review-reveal:{interaction['id']}"
    )
