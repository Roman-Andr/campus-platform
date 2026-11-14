"""Photo acceptance over PostgreSQL 18 and the production RustFS protocol."""

import asyncio
import threading
from collections.abc import Iterator
from contextlib import contextmanager
from datetime import datetime, timedelta
from io import BytesIO
from typing import Any
from urllib.error import HTTPError, URLError
from uuid import UUID, uuid4

import httpx2
import pytest
from botocore.exceptions import ClientError
from PIL import Image
from pydantic import SecretStr
from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncEngine
from testcontainers.core.container import DockerContainer
from testcontainers.core.wait_strategies import HttpWaitStrategy

from campus.core import clock
from campus.core.config import Settings, get_settings
from campus.core.db import create_session_factory
from campus.core.deadlines import process_due_deadlines
from campus.core.jobs import JobInfo
from campus.core.outbox import OutboxMessage, process_outbox
from campus.core.storage import Storage, storage_io
from campus.modules.files import File
from campus.modules.files.service import (
    InvalidPhotoError,
    expire_photo,
    process_photo,
    transcode,
)
from campus.modules.identity import Role, RoleAssignment, User
from campus.modules.listings import Listing
from tests.test_identity import Auth
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
from tests.test_profile import Account, Places

__all__ = ["auth", "borrower", "owner", "places", "staff"]


class ClosingHttpWait(HttpWaitStrategy):
    """Close urllib HTTP errors leaked by testcontainers during startup."""

    def _handle_http_error(self, error: URLError | HTTPError) -> bool:
        try:
            return super()._handle_http_error(error)
        finally:
            if isinstance(error, HTTPError):
                error.close()


@pytest.fixture(scope="session")
def rustfs() -> Iterator[str]:
    container = (
        DockerContainer("docker.io/rustfs/rustfs:1.0.5")
        .with_env("RUSTFS_ACCESS_KEY", "photo-tests")
        .with_env("RUSTFS_SECRET_KEY", "photo-tests-secret")
        .with_env("RUSTFS_OBS_LOG_DIRECTORY", "")
        .with_exposed_ports(9000)
        .waiting_for(ClosingHttpWait(9000, "/health/ready").for_status_code(200))
    )
    with container:
        yield f"http://{container.get_container_host_ip()}:{container.get_exposed_port(9000)}"


@pytest.fixture
async def storage(auth: Auth, rustfs: str, monkeypatch: pytest.MonkeyPatch) -> Storage:
    config = {
        "s3_endpoint_url": rustfs,
        "s3_bucket": f"photos-{uuid4().hex}",
        "s3_access_key": SecretStr("photo-tests"),
        "s3_secret_key": SecretStr("photo-tests-secret"),
    }
    auth.settings = auth.settings.model_copy(update=config)
    auth.app.state.settings = auth.settings
    for key, value in config.items():
        monkeypatch.setenv(
            "CAMPUS_" + key.upper(),
            value.get_secret_value() if isinstance(value, SecretStr) else str(value),
        )
    get_settings.cache_clear()
    store = Storage(auth.settings)
    await asyncio.to_thread(store.client.create_bucket, Bucket=auth.settings.s3_bucket)
    return store


def image(fmt: str = "JPEG", *, exif: bool = False) -> bytes:
    picture = Image.new("RGB", (100, 60), "red")
    picture.paste("blue", (0, 0, 50, 60))
    metadata = Image.Exif()
    if exif:
        metadata[274] = 6
        metadata[34853] = {1: "N", 2: (53.0, 0.0, 0.0)}
    buffer = BytesIO()
    picture.save(buffer, fmt, exif=metadata)
    return buffer.getvalue()


async def files_request(
    account: Account,
    method: str,
    path: str,
    data: dict[str, Any] | None = None,
    key: str | None = None,
) -> httpx2.Response:
    return await account.auth.client.request(
        method,
        "/api/v1/files" + path,
        json=data,
        headers={"Idempotency-Key": key or str(uuid4()), **account.headers},
    )


async def upload(account: Account, data: bytes | None = None) -> dict[str, Any]:
    response = await files_request(account, "POST", "/photo-uploads")
    assert response.status_code == 201, response.text
    result: dict[str, Any] = response.json()
    if data is not None:
        async with httpx2.AsyncClient() as client:
            response = await client.post(
                result["url"],
                data=result["fields"],
                files={"file": ("fake.jpg", data, "image/jpeg")},
            )
        assert response.status_code in (200, 204), response.text
    return result


