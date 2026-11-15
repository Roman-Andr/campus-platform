"""Profile rating and counters: formula, eligible set, rebuild and privacy.

The tests run on a real PostgreSQL. Most of them seed the primary data
directly (a completed interaction, a published review, a mark, a journal
entry) and rebuild the aggregate, so the deterministic projection is checked
independently of the HTTP flows; the last group drives the real endpoints
and the outbox to prove the incremental path.
"""

import asyncio
import contextlib
from collections.abc import Iterator, Sequence
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID

import pytest
import time_machine
from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncEngine

from campus.admin.__main__ import recompute
from campus.core.db import create_session_factory
from campus.modules.identity import RoleAssignment, User
from campus.modules.listings import (
    CompletionMethod,
    Interaction,
    InteractionStatus,
    Listing,
    ListingEvent,
)
from campus.modules.reputation import (
    ProfileAggregate,
    compute_aggregates,
    queue_profile_refresh,
    rebuild_aggregates,
    refresh_aggregates,
)
from campus.modules.reputation.models import (
    NoShowKind,
    NoShowMark,
    NoShowStatus,
    Review,
    ReviewTag,
)
from tests.test_identity import Auth
from tests.test_listings import (
    auth,
    borrower,
    move,
    owner,
    places,
    publish,
    reserve,
    staff,
)
from tests.test_profile import Account, Places, moscow_profile
from tests.test_reviews import completed, run_outbox

__all__ = ["auth", "borrower", "owner", "places", "staff"]

NOW = datetime(2026, 11, 16, 12, 0, tzinfo=UTC)


@pytest.fixture(autouse=True)
def long_lived_access(auth: Auth) -> None:
    """Keep access tokens valid while tests move time by days."""
    auth.settings = auth.settings.model_copy(
        update={"access_token_ttl": timedelta(days=365)}
    )
    auth.app.state.settings = auth.settings


@contextlib.contextmanager
def frozen(now: datetime = NOW) -> Iterator[None]:
    """Control the application clock around a test body."""
    with time_machine.travel(now, tick=False):
        yield


def identifier(account: Account) -> UUID:
    return UUID(account.tokens["user"]["id"])


async def new_account(auth: Auth, places: Places, email: str) -> Account:
    account = Account(auth, await auth.login(email=email))
    assert (await account.put(moscow_profile(places))).status_code == 200
    return account


async def seed_interaction(  # noqa: PLR0913 - seeded fields
    account: Account,
    *,
    author_id: UUID,
    participant_id: UUID,
    city_id: UUID,
    status: str = InteractionStatus.COMPLETED.value,
    completed_at: datetime | None = None,
    weight: float = 1.0,
    method: str = CompletionMethod.QR.value,
    kind: str = "giveaway",
    event_ends_at: datetime | None = None,
    cancelled_by: str | None = None,
    late: bool = False,
    accepted: bool = False,
    interaction_id: UUID | None = None,
) -> tuple[Listing, Interaction]:
    """Insert one interaction with its listing and the journal it implies."""
    db = account.auth.db
    listing = Listing(
        author_id=author_id,
        kind=kind,
        title="Seed listing",
        description="Primary data of the profile aggregate tests.",
        city_id=city_id,
        visibility="university",
        audience="students",
        version=1,
        status=(
            "cancelled"
            if cancelled_by is not None
            else "completed"
            if status == InteractionStatus.COMPLETED.value
            else "busy"
        ),
    )
    if kind == "event":
        assert event_ends_at is not None
        listing.event_starts_at = event_ends_at - timedelta(hours=2)
        listing.event_ends_at = event_ends_at
        listing.event_location = "Main hall"
        listing.event_capacity = 10
        listing.event_attendance_mode = "self"
    db.add(listing)
    await db.flush()
    fields: dict[str, Any] = {
        "listing_id": listing.id,
        "participant_id": participant_id,
        "slot": None,
        "status": status,
        "completed_at": completed_at,
        "completion_method": method if completed_at is not None else None,
        "completion_weight": weight if completed_at is not None else None,
        "cancelled_by": cancelled_by,
        "late_cancelled": late,
    }
    if interaction_id is not None:
        fields["id"] = interaction_id
    interaction = Interaction(**fields)
    db.add(interaction)
    await db.flush()
    if accepted:
        db.add(
            ListingEvent(
                listing_id=listing.id,
                interaction_id=interaction.id,
                actor_id=author_id,
                action="accepted",
                previous_status=InteractionStatus.PENDING.value,
                status=InteractionStatus.ACCEPTED.value,
                version=1,
            )
        )
    if cancelled_by is not None:
        db.add(
            ListingEvent(
                listing_id=listing.id,
                interaction_id=interaction.id,
                actor_id=author_id,
                action="cancelled_by_author"
                if cancelled_by == "author"
                else "cancelled",
                previous_status=(
                    InteractionStatus.ACCEPTED.value
                    if accepted
                    else InteractionStatus.PENDING.value
                ),
                status=InteractionStatus.CANCELLED.value,
                version=1,
            )
        )
    await db.flush()
    return listing, interaction


