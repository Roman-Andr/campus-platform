"""Archive cleanup of listings and their photos on PostgreSQL and RustFS."""

import asyncio
from datetime import datetime, timedelta
from typing import Any
from uuid import UUID

import pytest
from botocore.exceptions import ClientError
from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncEngine

from campus.core import clock
from campus.core.db import create_session_factory
from campus.core.storage import Storage
from campus.modules.files import File
from campus.modules.listings import Interaction, Listing, ListingEvent
from campus.modules.listings.retention import purge_archived_listings
from tests.test_listings import (
    auth,
    borrower,
    move,
    owner,
    places,
    publish,
    request,
    reserve,
)
from tests.test_photos import at, attach, ready, rustfs, storage, tick_jobs
from tests.test_profile import Account

__all__ = ["auth", "borrower", "owner", "places", "rustfs", "storage"]


async def cleanup(account: Account, **overrides: Any) -> dict[str, int]:
    assert isinstance(account.auth.db.bind, AsyncEngine)
    settings = account.auth.settings.model_copy(update=overrides)
    report = await purge_archived_listings(
        create_session_factory(account.auth.db.bind), settings
    )
    account.auth.db.expire_all()
    return report


async def row(account: Account, listing: dict[str, Any]) -> Listing:
    db = account.auth.db
    db.expire_all()
    found = await db.get(Listing, UUID(listing["id"]))
    assert found is not None
    db.expunge(found)  # keep loaded values readable after the rollback
    await db.rollback()
    return found


def missing(storage: Storage, key: str) -> bool:
    try:
        storage.read(key)
    except ClientError as error:
        return error.response["Error"]["Code"] == "NoSuchKey"
    return False


async def keys(account: Account, file_ids: list[str]) -> list[str]:
    files = await account.auth.db.scalars(
        select(File.key).where(File.id.in_([UUID(i) for i in file_ids]))
    )
    result = list(files)
    await account.auth.db.rollback()
    return result


async def archive_at(account: Account, listing: dict[str, Any], when: datetime) -> None:
    """Move the archive entry of a listing to ``when``."""
    db = account.auth.db
    await db.execute(
        update(Listing)
        .where(Listing.id == UUID(listing["id"]))
        .values(archived_at=when)
    )
    await db.commit()


async def due(account: Account, listing: dict[str, Any]) -> None:
    """Make an archived listing due for cleanup now."""
    retention = account.auth.settings.listing_archive_retention
    await archive_at(account, listing, clock.now() - retention)


async def expire_all(account: Account) -> None:
    """Run the expiry deadlines of every published listing."""
    with at(clock.now() + account.auth.settings.listing_lifetime + timedelta(days=1)):
        await tick_jobs(account)


async def test_retention_boundary_purges_content_and_keeps_history(
    owner: Account, borrower: Account, storage: Storage
) -> None:
    listing = await publish(owner)
    assert listing["archived_at"] is None
    assert listing["purged_at"] is None
    file_ids = [await ready(owner), await ready(owner)]
    assert (await attach(owner, listing, file_ids)).status_code == 204
    object_keys = await keys(owner, file_ids)
    interaction = (await reserve(borrower, listing)).json()
    assert (await move(owner, listing, interaction, "rejected")).status_code == 200
    cancelled = (await request(owner, "POST", f"/{listing['id']}/cancel")).json()
    assert cancelled["archived_at"] is not None
    archived_at = (await row(owner, listing)).archived_at
    assert archived_at is not None
    retention = owner.auth.settings.listing_archive_retention

    with at(archived_at + retention - timedelta(seconds=1)):
        assert (await cleanup(owner))["purged"] == 0
    assert (await row(owner, listing)).purged_at is None
    assert all(not missing(storage, key + "/photo") for key in object_keys)

    boundary = archived_at + retention
    with at(boundary):
        report = await cleanup(owner)
    assert report == {"purged": 1, "skipped": 0, "failed": 0, "photos": 2}
    purged = await row(owner, listing)
    assert purged.purged_at == boundary
    assert purged.description == ""
    assert purged.title == listing["title"]
    assert purged.status == "cancelled"
    for key in object_keys:
        for suffix in ("/source", "/photo", "/preview"):
            assert missing(storage, key + suffix)
    assert (
        await owner.auth.db.scalar(
            select(func.count()).select_from(File).where(File.key.in_(object_keys))
        )
        == 0
    )
    await owner.auth.db.rollback()
    # The interaction, its history and the card remain readable.
    output = (await request(owner, "GET", f"/{listing['id']}")).json()
    assert output["purged_at"] is not None
    assert output["description"] == ""
    interactions = await request(owner, "GET", f"/{listing['id']}/interactions")
    assert [i["id"] for i in interactions.json()["items"]] == [interaction["id"]]
    events = await request(
        borrower,
        "GET",
        f"/{listing['id']}/interactions/{interaction['id']}/events",
    )
    assert events.status_code == 200, events.text
    assert (await request(owner, "GET", f"/{listing['id']}/photos")).json()[
        "items"
    ] == []
    assert (
        await owner.auth.db.scalar(
            select(func.count())
            .select_from(ListingEvent)
            .where(
                ListingEvent.listing_id == UUID(listing["id"]),
                ListingEvent.action == "purged",
            )
        )
        == 1
    )
    await owner.auth.db.rollback()
    # A repeated run purges nothing more.
    with at(boundary + timedelta(days=1)):
        assert (await cleanup(owner))["purged"] == 0