async def work(account: Account) -> None:
    assert isinstance(account.auth.db.bind, AsyncEngine)
    await process_outbox(
        create_session_factory(account.auth.db.bind), account.auth.settings
    )
    account.auth.db.expire_all()


async def ready(account: Account, data: bytes | None = None) -> str:
    result = await upload(account, data or image())
    file_id: str = result["file"]["id"]
    response = await files_request(account, "POST", f"/{file_id}/complete")
    assert response.status_code == 202, response.text
    await work(account)
    response = await files_request(account, "GET", f"/{file_id}")
    assert response.json()["status"] == "ready", response.text
    return file_id


async def attach(
    account: Account, listing: dict[str, Any], ids: list[str]
) -> httpx2.Response:
    return await request(account, "PUT", f"/{listing['id']}/photos", {"file_ids": ids})


async def test_protocol_size_private_and_expiring_links(
    owner: Account, borrower: Account, storage: Storage
) -> None:
    result = await upload(owner)
    async with httpx2.AsyncClient() as client:
        response = await client.post(
            result["url"],
            data=result["fields"],
            files={"file": ("huge.jpg", b"x" * (10 * 1024 * 1024 + 1))},
        )
        assert response.status_code == 400, response.text
        with pytest.raises(ClientError) as error:
            storage.read(result["fields"]["key"])
        assert error.value.response["Error"]["Code"] == "NoSuchKey"
        response = await client.post(
            result["url"],
            data={**result["fields"], "key": "other"},
            files={"file": ("x.jpg", image())},
        )
        assert response.status_code in (400, 403)
    file_id = await ready(owner, image(exif=True))
    listing = await publish(owner)
    assert (await attach(owner, listing, [file_id])).status_code == 204
    response = await request(borrower, "GET", f"/{listing['id']}/photos")
    assert response.headers["Cache-Control"] == "private, no-store"
    photo = response.json()["items"][0]
    async with httpx2.AsyncClient() as client:
        for name in ("url", "preview_url"):
            response = await client.get(photo[name])
            assert response.status_code == 200
            with Image.open(BytesIO(response.content)) as decoded:
                assert decoded.size == (60, 100)
                assert not decoded.getexif()
                assert "exif" not in decoded.info
                pixel = decoded.getpixel((30, 75))
                assert isinstance(pixel, tuple)
                assert pixel[0] > 200
            assert (await client.get(photo[name].split("?")[0])).status_code == 403
        assert storage
        owner.auth.app.state.settings = owner.auth.settings.model_copy(
            update={"photo_read_ttl": timedelta(seconds=1)}
        )
        short = (await request(borrower, "GET", f"/{listing['id']}/photos")).json()
        short_url = short["items"][0]["url"]
        assert "X-Amz-Expires=1" in short_url
        assert (await client.get(short_url)).status_code == 200
        await asyncio.sleep(2)
        assert (await client.get(short_url)).status_code == 403


@pytest.mark.parametrize("fmt", ["JPEG", "PNG", "WEBP", "HEIF"])
async def test_supported_content(owner: Account, storage: Storage, fmt: str) -> None:
    assert storage
    await ready(owner, image(fmt))


async def test_invalid_content_and_actual_size(
    owner: Account, storage: Storage
) -> None:
    for data, reason in [
        (b"not an image", "invalid_image"),
        (b"x" * (10 * 1024 * 1024 + 1), "invalid_size"),
    ]:
        result = await upload(owner)
        storage.client.put_object(
            Bucket=storage.settings.s3_bucket,
            Key=result["fields"]["key"],
            Body=data,
            ContentType="image/jpeg",
        )
        file_id = result["file"]["id"]
        assert (
            await files_request(owner, "POST", f"/{file_id}/complete")
        ).status_code == 202
        await work(owner)
        output = (await files_request(owner, "GET", f"/{file_id}")).json()
        assert output["status"] == "rejected"
        assert output["rejection_reason"] == reason
    for data in (image("GIF"), image("JPEG")[:50]):
        result = await upload(owner, data)
        file_id = result["file"]["id"]
        await files_request(owner, "POST", f"/{file_id}/complete")
        await work(owner)
        assert (await files_request(owner, "GET", f"/{file_id}")).json()[
            "status"
        ] == "rejected"