async def seed_review(  # noqa: PLR0913 - seeded fields
    account: Account,
    listing: Listing,
    interaction: Interaction,
    *,
    author_id: UUID,
    subject_id: UUID,
    rating: int,
    tags: Sequence[str] = (),
    published_at: datetime | None = NOW - timedelta(days=1),
    hidden_at: datetime | None = None,
) -> Review:
    db = account.auth.db
    review = Review(
        listing_id=listing.id,
        interaction_id=interaction.id,
        kind=listing.kind,
        author_id=author_id,
        subject_id=subject_id,
        rating=rating,
        text=None,
        reveal_at=NOW + timedelta(days=14),
        published_at=published_at,
        hidden_at=hidden_at,
        hidden_by_id=author_id if hidden_at is not None else None,
    )
    review.tags = [ReviewTag(tag=tag) for tag in tags]
    db.add(review)
    await db.flush()
    return review


def engine_of(account: Account) -> AsyncEngine:
    engine = account.auth.db.bind
    assert isinstance(engine, AsyncEngine)
    return engine


async def rebuild(account: Account) -> int:
    async with create_session_factory(engine_of(account))() as session, session.begin():
        return await rebuild_aggregates(session, account.auth.settings)


async def refresh(account: Account, users: Sequence[UUID]) -> int:
    async with create_session_factory(engine_of(account))() as session, session.begin():
        return await refresh_aggregates(session, users, account.auth.settings)


async def read(account: Account, target: UUID) -> dict[str, Any]:
    response = await account.auth.client.get(
        f"/api/v1/users/{target}/reputation", headers=account.headers
    )
    assert response.status_code == 200, response.text
    body: dict[str, Any] = response.json()
    return body


async def tags_of(account: Account, target: UUID) -> dict[str, int]:
    body = await read(account, target)
    return {item["tag"]: item["count"] for item in body["tags"]}


def configure(account: Account, **changes: object) -> None:
    account.auth.settings = account.auth.settings.model_copy(update=changes)
    account.auth.app.state.settings = account.auth.settings


async def test_empty_profile_reports_few_reviews_and_zeros(
    auth: Auth, places: Places, owner: Account
) -> None:
    newcomer = await new_account(auth, places, "newcomer@university.example")
    with frozen():
        body = await read(owner, identifier(newcomer))
    assert body["user_id"] == str(identifier(newcomer))
    assert body["rating"] is None
    assert body["rating_state"] == "few_reviews"
    assert body["rating_count"] == 0
    assert body["completed_interactions"] == 0
    assert body["no_shows"] == 0
    assert body["cancelled_after_acceptance"] == 0
    assert body["late_cancellations"] == 0
    assert body["tags"] == []
    assert set(body) == {
        "user_id",
        "rating",
        "rating_state",
        "rating_count",
        "completed_interactions",
        "no_shows",
        "cancelled_after_acceptance",
        "late_cancellations",
        "tags",
    }


