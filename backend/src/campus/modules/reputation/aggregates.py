"""Derived profile rating and counters (specification, 5.1.1, modules 2 and 5).

The stored aggregate of a profile is a deterministic projection of the
primary data: completed interactions, reviews, no-show marks and the
interaction journal. The public rating is the smoothed mean

    R = (C * m + sum(w * r)) / (C + sum(w)),

where ``m`` is the mean of every eligible rating of the service and ``C``
is the configured smoothing constant. Instead of storing ``R``, a row keeps
the sums: ``m`` is then the sum over all rows, so a review of one user
changes only that user's row, and ``C`` stays a value read at request time.

The eligible set is fixed by the specification (module 5, item 8): a review
counts when it is published (``published_at``), not hidden by a moderator
(``hidden_at``), and belongs to one of the first
``rating_pair_monthly_limit`` completed interactions of its pair in the UTC
calendar month of the completion, ordered by the completion moment and then
by the interaction id. An event completes at ``event_ends_at``; the rest at
``completed_at``. A pair is unordered: the same limit covers both
directions of its reviews.

The row is only a cache. :func:`refresh_aggregates` and
:func:`rebuild_aggregates` recompute it from scratch under one advisory
lock, so a repeated, reordered or parallel delivery writes the same values
and can never multiply a counter. The outbox message of
:data:`PROFILE_AGGREGATE_TOPIC` carries the users to refresh; the domain
paths that change the primary data queue it in their own transaction.
"""

from collections.abc import Iterable
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any, Literal
from uuid import UUID

from sqlalchemy import and_, case, func, or_, select, text
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from campus.core import clock
from campus.core.config import Settings, get_settings
from campus.core.jobs import JobInfo
from campus.core.outbox import add_message, outbox_handlers
from campus.core.web import ProblemError
from campus.core.web.problems import NOT_FOUND
from campus.modules.identity import User
from campus.modules.listings import (
    Interaction,
    InteractionStatus,
    Listing,
    ListingEvent,
)
from campus.modules.reputation.models import (
    NoShowMark,
    NoShowStatus,
    ProfileAggregate,
    Review,
    ReviewTag,
)

PROFILE_AGGREGATE_TOPIC = "reputation.profile_aggregate"

# Below this many eligible ratings the profile shows "few reviews" instead of
# a number (specification, module 5, item 8: "up to 3 ratings").
FEW_REVIEWS_LIMIT = 3

# One lock for every aggregate write: a rebuild and an incremental refresh
# cannot interleave a primary-data read with an older write. Absolute values
# make an accidental repetition harmless; the lock only keeps the final row
# as fresh as the last committed primary change.
_AGGREGATE_LOCK = "reputation.profile-aggregate"

type RatingState = Literal["rated", "few_reviews"]


@dataclass(frozen=True, slots=True)
class ProfileAggregates:
    """The stored projection of one profile, without the smoothing constant."""

    user_id: UUID
    rating_count: int = 0
    rating_sum: int = 0
    rating_weight_sum: float = 0.0
    rating_weighted_sum: float = 0.0
    completed_interactions: int = 0
    no_shows: int = 0
    cancelled_after_acceptance: int = 0
    late_cancellations: int = 0
    tag_counts: dict[str, int] = field(default_factory=dict)


@dataclass(frozen=True, slots=True)
class ProfileReputation:
    """What a profile reader gets: the rating or the "few reviews" state."""

    user_id: UUID
    rating: float | None
    rating_state: RatingState
    rating_count: int
    completed_interactions: int
    no_shows: int
    cancelled_after_acceptance: int
    late_cancellations: int
    tag_counts: dict[str, int]


def _finished_at() -> Any:
    """When an interaction became completed: the event end or the QR moment."""
    return case(
        (Listing.kind == "event", Listing.event_ends_at),
        else_=Interaction.completed_at,
    )


def _completed() -> Any:
    """Interactions a review could belong to.

    A flat scenario completes through the status; an event signup keeps its
    accepted status and completes when the event ends, because the review
    and the attendance rules judge it by that moment.
    """
    return or_(
        Interaction.status == InteractionStatus.COMPLETED.value,
        and_(
            Listing.kind == "event",
            Interaction.status.in_(
                (
                    InteractionStatus.ACCEPTED.value,
                    InteractionStatus.COMPLETED.value,
                )
            ),
            Listing.event_ends_at.is_not(None),
        ),
    )


