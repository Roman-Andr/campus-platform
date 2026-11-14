"""Retryable image processing and expiry, serialized with attachment changes."""

from io import BytesIO
from uuid import UUID

from PIL import Image, ImageOps, UnidentifiedImageError
from pillow_heif import register_heif_opener
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from campus.core import clock
from campus.core.config import Settings, get_settings
from campus.core.deadlines import deadline_handlers, schedule_deadline
from campus.core.jobs import JobInfo
from campus.core.outbox import outbox_handlers
from campus.core.storage import Storage, storage_io
from campus.modules.files.models import File

register_heif_opener()


class InvalidPhotoError(ValueError):
    """Permanent content failure; storage failures must propagate for retry."""


def transcode(data: bytes, settings: Settings) -> tuple[bytes, bytes]:
    if not data or len(data) > settings.photo_max_bytes:
        raise InvalidPhotoError("invalid_size")
    try:
        with Image.open(BytesIO(data)) as source:
            if source.format not in {"JPEG", "PNG", "WEBP", "HEIF"}:
                raise InvalidPhotoError("unsupported_image")
            if source.width * source.height > settings.photo_max_pixels:
                raise InvalidPhotoError("too_many_pixels")
            source.load()
            oriented = ImageOps.exif_transpose(source).convert("RGB")
            # A fresh pixel-only image carries neither EXIF nor ICC/XMP/comments.
            clean = Image.new("RGB", oriented.size)
            clean.paste(oriented)
            full = BytesIO()
            clean.save(full, "JPEG", quality=settings.photo_jpeg_quality)
            clean.thumbnail((settings.photo_preview_size, settings.photo_preview_size))
            preview = BytesIO()
            clean.save(preview, "JPEG", quality=settings.photo_jpeg_quality)
            return full.getvalue(), preview.getvalue()
    except (
        UnidentifiedImageError,
        OSError,
        SyntaxError,
        Image.DecompressionBombError,
        Image.DecompressionBombWarning,
    ) as error:
        raise InvalidPhotoError("invalid_image") from error


async def locked_file(session: AsyncSession, file_id: UUID) -> File | None:
    return await session.scalar(
        select(File).where(File.id == file_id).with_for_update()
    )


async def expire_later(session: AsyncSession, file: File) -> None:
    # Append instead of upserting: a runner locks its deadline before the
    # file, while attachment locks the file first. Avoid a lock inversion.
    # Old deadlines simply observe the current expires_at and do nothing.
    await schedule_deadline(
        session,
        "files.expire",
        file.expires_at,
        {"file_id": str(file.id)},
    )


@outbox_handlers.register("files.process")
async def process_photo(session: AsyncSession, job: JobInfo) -> None:
    file = await locked_file(session, UUID(job.payload["file_id"]))
    if file is None or file.status != "processing":
        return
    settings = get_settings()
    storage = Storage(settings)
    data = await storage_io(storage.read, file.key + "/source")
    file.size = len(data)
    try:
        full, preview = await storage_io(transcode, data, settings)
    except InvalidPhotoError as error:
        file.status, file.rejection_reason = "rejected", str(error)
        return
    # Deterministic keys make partial writes and transaction retries harmless.
    # Keep the source until expiry: a failed DB commit must remain retryable.
    await storage_io(storage.write, file.key + "/photo", full)
    await storage_io(storage.write, file.key + "/preview", preview)
    file.size, file.status = len(data), "ready"


@deadline_handlers.register("files.expire")
async def expire_photo(session: AsyncSession, job: JobInfo) -> None:
    file = await locked_file(session, UUID(job.payload["file_id"]))
    if file is None or file.expires_at > clock.now():
        return
    storage = Storage(get_settings())
    # Expiry is never earlier than the upload credential expiration. Otherwise
    # a still-valid POST could recreate a source after cleanup removed its row.
    await storage_io(storage.delete, file.key + "/source")
    if file.listing_id is None and file.profile_user_id is None:
        for suffix in ("/photo", "/preview"):
            await storage_io(storage.delete, file.key + suffix)
        await session.delete(file)