async def test_attachment_invariants_and_parallel_replacement(
    owner: Account, borrower: Account, storage: Storage
) -> None:
    assert storage
    listing = await publish(owner)
    pending = (await upload(owner))["file"]["id"]
    foreign = await ready(borrower)
    assert (await attach(owner, listing, [pending])).status_code == 409
    assert (await attach(owner, listing, [foreign])).status_code == 409
    ids = [await ready(owner) for _ in range(11)]
    assert (await attach(owner, listing, ids)).status_code == 409
    assert (await attach(owner, listing, [ids[0], ids[0]])).status_code == 409
    responses = await asyncio.gather(
        attach(owner, listing, ids[:10]), attach(owner, listing, ids[1:])
    )
    assert [r.status_code for r in responses] == [204, 204]
    photos = (await request(owner, "GET", f"/{listing['id']}/photos")).json()["items"]
    final = [p["id"] for p in photos]
    assert final in (ids[:10], ids[1:])
    assert (await attach(borrower, listing, [foreign])).status_code == 403
    second = await publish(owner)
    responses = await asyncio.gather(
        attach(owner, second, [final[0]]), attach(owner, listing, final)
    )
    assert sorted(r.status_code for r in responses) == [204, 409]
    assert (await attach(owner, listing, list(reversed(final)))).status_code == 204
    assert [
        p["id"]
        for p in (await request(owner, "GET", f"/{listing['id']}/photos")).json()[
            "items"
        ]
    ] == list(reversed(final))
    assert (await attach(owner, listing, [])).status_code == 204
    assert (await request(owner, "GET", f"/{listing['id']}/photos")).json()[
        "items"
    ] == []


@contextmanager
def at(instant: datetime) -> Iterator[None]:
    # Control domain time without changing SigV4's clock: RustFS runs in a
    # separate process and correctly rejects signatures from tomorrow.
    with pytest.MonkeyPatch.context() as patch:
        patch.setattr(clock, "now", lambda: instant)
        yield


async def tick_jobs(account: Account) -> None:
    assert isinstance(account.auth.db.bind, AsyncEngine)
    await process_due_deadlines(
        create_session_factory(account.auth.db.bind), account.auth.settings
    )
    account.auth.db.expire_all()


async def test_processing_retry_and_duplicate_completion(
    owner: Account, storage: Storage, monkeypatch: pytest.MonkeyPatch
) -> None:
    result = await upload(owner, image())
    file_id = result["file"]["id"]
    key = str(uuid4())
    first = await files_request(owner, "POST", f"/{file_id}/complete", key=key)
    replay = await files_request(owner, "POST", f"/{file_id}/complete", key=key)
    assert first.json() == replay.json()
    assert replay.headers["Idempotent-Replayed"] == "true"
    await asyncio.gather(
        *(files_request(owner, "POST", f"/{file_id}/complete") for _ in range(3))
    )
    db = owner.auth.db
    assert (
        await db.scalar(
            select(func.count())
            .select_from(OutboxMessage)
            .where(OutboxMessage.topic == "files.process")
        )
        == 1
    )
    await db.rollback()
    original = Storage.write
    failed = False

    def flaky_write(self: Storage, key: str, data: bytes) -> None:
        nonlocal failed
        if key.endswith("/preview") and not failed:
            failed = True
            raise OSError("temporary object store outage")
        original(self, key, data)

    monkeypatch.setattr(Storage, "write", flaky_write)
    await work(owner)
    row = await db.get(File, UUID(file_id))
    assert row is not None
    assert row.status == "processing"
    assert storage.read(row.key + "/source") == image()
    job = await db.scalar(
        select(OutboxMessage).where(OutboxMessage.topic == "files.process")
    )
    assert job is not None
    assert job.attempts == 1
    assert job.processed_at is None
    retry_at = job.available_at
    await db.rollback()
    with at(retry_at):
        await work(owner)
    assert (await files_request(owner, "GET", f"/{file_id}")).json()[
        "status"
    ] == "ready"
    # A redelivered event is harmless once processing has completed.
    async with db.begin():
        await process_photo(
            db, JobInfo(uuid4(), "files.process", {"file_id": file_id}, 2)
        )


