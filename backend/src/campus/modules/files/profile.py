"""The profile photo of the signed-in user (specification, 5.1.1, module 2,
item 1).

A profile has at most one photo: a ``ready`` file of the user, uploaded and
checked like any photo (``/files/photo-uploads``), then attached here. A
replaced or removed photo is deleted from the storage at once, so its
already issued links stop working; its record follows with the expiry job.
"""

from uuid import UUID

from fastapi import Request, Response
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from campus.core import clock
from campus.core.config import Settings
from campus.core.i18n import N_
from campus.core.storage import Storage, storage_io
from campus.core.web import DbSession, Problem, ProblemError, ProblemType, api_router
from campus.core.web.auth import CurrentUser
from campus.core.web.datetimes import Instant
from campus.core.web.problems import NOT_FOUND
from campus.modules.files.models import File
from campus.modules.files.service import expire_later, locked_file
from campus.modules.identity import ProfiledUser, User

PROFILE_PHOTO = "profile_photo"
PHOTO_UNAVAILABLE = ProblemType(
    "photo_unavailable",
    409,
    N_("Photo unavailable"),
    N_("The photo is not processed yet, has expired or is used by a listing."),
)

router = api_router(
    prefix="/me/photo",
    tags=["Profile"],
    responses={401: {"model": Problem, "description": "Not signed in."}},
)


class ProfilePhotoInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    file_id: UUID = Field(description="A ready photo uploaded by the user.")


class ProfilePhoto(BaseModel):
    id: UUID
    url: str = Field(description="Signed link to the photo; expires.")
    preview_url: str = Field(description="Signed link to the preview; expires.")
    expires_at: Instant


def photo_output(settings: Settings, file: File) -> ProfilePhoto:
    storage = Storage(settings)
    return ProfilePhoto(
        id=file.id,
        url=storage.url(file.key + "/photo"),
        preview_url=storage.url(file.key + "/preview"),
        expires_at=clock.now() + settings.photo_read_ttl,
    )


async def _lock_profile(session: AsyncSession, user_id: UUID) -> File | None:
    """Serialize photo changes of the user; return the current photo."""
    await session.get(User, user_id, with_for_update=True)
    return await session.scalar(
        select(File).where(File.profile_user_id == user_id).with_for_update()
    )


async def _discard(session: AsyncSession, settings: Settings, file: File) -> None:
    file.profile_user_id = None
    file.expires_at = max(file.upload_expires_at, clock.now())
    await session.flush()
    await expire_later(session, file)
    # Delete the objects now: issued links must stop working at once. Should
    # the transaction fail afterwards, the photo stays attached without
    # objects and the user simply uploads a new one.
    storage = Storage(settings)
    for suffix in ("/photo", "/preview"):
        await storage_io(storage.delete, file.key + suffix)


@router.get("", responses={404: {"model": Problem, "description": "No photo."}})
async def get_my_photo(
    request: Request, response: Response, session: DbSession, principal: CurrentUser
) -> ProfilePhoto:
    """The profile photo with fresh signed links; ``404`` without a photo."""
    response.headers["Cache-Control"] = "private, no-store"
    file = await session.scalar(
        select(File).where(File.profile_user_id == principal.user_id)
    )
    if file is None:
        raise ProblemError(NOT_FOUND)
    return photo_output(request.app.state.settings, file)


@router.put("", responses={404: {"model": Problem}, 409: {"model": Problem}})
async def set_my_photo(
    data: ProfilePhotoInput,
    request: Request,
    response: Response,
    session: DbSession,
    principal: ProfiledUser,
) -> ProfilePhoto:
    """Set or replace the profile photo; the previous one is deleted.

    ``404`` for a file of someone else, ``409`` for a file that is not ready
    or is attached to a listing."""
    response.headers["Cache-Control"] = "private, no-store"
    settings: Settings = request.app.state.settings
    current = await _lock_profile(session, principal.user_id)
    if current is not None and current.id == data.file_id:
        return photo_output(settings, current)
    file = await locked_file(session, data.file_id)
    if file is None or file.owner_id != principal.user_id:
        raise ProblemError(NOT_FOUND)
    if (
        file.status != "ready"
        or file.listing_id is not None
        or file.expires_at <= clock.now()
    ):
        raise ProblemError(PHOTO_UNAVAILABLE)
    if current is not None:
        await _discard(session, settings, current)
    file.profile_user_id, file.purpose = principal.user_id, PROFILE_PHOTO
    await session.flush()
    return photo_output(settings, file)


@router.delete("", status_code=204)
async def delete_my_photo(
    request: Request, session: DbSession, principal: CurrentUser
) -> None:
    """Remove the profile photo, if any; it is deleted from the storage."""
    current = await _lock_profile(session, principal.user_id)
    if current is not None:
        await _discard(session, request.app.state.settings, current)
