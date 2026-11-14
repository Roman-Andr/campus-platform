"""Owner-only inbox and monotone read cursor."""

from typing import Annotated, Any
from uuid import UUID

from fastapi import Query, Request
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import func, select
from sqlalchemy.dialects.postgresql import insert

from campus.core.web import (
    DbSession,
    Page,
    PageQuery,
    Problem,
    ProblemError,
    api_router,
)
from campus.core.web.auth import CurrentUser
from campus.core.web.datetimes import Instant
from campus.core.web.pagination import paginate
from campus.core.web.problems import NOT_FOUND
from campus.modules.notifications.models import Inbox, Notification

router = api_router(
    prefix="/notifications", tags=["Notifications"], responses={404: {"model": Problem}}
)


class NotificationOutput(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    sequence: int
    type: str
    object_id: UUID | None
    occurred_at: Instant
    created_at: Instant
    text: dict[str, str]
    params: dict[str, Any]
    read: bool = False


class ReadInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    through_id: UUID = Field(
        description="Mark this notification and earlier ones read."
    )


class ReadCursor(BaseModel):
    sequence: int


@router.get("")
async def notification_feed(  # noqa: PLR0913, PLR0917 - request dependencies
    request: Request,
    session: DbSession,
    principal: CurrentUser,
    page: PageQuery,
    after_sequence: Annotated[int, Query(ge=0)] = 0,
    ascending: bool = False,
) -> Page[NotificationOutput]:
    """Recover from realtime gaps with ascending=true and after_sequence.

    Sequence follows inbox commit order, regardless of source event time.
    Poll again after reaching the last page; realtime is only a wakeup.
    """
    query = select(Notification).where(
        Notification.recipient_id == principal.user_id,
        Notification.sequence > after_sequence,
    )
    order = Notification.sequence.asc() if ascending else Notification.sequence.desc()
    result = await paginate(
        session,
        query.order_by(order),
        page,
        NotificationOutput,
        settings=request.app.state.settings,
        context=f"notifications:{principal.user_id}:{after_sequence}:{ascending}",
    )
    read_sequence = await session.scalar(
        select(Inbox.read_sequence).where(Inbox.user_id == principal.user_id)
    )
    for item in result.items:
        item.read = item.sequence <= (read_sequence or 0)
    return result


@router.post("/read")
async def read_notifications(
    body: ReadInput, session: DbSession, principal: CurrentUser
) -> ReadCursor:
    notification = await session.scalar(
        select(Notification).where(
            Notification.id == body.through_id,
            Notification.recipient_id == principal.user_id,
        )
    )
    if notification is None:
        raise ProblemError(NOT_FOUND)
    statement = insert(Inbox).values(
        user_id=principal.user_id,
        sequence=notification.sequence,
        read_sequence=notification.sequence,
    )
    sequence = await session.scalar(
        statement.on_conflict_do_update(
            index_elements=[Inbox.user_id],
            set_={
                "read_sequence": func.greatest(
                    Inbox.read_sequence, notification.sequence
                )
            },
        ).returning(Inbox.read_sequence)
    )
    assert sequence is not None  # noqa: S101 - INSERT RETURNING
    return ReadCursor(sequence=sequence)
