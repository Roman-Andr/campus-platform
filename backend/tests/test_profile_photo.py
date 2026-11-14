"""Profile photo over PostgreSQL 18 and the production RustFS protocol."""

import asyncio
from datetime import timedelta
from io import BytesIO
from typing import Any
from uuid import UUID, uuid4

import httpx2
import pytest
from PIL import Image
from sqlalchemy import func, select

from campus.modules.files import File
from tests.test_listings import auth, borrower, owner, places, publish
from tests.test_photos import (
    at,
    attach,
    files_request,
    image,
    ready,
    rustfs,
    storage,
    tick_jobs,
    upload,
    work,
)
from tests.test_profile import Account

__all__ = ["auth", "borrower", "owner", "places", "rustfs", "storage"]


async def photo_request(
    account: Account, method: str, data: dict[str, Any] | None = None
) -> httpx2.Response:
    headers = dict(account.headers)
    if method != "GET":
        headers["Idempotency-Key"] = str(uuid4())
    return await account.auth.client.request(
        method, "/api/v1/me/photo", json=data, headers=headers
    )


async def set_photo(account: Account, file_id: str) -> httpx2.Response:
    return await photo_request(account, "PUT", {"file_id": file_id})


async def fetch(url: str) -> httpx2.Response:
    async with httpx2.AsyncClient() as client:
        return await client.get(url)


async def file_row(account: Account, file_id: str) -> File | None:
    """The file record, detached from the session of the test."""
    db = account.auth.db
    row = await db.get(File, UUID(file_id))
    if row is not None:
        db.expunge(row)
    await db.rollback()
    return row


@pytest.mark.usefixtures("storage")
async def test_photo_is_checked_and_reencoded_without_exif(owner: Account) -> None:
    assert (await photo_request(owner, "GET")).status_code == 404
    file_id = await ready(owner, image(exif=True))
    response = await set_photo(owner, file_id)
    assert response.status_code == 200, response.text
    assert response.headers["Cache-Control"] == "private, no-store"
    photo = response.json()
    assert photo["id"] == file_id
    current = (await photo_request(owner, "GET")).json()
    assert current["id"] == file_id
    for name in ("url", "preview_url"):
        response = await fetch(current[name])
        assert response.status_code == 200
        with Image.open(BytesIO(response.content)) as decoded:
            assert decoded.size == (60, 100)  # EXIF orientation applied
            assert not decoded.getexif()
            assert "exif" not in decoded.info
    # Setting the same photo again changes nothing.
    assert (await set_photo(owner, file_id)).json()["id"] == file_id


@pytest.mark.usefixtures("storage")
async def test_invalid_upload_is_rejected_and_cannot_be_set(owner: Account) -> None:
    result = await upload(owner, b"not an image at all")
    file_id = result["file"]["id"]
    await files_request(owner, "POST", f"/{file_id}/complete")
    await work(owner)
    response = await files_request(owner, "GET", f"/{file_id}")
    assert response.json()["status"] == "rejected"
    response = await set_photo(owner, file_id)
    assert response.status_code == 409
    assert response.json()["code"] == "photo_unavailable"


@pytest.mark.usefixtures("storage")
async def test_replaced_and_removed_photo_is_unavailable(owner: Account) -> None:
    first = await ready(owner)
    old = (await set_photo(owner, first)).json()
    second = await ready(owner)
    new = (await set_photo(owner, second)).json()
    assert new["id"] == second
    for name in ("url", "preview_url"):
        assert (await fetch(old[name])).status_code in (403, 404)
        assert (await fetch(new[name])).status_code == 200
    # The record of the replaced photo goes with the expiry job.
    row = await file_row(owner, first)
    assert row is not None
    assert row.profile_user_id is None
    with at(row.expires_at + timedelta(seconds=1)):
        await tick_jobs(owner)
    assert await file_row(owner, first) is None

    response = await photo_request(owner, "DELETE")
    assert response.status_code == 204
    assert (await photo_request(owner, "GET")).status_code == 404
    for name in ("url", "preview_url"):
        assert (await fetch(new[name])).status_code in (403, 404)
    # Removing again is fine.
    assert (await photo_request(owner, "DELETE")).status_code == 204


@pytest.mark.usefixtures("storage")
async def test_profile_photo_survives_expiry(owner: Account) -> None:
    file_id = await ready(owner)
    await set_photo(owner, file_id)
    row = await file_row(owner, file_id)
    assert row is not None
    with at(row.expires_at + timedelta(days=2)):
        await tick_jobs(owner)
    current = (await photo_request(owner, "GET")).json()
    assert current["id"] == file_id
    assert (await fetch(current["url"])).status_code == 200


@pytest.mark.usefixtures("storage")
async def test_photo_of_someone_else_or_unready_cannot_be_set(
    owner: Account, borrower: Account
) -> None:
    foreign = await ready(borrower)
    response = await set_photo(owner, foreign)
    assert response.status_code == 404
    assert (await set_photo(owner, str(uuid4()))).status_code == 404
    pending = (await upload(owner))["file"]["id"]
    assert (await set_photo(owner, pending)).status_code == 409
    assert (await photo_request(owner, "GET")).status_code == 404


@pytest.mark.usefixtures("storage")
async def test_photo_is_not_shared_with_a_listing(owner: Account) -> None:
    listing = await publish(owner)
    on_listing = await ready(owner)
    assert (await attach(owner, listing, [on_listing])).status_code == 204
    assert (await set_photo(owner, on_listing)).status_code == 409
    on_profile = await ready(owner)
    assert (await set_photo(owner, on_profile)).status_code == 200
    response = await attach(owner, listing, [on_listing, on_profile])
    assert response.status_code == 409
    assert (await photo_request(owner, "GET")).json()["id"] == on_profile


@pytest.mark.usefixtures("storage")
async def test_parallel_changes_keep_one_photo(owner: Account) -> None:
    ids = [await ready(owner) for _ in range(4)]
    responses = await asyncio.gather(*(set_photo(owner, file_id) for file_id in ids))
    assert {response.status_code for response in responses} == {200}
    db = owner.auth.db
    attached = await db.scalar(
        select(func.count()).select_from(File).where(File.profile_user_id.is_not(None))
    )
    await db.rollback()
    assert attached == 1
    current = (await photo_request(owner, "GET")).json()
    assert current["id"] in ids
    assert (await fetch(current["url"])).status_code == 200


@pytest.mark.usefixtures("storage")
async def test_photo_requires_sign_in(owner: Account) -> None:
    client = owner.auth.client
    assert (await client.get("/api/v1/me/photo")).status_code == 401
    headers = {"Idempotency-Key": str(uuid4())}
    response = await client.put(
        "/api/v1/me/photo", json={"file_id": str(uuid4())}, headers=headers
    )
    assert response.status_code == 401
    response = await client.delete("/api/v1/me/photo", headers=headers)
    assert response.status_code == 401


@pytest.mark.usefixtures("storage")
async def test_photo_needs_filled_profile(owner: Account) -> None:
    file_id = await ready(owner)
    newcomer = Account(
        owner.auth, await owner.auth.login(email="newcomer@university.example")
    )
    response = await set_photo(newcomer, file_id)
    assert response.status_code == 403
    assert response.json()["code"] == "profile_incomplete"
    assert (await photo_request(newcomer, "GET")).status_code == 404
    assert (await photo_request(newcomer, "DELETE")).status_code == 204
