"""Domain operations of the complaint reason catalogue and rules publishing."""

from typing import Any
from uuid import UUID

from sqlalchemy import Select, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from campus.core.i18n import N_
from campus.core.web import ProblemError
from campus.core.web.problems import NOT_FOUND, ProblemType
from campus.modules.identity import DocumentKind, DocumentVersion
from campus.modules.moderation.models import ComplaintReason

CODE_CONFLICT = ProblemType(
    "complaint_reason_code_conflict",
    409,
    N_("The complaint reason code is already used"),
    N_("Another complaint reason already uses the code {code}."),
)
RULES_INVALID = ProblemType(
    "complaint_reason_rules_invalid",
    422,
    N_("Invalid rules clause"),
    N_("Choose a published version of the community rules."),
)
STALE_REASON = ProblemType(
    "complaint_reason_version_conflict",
    409,
    N_("The complaint reason was edited"),
    N_("Reload the complaint reason. Its current version is {version}."),
)


async def require_rules_document(
    session: AsyncSession, document_id: UUID
) -> DocumentVersion:
    """Load the published community rules version a reason is bound to."""
    document = await session.get(DocumentVersion, document_id)
    if document is None or document.kind != DocumentKind.RULES:
        raise ProblemError(RULES_INVALID)
    return document


def _reason_query() -> Select[ComplaintReason]:
    return select(ComplaintReason).options(selectinload(ComplaintReason.rules_document))


async def load_reason(session: AsyncSession, reason_id: UUID) -> ComplaintReason:
    """A reason with its rules document, or 404."""
    reason = await session.scalar(
        _reason_query().where(ComplaintReason.id == reason_id)
    )
    if reason is None:
        raise ProblemError(NOT_FOUND)
    return reason


async def locked_reason(session: AsyncSession, reason_id: UUID) -> ComplaintReason:
    """A reason locked for its update transaction, or 404."""
    reason = await session.scalar(
        _reason_query().where(ComplaintReason.id == reason_id).with_for_update()
    )
    if reason is None:
        raise ProblemError(NOT_FOUND)
    return reason


def reason_audit_state(reason: ComplaintReason) -> dict[str, Any]:
    """Short fields of a reason for the audit journal (no texts)."""
    return {
        "reason_code": reason.code,
        "name_ru": reason.name_ru,
        "name_en": reason.name_en,
        "rules_document_id": reason.rules_document_id,
        "rules_clause": reason.rules_clause,
        "active": reason.active,
        "version": reason.version,
    }