def _pair_interactions(user_id: UUID) -> Any:
    """Completed interactions of every pair the user belongs to."""
    finished = _finished_at()
    return (
        select(
            Interaction.id.label("interaction_id"),
            Interaction.completion_weight.label("completion_weight"),
            finished.label("finished_at"),
            func.least(Listing.author_id, Interaction.participant_id).label("pair_low"),
            func.greatest(Listing.author_id, Interaction.participant_id).label(
                "pair_high"
            ),
        )
        .join(Listing, Listing.id == Interaction.listing_id)
        .where(
            or_(Listing.author_id == user_id, Interaction.participant_id == user_id),
            _completed(),
            finished.is_not(None),
        )
    )


def _weight(completion_weight: float | None, settings: Settings) -> float:
    """The review weight of an interaction.

    The completion stores the configured weight (QR or without a meeting);
    an event signup has no completion row, so its review weighs as a QR one.
    """
    if completion_weight is None:
        return settings.rating_weight_qr
    return float(completion_weight)


def _rating_sum(
    aggregates: ProfileAggregates, total_sum: int, total_count: int, settings: Settings
) -> float | None:
    """The smoothed rating, or ``None`` when no number may be published."""
    if aggregates.rating_count <= FEW_REVIEWS_LIMIT or total_count <= 0:
        return None
    denominator = settings.rating_prior_c + aggregates.rating_weight_sum
    if denominator <= 0:
        # Only a zero smoothing constant with zero weights gets here: there is
        # no average to publish, and a division must not happen.
        return None
    mean = total_sum / total_count
    return (settings.rating_prior_c * mean + aggregates.rating_weighted_sum) / (
        denominator
    )


def _from_row(row: ProfileAggregate) -> ProfileAggregates:
    return ProfileAggregates(
        user_id=row.user_id,
        rating_count=row.rating_count,
        rating_sum=row.rating_sum,
        rating_weight_sum=row.rating_weight_sum,
        rating_weighted_sum=row.rating_weighted_sum,
        completed_interactions=row.completed_interactions,
        no_shows=row.no_shows,
        cancelled_after_acceptance=row.cancelled_after_acceptance,
        late_cancellations=row.late_cancellations,
        tag_counts=dict(row.tag_counts),
    )


async def _lock(session: AsyncSession) -> None:
    await session.execute(
        text("SELECT pg_advisory_xact_lock(hashtextextended(:key, 0))"),
        {"key": _AGGREGATE_LOCK},
    )