@pytest.mark.parametrize("state", ["pending", "processing", "ready", "rejected"])
async def test_expiry_retry_and_replay(
    owner: Account, storage: Storage, monkeypatch: pytest.MonkeyPatch, state: str
) -> None:
    result = await upload(owner, image())
    file_id = result["file"]["id"]
    if state in {"ready", "rejected"}:
        if state == "rejected":
            storage.client.put_object(
                Bucket=storage.settings.s3_bucket,
                Key=result["fields"]["key"],
                Body=b"fake jpg",
            )
        await files_request(owner, "POST", f"/{file_id}/complete")
        await work(owner)
    elif state == "processing":
        await files_request(owner, "POST", f"/{file_id}/complete")
    db = owner.auth.db
    row = await db.get(File, UUID(file_id))
    assert row is not None
    expires_at, object_key = row.expires_at, row.key
    await db.rollback()
    original = Storage.delete
    failed = False

    def flaky_delete(self: Storage, key: str) -> None:
        nonlocal failed
        if key.endswith("/preview") and not failed:
            failed = True
            raise OSError("delete temporarily unavailable")
        original(self, key)

    monkeypatch.setattr(Storage, "delete", flaky_delete)
    with at(expires_at + timedelta(seconds=1)):
        await tick_jobs(owner)
        row = await db.get(File, UUID(file_id))
        assert row is not None
        await db.rollback()
    with at(expires_at + timedelta(hours=1)):
        await asyncio.gather(tick_jobs(owner), tick_jobs(owner))
    assert await db.get(File, UUID(file_id)) is None
    for suffix in ("/source", "/photo", "/preview"):
        with pytest.raises(ClientError) as error:
            storage.read(object_key + suffix)
        assert error.value.response["Error"]["Code"] == "NoSuchKey"
    await db.rollback()
    async with db.begin():
        await expire_photo(
            db, JobInfo(uuid4(), "files.expire", {"file_id": file_id}, 2)
        )
        await process_photo(
            db, JobInfo(uuid4(), "files.process", {"file_id": file_id}, 2)
        )


async def test_attached_survives_expiry_then_detach_is_cleaned(
    owner: Account, storage: Storage
) -> None:
    file_id = await ready(owner)
    listing = await publish(owner)
    assert (await attach(owner, listing, [file_id])).status_code == 204
    db = owner.auth.db
    row = await db.get(File, UUID(file_id))
    assert row is not None
    expires_at, object_key = row.expires_at, row.key
    await db.rollback()
    with at(expires_at + timedelta(seconds=1)):
        await tick_jobs(owner)
    assert storage.read(object_key + "/photo")
    assert await db.get(File, UUID(file_id)) is not None
    await db.rollback()
    assert (await attach(owner, listing, [])).status_code == 204
    row = await db.get(File, UUID(file_id))
    assert row is not None
    expires_at = row.expires_at
    await db.rollback()
    with at(expires_at + timedelta(days=2)):
        await tick_jobs(owner)
    assert await db.get(File, UUID(file_id)) is None


@pytest.mark.parametrize("visibility", ["city", "faculty", "dormitory"])
async def test_photo_links_follow_listing_visibility(
    owner: Account, borrower: Account, staff: Account, storage: Storage, visibility: str
) -> None:
    assert storage
    listing = await publish(owner, visibility=visibility)
    file_id = await ready(owner)
    await attach(owner, listing, [file_id])
    path = f"/{listing['id']}/photos"
    assert (await request(borrower, "GET", path)).status_code == 200
    assert (await request(staff, "GET", path)).status_code == 404
    db = owner.auth.db
    user_id = UUID(borrower.tokens["user"]["id"])
    await db.execute(
        update(User)
        .where(User.id == user_id)
        .values(city_id=None, dormitory_id=None, faculty_id=None, course=None)
    )
    await db.commit()
    assert (await request(borrower, "GET", path)).status_code == 404
    await db.execute(
        update(Listing).where(Listing.id == UUID(listing["id"])).values(status="hidden")
    )
    await db.commit()
    assert (await request(borrower, "GET", path)).status_code == 404
    assert (await files_request(borrower, "GET", f"/{file_id}")).status_code == 404
    assert (
        await files_request(borrower, "POST", f"/{file_id}/complete")
    ).status_code in (403, 404)


