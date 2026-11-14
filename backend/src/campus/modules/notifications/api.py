"""Owner-only inbox, monotone read cursor and delivery settings."""

from datetime import time
from typing import Annotated, Any, Self
from uuid import UUID

from fastapi import Depends, Query, Request
from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    field_validator,
    model_validator,
)
from pydantic_core import PydanticCustomError
from sqlalchemy import delete, func, select
from sqlalchemy.dialects.postgresql import insert

from campus.core import clock
from campus.core.i18n import N_
from campus.core.web import (
    DbSession,
    Page,
    PageQuery,
    Problem,
    ProblemError,
    ProblemType,
    api_router,
)
from campus.core.web.auth import UNAUTHORIZED, CurrentUser, Principal
from campus.core.web.datetimes import Instant
from campus.core.web.pagination import paginate
from campus.core.web.problems import NOT_FOUND, ProblemResponse, problem_response
from campus.modules.identity import Session
from campus.modules.notifications.delivery import NOTIFICATION_TYPES
from campus.modules.notifications.models import (
    Inbox,
    MutedChat,
    Notification,
    NotificationSettings,
    PushToken,
)
from campus.modules.notifications.preferences import (
    EffectiveSettings,
    effective_settings,
    is_chat_member,
    user_timezone,
)

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


class NotificationPage(Page[NotificationOutput]):
    """One page of the inbox and the exact number of unread notifications.

    The count covers every page, not only the returned one, so a client
    shows the same badge after a cold start and on another device.
    """

    unread_count: int = Field(
        description="Unread notifications of the user; they are exactly the ones"
        " after the read cursor."
    )


class ReadInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    through_id: UUID = Field(
        description="Mark this notification and earlier ones read."
    )


class ReadCursor(BaseModel):
    sequence: int
    unread_count: int = Field(
        description="Unread notifications left after the cursor moved."
    )


class PushTokenInput(BaseModel):
    """A device registration token issued by FCM."""

    model_config = ConfigDict(extra="forbid")

    token: str = Field(
        min_length=1,
        max_length=512,
        description="FCM registration token of this Android device.",
    )


async def active_session(session: DbSession, principal: CurrentUser) -> Principal:
    """Reject a revoked device and lock its row for token rotation.

    The lock serializes registration and removal with session revocation and
    with another registration from the same device. Dependencies run on an
    idempotent replay too, so a stored answer is never returned to a session
    revoked after the original request.
    """
    device = await session.scalar(
        select(Session).where(Session.id == principal.session_id).with_for_update()
    )
    if (
        device is None
        or device.user_id != principal.user_id
        or device.revoked_at is not None
    ):
        raise ProblemError(UNAUTHORIZED, headers={"WWW-Authenticate": "Bearer"})
    return principal


ActiveSession = Annotated[Principal, Depends(active_session)]


@router.get("")
async def notification_feed(  # noqa: PLR0913, PLR0917 - request dependencies
    request: Request,
    session: DbSession,
    principal: CurrentUser,
    page: PageQuery,
    after_sequence: Annotated[int, Query(ge=0)] = 0,
    ascending: bool = False,
) -> NotificationPage:
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
    unread_count = await session.scalar(
        select(func.count())
        .select_from(Notification)
        .where(
            Notification.recipient_id == principal.user_id,
            Notification.sequence > (read_sequence or 0),
        )
    )
    for item in result.items:
        item.read = item.sequence <= (read_sequence or 0)
    return NotificationPage(
        items=result.items,
        next_page=result.next_page,
        unread_count=unread_count or 0,
    )


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
    unread_count = await session.scalar(
        select(func.count())
        .select_from(Notification)
        .where(
            Notification.recipient_id == principal.user_id,
            Notification.sequence > sequence,
        )
    )
    return ReadCursor(sequence=sequence, unread_count=unread_count or 0)


SETTINGS_VERSION_CONFLICT = ProblemType(
    "notification_settings_version_conflict",
    409,
    N_("The notification settings were changed."),
    N_("Reload the settings. Their current version is {version}."),
)
QUIET_HOURS_INVALID = ProblemType(
    "notification_quiet_hours_invalid",
    422,
    N_("Invalid quiet hours"),
    N_("Quiet hours must start and end at different times."),
)
CHAT_NOT_MEMBER = ProblemType(
    "notification_chat_forbidden",
    403,
    N_("Chat not available"),
    N_("You are not a member of this chat."),
)
UNKNOWN_NOTIFICATION_TYPE = ProblemType(
    "notification_type_unknown",
    422,
    N_("Unknown notification type"),
    N_("The notification type {type} is not supported."),
)


