"""FastAPI application factory."""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Any

from asgi_correlation_id import CorrelationIdMiddleware
from fastapi import FastAPI
from fastapi.routing import APIRoute
from uvicorn.middleware.proxy_headers import ProxyHeadersMiddleware

from campus import __version__
from campus.api import health
from campus.api.access_log import AccessLogMiddleware
from campus.core.config import Settings, get_settings
from campus.core.db import create_engine, create_session_factory
from campus.core.observability import configure_observability
from campus.core.web import (
    install_problem_handlers,
    response_keyring,
    use_problem_media_type,
)
from campus.modules import identity, university

API_PREFIX = "/api/v1"


def _operation_id(route: APIRoute) -> str:
    # Stable, readable operation IDs for generated clients: the handler name.
    return route.name


def _install_openapi(app: FastAPI) -> None:
    """Post-process the generated schema (error media type, problem codes)."""
    generate = app.openapi

    def openapi() -> dict[str, Any]:
        if app.openapi_schema is None:
            app.openapi_schema = use_problem_media_type(generate())
        return app.openapi_schema

    app.openapi = openapi  # type: ignore[method-assign]


def create_app(settings: Settings | None = None) -> FastAPI:
    """Build the API application; used by uvicorn as a factory."""
    settings = settings or get_settings()
    configure_observability(settings, process="api")
    engine = create_engine(settings) if settings.database_url else None

    @asynccontextmanager
    async def lifespan(_app: FastAPI) -> AsyncIterator[None]:
        # Fail fast: without keys no request that changes data could run.
        _app.state.idempotency_keyring = response_keyring(settings)
        yield
        redis = getattr(_app.state, "auth_redis", None)
        if redis is not None:
            await redis.aclose()
        storage = getattr(_app.state, "auth_limit_storage", None)
        if storage is not None:
            storage.bridge.storage.connection_pool.disconnect()
        if engine is not None:
            await engine.dispose()

    app = FastAPI(
        title="Campus API",
        version=__version__,
        openapi_url=f"{API_PREFIX}/openapi.json",
        docs_url=f"{API_PREFIX}/docs",
        redoc_url=f"{API_PREFIX}/redoc",
        generate_unique_id_function=_operation_id,
        lifespan=lifespan,
    )
    app.state.settings = settings
    app.state.session_factory = (
        create_session_factory(engine) if engine is not None else None
    )
    install_problem_handlers(app)
    _install_openapi(app)
    app.include_router(health.router, prefix=API_PREFIX)
    app.include_router(university.router, prefix=API_PREFIX)
    app.include_router(identity.router, prefix=API_PREFIX)

    # The last added middleware is the outermost: the request ID is set
    # before the access log record is written.
    app.add_middleware(AccessLogMiddleware)
    app.add_middleware(CorrelationIdMiddleware)
    # Outermost: everything below sees the client address and scheme from
    # X-Forwarded-* of a trusted reverse proxy, e.g. the sign-in IP limit.
    app.add_middleware(ProxyHeadersMiddleware, trusted_hosts=settings.trusted_proxies)
    return app
