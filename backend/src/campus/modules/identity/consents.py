"""Versioned legal documents and append-only consent decisions.

Publication takes an exclusive advisory lock; reads/decisions take its
shared counterpart until commit. Decisions for a user are serialized too.
Consumers must recheck cross_border_allowed before sending data abroad.
"""

from datetime import datetime
from enum import StrEnum
from uuid import UUID

from fastapi import Request, Response
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import (
    CheckConstraint,
    ForeignKey,
    String,
    UniqueConstraint,
    select,
    text,
)
from sqlalchemy.dialects.postgresql import distinct_on
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import Mapped, mapped_column

from campus.core import clock
from campus.core.db import Entity
from campus.core.i18n import N_
from campus.core.outbox import add_message
from campus.core.web import (
    DbSession,
    FieldError,
    Principal,
    ProblemError,
    ProblemType,
    api_router,
    request_locale,
)
from campus.core.web.auth import CurrentUser
from campus.core.web.datetimes import Instant


class DocumentKind(StrEnum):
    RULES = "community_rules"
    POLICY = "privacy_policy"
    PROCESSING = "personal_data_processing"
    CROSS_BORDER = "cross_border_transfer"


REQUIRED = frozenset(DocumentKind) - {DocumentKind.CROSS_BORDER}
CONSENT_REQUIRED = ProblemType(
    "consent_required", 403, N_("Current documents must be accepted")
)
CONSENT_INVALID = ProblemType("consent_invalid", 422, N_("Invalid consent decision"))
# Stable namespace shared by publications and decisions, not a product setting.
PUBLICATION_LOCK = 68001


class DocumentVersion(Entity):
    __tablename__ = "identity_document_version"
    __table_args__ = (
        UniqueConstraint("kind", "version"),
        CheckConstraint("version > 0", name="version_positive"),
        CheckConstraint(
            "kind IN ('community_rules', 'privacy_policy', "
            "'personal_data_processing', 'cross_border_transfer')",
            name="kind_valid",
        ),
        CheckConstraint(
            "length(text_ru) > 0 AND length(text_en) > 0", name="texts_nonempty"
        ),
    )
    kind: Mapped[str] = mapped_column(String(32))
    version: Mapped[int]
    text_ru: Mapped[str]
    text_en: Mapped[str]
    published_at: Mapped[datetime]

    @property
    def required(self) -> bool:
        """Whether users must accept this document kind."""
        return self.kind in REQUIRED


class ConsentDecision(Entity):
    __tablename__ = "identity_consent_decision"
    user_id: Mapped[UUID] = mapped_column(ForeignKey("identity_user.id"), index=True)
    document_id: Mapped[UUID] = mapped_column(
        ForeignKey("identity_document_version.id"), index=True
    )
    accepted: Mapped[bool]
    decided_at: Mapped[datetime]
    # Audit snapshot: credential retention may delete the original session.
    session_id: Mapped[UUID]


async def publication_lock(session: AsyncSession, *, exclusive: bool = False) -> None:
    function = "pg_advisory_xact_lock" if exclusive else "pg_advisory_xact_lock_shared"
    await session.execute(text(f"SELECT {function}(:key)"), {"key": PUBLICATION_LOCK})


async def current_documents(session: AsyncSession) -> list[DocumentVersion]:
    return list(
        (
            await session.scalars(
                select(DocumentVersion)
                .ext(distinct_on(DocumentVersion.kind))
                .order_by(DocumentVersion.kind, DocumentVersion.version.desc())
            )
        ).all()
    )


async def publish_document(
    session: AsyncSession, kind: DocumentKind, *, text_ru: str, text_en: str
) -> DocumentVersion:
    """Publish immediately in the caller's transaction (admin API: #101)."""
    if not text_ru.strip() or not text_en.strip():
        raise ValueError("Both document translations are required")
    await publication_lock(session, exclusive=True)
    previous = await session.scalar(
        select(DocumentVersion)
        .where(DocumentVersion.kind == kind)
        .order_by(DocumentVersion.version.desc())
        .limit(1)
    )
    document = DocumentVersion(
        kind=kind,
        version=previous.version + 1 if previous else 1,
        text_ru=text_ru,
        text_en=text_en,
        published_at=clock.now(),
    )
    session.add(document)
    await session.flush()
    if kind == DocumentKind.CROSS_BORDER and previous is not None:
        # A new optional version invalidates previous grants. Include the
        # new version ID; consumers recheck current state on delivery.
        latest = (
            await session.scalars(
                select(ConsentDecision)
                .ext(distinct_on(ConsentDecision.user_id))
                .where(ConsentDecision.document_id == previous.id)
                .order_by(ConsentDecision.user_id, ConsentDecision.id.desc())
            )
        ).all()
        for decision in latest:
            if decision.accepted:
                consent_changed(session, decision.user_id, document.id, allowed=False)
    return document


async def latest_decision(
    session: AsyncSession, user_id: UUID, document_id: UUID
) -> ConsentDecision | None:
    return await session.scalar(
        select(ConsentDecision)
        .where(
            ConsentDecision.user_id == user_id,
            ConsentDecision.document_id == document_id,
        )
        .order_by(ConsentDecision.id.desc())
        .limit(1)
    )


async def cross_border_allowed(session: AsyncSession, user_id: UUID) -> bool:
    """Only an explicit acceptance of the current version permits transfer."""
    document = await session.scalar(
        select(DocumentVersion)
        .where(DocumentVersion.kind == DocumentKind.CROSS_BORDER)
        .order_by(DocumentVersion.version.desc())
        .limit(1)
    )
    if document is None:
        return False
    decision = await latest_decision(session, user_id, document.id)
    return decision is not None and decision.accepted