@pytest.mark.parametrize(
    "actor",
    [
        "student",
        "employee",
        "alumni",
        "former_employee",
        "headman",
        "moderator",
        "administrator",
        "employee_moderator",
        "employee_administrator",
    ],
)
async def test_photo_author_role_matrix(
    owner: Account, borrower: Account, storage: Storage, actor: str
) -> None:
    assert storage
    file_id = await ready(owner)
    listing = await publish(owner, audience="community")
    foreign = [
        await publish(borrower, audience=audience, visibility=scope)
        for audience, scope in [
            ("students", "city"),
            ("community", "city"),
            ("students", "dormitory"),
            ("community", "dormitory"),
        ]
    ]
    db = owner.auth.db
    user_id = UUID(owner.tokens["user"]["id"])
    kind = (
        "employee"
        if actor.startswith("employee")
        else actor
        if actor in {"alumni", "former_employee"}
        else "student"
    )
    role = {
        "headman": Role.HEADMAN,
        "moderator": Role.MODERATOR,
        "administrator": Role.ADMINISTRATOR,
        "employee_moderator": Role.MODERATOR,
        "employee_administrator": Role.ADMINISTRATOR,
    }.get(actor)
    await db.execute(update(User).where(User.id == user_id).values(account_type=kind))
    if role:
        user = await db.get(User, user_id)
        assert user is not None
        db.add(
            RoleAssignment(
                user_id=user_id,
                role=role,
                dormitory_id=user.dormitory_id if role == Role.HEADMAN else None,
            )
        )
    await db.commit()
    response = await files_request(owner, "POST", "/photo-uploads")
    assert response.status_code == (
        403 if kind in {"alumni", "former_employee"} else 201
    ), response.text
    for other in foreign:
        visible = kind == "student" or (
            other["audience"] == "community" and other["visibility"] != "dormitory"
        )
        photos = await request(owner, "GET", f"/{other['id']}/photos")
        assert photos.status_code == (200 if visible else 404), photos.text
    allowed = kind not in {"alumni", "former_employee"}
    assert (await files_request(owner, "POST", f"/{file_id}/complete")).status_code == (
        202 if allowed else 403
    )
    assert (await attach(owner, listing, [file_id])).status_code == (
        204 if allowed else 403
    )


def test_pixel_limit_and_preview_config() -> None:
    with pytest.raises(InvalidPhotoError, match="too_many_pixels"):
        transcode(image(), Settings(photo_max_pixels=10))
    full, preview = transcode(image(exif=True), Settings(photo_preview_size=20))
    with Image.open(BytesIO(full)) as decoded:
        assert decoded.size == (60, 100)
    with Image.open(BytesIO(preview)) as decoded:
        assert decoded.size == (12, 20)
        assert not decoded.getexif()


async def test_cancel_waits_for_inflight_storage_write() -> None:
    started, release, finished = threading.Event(), threading.Event(), threading.Event()

    def write() -> None:
        started.set()
        assert release.wait(timeout=5)
        finished.set()

    task = asyncio.create_task(storage_io(write))
    assert await asyncio.to_thread(started.wait, 5)
    task.cancel()
    await asyncio.sleep(0)
    assert not task.done()
    task.cancel()
    await asyncio.sleep(0)
    assert not task.done()
    release.set()
    with pytest.raises(asyncio.CancelledError):
        await task
    assert finished.is_set()


async def test_parallel_attachment_to_distinct_listings(
    owner: Account, storage: Storage
) -> None:
    assert storage
    first, second = await publish(owner), await publish(owner)
    file_id = await ready(owner)
    responses = await asyncio.gather(
        attach(owner, first, [file_id]), attach(owner, second, [file_id])
    )
    assert sorted(response.status_code for response in responses) == [204, 409]


async def test_expired_and_unready_files_cannot_attach(
    owner: Account, storage: Storage
) -> None:
    assert storage
    listing = await publish(owner)
    file_id = await ready(owner)
    db = owner.auth.db
    for state in ("pending", "processing", "rejected"):
        await db.execute(
            update(File).where(File.id == UUID(file_id)).values(status=state)
        )
        await db.commit()
        assert (await attach(owner, listing, [file_id])).status_code == 409
    await db.execute(
        update(File)
        .where(File.id == UUID(file_id))
        .values(status="ready", expires_at=clock.now() - timedelta(seconds=1))
    )
    await db.commit()
    assert (await attach(owner, listing, [file_id])).status_code == 409
    assert (
        await files_request(owner, "POST", f"/{file_id}/complete")
    ).status_code == 409