async def test_formula_uses_the_eligible_ratings_and_their_weights(
    auth: Auth, places: Places, owner: Account
) -> None:
    author_a = await new_account(auth, places, "author-a@university.example")
    author_b = await new_account(auth, places, "author-b@university.example")
    subject = await new_account(auth, places, "subject@university.example")
    a, b, s = identifier(author_a), identifier(author_b), identifier(subject)
    with frozen():
        # The same pair may add four interactions a month; only the first
        # three reviews enter the rating, the fourth stays public.
        for day, rating in ((2, 5), (3, 5), (4, 4), (5, 1)):
            listing, interaction = await seed_interaction(
                owner,
                author_id=a,
                participant_id=s,
                city_id=places.moscow,
                completed_at=datetime(2026, 11, day, 10, 0, tzinfo=UTC),
            )
            await seed_review(
                owner,
                listing,
                interaction,
                author_id=a,
                subject_id=s,
                rating=rating,
                tags=("punctual", "friendly") if rating == 5 else (),
            )
        # A second pair is a separate limit; its completion weighs less.
        listing, low_weight = await seed_interaction(
            owner,
            author_id=b,
            participant_id=s,
            city_id=places.moscow,
            completed_at=datetime(2026, 11, 6, 10, 0, tzinfo=UTC),
            weight=0.5,
            method=CompletionMethod.NO_MEETING.value,
        )
        await seed_review(
            owner,
            listing,
            low_weight,
            author_id=b,
            subject_id=s,
            rating=3,
            tags=("punctual",),
        )
        await owner.auth.db.commit()
        assert await rebuild(owner) == 3
        body = await read(author_a, s)

    # Eligible: 5, 5, 4 (w=1) and 3 (w=0.5); the excluded 1 is only public.
    # m = (5 + 5 + 4 + 3) / 4 = 4.25
    # R = (5*4.25 + (5+5+4+1.5)) / (5 + 3.5) = 36.75 / 8.5
    assert body["rating"] == pytest.approx(36.75 / 8.5, rel=1e-9)
    assert body["rating_state"] == "rated"
    assert body["rating_count"] == 4
    assert body["completed_interactions"] == 5
    assert await tags_of(author_a, s) == {"friendly": 2, "punctual": 3}
    about_a = await read(author_a, a)
    assert about_a["completed_interactions"] == 4
    assert about_a["rating_count"] == 0


async def test_pair_limit_counts_the_first_three_of_each_utc_month(
    auth: Auth, places: Places, owner: Account
) -> None:
    author = await new_account(auth, places, "month-author@university.example")
    subject = await new_account(auth, places, "month-subject@university.example")
    a, s = identifier(author), identifier(subject)
    with frozen():
        # Three October reviews of 5, one later October review of 1 that
        # must be excluded, and three November reviews of 5.
        for day, rating in ((2, 5), (3, 5), (4, 5), (5, 1)):
            listing, interaction = await seed_interaction(
                owner,
                author_id=a,
                participant_id=s,
                city_id=places.moscow,
                completed_at=datetime(2026, 10, day, 10, 0, tzinfo=UTC),
            )
            await seed_review(
                owner, listing, interaction, author_id=a, subject_id=s, rating=rating
            )
        for day in (2, 3, 4):
            listing, interaction = await seed_interaction(
                owner,
                author_id=a,
                participant_id=s,
                city_id=places.moscow,
                completed_at=datetime(2026, 11, day, 10, 0, tzinfo=UTC),
            )
            await seed_review(
                owner, listing, interaction, author_id=a, subject_id=s, rating=5
            )
        await owner.auth.db.commit()
        await rebuild(owner)
        body = await read(owner, s)

    assert body["rating_count"] == 6
    assert body["rating"] == pytest.approx(5.0)
    assert body["completed_interactions"] == 7


async def test_the_tie_of_the_completion_moment_breaks_by_interaction_id(
    auth: Auth, places: Places, owner: Account
) -> None:
    author = await new_account(auth, places, "tie-author@university.example")
    second = await new_account(auth, places, "tie-second@university.example")
    subject = await new_account(auth, places, "tie-subject@university.example")
    a, c, s = identifier(author), identifier(second), identifier(subject)
    with frozen():
        for minute, rating in ((0, 5), (1, 4)):
            listing, interaction = await seed_interaction(
                owner,
                author_id=a,
                participant_id=s,
                city_id=places.moscow,
                completed_at=datetime(2026, 11, 2, 10, minute, tzinfo=UTC),
            )
            await seed_review(
                owner, listing, interaction, author_id=a, subject_id=s, rating=rating
            )
        same_moment = datetime(2026, 11, 2, 10, 2, tzinfo=UTC)
        for suffix, rating in ((1, 2), (2, 1)):
            listing, interaction = await seed_interaction(
                owner,
                author_id=a,
                participant_id=s,
                city_id=places.moscow,
                completed_at=same_moment,
                interaction_id=UUID(f"00000000-0000-0000-0000-0000000000{suffix:02d}"),
            )
            await seed_review(
                owner, listing, interaction, author_id=a, subject_id=s, rating=rating
            )
        # A second pair gives the fourth eligible rating so R is published.
        listing, interaction = await seed_interaction(
            owner,
            author_id=c,
            participant_id=s,
            city_id=places.moscow,
            completed_at=datetime(2026, 11, 2, 11, 0, tzinfo=UTC),
            weight=0.5,
            method=CompletionMethod.NO_MEETING.value,
        )
        await seed_review(
            owner, listing, interaction, author_id=c, subject_id=s, rating=4
        )
        await owner.auth.db.commit()
        await rebuild(owner)
        body = await read(owner, s)

    # The lower interaction id is third and counts; the higher one is fourth.
    # Eligible: 5, 4, 2 (w=1) and 4 (w=0.5); m = 15/4 = 3.75,
    # R = (5*3.75 + 13) / (5 + 3.5) = 31.75 / 8.5.
    # If the tie broke the other way, the eligible set would be 5, 4, 1, 4
    # and R would be 30.75 / 8.5.
    assert body["rating_count"] == 4
    assert body["rating"] == pytest.approx(31.75 / 8.5, rel=1e-9)


