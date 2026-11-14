"""Route class of API endpoints: client checks, idempotency, transaction.

Routers of domain modules use :func:`api_router`. For every request of such
a route, before FastAPI validates parameters:

1. the client platform and version are checked
   (:mod:`campus.core.web.clients`);
2. a mutating request (POST, PUT, PATCH, DELETE) must carry a UUID
   ``Idempotency-Key``;
3. a database session is opened for the request (:data:`DbSession`); a
   mutating request claims its key in it (:mod:`campus.core.idempotency`).

The endpoint runs in that session's transaction and does not commit: a 2xx
response is committed together with the stored idempotent response; an
exception or any other status rolls everything back, including the key.
The headers and error responses are added to the OpenAPI schema.
"""

import hashlib
from collections.abc import Callable, Coroutine, Sequence
from typing import Annotated, Any
from uuid import UUID

from fastapi import APIRouter, Depends, Header, Request, Response
from fastapi.params import Depends as DependsParam
from fastapi.routing import APIRoute
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from campus.core import clock
from campus.core.config import ClientPlatform, Settings
from campus.core.db import DatabaseNotConfiguredError
from campus.core.i18n import N_
from campus.core.idempotency import (
    ANONYMOUS_SCOPE,
    IdempotencyKeyReusedError,
    StoredResponse,
    claim_idempotency_key,
    store_response,
)
from campus.core.web.auth import authenticate
from campus.core.web.clients import (
    PLATFORM_HEADER,
    VERSION_HEADER,
    check_client_version,
)
from campus.core.web.problems import Problem, ProblemError, ProblemType

MUTATING_METHODS = frozenset({"POST", "PUT", "PATCH", "DELETE"})
IDEMPOTENCY_KEY_HEADER = "Idempotency-Key"
REPLAYED_HEADER = "Idempotent-Replayed"

IDEMPOTENCY_KEY_MISSING = ProblemType(
    "idempotency_key_missing",
    400,
    N_("Idempotency key missing"),
    N_("Requests that change data need an Idempotency-Key header."),
)
IDEMPOTENCY_KEY_INVALID = ProblemType(
    "idempotency_key_invalid",
    400,
    N_("Invalid idempotency key"),
    N_("The Idempotency-Key header must be a UUID."),
)
IDEMPOTENCY_KEY_REUSED = ProblemType(
    "idempotency_key_reused",
    422,
    N_("Idempotency key reused"),
    N_("This Idempotency-Key was already used for a different request."),
)

# Stored with an idempotent response; others are set anew on every response.
_NOT_STORED_HEADERS = frozenset({b"content-length", b"x-request-id"})


async def _client_headers(
    platform: Annotated[
        ClientPlatform,
        Header(alias=PLATFORM_HEADER, description="Client application."),
    ],
    version: Annotated[
        str,
        Header(
            alias=VERSION_HEADER,
            description="Client version, e.g. 1.4.0.",
            examples=["1.0.0"],
        ),
    ],
) -> None:
    """Document the client headers; :class:`ApiRoute` checks them."""
    del platform, version


async def _idempotency_header(
    key: Annotated[
        UUID,
        Header(
            alias=IDEMPOTENCY_KEY_HEADER,
            description=(
                "Unique per operation; a repeat with the same key within 24"
                " hours returns the original response."
            ),
        ),
    ],
) -> None:
    """Document the Idempotency-Key header; :class:`ApiRoute` checks it."""
    del key


def _problem(description: str) -> dict[str, Any]:
    return {"model": Problem, "description": description}


_ERROR_RESPONSES: dict[int | str, dict[str, Any]] = {
    400: _problem(
        "Bad request: client headers or Idempotency-Key missing or invalid"
        " (client_version_missing, client_version_invalid,"
        " idempotency_key_missing, idempotency_key_invalid, ...)."
    ),
    401: _problem("Invalid, expired or revoked authentication (unauthorized)."),
    422: _problem(
        "Invalid request (validation_failed) or Idempotency-Key used for a"
        " different request (idempotency_key_reused)."
    ),
    426: _problem("The client version is too old (client_update_required)."),
    500: _problem("Internal error (internal_error)."),
}


