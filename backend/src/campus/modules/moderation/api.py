"""Administrator API of the rules versions and the complaint reason catalogue.

Only an administrator may publish a new document version or change a reason;
a published version is append-only and every successful change is recorded
in the audit journal in the same transaction. Document publication goes
through :func:`campus.modules.identity.publish_document`, so the existing
consent gate and the cross-border revocation events keep working unchanged.
"""

from typing import Annotated, Any, Literal
from uuid import UUID

from fastapi import Depends, Query, Request, Response
from pydantic import BaseModel, ConfigDict, StringConstraints
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import selectinload

from campus.core.audit import record_action
from campus.core.db import NAME_MAX_LENGTH
from campus.core.web import (
    DbSession,
    Instant,
    Page,
    PageQuery,
    api_router,
    paginate,
    request_locale,
    sort_by,
)
from campus.core.web.problems import (
    NOT_FOUND,
    ProblemError,
    ProblemResponse,
    problem_response,
)
from campus.modules.identity import (
    DocumentKind,
    DocumentVersion,
    Permissions,
    Role,
    publish_document,
    require_roles,
)
from campus.modules.moderation.models import (
    CLAUSE_MAX_LENGTH,
    CODE_MAX_LENGTH,
    CODE_PATTERN,
    ComplaintReason,
)
from campus.modules.moderation.service import (
    CODE_CONFLICT,
    STALE_REASON,
    load_reason,
    locked_reason,
    reason_audit_state,
    require_rules_document,
)

ReasonCode = Annotated[
    str, StringConstraints(pattern=CODE_PATTERN, max_length=CODE_MAX_LENGTH)
]
ReasonName = Annotated[
    str,
    StringConstraints(strip_whitespace=True, min_length=1, max_length=NAME_MAX_LENGTH),
]
ReasonClause = Annotated[
    str,
    StringConstraints(
        strip_whitespace=True, min_length=1, max_length=CLAUSE_MAX_LENGTH
    ),
]
DocumentText = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1)]


class DocumentVersionOut(BaseModel):
    """A published document version with both languages for the panel."""

    model_config = ConfigDict(from_attributes=True, frozen=True)

    id: UUID
    kind: DocumentKind
    version: int
    text_ru: str
    text_en: str
    published_at: Instant
    required: bool


class DocumentVersionSummary(BaseModel):
    """A document version in the version list."""

    model_config = ConfigDict(from_attributes=True, frozen=True)

    id: UUID
    kind: DocumentKind
    version: int
    published_at: Instant
    required: bool


class DocumentPublishInput(BaseModel):
    model_config = ConfigDict(extra="forbid")

    kind: DocumentKind
    text_ru: DocumentText
    text_en: DocumentText


class ComplaintReasonOut(BaseModel):
    """A complaint reason with both languages and its rules basis."""

    model_config = ConfigDict(from_attributes=True, frozen=True)

    id: UUID
    code: str
    name_ru: str
    name_en: str
    rules_document_id: UUID
    rules_version: int
    rules_clause: str
    active: bool
    version: int
    created_at: Instant
    updated_at: Instant


class ComplaintReasonInput(BaseModel):
    model_config = ConfigDict(extra="forbid")

    code: ReasonCode
    name_ru: ReasonName
    name_en: ReasonName
    rules_document_id: UUID
    rules_clause: ReasonClause


class ComplaintReasonEdit(BaseModel):
    model_config = ConfigDict(extra="forbid")

    version: int
    name_ru: ReasonName | None = None
    name_en: ReasonName | None = None
    rules_document_id: UUID | None = None
    rules_clause: ReasonClause | None = None
    active: bool | None = None


class PublicComplaintReasonOut(BaseModel):
    """A reason offered to a complainant in the request language."""

    id: UUID
    code: str
    name: str
    rules_version: int
    rules_clause: str


class PublicComplaintReasonList(BaseModel):
    items: list[PublicComplaintReasonOut]


router = api_router(tags=["moderation"])
admin_router = api_router(
    tags=["moderation admin"],
    dependencies=[Depends(require_roles(Role.ADMINISTRATOR))],
)