class QuietHours(BaseModel):
    """Daily quiet interval in the wall clock of the user's city."""

    enabled: bool = Field(
        description="Whether quiet hours suppress external notifications."
    )
    start: time = Field(description="Start wall time; may be after the end.")
    end: time = Field(description="End wall time, exclusive.")


class NotificationSettingsOutput(BaseModel):
    """Current settings of the signed-in user, with defaults filled in."""

    version: int = Field(
        description="Incremented by every change; send it back to reject a stale edit."
    )
    types: dict[str, bool] = Field(
        description="Every notification type and whether it is enabled."
    )
    quiet_hours: QuietHours
    muted_chat_ids: list[UUID] = Field(description="Chats with muted notifications.")
    timezone: str = Field(
        description="IANA zone of the user's city used for quiet hours."
    )


class QuietHoursPatch(BaseModel):
    """Fields of quiet hours to change; omitted fields keep their values."""

    model_config = ConfigDict(extra="forbid")

    enabled: bool | None = None
    start: time | None = None
    end: time | None = None

    @field_validator("start", "end")
    @classmethod
    def wall_time(cls, value: time | None) -> time | None:
        if value is not None and value.tzinfo is not None:
            raise PydanticCustomError(
                "quiet_hours_offset",
                "Quiet hours are wall times without an offset.",
            )
        return value


class NotificationSettingsPatch(BaseModel):
    """Partial settings update; omitted fields keep their values."""

    model_config = ConfigDict(extra="forbid")

    version: int | None = Field(
        default=None,
        ge=0,
        description=(
            "Version the edit is based on; a different one is rejected."
            " Required when replacing muted chats."
        ),
    )
    types: dict[str, bool] | None = Field(
        default=None,
        description="Types to enable or disable; other types keep their state.",
    )
    quiet_hours: QuietHoursPatch | None = None
    muted_chat_ids: list[UUID] | None = Field(
        default=None,
        description="Replaces the whole set of muted chats; requires version.",
    )

    @model_validator(mode="after")
    def mute_requires_version(self) -> Self:
        # The list replaces every muted chat, so without a version two clients
        # could silently drop each other's mutes. Other fields are partial.
        if self.muted_chat_ids is not None and self.version is None:
            raise PydanticCustomError(
                "notification_version_required",
                "Send the current version to replace muted chats.",
            )
        return self


def settings_output(
    current: EffectiveSettings, timezone: str
) -> NotificationSettingsOutput:
    return NotificationSettingsOutput(
        version=current.version,
        types={
            kind: kind not in current.disabled_types
            for kind in sorted(NOTIFICATION_TYPES)
        },
        quiet_hours=QuietHours(
            enabled=current.quiet_hours_enabled,
            start=current.quiet_hours_start,
            end=current.quiet_hours_end,
        ),
        muted_chat_ids=sorted(current.muted_chats, key=str),
        timezone=timezone,
    )


async def current_settings(
    session: DbSession, principal: CurrentUser, request: Request
) -> NotificationSettingsOutput:
    """Effective settings and the current city zone of the signed-in user."""
    settings = request.app.state.settings
    current = await effective_settings(session, principal.user_id, settings)
    timezone = await user_timezone(session, principal.user_id, settings)
    return settings_output(current, timezone)


@router.get("/settings")
async def read_settings(
    request: Request, session: DbSession, principal: CurrentUser
) -> NotificationSettingsOutput:
    """Owner-only settings; defaults apply until the user changes them."""
    return await current_settings(session, principal, request)