async def test_purged_listing_rejects_republication_and_photos(
    owner: Account, storage: Storage
) -> None:
    assert storage
    listing = await publish(owner)
    await expire_all(owner)
    expired = await row(owner, listing)
    assert expired.status == "expired"
    assert expired.archived_at is not None
    await due(owner, listing)
    assert (await cleanup(owner))["purged"] == 1
    file_id = await ready(owner)
    for response in (
        await request(owner, "POST", f"/{listing['id']}/publish"),
        await attach(owner, listing, [file_id]),
        await request(owner, "POST", f"/{listing['id']}/extend"),
    ):
        assert response.status_code == 409, response.text
        assert response.headers["Content-Type"] == "application/problem+json"
        assert response.json()["type"].endswith("listing_conflict")


async def test_republication_restarts_the_archive_clock(
    owner: Account,
) -> None:
    listing = await publish(owner)
    await expire_all(owner)
    await due(owner, listing)
    republished = (await request(owner, "POST", f"/{listing['id']}/publish")).json()
    assert republished["status"] == "active"
    assert republished["archived_at"] is None
    cancelled = (await request(owner, "POST", f"/{listing['id']}/cancel")).json()
    assert cancelled["archived_at"] is not None
    archived_at = (await row(owner, listing)).archived_at
    assert archived_at is not None
    retention = owner.auth.settings.listing_archive_retention
    with at(archived_at + retention - timedelta(microseconds=1)):
        assert (await cleanup(owner))["purged"] == 0
    with at(archived_at + retention):
        assert (await cleanup(owner))["purged"] == 1


async def test_active_drafts_and_unfinished_obligations_are_kept(
    owner: Account, borrower: Account
) -> None:
    occupied = await publish(owner)
    interaction = (await reserve(borrower, occupied)).json()
    assert (await move(owner, occupied, interaction, "accepted")).status_code == 200
    await expire_all(owner)
    assert (await row(owner, occupied)).status == "expired"
    await due(owner, occupied)
    active = await publish(owner)
    draft = (
        await request(
            owner,
            "POST",
            "/giveaways",
            {"title": "A lamp", "description": "Draft", "draft": True},
        )
    ).json()
    # Old creation dates do not matter, only the archive entry.
    db = owner.auth.db
    await db.execute(
        update(Listing).values(created_at=Listing.created_at - timedelta(days=3650))
    )
    await db.commit()
    retention = owner.auth.settings.listing_archive_retention
    assert (await cleanup(owner))["purged"] == 0
    for listing in (active, draft, occupied):
        assert (await row(owner, listing)).purged_at is None
    # The obligation ends later; retention counts from that change.
    assert (await move(borrower, occupied, interaction, "cancelled")).status_code == 200
    finished = await db.get(Interaction, UUID(interaction["id"]))
    assert finished is not None
    finished_at = finished.updated_at
    await db.rollback()
    with at(finished_at + retention - timedelta(seconds=1)):
        assert (await cleanup(owner))["purged"] == 0
    with at(finished_at + retention):
        assert (await cleanup(owner))["purged"] == 1
    assert (await row(owner, occupied)).purged_at is not None
    assert (await row(owner, active)).purged_at is None
    assert (await row(owner, draft)).purged_at is None