@admin_router.get("/documents")
async def admin_list_documents(
    request: Request,
    session: DbSession,
    page: PageQuery,
    kind: Annotated[
        DocumentKind | None,
        Query(description="Only versions of this document kind."),
    ] = None,
    order_by: Literal["published_at", "-published_at", "version", "-version"] = (
        "-published_at"
    ),
) -> Page[DocumentVersionSummary]:
    """All published versions, newest first by default; both languages are
    returned by the detail endpoint."""
    query = select(DocumentVersion)
    if kind is not None:
        query = query.where(DocumentVersion.kind == kind)
    query = sort_by(
        query,
        order_by,
        {
            "published_at": DocumentVersion.published_at,
            "version": DocumentVersion.version,
        },
        DocumentVersion.id,
    )
    return await paginate(
        session,
        query,
        page,
        DocumentVersionSummary,
        settings=request.app.state.settings,
        context=kind.value if kind is not None else "",
    )


@admin_router.get("/documents/{document_id}")
async def admin_get_document(
    document_id: UUID, session: DbSession
) -> DocumentVersionOut:
    """One version with both language texts, for editing and review."""
    document = await session.get(DocumentVersion, document_id)
    if document is None:
        raise ProblemError(NOT_FOUND)
    return DocumentVersionOut.model_validate(document)


@admin_router.post("/documents", status_code=201)
async def admin_publish_document(
    data: DocumentPublishInput, session: DbSession, permissions: Permissions
) -> DocumentVersionOut:
    """Publish a new version atomically; the previous one stays unchanged.

    A required kind gates every account until it accepts the new version,
    and a new cross-border version revokes the previous grants with the
    existing consent events.
    """
    document = await publish_document(
        session, data.kind, text_ru=data.text_ru, text_en=data.text_en
    )
    await record_action(
        session,
        actor_id=permissions.user_id,
        action="administration.document.publish",
        object_type="document_version",
        object_id=document.id,
        before={"version": document.version - 1} if document.version > 1 else None,
        after={
            "kind": document.kind,
            "version": document.version,
            "required": document.required,
        },
    )
    return DocumentVersionOut.model_validate(document)


@admin_router.get("/complaint-reasons")
async def admin_list_complaint_reasons(
    request: Request,
    session: DbSession,
    page: PageQuery,
    active: Annotated[
        bool | None,
        Query(description="Only active or only deactivated reasons."),
    ] = None,
    order_by: Literal["code", "-code", "created_at", "-created_at"] = "code",
) -> Page[ComplaintReasonOut]:
    """The whole catalogue, including deactivated reasons and their basis."""
    query = select(ComplaintReason).options(
        selectinload(ComplaintReason.rules_document)
    )
    if active is not None:
        query = query.where(ComplaintReason.active == active)
    query = sort_by(
        query,
        order_by,
        {
            "code": ComplaintReason.code,
            "created_at": ComplaintReason.created_at,
        },
        ComplaintReason.id,
    )
    return await paginate(
        session,
        query,
        page,
        ComplaintReasonOut,
        settings=request.app.state.settings,
        context=f"active={active}",
    )


@admin_router.get("/complaint-reasons/{reason_id}")
async def admin_get_complaint_reason(
    reason_id: UUID, session: DbSession
) -> ComplaintReasonOut:
    """One reason with both names and the rules basis it points to."""
    return ComplaintReasonOut.model_validate(await load_reason(session, reason_id))


@admin_router.post("/complaint-reasons", status_code=201)
async def admin_create_complaint_reason(
    data: ComplaintReasonInput, session: DbSession, permissions: Permissions
) -> ComplaintReasonOut:
    """Add a reason bound to a published community rules version."""
    document = await require_rules_document(session, data.rules_document_id)
    reason = ComplaintReason(
        code=data.code,
        name_ru=data.name_ru,
        name_en=data.name_en,
        rules_document=document,
        rules_clause=data.rules_clause,
    )
    try:
        async with session.begin_nested():
            session.add(reason)
            await session.flush()
    except IntegrityError:
        raise ProblemError(CODE_CONFLICT, code=data.code) from None
    await record_action(
        session,
        actor_id=permissions.user_id,
        action="moderation.complaint_reason.create",
        object_type="complaint_reason",
        object_id=reason.id,
        after=reason_audit_state(reason),
    )
    return ComplaintReasonOut.model_validate(reason)