@pytest.mark.parametrize("account_type", ["alumni", "former_employee"])
async def test_historical_participant_keeps_photo_access(
    owner: Account,
    borrower: Account,
    staff: Account,
    storage: Storage,
    account_type: str,
) -> None:
    assert storage
    listing = await publish(owner, visibility="dormitory")
    file_id = await ready(owner)
    assert (await attach(owner, listing, [file_id])).status_code == 204
    interaction = (await reserve(borrower, listing)).json()
    assert (await move(borrower, listing, interaction, "cancelled")).status_code == 200
    await owner.auth.db.execute(
        update(User)
        .where(User.id == UUID(borrower.tokens["user"]["id"]))
        .values(account_type=account_type)
    )
    await owner.auth.db.commit()
    response = await request(borrower, "GET", f"/{listing['id']}/photos")
    assert response.status_code == 200, response.text
    assert response.json()["items"][0]["id"] == file_id
    assert (await request(staff, "GET", f"/{listing['id']}/photos")).status_code == 404


async def test_feed_and_my_listings_carry_the_first_photo(
    owner: Account, borrower: Account, storage: Storage
) -> None:
    assert storage
    listing = await publish(owner)
    first = await ready(owner)
    second = await ready(owner)
    assert (await attach(owner, listing, [second, first])).status_code == 204

    def row(items: list[dict[str, Any]], item_id: str) -> dict[str, Any]:
        return next(item for item in items if item["id"] == item_id)

    feed = row((await request(borrower, "GET")).json()["items"], listing["id"])
    assert feed["preview_file_id"] == second
    assert feed["preview_url"]
    assert "X-Amz-Expires" in feed["preview_url"]
    expires = datetime.fromisoformat(feed["preview_expires_at"].replace("Z", "+00:00"))
    assert timedelta(0) < expires - clock.now() <= owner.auth.settings.photo_read_ttl

    mine = row((await request(owner, "GET", "/mine")).json()["items"], listing["id"])
    assert mine["preview_file_id"] == second
    card = (await request(borrower, "GET", f"/{listing['id']}")).json()
    assert card["preview_file_id"] == second

    # The preview follows the order: the first photo is the one shown.
    assert (await attach(owner, listing, [first, second])).status_code == 204
    mine = row((await request(owner, "GET", "/mine")).json()["items"], listing["id"])
    assert mine["preview_file_id"] == first


async def test_listing_without_photos_has_no_preview(
    owner: Account, storage: Storage
) -> None:
    assert storage
    listing = await publish(owner)
    for item in [
        (await request(owner, "GET", f"/{listing['id']}")).json(),
        *((await request(owner, "GET", "/mine")).json()["items"]),
        *((await request(owner, "GET")).json()["items"]),
    ]:
        assert item["preview_url"] is None
        assert item["preview_file_id"] is None
        assert item["preview_expires_at"] is None


async def test_preview_follows_listing_visibility(
    owner: Account, borrower: Account, storage: Storage, places: Places
) -> None:
    assert storage
    home = await publish(owner, visibility="dormitory")
    file_id = await ready(owner)
    assert (await attach(owner, home, [file_id])).status_code == 204
    # A student of the same dormitory sees the listing and its preview.
    feed = (await request(borrower, "GET")).json()["items"]
    assert (
        next(item for item in feed if item["id"] == home["id"])["preview_file_id"]
        == file_id
    )
    # Moving to another city hides the listing: neither the row nor its
    # signed preview link may leak through the feed or the card.
    assert (
        await borrower.put(
            {
                "city_id": str(places.perm),
                "faculty_id": str(places.perm_faculty),
                "course": 1,
            }
        )
    ).status_code == 200
    assert (await request(borrower, "GET")).json()["items"] == []
    assert (await request(borrower, "GET", f"/{home['id']}")).status_code == 404
    assert (await request(borrower, "GET", f"/{home['id']}/photos")).status_code == 404