async def test_few_reviews_until_four_eligible_and_no_division_by_zero(
    auth: Auth, places: Places, owner: Account
) -> None:
    author = await new_account(auth, places, "few-author@university.example")
    second = await new_account(auth, places, "few-second@university.example")
    subject = await new_account(auth, places, "few-subject@university.example")
    a, c, s = identifier(author), identifier(second), identifier(subject)
    with frozen():
        for day in (2, 3, 4):
            listing, interaction = await seed_interaction(
                owner,
                author_id=a,
                participant_id=s,
                city_id=places.moscow,
                completed_at=datetime(2026, 11, day, 10, 0, tzinfo=UTC),
            )
            await seed_review(
                owner, listing, interaction, author_id=a, subject_id=s, rating=4
            )
        await owner.auth.db.commit()
        await rebuild(owner)
        three = await read(owner, s)
        assert three["rating"] is None
        assert three["rating_state"] == "few_reviews"
        assert three["rating_count"] == 3

        # A second pair is not limited by the three reviews of the first one.
        listing, fourth = await seed_interaction(
            owner,
            author_id=c,
            participant_id=s,
            city_id=places.moscow,
            completed_at=datetime(2026, 11, 6, 10, 0, tzinfo=UTC),
        )
        await seed_review(owner, listing, fourth, author_id=c, subject_id=s, rating=4)
        await owner.auth.db.commit()
        await rebuild(owner)
        four = await read(owner, s)

    assert four["rating_state"] == "rated"
    assert four["rating_count"] == 4
    assert four["rating"] == pytest.approx(4.0)


async def test_hidden_and_unrevealed_reviews_do_not_leak(
    auth: Auth, places: Places, owner: Account
) -> None:
    author = await new_account(auth, places, "hide-author@university.example")
    second = await new_account(auth, places, "hide-second@university.example")
    subject = await new_account(auth, places, "hide-subject@university.example")
    a, c, s = identifier(author), identifier(second), identifier(subject)
    with frozen():
        listing, hidden = await seed_interaction(
            owner,
            author_id=a,
            participant_id=s,
            city_id=places.moscow,
            completed_at=datetime(2026, 11, 2, 10, 0, tzinfo=UTC),
        )
        await seed_review(
            owner,
            listing,
            hidden,
            author_id=a,
            subject_id=s,
            rating=1,
            tags=("friendly",),
            hidden_at=NOW - timedelta(hours=1),
        )
        listing, pending = await seed_interaction(
            owner,
            author_id=a,
            participant_id=s,
            city_id=places.moscow,
            completed_at=datetime(2026, 11, 3, 10, 0, tzinfo=UTC),
        )
        await seed_review(
            owner,
            listing,
            pending,
            author_id=a,
            subject_id=s,
            rating=1,
            tags=("punctual",),
            published_at=None,
        )
        listing, visible = await seed_interaction(
            owner,
            author_id=a,
            participant_id=s,
            city_id=places.moscow,
            completed_at=datetime(2026, 11, 4, 10, 0, tzinfo=UTC),
        )
        await seed_review(
            owner,
            listing,
            visible,
            author_id=a,
            subject_id=s,
            rating=5,
            tags=("punctual",),
        )
        listing, other_pair = await seed_interaction(
            owner,
            author_id=c,
            participant_id=s,
            city_id=places.moscow,
            completed_at=datetime(2026, 11, 5, 10, 0, tzinfo=UTC),
        )
        await seed_review(
            owner,
            listing,
            other_pair,
            author_id=c,
            subject_id=s,
            rating=4,
            tags=("punctual",),
        )
        await owner.auth.db.commit()
        await rebuild(owner)
        hidden_body = await read(owner, s)

        # Reveal and unhide everything: the projection changes with the data.
        await owner.auth.db.execute(
            update(Review).values(published_at=NOW, hidden_at=None, hidden_by_id=None)
        )
        await owner.auth.db.commit()
        await rebuild(owner)
        visible_body = await read(owner, s)

    assert hidden_body["rating_count"] == 2
    assert hidden_body["rating_state"] == "few_reviews"
    assert hidden_body["tags"] == [{"tag": "punctual", "count": 2}]
    assert visible_body["rating_count"] == 4
    assert visible_body["rating_state"] == "rated"
    assert {item["tag"]: item["count"] for item in visible_body["tags"]} == {
        "friendly": 1,
        "punctual": 3,
    }


