"""A router used only by tests to exercise the shared API conventions."""

import asyncio
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from datetime import datetime
from typing import Annotated, Literal
from uuid import UUID

import httpx2
from fastapi import FastAPI, Query, Request, Response
from pydantic import BaseModel, Field
from sqlalchemy import select

from campus.api.app import API_PREFIX, create_app
from campus.core.config import Settings
from campus.core.i18n import N_
from campus.core.web import (
    DbSession,
    Page,
    PageQuery,
    ProblemError,
    ProblemType,
    api_router,
    paginate,
    sort_by,
)
from tests.models import Note

NOTES_URL = f"{API_PREFIX}/test/notes"
# Key of stored idempotent responses: 32 bytes, base64.
ENCRYPTION_KEY = "dGVzdC1pZGVtcG90ZW5jeS1lbmNyeXB0aW9uLWtleSE="
CLIENT_HEADERS = {"X-Client-Platform": "android", "X-Client-Version": "1.2.0"}

TEST_CONFLICT = ProblemType("test_conflict", 409, N_("Conflict"))

router = api_router(prefix="/test/notes", tags=["test"])


class NoteIn(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    body: str | None = None


class NoteOut(BaseModel):
    id: UUID
    title: str
    body: str | None
    created_at: datetime


@router.post("", status_code=201)
async def create_note(
    note: NoteIn,
    session: DbSession,
    delay: Annotated[float, Query(ge=0)] = 0.0,
    outcome: Literal["ok", "problem", "conflict_response", "crash"] = "ok",
) -> NoteOut:
    """Create a note; ``outcome`` makes the request fail after the insert."""
    row = Note(title=note.title, body=note.body)
    session.add(row)
    await session.flush()
    await asyncio.sleep(delay)
    if outcome == "problem":
        raise ProblemError(TEST_CONFLICT)
    if outcome == "conflict_response":
        return Response(status_code=409)  # type: ignore[return-value]
    if outcome == "crash":
        msg = "secret internal detail"
        raise RuntimeError(msg)
    return NoteOut.model_validate(row, from_attributes=True)


@router.get("")
async def list_notes(
    request: Request,
    session: DbSession,
    page: PageQuery,
    order_by: Literal["created_at", "-created_at", "title", "-title"] = "created_at",
) -> Page[NoteOut]:
    """List notes page by page."""
    query = sort_by(
        select(Note),
        order_by,
        {"created_at": Note.created_at, "title": Note.title},
        Note.id,
    )
    return await paginate(
        session,
        query,
        page,
        NoteOut,
        settings=request.app.state.settings,
    )


@router.delete("/{note_id}", status_code=204)
async def delete_note(note_id: UUID, session: DbSession) -> None:
    """Delete a note."""
    note = await session.get(Note, note_id)
    if note is not None:
        await session.delete(note)


@router.get("/echo")
async def echo(number: Annotated[int, Query(le=10)]) -> dict[str, int]:
    """Return the parameter; needs no database."""
    return {"number": number}


@router.get("/crash")
async def crash() -> None:
    """Fail with an unhandled exception."""
    msg = "secret internal detail"
    raise RuntimeError(msg)


def create_test_app(settings: Settings) -> FastAPI:
    app = create_app(settings)
    app.include_router(router, prefix=API_PREFIX)
    return app


@asynccontextmanager
async def serve(app: FastAPI) -> AsyncIterator[httpx2.AsyncClient]:
    """An async client of ``app``; unhandled errors become 500 responses."""
    transport = httpx2.ASGITransport(app=app, raise_app_exceptions=False)
    async with (
        app.router.lifespan_context(app),
        httpx2.AsyncClient(
            transport=transport, base_url="http://test", headers=CLIENT_HEADERS
        ) as client,
    ):
        yield client