async def require_registration_consents(
    session: AsyncSession, accepted: list[UUID], cross_border_id: UUID | None
) -> None:
    await publication_lock(session)
    documents = await current_documents(session)
    missing = [d for d in documents if d.kind in REQUIRED and d.id not in accepted]
    if missing or {d.kind for d in documents} != set(DocumentKind):
        raise ProblemError(
            CONSENT_REQUIRED,
            errors=[
                FieldError(
                    code=d.kind, detail=str(d.id), pointer="#/accepted_document_ids"
                )
                for d in missing
            ],
        )
    if set(accepted) - {d.id for d in documents if d.kind in REQUIRED}:
        raise ProblemError(CONSENT_INVALID)
    if cross_border_id is not None and cross_border_id not in {
        d.id for d in documents if d.kind == DocumentKind.CROSS_BORDER
    }:
        raise ProblemError(CONSENT_INVALID)


async def record_decision(
    session: AsyncSession,
    principal: Principal,
    document: DocumentVersion,
    *,
    accepted: bool,
) -> None:
    session.add(
        ConsentDecision(
            user_id=principal.user_id,
            session_id=principal.session_id,
            document_id=document.id,
            accepted=accepted,
            decided_at=clock.now(),
        )
    )
    if document.kind == DocumentKind.CROSS_BORDER:
        consent_changed(session, principal.user_id, document.id, allowed=accepted)
    await session.flush()


def consent_changed(
    session: AsyncSession, user_id: UUID, document_id: UUID, *, allowed: bool
) -> None:
    add_message(
        session,
        "identity.cross_border_consent_changed",
        {
            "user_id": str(user_id),
            "document_id": str(document_id),
            "allowed": allowed,
        },
    )


async def check_consents(
    request: Request, session: AsyncSession, principal: Principal
) -> None:
    """Global API gate; future export/deletion handlers use these route names."""
    route = request.scope["route"]
    if route.name in {
        # Publishing changes the gate itself: a retry must replay its stored
        # response, and concurrent publications must both get a version
        # instead of the second one being gated by the first.
        "admin_publish_document",
        "get_documents",
        "accept_documents",
        "change_cross_border_consent",
        "sign_out",
        "list_sessions",
        "revoke_session",
        "revoke_all_sessions",
        "export_my_data",
        "delete_my_account",
    }:
        return
    await publication_lock(session)
    missing = []
    for document in await current_documents(session):
        if document.kind in REQUIRED:
            decision = await latest_decision(session, principal.user_id, document.id)
            if decision is None or not decision.accepted:
                missing.append(FieldError(code=document.kind, detail=str(document.id)))
    if missing:
        raise ProblemError(CONSENT_REQUIRED, errors=missing)


class DocumentOutput(BaseModel):
    id: UUID
    kind: DocumentKind
    version: int
    text: str
    published_at: Instant
    required: bool


class AcceptanceInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    document_ids: list[UUID] = Field(min_length=1)


class CrossBorderInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    document_id: UUID
    accepted: bool


router = api_router(tags=["Consents"])


@router.get("/documents")
async def get_documents(request: Request, session: DbSession) -> list[DocumentOutput]:
    locale = request_locale(request)
    return [
        DocumentOutput(
            id=d.id,
            kind=DocumentKind(d.kind),
            version=d.version,
            text=d.text_ru if locale == "ru" else d.text_en,
            published_at=d.published_at,
            required=d.kind in REQUIRED,
        )
        for d in await current_documents(session)
    ]


async def lock_decisions(session: AsyncSession, principal: Principal) -> None:
    await lock_consent_state(session, principal.user_id)


async def lock_consent_state(session: AsyncSession, user_id: UUID) -> None:
    """Keep current permission stable through a decision or external transfer."""
    await publication_lock(session)
    await session.execute(
        text("SELECT pg_advisory_xact_lock(hashtextextended(:user_id, 0))"),
        {"user_id": str(user_id)},
    )


@router.post("/me/consents", status_code=204)
async def accept_documents(
    data: AcceptanceInput, session: DbSession, principal: CurrentUser
) -> Response:
    await lock_decisions(session, principal)
    documents = {
        d.id: d for d in await current_documents(session) if d.kind in REQUIRED
    }
    if set(data.document_ids) - documents.keys():
        raise ProblemError(CONSENT_INVALID)
    for document_id in dict.fromkeys(data.document_ids):
        document = documents[document_id]
        previous = await latest_decision(session, principal.user_id, document_id)
        if previous is None or not previous.accepted:
            await record_decision(session, principal, document, accepted=True)
    return Response(status_code=204)


@router.put("/me/consents/cross-border", status_code=204)
async def change_cross_border_consent(
    data: CrossBorderInput, session: DbSession, principal: CurrentUser
) -> Response:
    await lock_decisions(session, principal)
    document = next(
        (
            d
            for d in await current_documents(session)
            if d.kind == DocumentKind.CROSS_BORDER
        ),
        None,
    )
    if document is None or document.id != data.document_id:
        raise ProblemError(CONSENT_INVALID)
    previous = await latest_decision(session, principal.user_id, document.id)
    if previous is None or previous.accepted != data.accepted:
        await record_decision(session, principal, document, accepted=data.accepted)
    return Response(status_code=204)
