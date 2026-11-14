"""Cleanup of archived listings (specification, 5.3.2).

Run by the cleanup task (``CAMPUS_CLEANUP_CRON``). A listing is archived
while it is expired, completed or cancelled; ``archived_at`` records when
it last entered the archive and is cleared when it leaves (re-publication).
Hidden listings are kept for moderation and never enter the archive.

``listing_archive_retention`` after the later of that moment and the last
change of any of its interactions, the listing is purged: its description
and attached content (photos, through :data:`archive_purgers`) are removed
and ``purged_at`` is set. The listing row, its interactions and its history
stay, so participants still read what they took part in. A listing with an
unfinished interaction (pending or accepted) is not purged.

Every listing is purged in its own transaction under its row lock, taken
with ``SKIP LOCKED``: a concurrent re-publication, extension or photo change
either commits first and takes the listing out of the archive, or waits and
then sees ``purged_at``. Content purgers delete external objects before the
commit; deleting a missing object is allowed, and a failure rolls the
listing back for the next run. The report holds counts only.
"""

from collections.abc import Awaitable, Callable
from datetime import datetime
from uuid import UUID

import structlog
from sqlalchemy import ColumnElement, exists, or_, select, tuple_
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from campus.core import clock
from campus.core.config import Settings
from campus.core.tasks import register_cleanup
from campus.modules.listings.models import (
    Interaction,
    InteractionStatus,
    Listing,
    ListingEvent,
)
from campus.modules.listings.service import ARCHIVED

logger = structlog.get_logger(__name__)

type ArchivePurger = Callable[[AsyncSession, Listing, Settings], Awaitable[int]]
"""Removes content of a locked listing kept by another module; returns its count.

It runs in the purge transaction and must tolerate repetition: a failure
after an external deletion retries the whole listing later.
"""

archive_purgers: dict[str, ArchivePurger] = {}


def register_archive_purger(name: str) -> Callable[[ArchivePurger], ArchivePurger]:
    """Decorator: purge the module's content of archived listings."""

    def decorator(purger: ArchivePurger) -> ArchivePurger:
        if name in archive_purgers:
            msg = f"an archive purger {name!r} is already registered"
            raise ValueError(msg)
        archive_purgers[name] = purger
        return purger

    return decorator


def _purgeable(cutoff: datetime) -> tuple[ColumnElement[bool], ...]:
    return (
        Listing.archived_at <= cutoff,
        Listing.purged_at.is_(None),
        Listing.status.in_(ARCHIVED),
        ~exists().where(
            Interaction.listing_id == Listing.id,
            or_(
                Interaction.status.in_(
                    (InteractionStatus.PENDING, InteractionStatus.ACCEPTED)
                ),
                Interaction.updated_at > cutoff,
            ),
        ),
    )


async def purge_listing(
    session: AsyncSession, listing_id: UUID, settings: Settings
) -> dict[str, int] | None:
    """Purge one archived listing if it is still due; ``None`` when it is not."""
    now = clock.now()
    listing = await session.scalar(
        select(Listing)
        .where(
            Listing.id == listing_id,
            *_purgeable(now - settings.listing_archive_retention),
        )
        .with_for_update(of=Listing, skip_locked=True)
    )
    if listing is None:
        return None
    counts = {
        name: await purger(session, listing, settings)
        for name, purger in archive_purgers.items()
    }
    listing.description = ""
    listing.purged_at = now
    listing.version += 1
    session.add(
        ListingEvent(
            listing_id=listing.id,
            actor_id=None,
            action="purged",
            previous_status=listing.status,
            status=listing.status,
            version=listing.version,
        )
    )
    return counts


@register_cleanup("listings")
async def purge_archived_listings(
    sessions: async_sessionmaker[AsyncSession], settings: Settings
) -> dict[str, int]:
    """Purge due archived listings in batches, at most a limit per run."""
    cutoff = clock.now() - settings.listing_archive_retention
    report = {"purged": 0, "skipped": 0, "failed": 0}
    report.update(dict.fromkeys(archive_purgers, 0))
    after: tuple[datetime, UUID] | None = None
    seen = 0
    while seen < settings.listing_archive_cleanup_limit:
        query = (
            select(Listing.archived_at, Listing.id)
            .where(*_purgeable(cutoff))
            .order_by(Listing.archived_at, Listing.id)
            .limit(
                min(
                    settings.listing_archive_cleanup_batch,
                    settings.listing_archive_cleanup_limit - seen,
                )
            )
        )
        if after is not None:
            query = query.where(tuple_(Listing.archived_at, Listing.id) > after)
        async with sessions() as db:
            batch = [(row.archived_at, row.id) for row in await db.execute(query)]
        if not batch:
            break
        seen += len(batch)
        after = batch[-1]
        for _, listing_id in batch:
            try:
                async with sessions() as db, db.begin():
                    counts = await purge_listing(db, listing_id, settings)
            except Exception as error:
                report["failed"] += 1
                logger.warning(
                    "listing_purge_failed",
                    listing_id=str(listing_id),
                    error=type(error).__name__,
                )
                continue
            if counts is None:
                report["skipped"] += 1
                continue
            report["purged"] += 1
            for name, count in counts.items():
                report[name] += count
    return report
