"""The global journal of moderator and administrator actions.

Only administrators read it (specification, table of roles): a moderator's
access to the timeline of a particular case is granted by that case, not
by this journal. Records are written by the modules that perform actions
(:func:`campus.core.audit.record_action`); this module lists them and
purges them after the retention period.
"""

from typing import Annotated, Any, Literal
from uuid import UUID

from fastapi import Depends, Query
from pydantic import BaseModel, ConfigDict
from sqlalchemy import Select, select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from campus.core.audit import AuditRecord, purge_expired_records
from campus.core.config import Settings
from campus.core.tasks import register_cleanup
from campus.core.web import (
    DbSession,
    Instant,
    Page,
    PageQuery,
    api_router,
    paginate,
    sort_by,
)
from campus.modules.identity import Role, require_roles

router = api_router(
    prefix="/audit",
    tags=["audit"],
    dependencies=[Depends(require_roles(Role.ADMINISTRATOR))],
)


class AuditRecordOut(BaseModel):
    model_config = ConfigDict(from_attributes=True, frozen=True)

    id: UUID
    occurred_at: Instant
    actor_id: UUID | None
    action: str
    object_type: str
    object_id: UUID | None
    reason: str | None
    participant_ids: list[UUID]
    own_case: bool
    before: dict[str, Any] | None
    after: dict[str, Any] | None
    details: dict[str, Any] | None
    request_id: str | None


class AuditFilters(BaseModel):
    actor_id: UUID | None = None
    action: str | None = None
    object_type: str | None = None
    object_id: UUID | None = None
    participant_id: UUID | None = None
    own_case: bool | None = None
    occurred_from: Instant | None = None
    occurred_to: Instant | None = None


def _filtered(filters: AuditFilters) -> Select[AuditRecord]:
    query = select(AuditRecord)
    for column, value in (
        (AuditRecord.actor_id, filters.actor_id),
        (AuditRecord.action, filters.action),
        (AuditRecord.object_type, filters.object_type),
        (AuditRecord.object_id, filters.object_id),
        (AuditRecord.own_case, filters.own_case),
    ):
        if value is not None:
            query = query.where(column == value)
    if filters.participant_id is not None:
        query = query.where(
            AuditRecord.participant_ids.contains([filters.participant_id])
        )
    if filters.occurred_from is not None:
        query = query.where(AuditRecord.occurred_at >= filters.occurred_from)
    if filters.occurred_to is not None:
        query = query.where(AuditRecord.occurred_at < filters.occurred_to)
    return query


@router.get("")
async def list_audit_records(
    session: DbSession,
    page: PageQuery,
    filters: Annotated[AuditFilters, Query()],
    order_by: Literal["occurred_at", "-occurred_at"] = "-occurred_at",
) -> Page[AuditRecordOut]:
    """Journal of moderator and administrator actions; administrators only.

    ``own_case=true`` lists decisions in cases the actor takes part in;
    ``participant_id`` lists actions concerning a user. The period is
    ``occurred_from`` inclusive to ``occurred_to`` exclusive.
    """
    query = sort_by(
        _filtered(filters),
        order_by,
        {"occurred_at": AuditRecord.occurred_at},
        AuditRecord.id,
    )
    return await paginate(session, query, page, AuditRecordOut)


@register_cleanup("audit")
async def purge_audit_records(
    sessions: async_sessionmaker[AsyncSession], settings: Settings
) -> dict[str, int]:
    """Delete records older than ``CAMPUS_AUDIT_RETENTION``."""
    async with sessions() as session, session.begin():
        deleted = await purge_expired_records(session, settings.audit_retention)
    return {"records": deleted}


__all__ = ["AuditRecordOut", "purge_audit_records", "router"]