def _session_factory(request: Request) -> async_sessionmaker[AsyncSession] | None:
    factory: async_sessionmaker[AsyncSession] | None = getattr(
        request.app.state, "session_factory", None
    )
    return factory


def _request_session(request: Request) -> AsyncSession:
    session: AsyncSession | None = getattr(request.state, "db_session", None)
    if session is None:
        raise DatabaseNotConfiguredError
    return session


DbSession = Annotated[AsyncSession, Depends(_request_session)]
"""The session of the current request; endpoints flush but never commit."""


def _idempotency_key(request: Request) -> UUID:
    value = request.headers.get(IDEMPOTENCY_KEY_HEADER)
    if not value:
        raise ProblemError(IDEMPOTENCY_KEY_MISSING)
    try:
        return UUID(value)
    except ValueError:
        raise ProblemError(IDEMPOTENCY_KEY_INVALID) from None


async def _fingerprint(request: Request) -> bytes:
    digest = hashlib.sha256()
    for part in (request.method, request.url.path, request.url.query):
        digest.update(part.encode())
        digest.update(b"\0")
    digest.update(await request.body())
    return digest.digest()


def _stored(response: Response) -> StoredResponse:
    return StoredResponse(
        status_code=response.status_code,
        body=bytes(response.body),
        headers=[
            (name.decode("latin-1"), value.decode("latin-1"))
            for name, value in response.raw_headers
            if name.lower() not in _NOT_STORED_HEADERS
        ],
    )


def _replay(stored: StoredResponse) -> Response:
    response = Response(content=stored.body, status_code=stored.status_code)
    for name, value in stored.headers:
        response.headers.append(name, value)
    response.headers[REPLAYED_HEADER] = "true"
    return response


class ApiRoute(APIRoute):
    """API endpoint: client checks, idempotency and the request transaction."""

    def __init__(
        self,
        path: str,
        endpoint: Callable[..., Any],
        *,
        methods: set[str] | list[str] | None = None,
        dependencies: Sequence[DependsParam] | None = None,
        responses: dict[int | str, dict[str, Any]] | None = None,
        **kwargs: Any,
    ) -> None:
        upper = {method.upper() for method in methods or ("GET",)}
        self.mutating = bool(upper & MUTATING_METHODS)
        own = [Depends(_client_headers)]
        if self.mutating:
            own.append(Depends(_idempotency_header))
        super().__init__(
            path,
            endpoint,
            methods=methods,
            dependencies=[*own, *(dependencies or [])],
            responses={**_ERROR_RESPONSES, **(responses or {})},
            **kwargs,
        )

    def get_route_handler(self) -> Callable[[Request], Coroutine[Any, Any, Response]]:
        """Wrap FastAPI's handler with the checks and the transaction."""
        handler = super().get_route_handler()
        mutating = self.mutating

        async def route_handler(request: Request) -> Response:
            settings: Settings = request.app.state.settings
            check_client_version(request, settings)
            principal = await authenticate(request)
            key = _idempotency_key(request) if mutating else None

            sessions = _session_factory(request)
            if sessions is None:
                if mutating:
                    raise DatabaseNotConfiguredError
                return await handler(request)

            async with sessions() as session:
                request.state.db_session = session
                scope = str(principal.user_id) if principal else ANONYMOUS_SCOPE
                if key is not None:
                    try:
                        stored = await claim_idempotency_key(
                            session,
                            scope=scope,
                            key=key,
                            fingerprint=await _fingerprint(request),
                            now=clock.now(),
                            ttl=settings.idempotency_key_ttl,
                        )
                    except IdempotencyKeyReusedError:
                        raise ProblemError(IDEMPOTENCY_KEY_REUSED) from None
                    if stored is not None:
                        return _replay(stored)

                response = await handler(request)
                if not 200 <= response.status_code < 300:  # noqa: PLR2004
                    await session.rollback()
                    return response
                if key is not None:
                    await store_response(
                        session, scope=scope, key=key, response=_stored(response)
                    )
                await session.commit()
                return response

        return route_handler


def api_router(**kwargs: Any) -> APIRouter:
    """Router whose endpoints are :class:`ApiRoute` s."""
    return APIRouter(route_class=ApiRoute, **kwargs)