def _apply_reason_edit(
    reason: ComplaintReason, data: ComplaintReasonEdit
) -> tuple[dict[str, Any], dict[str, Any]]:
    """Change the provided fields and return the audit diff."""
    before: dict[str, Any] = {}
    after: dict[str, Any] = {}
    for field in ("name_ru", "name_en", "rules_clause", "active"):
        value = getattr(data, field)
        if value is not None and getattr(reason, field) != value:
            before[field] = getattr(reason, field)
            setattr(reason, field, value)
            after[field] = value
    return before, after


@admin_router.patch("/complaint-reasons/{reason_id}", response_model=ComplaintReasonOut)
async def admin_update_complaint_reason(
    reason_id: UUID,
    data: ComplaintReasonEdit,
    request: Request,
    session: DbSession,
    permissions: Permissions,
) -> ComplaintReasonOut | ProblemResponse:
    """Change a reason; a stale version is rejected without overwriting."""
    reason = await locked_reason(session, reason_id)
    if reason.version != data.version:
        return problem_response(
            request,
            STALE_REASON,
            params={"version": reason.version},
            current_version=reason.version,
        )
    before, after = _apply_reason_edit(reason, data)
    if (
        "rules_document_id" in data.model_fields_set
        and data.rules_document_id is not None
        and data.rules_document_id != reason.rules_document_id
    ):
        document = await require_rules_document(session, data.rules_document_id)
        before["rules_document_id"] = reason.rules_document_id
        reason.rules_document = document
        after["rules_document_id"] = document.id
    if not after:
        return ComplaintReasonOut.model_validate(reason)
    before["version"] = reason.version
    reason.version += 1
    after["version"] = reason.version
    await session.flush()
    await record_action(
        session,
        actor_id=permissions.user_id,
        action="moderation.complaint_reason.update",
        object_type="complaint_reason",
        object_id=reason.id,
        before=before,
        after=after,
    )
    return ComplaintReasonOut.model_validate(reason)


@admin_router.delete("/complaint-reasons/{reason_id}", status_code=204)
async def admin_deactivate_complaint_reason(
    reason_id: UUID, session: DbSession, permissions: Permissions
) -> Response:
    """Deactivate a reason without deleting it or its rules basis.

    Complaints keep their own immutable snapshot; an inactive reason is
    simply no longer offered for new complaints.
    """
    reason = await locked_reason(session, reason_id)
    if reason.active:
        before = {"active": True, "version": reason.version}
        reason.active = False
        reason.version += 1
        await session.flush()
        await record_action(
            session,
            actor_id=permissions.user_id,
            action="moderation.complaint_reason.deactivate",
            object_type="complaint_reason",
            object_id=reason.id,
            before=before,
            after={"active": False, "version": reason.version},
        )
    return Response(status_code=204)


@router.get("/complaint-reasons")
async def list_complaint_reasons(
    request: Request, response: Response, session: DbSession
) -> PublicComplaintReasonList:
    """Active reasons for a new complaint in the request language."""
    locale = request_locale(request)
    response.headers["Content-Language"] = locale
    response.headers["Vary"] = "Accept-Language"
    reasons = await session.scalars(
        select(ComplaintReason)
        .where(ComplaintReason.active.is_(True))
        .options(selectinload(ComplaintReason.rules_document))
        .order_by(ComplaintReason.code, ComplaintReason.id)
    )
    return PublicComplaintReasonList(
        items=[
            PublicComplaintReasonOut(
                id=reason.id,
                code=reason.code,
                name=reason.name_in(locale),
                rules_version=reason.rules_version,
                rules_clause=reason.rules_clause,
            )
            for reason in reasons
        ]
    )