async def test_counters_match_the_primary_data(
    auth: Auth, places: Places, owner: Account
) -> None:
    subject = await new_account(auth, places, "counter-subject@university.example")
    other = await new_account(auth, places, "counter-other@university.example")
    s, o = identifier(subject), identifier(other)
    with frozen():
        # Two completed interactions as a participant and one as an author.
        for participant, author in ((s, o), (s, o), (o, s)):
            await seed_interaction(
                owner,
                author_id=author,
                participant_id=participant,
                city_id=places.moscow,
                completed_at=NOW - timedelta(days=10),
            )
        # An ended event signup counts as a completion of its participant.
        await seed_interaction(
            owner,
            author_id=o,
            participant_id=s,
            city_id=places.moscow,
            status=InteractionStatus.ACCEPTED.value,
            kind="event",
            event_ends_at=NOW - timedelta(days=2),
        )
        # No-shows: only the counted mark is final.
        for index, status in enumerate(
            (
                NoShowStatus.COUNTED.value,
                NoShowStatus.DISPUTED.value,
                NoShowStatus.REMOVED.value,
            )
        ):
            listing, interaction = await seed_interaction(
                owner,
                author_id=o,
                participant_id=s,
                city_id=places.moscow,
                completed_at=NOW - timedelta(days=30 + index),
            )
            owner.auth.db.add(
                NoShowMark(
                    listing_id=listing.id,
                    interaction_id=interaction.id,
                    reporter_id=o,
                    subject_id=s,
                    kind=NoShowKind.PERSONAL.value,
                    status=status,
                    reason="did not come",
                    disputed_at=NOW - timedelta(days=1)
                    if status == NoShowStatus.DISPUTED.value
                    else None,
                    removed_at=NOW - timedelta(days=1)
                    if status == NoShowStatus.REMOVED.value
                    else None,
                    removed_by_id=o if status == NoShowStatus.REMOVED.value else None,
                )
            )
        # The author cancelled an accepted interaction of this profile.
        await seed_interaction(
            owner,
            author_id=s,
            participant_id=o,
            city_id=places.moscow,
            status=InteractionStatus.CANCELLED.value,
            cancelled_by="author",
            accepted=True,
        )
        # The participant cancelled after acceptance, one time late.
        await seed_interaction(
            owner,
            author_id=o,
            participant_id=s,
            city_id=places.moscow,
            status=InteractionStatus.CANCELLED.value,
            cancelled_by="participant",
            late=True,
            accepted=True,
        )
        # A pending application that was withdrawn is not an after-acceptance
        # cancellation; the system reservation timeout belongs to nobody.
        await seed_interaction(
            owner,
            author_id=o,
            participant_id=s,
            city_id=places.moscow,
            status=InteractionStatus.CANCELLED.value,
            cancelled_by="participant",
        )
        await seed_interaction(
            owner,
            author_id=o,
            participant_id=s,
            city_id=places.moscow,
            status=InteractionStatus.CANCELLED.value,
            cancelled_by="system",
            accepted=True,
        )
        await owner.auth.db.commit()
        await rebuild(owner)
        body = await read(owner, s)

    assert body["completed_interactions"] == 7
    assert body["no_shows"] == 1
    assert body["cancelled_after_acceptance"] == 2
    assert body["late_cancellations"] == 1