async def test_storage_failure_is_retried_and_missing_objects_are_allowed(
    owner: Account, storage: Storage, monkeypatch: pytest.MonkeyPatch
) -> None:
    listing = await publish(owner)
    file_ids = [await ready(owner), await ready(owner)]
    assert (await attach(owner, listing, file_ids)).status_code == 204
    object_keys = await keys(owner, file_ids)
    # Photo expiry has already removed the sources of attached photos.
    storage.delete(object_keys[0] + "/source")
    await request(owner, "POST", f"/{listing['id']}/cancel")
    await due(owner, listing)
    original = Storage.delete
    failed = False

    def flaky_delete(self: Storage, key: str) -> None:
        nonlocal failed
        if key.startswith(object_keys[1]) and not failed:
            failed = True
            raise OSError("delete temporarily unavailable")
        original(self, key)

    monkeypatch.setattr(Storage, "delete", flaky_delete)
    report = await cleanup(owner)
    assert report == {"purged": 0, "skipped": 0, "failed": 1, "photos": 0}
    kept = await row(owner, listing)
    assert kept.purged_at is None
    assert kept.description != ""
    assert len(await keys(owner, file_ids)) == 2
    report = await cleanup(owner)
    assert report == {"purged": 1, "skipped": 0, "failed": 0, "photos": 2}
    assert await keys(owner, file_ids) == []
    assert all(missing(storage, key + "/photo") for key in object_keys)


async def test_photo_moved_to_another_listing_survives(
    owner: Account, storage: Storage
) -> None:
    old = await publish(owner)
    new = await publish(owner)
    shared, own = await ready(owner), await ready(owner)
    assert (await attach(owner, old, [shared, own])).status_code == 204
    assert (await attach(owner, old, [own])).status_code == 204
    assert (await attach(owner, new, [shared])).status_code == 204
    shared_key, own_key = (
        (await keys(owner, [shared]))[0],
        (await keys(owner, [own]))[0],
    )
    await request(owner, "POST", f"/{old['id']}/cancel")
    await due(owner, old)
    assert (await cleanup(owner))["photos"] == 1
    assert missing(storage, own_key + "/photo")
    assert not missing(storage, shared_key + "/photo")
    photos = (await request(owner, "GET", f"/{new['id']}/photos")).json()["items"]
    assert [p["id"] for p in photos] == [shared]


async def test_batches_respect_the_run_limit(owner: Account) -> None:
    listings = [await publish(owner) for _ in range(5)]
    for listing in listings:
        await request(owner, "POST", f"/{listing['id']}/cancel")
        await due(owner, listing)
    limited = {"listing_archive_cleanup_batch": 2, "listing_archive_cleanup_limit": 3}
    assert (await cleanup(owner, **limited))["purged"] == 3
    assert (await cleanup(owner, **limited))["purged"] == 2
    assert (await cleanup(owner, **limited))["purged"] == 0


@pytest.mark.parametrize("action", ["publish", "photos"])
async def test_parallel_cleanup_and_republication(
    owner: Account, storage: Storage, action: str
) -> None:
    assert storage
    listing = await publish(owner)
    await expire_all(owner)
    await due(owner, listing)
    file_id = await ready(owner)
    if action == "publish":
        mutation = request(owner, "POST", f"/{listing['id']}/publish")
    else:
        mutation = attach(owner, listing, [file_id])
    response, report = await asyncio.gather(mutation, cleanup(owner))
    final = await row(owner, listing)
    assert report["failed"] == 0
    if response.status_code == 409:
        # Cleanup won: the change sees the purge and nothing is attached.
        assert report["purged"] == 1
        assert final.purged_at is not None
        assert len(await keys(owner, [file_id])) == 1
        return
    assert response.status_code in (200, 204), response.text
    if action == "publish" or report["purged"] == 0:
        # The change held the lock or left the archive; the content stays.
        assert final.purged_at is None
        assert final.description == listing["description"]
        assert len(await keys(owner, [file_id])) == 1
    else:
        # The photo change committed first; cleanup removed it with the card.
        assert final.purged_at is not None
        assert await keys(owner, [file_id]) == []
    if action == "publish":
        assert final.status == "active"
        assert final.archived_at is None