async def compute_aggregates(
    session: AsyncSession,
    user_id: UUID,
    settings: Settings,
    now: datetime | None = None,
) -> ProfileAggregates:
    """Recompute every stored field of one profile from the primary data."""
    moment = now or clock.now()
    interactions = _pair_interactions(user_id).subquery()
    ranked = select(
        interactions.c.interaction_id,
        interactions.c.completion_weight,
        func.row_number()
        .over(
            partition_by=(
                interactions.c.pair_low,
                interactions.c.pair_high,
                func.date_trunc(
                    "month", func.timezone("UTC", interactions.c.finished_at)
                ),
            ),
            order_by=(interactions.c.finished_at, interactions.c.interaction_id),
        )
        .label("place"),
    ).subquery()
    ratings = await session.execute(
        select(Review.rating, ranked.c.completion_weight)
        .join(ranked, ranked.c.interaction_id == Review.interaction_id)
        .where(
            Review.subject_id == user_id,
            Review.published_at.is_not(None),
            Review.hidden_at.is_(None),
            ranked.c.place <= settings.rating_pair_monthly_limit,
        )
    )
    rating_count = 0
    rating_sum = 0
    weight_sum = 0.0
    weighted_sum = 0.0
    for rating, completion_weight in ratings:
        weight = _weight(completion_weight, settings)
        rating_count += 1
        rating_sum += rating
        weight_sum += weight
        weighted_sum += weight * rating

    completed = await session.scalar(
        select(func.count())
        .select_from(Interaction)
        .join(Listing, Listing.id == Interaction.listing_id)
        .where(
            or_(
                Listing.author_id == user_id,
                Interaction.participant_id == user_id,
            ),
            _completed(),
            _finished_at() <= moment,
        )
    )
    no_shows = await session.scalar(
        select(func.count())
        .select_from(NoShowMark)
        .where(
            NoShowMark.subject_id == user_id,
            NoShowMark.status == NoShowStatus.COUNTED.value,
        )
    )
    cancelled = await session.scalar(
        select(func.count(func.distinct(Interaction.id)))
        .select_from(Interaction)
        .join(Listing, Listing.id == Interaction.listing_id)
        .join(ListingEvent, ListingEvent.interaction_id == Interaction.id)
        .where(
            Interaction.status == InteractionStatus.CANCELLED.value,
            ListingEvent.previous_status == InteractionStatus.ACCEPTED.value,
            ListingEvent.status == InteractionStatus.CANCELLED.value,
            or_(
                and_(
                    Interaction.cancelled_by == "author",
                    Listing.author_id == user_id,
                ),
                and_(
                    Interaction.cancelled_by == "participant",
                    Interaction.participant_id == user_id,
                ),
            ),
        )
    )
    late = await session.scalar(
        select(func.count())
        .select_from(Interaction)
        .where(
            Interaction.participant_id == user_id,
            Interaction.late_cancelled.is_(True),
        )
    )
    tag_rows = await session.execute(
        select(ReviewTag.tag, func.count().label("uses"))
        .join(Review, Review.id == ReviewTag.review_id)
        .where(
            Review.subject_id == user_id,
            Review.published_at.is_not(None),
            Review.hidden_at.is_(None),
        )
        .group_by(ReviewTag.tag)
    )
    return ProfileAggregates(
        user_id=user_id,
        rating_count=rating_count,
        rating_sum=rating_sum,
        rating_weight_sum=weight_sum,
        rating_weighted_sum=weighted_sum,
        completed_interactions=int(completed or 0),
        no_shows=int(no_shows or 0),
        cancelled_after_acceptance=int(cancelled or 0),
        late_cancellations=int(late or 0),
        tag_counts={tag: int(uses) for tag, uses in tag_rows},
    )


async def _store(
    session: AsyncSession, aggregates: ProfileAggregates, now: datetime
) -> None:
    values: dict[str, Any] = {
        "user_id": aggregates.user_id,
        "rating_count": aggregates.rating_count,
        "rating_sum": aggregates.rating_sum,
        "rating_weight_sum": aggregates.rating_weight_sum,
        "rating_weighted_sum": aggregates.rating_weighted_sum,
        "completed_interactions": aggregates.completed_interactions,
        "no_shows": aggregates.no_shows,
        "cancelled_after_acceptance": aggregates.cancelled_after_acceptance,
        "late_cancellations": aggregates.late_cancellations,
        "tag_counts": aggregates.tag_counts,
        "computed_at": now,
    }
    statement = insert(ProfileAggregate).values(
        **values, created_at=now, updated_at=now
    )
    changes = {
        name: getattr(statement.excluded, name) for name in values if name != "user_id"
    }
    changes["updated_at"] = now
    await session.execute(
        statement.on_conflict_do_update(index_elements=["user_id"], set_=changes)
    )


async def refresh_aggregates(
    session: AsyncSession,
    user_ids: Iterable[UUID],
    settings: Settings,
    now: datetime | None = None,
) -> int:
    """Rebuild the rows of ``user_ids`` from the primary data; return their number.

    Safe to repeat and to run in parallel: the values are absolute and the
    advisory lock serializes a read-write pair. A user that disappeared is
    skipped, so a stale delivery never fails.
    """
    unique = sorted({user_id for user_id in user_ids if user_id is not None}, key=str)
    if not unique:
        return 0
    await _lock(session)
    moment = now or clock.now()
    existing = set(await session.scalars(select(User.id).where(User.id.in_(unique))))
    updated = 0
    for user_id in unique:
        if user_id not in existing:
            continue
        aggregates = await compute_aggregates(session, user_id, settings, moment)
        await _store(session, aggregates, moment)
        updated += 1
    return updated


