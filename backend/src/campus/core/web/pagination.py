"""Keyset (cursor) pagination of lists (specification, 4.6).

A list endpoint takes :data:`PageQuery` (``?size=&cursor=``) and an
``order_by`` parameter of its own, sorts its query with :func:`sort_by`
(which adds a unique tiebreaker) and returns :func:`paginate`'s
:class:`Page`. The cursor holds the sort key of the last row seen, not an
offset, so rows inserted or deleted while a client scrolls do not shift
pages: no row is skipped or repeated.

Cursors are opaque to clients. A cursor is valid only for the ordering it
came from; any other cursor is rejected with ``400 invalid_cursor``. The
ordering signature, the bookmark and the caller's context are authenticated
with HMAC-SHA256 under ``CAMPUS_CURSOR_SECRET_KEY``, so a cursor cannot be
forged or edited by a client. Sorting by nullable columns is not supported
by the underlying library (sqlakeyset).
"""

import base64
import binascii
import hashlib
import hmac
from collections.abc import Mapping
from contextlib import nullcontext
from dataclasses import dataclass
from typing import Annotated, Any

from fastapi import Depends, Query, Request
from pydantic import BaseModel, Field
from sqlakeyset import InvalidPage, unserialize_bookmark
from sqlakeyset.asyncio import select_page
from sqlalchemy import ColumnElement, Select, UnaryExpression, asc, desc
from sqlalchemy.exc import DBAPIError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import QueryableAttribute

from campus.core.config import Settings
from campus.core.i18n import N_
from campus.core.web.problems import (
    VALIDATION_FAILED,
    ProblemError,
    ProblemType,
    field_error,
    request_locale,
)

INVALID_CURSOR = ProblemType(
    "invalid_cursor",
    400,
    N_("Invalid cursor"),
    N_("The page cursor is invalid or belongs to another list; start over."),
)


class Page[T](BaseModel):
    """One page of a list."""

    items: list[T]
    next_page: str | None = Field(
        description="Cursor of the next page; null on the last page."
    )


@dataclass(frozen=True, slots=True)
class PageParams:
    """Requested page: its size and the cursor of the previous page's end."""

    size: int
    cursor: str | None = None


async def _page_params(
    request: Request,
    size: Annotated[
        int | None,
        Query(
            ge=1,
            description=(
                "Number of items; the default (20) and the maximum (100) are"
                " set in the server configuration."
            ),
        ),
    ] = None,
    cursor: Annotated[
        str | None, Query(description="`next_page` of the previous page.")
    ] = None,
) -> PageParams:
    settings: Settings = request.app.state.settings
    if size is None:
        size = settings.page_size_default
    if size > settings.page_size_max:
        error = {
            "type": "less_than_equal",
            "loc": ("query", "size"),
            "ctx": {"le": settings.page_size_max},
        }
        raise ProblemError(
            VALIDATION_FAILED, errors=[field_error(error, request_locale(request))]
        )
    return PageParams(size=size, cursor=cursor or None)


PageQuery = Annotated[PageParams, Depends(_page_params)]

type Sortable = ColumnElement[Any] | QueryableAttribute[Any]


def sort_by[Q: Select[Any]](
    query: Q,
    order_by: str,
    columns: Mapping[str, Sortable],
    tiebreaker: Sortable,
) -> Q:
    """Order ``query`` by ``order_by`` (``field`` or ``-field``).

    ``columns`` maps the field names an endpoint accepts to columns;
    ``tiebreaker`` (a unique column, usually ``id``) makes the order total,
    so pages are deterministic.
    """
    direction = desc if order_by.startswith("-") else asc
    column = columns[order_by.removeprefix("-")]
    return query.order_by(direction(column), direction(tiebreaker))


SIGNATURE_LENGTH = 16
MAC_LENGTH = 64  # hex digest of HMAC-SHA256


def cursor_key(settings: Settings) -> bytes:
    """Secret that authenticates cursors; list endpoints cannot run without it."""
    if settings.cursor_secret_key is None:
        raise RuntimeError("CAMPUS_CURSOR_SECRET_KEY is required")
    return settings.cursor_secret_key.get_secret_value().encode()


def _mac(secret: bytes, signature: str, bookmark: str) -> str:
    payload = f"{signature}{bookmark}".encode()
    return hmac.new(secret, payload, hashlib.sha256).hexdigest()


def _ordering_signature(query: Select[Any]) -> str:
    clauses: tuple[ColumnElement[Any] | UnaryExpression[Any], ...] = (
        query._order_by_clauses
    )
    text = ",".join(str(clause) for clause in clauses)
    return hashlib.sha256(text.encode()).hexdigest()[:SIGNATURE_LENGTH]


def _encode_cursor(secret: bytes, signature: str, bookmark: str) -> str:
    raw = f"{signature}{_mac(secret, signature, bookmark)}{bookmark}"
    return base64.urlsafe_b64encode(raw.encode()).decode().rstrip("=")


def _decode_cursor(secret: bytes, signature: str, cursor: str) -> str:
    try:
        raw = base64.urlsafe_b64decode(cursor + "=" * (-len(cursor) % 4)).decode()
    except binascii.Error, UnicodeDecodeError, ValueError:
        raise ProblemError(INVALID_CURSOR) from None
    if len(raw) < SIGNATURE_LENGTH + MAC_LENGTH:
        raise ProblemError(INVALID_CURSOR)
    got_signature = raw[:SIGNATURE_LENGTH]
    end = SIGNATURE_LENGTH + MAC_LENGTH
    got_mac = raw[SIGNATURE_LENGTH:end]
    bookmark = raw[end:]
    expected_mac = _mac(secret, got_signature, bookmark)
    if not hmac.compare_digest(got_mac.encode(), expected_mac.encode()):
        raise ProblemError(INVALID_CURSOR)
    if not hmac.compare_digest(got_signature.encode(), signature.encode()):
        raise ProblemError(INVALID_CURSOR)
    try:
        unserialize_bookmark(bookmark)
    except InvalidPage, ValueError, TypeError:
        raise ProblemError(INVALID_CURSOR) from None
    return bookmark


async def paginate[T: BaseModel](  # noqa: PLR0913 - page, item and signing key
    session: AsyncSession,
    query: Select[Any],
    params: PageParams,
    item: type[T],
    *,
    settings: Settings,
    context: str = "",
) -> Page[T]:
    """Fetch one page of ``query``, which selects a single entity or column.

    Rows are converted to ``item`` (from attributes); ``query`` must be
    ordered by :func:`sort_by`. Optional ``context`` binds cursors to the
    caller's filters, scope or snapshot without changing SQL ordering.
    """
    secret = cursor_key(settings)
    signature = _ordering_signature(query)
    if context:
        signature = hashlib.sha256((signature + context).encode()).hexdigest()[
            :SIGNATURE_LENGTH
        ]
    bookmark = None
    if params.cursor is not None:
        bookmark = _decode_cursor(secret, signature, params.cursor)
    # A crafted cursor may carry values of the wrong type; the savepoint
    # keeps the request transaction usable when the database rejects it.
    async with session.begin_nested() if bookmark else nullcontext():
        try:
            page = await select_page(
                session, query, per_page=params.size, page=bookmark
            )
        except InvalidPage, DBAPIError:
            raise ProblemError(INVALID_CURSOR) from None
    next_page = (
        _encode_cursor(secret, signature, page.paging.bookmark_next)
        if page.paging.has_next
        else None
    )
    return Page[T](
        items=[item.model_validate(row[0], from_attributes=True) for row in page],
        next_page=next_page,
    )