async def test_rebuild_is_idempotent_and_heals_corrected_data(
    auth: Auth, places: Places, owner: Account
) -> None:
    author = await new_account(auth, places, "idem-author@university.example")
    subject = await new_account(auth, places, "idem-subject@university.example")
    a, s = identifier(author), identifier(subject)
    with frozen():
        reviews: list[Review] = []
        for day in (2, 3, 4):
            listing, interaction = await seed_interaction(
                owner,
                author_id=a,
                participant_id=s,
                city_id=places.moscow,
                completed_at=datetime(2026, 11, day, 10, 0, tzinfo=UTC),
            )
            reviews.append(
                await seed_review(
                    owner,
                    listing,
                    interaction,
                    author_id=a,
                    subject_id=s,
                    rating=4,
                    tags=("punctual",),
                )
            )
        await owner.auth.db.commit()
        first = await rebuild(owner)
        one = await read(owner, s)
        second = await rebuild(owner)
        two = await read(owner, s)
        await owner.auth.db.rollback()
        rows = await owner.auth.db.scalar(
            select(func.count())
            .select_from(ProfileAggregate)
            .where(ProfileAggregate.user_id == s)
        )
        assert first == second
        assert one == two
        assert rows == 1

        # Hiding one review changes the stored projection on the next rebuild.
        await owner.auth.db.execute(
            update(Review)
            .where(Review.id == reviews[0].id)
            .values(hidden_at=NOW, hidden_by_id=a)
        )
        await owner.auth.db.commit()
        await rebuild(owner)
        hidden = await read(owner, s)
        assert hidden["rating_count"] == 2
        assert hidden["rating_state"] == "few_reviews"
        assert hidden["tags"] == [{"tag": "punctual", "count": 2}]

        # A full recompute from scratch gives exactly the stored result again.
        async with create_session_factory(engine_of(owner))() as session:
            computed = await compute_aggregates(session, s, owner.auth.settings)
        await owner.auth.db.rollback()
        stored = await owner.auth.db.scalar(
            select(ProfileAggregate).where(ProfileAggregate.user_id == s)
        )
        assert stored is not None
        assert stored.rating_count == computed.rating_count
        assert stored.rating_sum == computed.rating_sum
        assert stored.completed_interactions == computed.completed_interactions
        assert stored.tag_counts == computed.tag_counts


async def test_parallel_recomputations_do_not_multiply_counters(
    auth: Auth, places: Places, owner: Account
) -> None:
    author = await new_account(auth, places, "race-author@university.example")
    subject = await new_account(auth, places, "race-subject@university.example")
    a, s = identifier(author), identifier(subject)
    with frozen():
        for day in (2, 3, 4):
            listing, interaction = await seed_interaction(
                owner,
                author_id=a,
                participant_id=s,
                city_id=places.moscow,
                completed_at=datetime(2026, 11, day, 10, 0, tzinfo=UTC),
            )
            await seed_review(
                owner,
                listing,
                interaction,
                author_id=a,
                subject_id=s,
                rating=5,
                tags=("punctual",),
            )
        await owner.auth.db.commit()

        await asyncio.gather(rebuild(owner), refresh(owner, [s]), rebuild(owner))
        body = await read(owner, s)

    assert body["rating_count"] == 3
    assert body["completed_interactions"] == 3
    assert body["tags"] == [{"tag": "punctual", "count": 3}]


async def test_outbox_refreshes_after_a_review_is_published(
    owner: Account, borrower: Account
) -> None:
    listing, interaction = await completed(owner, borrower)
    o, b = identifier(owner), identifier(borrower)
    path = f"/api/v1/listings/{listing['id']}/interactions/{interaction['id']}/review"
    first = await owner.auth.client.post(
        path,
        json={"rating": 5, "tags": ["punctual"]},
        headers={"Idempotency-Key": str(UUID(int=1)), **owner.headers},
    )
    assert first.status_code == 201, first.text
    # One unpublished review is not eligible yet.
    await run_outbox(owner)
    assert (await read(owner, b))["rating_count"] == 0

    second = await borrower.auth.client.post(
        path,
        json={"rating": 4, "tags": ["friendly"]},
        headers={"Idempotency-Key": str(UUID(int=2)), **borrower.headers},
    )
    assert second.status_code == 201, second.text
    assert second.json()["revealed"] is True
    await run_outbox(owner)
    about_owner = await read(owner, o)
    about_borrower = await read(owner, b)
    assert about_owner["rating_count"] == 1
    assert about_owner["rating_state"] == "few_reviews"
    assert about_owner["completed_interactions"] == 1
    assert about_owner["tags"] == [{"tag": "friendly", "count": 1}]
    assert about_borrower["tags"] == [{"tag": "punctual", "count": 1}]

    # A repeated delivery of the same messages changes nothing.
    await run_outbox(owner)
    assert await read(owner, o) == about_owner
    assert await read(owner, b) == about_borrower


