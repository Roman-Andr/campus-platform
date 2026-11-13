"""FastAPI application factory."""

from asgi_correlation_id import CorrelationIdMiddleware
from fastapi import FastAPI
from fastapi.routing import APIRoute

from campus import __version__
from campus.api import health
from campus.api.access_log import AccessLogMiddleware
from campus.core.config import Settings, get_settings
from campus.core.observability import configure_observability

API_PREFIX = "/api/v1"


def _operation_id(route: APIRoute) -> str:
    # Stable, readable operation IDs for generated clients: the handler name.
    return route.name


def create_app(settings: Settings | None = None) -> FastAPI:
    """Build the API application; used by uvicorn as a factory."""
    settings = settings or get_settings()
    configure_observability(settings, process="api")

    app = FastAPI(
        title="Campus API",
        version=__version__,
        openapi_url=f"{API_PREFIX}/openapi.json",
        docs_url=f"{API_PREFIX}/docs",
        redoc_url=f"{API_PREFIX}/redoc",
        generate_unique_id_function=_operation_id,
    )
    app.include_router(health.router, prefix=API_PREFIX)

    # The last added middleware is the outermost: the request ID is set
    # before the access log record is written.
    app.add_middleware(AccessLogMiddleware)
    app.add_middleware(CorrelationIdMiddleware)
    return app
