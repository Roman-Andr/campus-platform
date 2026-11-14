"""Private photo upload and listing attachment endpoints."""

from collections.abc import Sequence
from datetime import datetime
from uuid import UUID, uuid4

from fastapi import Request, Response
from pydantic import BaseModel, ConfigDict
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from campus.core import clock
from campus.core.config import Settings
from campus.core.outbox import add_message
from campus.core.storage import Storage, storage_io
from campus.core.web import DbSession, Problem, ProblemError, api_router
from campus.core.web.auth import CurrentUser
from campus.core.web.datetimes import Instant
from campus.core.web.problems import NOT_FOUND
from campus.modules.files.models import File
from campus.modules.files.service import expire_later, locked_file
from campus.modules.identity import ProfiledUser
from campus.modules.listings import (
    CONFLICT,
    FORBIDDEN,
    Preview,
    locked,
    readable,
    register_preview_loader,
    user_for,
)
from campus.modules.university import AccountType

router = api_router(
    tags=["Photos"],
    responses={
        403: {"model": Problem},
        404: {"model": Problem},
        409: {"model": Problem},
    },
)


class FileOutput(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    purpose: str
    status: str
    size: int
    rejection_reason: str | None
    expires_at: Instant


class UploadOutput(BaseModel):
    file: FileOutput
    url: str
    fields: dict[str, str]
    expires_at: Instant


class PhotoOrder(BaseModel):
    model_config = ConfigDict(extra="forbid")
    file_ids: list[UUID]


class PhotoOutput(BaseModel):
    id: UUID
    url: str
    preview_url: str
    expires_at: Instant


class PhotosOutput(BaseModel):
    items: list[PhotoOutput]


@router.post("/files/photo-uploads", status_code=201)
async def request_photo_upload(
    request: Request, response: Response, session: DbSession, principal: ProfiledUser
) -> UploadOutput:
    """Return a size-constrained S3 POST form; upload its file field last."""
    response.headers["Cache-Control"] = "private, no-store"
    await require_author(session, principal)
    settings = request.app.state.settings
    now = clock.now()
    file = File(
        owner_id=principal.user_id,
        key=f"photos/{uuid4()}",
        upload_expires_at=now + settings.photo_upload_ttl,
        expires_at=now + max(settings.photo_upload_ttl, settings.photo_unattached_ttl),
    )
    session.add(file)
    await session.flush()
    post = await storage_io(Storage(settings).upload, file.key + "/source")
    await expire_later(session, file)
    return UploadOutput(
        file=FileOutput.model_validate(file),
        url=post["url"],
        fields=post["fields"],
        expires_at=file.upload_expires_at,
    )


async def require_author(session: DbSession, principal: ProfiledUser) -> None:
    if (await user_for(session, principal)).account_type not in (
        AccountType.STUDENT,
        AccountType.EMPLOYEE,
    ):
        raise ProblemError(FORBIDDEN)


async def owned(session: DbSession, file_id: UUID, user_id: UUID) -> File:
    file = await locked_file(session, file_id)
    if file is None or file.owner_id != user_id:
        raise ProblemError(NOT_FOUND)
    return file


@router.get("/files/{file_id}")
async def get_photo_upload(
    file_id: UUID, session: DbSession, principal: CurrentUser
) -> FileOutput:
    return FileOutput.model_validate(await owned(session, file_id, principal.user_id))


@router.post("/files/{file_id}/complete", status_code=202)
async def complete_photo_upload(
    file_id: UUID, session: DbSession, principal: ProfiledUser
) -> FileOutput:
    await require_author(session, principal)
    file = await owned(session, file_id, principal.user_id)
    if file.expires_at <= clock.now():
        raise ProblemError(CONFLICT)
    if file.status == "pending":
        file.status = "processing"
        add_message(session, "files.process", {"file_id": str(file.id)})
    return FileOutput.model_validate(file)


@router.put("/listings/{listing_id}/photos", status_code=204)
async def set_listing_photos(
    listing_id: UUID,
    data: PhotoOrder,
    request: Request,
    session: DbSession,
    principal: ProfiledUser,
) -> None:
    await require_author(session, principal)
    listing = await locked(session, listing_id)
    if listing.author_id != principal.user_id:
        raise ProblemError(FORBIDDEN)
    if listing.purged_at is not None:
        raise ProblemError(CONFLICT)
    settings = request.app.state.settings
    if len(data.file_ids) > settings.photo_listing_limit or len(
        set(data.file_ids)
    ) != len(data.file_ids):
        raise ProblemError(CONFLICT)
    files = list(
        await session.scalars(
            select(File)
            .where((File.listing_id == listing.id) | File.id.in_(data.file_ids))
            .order_by(File.id)
            .with_for_update()
        )
    )
    by_id = {file.id: file for file in files}
    for file_id in data.file_ids:
        file = by_id.get(file_id)
        if (
            file is None
            or file.owner_id != principal.user_id
            or file.status != "ready"
            or file.purpose != "listing_photo"
            or file.listing_id not in (None, listing.id)
            or (file.listing_id is None and file.expires_at <= clock.now())
        ):
            raise ProblemError(CONFLICT)
    for file in files:
        if file.id in data.file_ids:
            file.listing_id, file.position = listing.id, data.file_ids.index(file.id)
        else:
            file.listing_id, file.position = None, None
            file.expires_at = max(
                file.upload_expires_at, clock.now() + settings.photo_unattached_ttl
            )
            await expire_later(session, file)
    listing.version += 1


@router.get("/listings/{listing_id}/photos")
async def listing_photos(
    listing_id: UUID,
    request: Request,
    response: Response,
    session: DbSession,
    principal: CurrentUser,
) -> PhotosOutput:
    """Issue bearer URLs only after the normal listing visibility check."""
    response.headers["Cache-Control"] = "private, no-store"
    await readable(session, listing_id, await user_for(session, principal))
    storage = Storage(request.app.state.settings)
    expires_at: datetime = clock.now() + request.app.state.settings.photo_read_ttl
    files = await session.scalars(
        select(File)
        .where(File.listing_id == listing_id, File.status == "ready")
        .order_by(File.position)
    )
    return PhotosOutput(
        items=[
            PhotoOutput(
                id=file.id,
                url=storage.url(file.key + "/photo"),
                preview_url=storage.url(file.key + "/preview"),
                expires_at=expires_at,
            )
            for file in files
        ]
    )


@register_preview_loader("photos")
async def first_photo_previews(
    session: AsyncSession, settings: Settings, listing_ids: Sequence[UUID]
) -> dict[UUID, Preview]:
    """The first ready photo of each listing, with one signed preview link.

    The caller passes listings it has already filtered by visibility; the
    query only batches what would otherwise be a request per feed row.
    """
    files = await session.scalars(
        select(File)
        .where(File.listing_id.in_(listing_ids), File.status == "ready")
        .order_by(File.listing_id, File.position, File.id)
    )
    first: dict[UUID, File] = {}
    for file in files:
        if file.listing_id is not None:
            first.setdefault(file.listing_id, file)
    if not first:
        return {}
    storage = Storage(settings)
    expires_at = clock.now() + settings.photo_read_ttl
    return {
        listing_id: Preview(
            file_id=file.id,
            url=storage.url(file.key + "/preview"),
            expires_at=expires_at,
        )
        for listing_id, file in first.items()
    }