async def test_outbox_refreshes_after_a_cancellation(
    owner: Account, borrower: Account
) -> None:
    listing = await publish(owner)
    interaction = (await reserve(borrower, listing)).json()
    assert (await move(owner, listing, interaction, "accepted")).status_code == 200
    response = await owner.auth.client.post(
        f"/api/v1/listings/{listing['id']}/cancel",
        json={"reason": "No longer available"},
        headers={"Idempotency-Key": str(UUID(int=3)), **owner.headers},
    )
    assert response.status_code == 200, response.text
    await run_outbox(owner)
    assert (await read(owner, identifier(owner)))["cancelled_after_acceptance"] == 1
    assert (await read(owner, identifier(borrower)))["cancelled_after_acceptance"] == 0


async def test_a_reader_of_every_role_sees_the_same_aggregates_without_contacts(
    auth: Auth, places: Places, owner: Account
) -> None:
    author = await new_account(auth, places, "role-author@university.example")
    subject = await new_account(auth, places, "role-subject@university.example")
    a, s = identifier(author), identifier(subject)
    with frozen():
        listing, interaction = await seed_interaction(
            owner,
            author_id=a,
            participant_id=s,
            city_id=places.moscow,
            completed_at=datetime(2026, 11, 2, 10, 0, tzinfo=UTC),
        )
        await seed_review(
            owner,
            listing,
            interaction,
            author_id=a,
            subject_id=s,
            rating=5,
            tags=("punctual",),
        )
        await owner.auth.db.commit()
        await rebuild(owner)

        readings: list[dict[str, Any]] = []
        for role in ("student", "employee", "alumni", "former_employee"):
            account = await new_account(
                auth, places, f"reader-{role}@university.example"
            )
            if role in ("alumni", "former_employee"):
                await owner.auth.db.execute(
                    update(User)
                    .where(User.id == identifier(account))
                    .values(account_type=role)
                )
                await owner.auth.db.commit()
            readings.append(await read(account, s))
        for role, role_place in (
            ("headman", "dormitory"),
            ("moderator", None),
            ("administrator", None),
        ):
            account = await new_account(
                auth, places, f"reader-{role}@university.example"
            )
            owner.auth.db.add(
                RoleAssignment(
                    user_id=identifier(account),
                    role=role,
                    dormitory_id=places.dubki if role_place else None,
                    faculty_id=None,
                )
            )
            await owner.auth.db.commit()
            readings.append(await read(account, s))
        self_read = await read(subject, s)
        outsider_read = await read(owner, s)

    assert all(item == self_read for item in readings)
    assert self_read == outsider_read
    # The response is exactly the aggregate: no address, contact or area.
    for forbidden in ("email", "phone", "contacts", "dormitory", "faculty", "course"):
        assert forbidden not in self_read

    anonymous = await owner.auth.client.get(f"/api/v1/users/{s}/reputation")
    assert anonymous.status_code == 401
    unknown = await owner.auth.client.get(
        f"/api/v1/users/{UUID(int=999)}/reputation", headers=owner.headers
    )
    assert unknown.status_code == 404
    assert unknown.json()["code"] == "not_found"


async def test_an_alumni_profile_keeps_its_rating_and_counters(
    auth: Auth, places: Places, owner: Account
) -> None:
    author = await new_account(auth, places, "alumni-author@university.example")
    second = await new_account(auth, places, "alumni-second@university.example")
    graduate = await new_account(auth, places, "graduate@university.example")
    a, c, g = identifier(author), identifier(second), identifier(graduate)
    with frozen():
        for day, writer in ((2, a), (3, a), (4, a), (5, c)):
            listing, interaction = await seed_interaction(
                owner,
                author_id=writer,
                participant_id=g,
                city_id=places.moscow,
                completed_at=datetime(2026, 11, day, 10, 0, tzinfo=UTC),
            )
            await seed_review(
                owner, listing, interaction, author_id=writer, subject_id=g, rating=5
            )
        await owner.auth.db.execute(
            update(User).where(User.id == g).values(account_type="alumni")
        )
        await owner.auth.db.commit()
        await rebuild(owner)
        profile = await read(owner, g)

    assert profile["rating"] == pytest.approx(5.0)
    assert profile["rating_state"] == "rated"
    assert profile["rating_count"] == 4
    assert profile["completed_interactions"] == 4