async def _aggregate_user_ids(session: AsyncSession) -> set[UUID]:
    """Everyone whose row exists or may become non-zero."""
    found: set[UUID] = set()
    queries = (
        select(Interaction.participant_id).distinct(),
        select(Listing.author_id)
        .join(Interaction, Interaction.listing_id == Listing.id)
        .distinct(),
        select(Review.author_id).distinct(),
        select(Review.subject_id).distinct(),
        select(NoShowMark.subject_id).distinct(),
        select(ProfileAggregate.user_id),
    )
    for query in queries:
        found.update(await session.scalars(query))
    return found


async def rebuild_aggregates(
    session: AsyncSession, settings: Settings, now: datetime | None = None
) -> int:
    """Recompute every profile row from the primary data; return their number.

    The full pass is the recovery path of the aggregate: it heals a missed
    delivery and is safe to interrupt and rerun.
    """
    await _lock(session)
    moment = now or clock.now()
    user_ids = await _aggregate_user_ids(session)
    for user_id in sorted(user_ids, key=str):
        aggregates = await compute_aggregates(session, user_id, settings, moment)
        await _store(session, aggregates, moment)
    return len(user_ids)


async def profile_reputation(
    session: AsyncSession, user_id: UUID, settings: Settings
) -> ProfileReputation:
    """The aggregates of one profile, or 404 for an unknown user.

    A row missing for a known user (before the first background run or the
    deployment rebuild) is computed in place: the read never invents a zero
    profile for someone who has history.
    """
    if await session.scalar(select(User.id).where(User.id == user_id)) is None:
        raise ProblemError(NOT_FOUND)
    stored = await session.execute(
        select(
            ProfileAggregate,
            select(func.coalesce(func.sum(ProfileAggregate.rating_sum), 0))
            .scalar_subquery()
            .label("total_rating_sum"),
            select(func.coalesce(func.sum(ProfileAggregate.rating_count), 0))
            .scalar_subquery()
            .label("total_rating_count"),
        ).where(ProfileAggregate.user_id == user_id)
    )
    record = stored.first()
    if record is None:
        aggregates = await compute_aggregates(session, user_id, settings)
        total_sum, total_count = (
            await session.execute(
                select(
                    func.coalesce(func.sum(ProfileAggregate.rating_sum), 0),
                    func.coalesce(func.sum(ProfileAggregate.rating_count), 0),
                )
            )
        ).one()
        total_sum = int(total_sum) + aggregates.rating_sum
        total_count = int(total_count) + aggregates.rating_count
    else:
        row, total_sum, total_count = record
        aggregates = _from_row(row)
    rating = _rating_sum(aggregates, int(total_sum), int(total_count), settings)
    return ProfileReputation(
        user_id=user_id,
        rating=rating,
        rating_state="rated" if rating is not None else "few_reviews",
        rating_count=aggregates.rating_count,
        completed_interactions=aggregates.completed_interactions,
        no_shows=aggregates.no_shows,
        cancelled_after_acceptance=aggregates.cancelled_after_acceptance,
        late_cancellations=aggregates.late_cancellations,
        tag_counts=aggregates.tag_counts,
    )


def queue_profile_refresh(session: AsyncSession, users: Iterable[UUID]) -> None:
    """Queue the background refresh of ``users`` in the current transaction."""
    unique = sorted({user_id for user_id in users if user_id is not None}, key=str)
    if not unique:
        return
    add_message(
        session,
        PROFILE_AGGREGATE_TOPIC,
        {"users": [str(user_id) for user_id in unique]},
    )


@outbox_handlers.register(PROFILE_AGGREGATE_TOPIC)
async def refresh_delivered_profiles(session: AsyncSession, job: JobInfo) -> None:
    """Rebuild the profiles of one delivered change; safe to deliver twice."""
    users = [UUID(str(value)) for value in list(job.payload.get("users", []))]
    await refresh_aggregates(session, users, get_settings())


__all__ = [
    "FEW_REVIEWS_LIMIT",
    "PROFILE_AGGREGATE_TOPIC",
    "ProfileAggregates",
    "ProfileReputation",
    "RatingState",
    "compute_aggregates",
    "profile_reputation",
    "queue_profile_refresh",
    "rebuild_aggregates",
    "refresh_aggregates",
    "refresh_delivered_profiles",
]
