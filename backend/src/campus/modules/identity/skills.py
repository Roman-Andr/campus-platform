"""Skills of the profile (specification, 5.1.1, module 2, item 1) from the
common skill tag reference (module 10, item 2).

A profile has two lists, "can" and "wants to learn"; each holds tags of the
reference only and is replaced whole. Tag names are returned and searched in
the language of the request.
"""

from typing import Annotated
from uuid import UUID

from fastapi import Query, Request, Response
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import delete, func, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from campus.core.config import Locale, Settings
from campus.core.i18n import N_, translate
from campus.core.web import (
    DbSession,
    FieldError,
    Problem,
    ProblemError,
    api_router,
    request_locale,
)
from campus.core.web.auth import CurrentUser
from campus.core.web.problems import VALIDATION_FAILED
from campus.modules.identity.models import SkillKind, SkillTag, User, UserSkill

UNKNOWN_TAG = N_("No such skill tag.")
TOO_MANY_TAGS = N_("At most {max} skills.")

router = api_router(
    responses={401: {"model": Problem, "description": "Not signed in."}},
)


class SkillTagOutput(BaseModel):
    """A skill tag of the reference."""

    id: UUID
    code: str = Field(examples=["guitar"])
    name: str = Field(description="In the request language.", examples=["Guitar"])


class SkillTagList(BaseModel):
    items: list[SkillTagOutput]


class SkillsInput(BaseModel):
    """Both lists of the profile; each replaces the current one whole."""

    model_config = ConfigDict(extra="forbid")
    can: list[UUID] = Field(description="Tags of what the user can do.")
    wants: list[UUID] = Field(description="Tags of what the user wants to learn.")


class SkillsOutput(BaseModel):
    """Skills of the profile, each list by name."""

    can: list[SkillTagOutput]
    wants: list[SkillTagOutput]


def _localized(request: Request, response: Response) -> Locale:
    locale = request_locale(request)
    response.headers["Content-Language"] = locale
    response.headers["Vary"] = "Accept-Language"
    return locale


def _tag(tag: SkillTag, locale: Locale) -> SkillTagOutput:
    return SkillTagOutput(id=tag.id, code=tag.code, name=tag.name_in(locale))


def _escape_like(text: str) -> str:
    return text.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")


@router.get("/skill-tags", tags=["Skills"])
async def list_skill_tags(
    request: Request,
    response: Response,
    session: DbSession,
    _principal: CurrentUser,
    q: Annotated[
        str | None,
        Query(
            max_length=100,
            description="Only tags whose name in the request language starts"
            " with this text, case-insensitively.",
        ),
    ] = None,
    limit: Annotated[int | None, Query(ge=1)] = None,
) -> SkillTagList:
    """Skill tags by name in the request language."""
    settings: Settings = request.app.state.settings
    locale = _localized(request, response)
    name = SkillTag.name_column(locale)
    query = select(SkillTag).order_by(func.lower(name), SkillTag.id)
    if q is not None and q.strip():
        query = query.where(
            func.lower(name).like(_escape_like(q.strip().lower()) + "%", escape="\\")
        )
    query = query.limit(
        min(limit or settings.page_size_default, settings.page_size_max)
    )
    tags = await session.scalars(query)
    return SkillTagList(items=[_tag(tag, locale) for tag in tags])


async def _skills(session: AsyncSession, user_id: UUID, locale: Locale) -> SkillsOutput:
    rows = await session.execute(
        select(UserSkill.kind, SkillTag)
        .join(SkillTag, SkillTag.id == UserSkill.tag_id)
        .where(UserSkill.user_id == user_id)
        .order_by(func.lower(SkillTag.name_column(locale)), SkillTag.id)
    )
    lists: dict[str, list[SkillTagOutput]] = {kind: [] for kind in SkillKind}
    for kind, tag in rows:
        lists[kind].append(_tag(tag, locale))
    return SkillsOutput(can=lists[SkillKind.CAN], wants=lists[SkillKind.WANTS])


@router.get("/me/skills", tags=["Profile"])
async def get_my_skills(
    request: Request, response: Response, session: DbSession, principal: CurrentUser
) -> SkillsOutput:
    """Skills of the signed-in user's profile."""
    locale = _localized(request, response)
    return await _skills(session, principal.user_id, locale)


@router.put("/me/skills", tags=["Profile"], responses={422: {"model": Problem}})
async def set_my_skills(
    data: SkillsInput,
    request: Request,
    response: Response,
    session: DbSession,
    principal: CurrentUser,
) -> SkillsOutput:
    """Replace both skill lists; a tag outside the reference answers
    ``validation_failed`` (code ``not_found``)."""
    settings: Settings = request.app.state.settings
    locale = _localized(request, response)
    requested = {*data.can, *data.wants}
    known = set(
        await session.scalars(select(SkillTag.id).where(SkillTag.id.in_(requested)))
    )
    errors: list[FieldError] = []
    for field, ids in (("can", data.can), ("wants", data.wants)):
        unique = list(dict.fromkeys(ids))
        if len(unique) > settings.profile_skills_max:
            errors.append(
                FieldError(
                    detail=translate(
                        TOO_MANY_TAGS, locale, max=settings.profile_skills_max
                    ),
                    code="too_long",
                    pointer=f"#/{field}",
                )
            )
        errors.extend(
            FieldError(
                detail=translate(UNKNOWN_TAG, locale),
                code="not_found",
                pointer=f"#/{field}/{index}",
            )
            for index, tag_id in enumerate(ids)
            if tag_id not in known
        )
    if errors:
        raise ProblemError(VALIDATION_FAILED, errors=errors)
    # Serialize replacements of one user's lists.
    await session.get(User, principal.user_id, with_for_update=True)
    await session.execute(
        delete(UserSkill).where(UserSkill.user_id == principal.user_id)
    )
    rows = [
        {"user_id": principal.user_id, "kind": kind, "tag_id": tag_id}
        for kind, ids in ((SkillKind.CAN, data.can), (SkillKind.WANTS, data.wants))
        for tag_id in dict.fromkeys(ids)
    ]
    if rows:
        await session.execute(insert(UserSkill).values(rows))
    return await _skills(session, principal.user_id, locale)