async def test_the_smoothing_constant_and_weights_are_configuration(
    auth: Auth, places: Places, owner: Account
) -> None:
    author = await new_account(auth, places, "config-author@university.example")
    second = await new_account(auth, places, "config-second@university.example")
    subject = await new_account(auth, places, "config-subject@university.example")
    a, c, s = identifier(author), identifier(second), identifier(subject)
    with frozen():
        for day, rating, weight in ((2, 5, 1.0), (3, 5, 1.0), (4, 5, 1.0)):
            listing, interaction = await seed_interaction(
                owner,
                author_id=a,
                participant_id=s,
                city_id=places.moscow,
                completed_at=datetime(2026, 11, day, 10, 0, tzinfo=UTC),
                weight=weight,
            )
            await seed_review(
                owner, listing, interaction, author_id=a, subject_id=s, rating=rating
            )
        listing, interaction = await seed_interaction(
            owner,
            author_id=c,
            participant_id=s,
            city_id=places.moscow,
            completed_at=datetime(2026, 11, 5, 10, 0, tzinfo=UTC),
            weight=0.5,
            method=CompletionMethod.NO_MEETING.value,
        )
        await seed_review(
            owner, listing, interaction, author_id=c, subject_id=s, rating=1
        )
        await owner.auth.db.commit()
        await rebuild(owner)
        # m = 16/4 = 4; weighted sum = 15 + 0.5 = 15.5; weight sum = 3.5.
        configure(owner, rating_prior_c=0.0)
        plain = await read(owner, s)
        configure(owner, rating_prior_c=5.0)
        default = await read(owner, s)
        configure(owner, rating_prior_c=1000.0)
        pulled = await read(owner, s)

    assert plain["rating"] == pytest.approx(15.5 / 3.5, rel=1e-9)
    assert default["rating"] == pytest.approx(35.5 / 8.5, rel=1e-9)
    assert pulled["rating"] == pytest.approx(4015.5 / 1003.5, rel=1e-9)


async def test_the_pair_limit_is_configurable(
    auth: Auth, places: Places, owner: Account
) -> None:
    author = await new_account(auth, places, "limit-author@university.example")
    subject = await new_account(auth, places, "limit-subject@university.example")
    a, s = identifier(author), identifier(subject)
    with frozen():
        for day in (2, 3, 4):
            listing, interaction = await seed_interaction(
                owner,
                author_id=a,
                participant_id=s,
                city_id=places.moscow,
                completed_at=datetime(2026, 11, day, 10, 0, tzinfo=UTC),
            )
            await seed_review(
                owner, listing, interaction, author_id=a, subject_id=s, rating=5
            )
        await owner.auth.db.commit()
        await rebuild(owner)
        assert (await read(owner, s))["rating_count"] == 3
        configure(owner, rating_pair_monthly_limit=1)
        await rebuild(owner)
        limited = await read(owner, s)

    assert limited["rating_count"] == 1
    assert limited["rating_state"] == "few_reviews"


async def test_the_recompute_command_rebuilds_every_profile(
    auth: Auth, places: Places, owner: Account
) -> None:
    author = await new_account(auth, places, "cli-author@university.example")
    subject = await new_account(auth, places, "cli-subject@university.example")
    a, s = identifier(author), identifier(subject)
    with frozen():
        listing, interaction = await seed_interaction(
            owner,
            author_id=a,
            participant_id=s,
            city_id=places.moscow,
            completed_at=datetime(2026, 11, 2, 10, 0, tzinfo=UTC),
        )
        await seed_review(
            owner, listing, interaction, author_id=a, subject_id=s, rating=5
        )
        await owner.auth.db.commit()
        count = await recompute(auth.settings, [])
        body = await read(owner, s)

    assert count >= 2
    assert body["rating_count"] == 1
    assert body["completed_interactions"] == 1


async def test_a_delivery_for_an_unknown_user_is_skipped(
    owner: Account, borrower: Account
) -> None:
    o, b = identifier(owner), identifier(borrower)
    async with create_session_factory(engine_of(owner))() as session, session.begin():
        queue_profile_refresh(session, [UUID(int=12345)])
    await run_outbox(owner)
    async with create_session_factory(engine_of(owner))() as session, session.begin():
        updated = await refresh_aggregates(
            session, [UUID(int=12345), b], owner.auth.settings
        )
    assert updated == 1
    assert (await read(owner, o))["rating_count"] == 0