async def apply_patch(  # noqa: PLR0912 - independent optional fields
    session: DbSession,
    row: NotificationSettings,
    data: NotificationSettingsPatch,
    user_id: UUID,
) -> bool:
    """Apply the given fields to ``row``; return whether anything changed."""
    if data.types is not None:
        unknown = sorted(set(data.types) - NOTIFICATION_TYPES)
        if unknown:
            raise ProblemError(UNKNOWN_NOTIFICATION_TYPE, type=unknown[0])
    muted = frozenset(
        await session.scalars(
            select(MutedChat.chat_id).where(MutedChat.user_id == user_id)
        )
    )
    if data.muted_chat_ids is not None:
        for chat_id in dict.fromkeys(data.muted_chat_ids):
            if not await is_chat_member(session, user_id, chat_id):
                raise ProblemError(CHAT_NOT_MEMBER)
    changed = False
    if data.types is not None:
        disabled = set(row.disabled_types)
        for kind, enabled in data.types.items():
            if enabled:
                disabled.discard(kind)
            else:
                disabled.add(kind)
        if disabled != set(row.disabled_types):
            row.disabled_types = sorted(disabled)
            changed = True
    if data.quiet_hours is not None:
        quiet = data.quiet_hours
        if quiet.enabled is not None and quiet.enabled != row.quiet_hours_enabled:
            row.quiet_hours_enabled = quiet.enabled
            changed = True
        if quiet.start is not None and quiet.start != row.quiet_hours_start:
            row.quiet_hours_start = quiet.start
            changed = True
        if quiet.end is not None and quiet.end != row.quiet_hours_end:
            row.quiet_hours_end = quiet.end
            changed = True
    if row.quiet_hours_start == row.quiet_hours_end:
        raise ProblemError(QUIET_HOURS_INVALID)
    if data.muted_chat_ids is not None:
        desired = frozenset(data.muted_chat_ids)
        if desired != muted:
            await session.execute(delete(MutedChat).where(MutedChat.user_id == user_id))
            session.add_all(
                MutedChat(user_id=user_id, chat_id=chat_id) for chat_id in desired
            )
            changed = True
    return changed


@router.patch(
    "/settings",
    response_model=NotificationSettingsOutput,
    responses={
        403: {"model": Problem, "description": "Not a member of the chat."},
        409: {
            "model": Problem,
            "description": "Stale settings version; current_version is returned.",
        },
    },
)
async def update_settings(
    data: NotificationSettingsPatch,
    request: Request,
    session: DbSession,
    principal: CurrentUser,
) -> NotificationSettingsOutput | ProblemResponse:
    """Change only the given fields; a stale ``version`` is rejected."""
    settings = request.app.state.settings
    defaults = {
        "user_id": principal.user_id,
        "version": 1,
        "quiet_hours_enabled": settings.notification_quiet_hours_enabled,
        "quiet_hours_start": settings.notification_quiet_hours_start,
        "quiet_hours_end": settings.notification_quiet_hours_end,
        "disabled_types": [],
    }
    created = (
        await session.scalar(
            insert(NotificationSettings)
            .values(**defaults)
            .on_conflict_do_nothing()
            .returning(NotificationSettings.user_id)
        )
    ) is not None
    row = await session.scalar(
        select(NotificationSettings)
        .where(NotificationSettings.user_id == principal.user_id)
        .with_for_update()
    )
    assert row is not None  # noqa: S101 - inserted above
    current_version = row.version if not created else 0
    if data.version is not None and data.version != current_version:
        return problem_response(
            request,
            SETTINGS_VERSION_CONFLICT,
            params={"version": current_version},
            current_version=current_version,
        )
    changed = await apply_patch(session, row, data, principal.user_id)
    if changed and not created:
        row.version += 1
    if changed or created:
        await session.flush()
    current = await effective_settings(session, principal.user_id, settings)
    timezone = await user_timezone(session, principal.user_id, settings)
    return settings_output(current, timezone)


@router.put("/push-token", status_code=204)
async def register_push_token(
    data: PushTokenInput, session: DbSession, principal: ActiveSession
) -> None:
    """Bind this device's FCM token to the current user and session.

    A new token replaces the previous token of the same session; repeating
    the same registration is a no-op. A token previously bound to another
    account is moved, so a device that switched accounts stops receiving the
    previous user's pushes.
    """
    await session.execute(
        delete(PushToken).where(
            PushToken.session_id == principal.session_id,
            PushToken.token != data.token,
        )
    )
    await session.execute(
        insert(PushToken)
        .values(
            token=data.token,
            user_id=principal.user_id,
            session_id=principal.session_id,
        )
        .on_conflict_do_update(
            index_elements=[PushToken.token],
            set_={
                "user_id": principal.user_id,
                "session_id": principal.session_id,
                "updated_at": clock.now(),
            },
        )
    )


@router.delete("/push-token", status_code=204)
async def unregister_push_token(session: DbSession, principal: ActiveSession) -> None:
    """Forget the current session's token, e.g. on sign-out."""
    await session.execute(
        delete(PushToken).where(
            PushToken.session_id == principal.session_id,
            PushToken.user_id == principal.user_id,
        )
    )
