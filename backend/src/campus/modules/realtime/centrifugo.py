"""Centrifugo server API client used by the API and the worker."""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from cent import AsyncClient

from campus.core.config import Settings


class CentrifugoNotConfiguredError(RuntimeError):
    """The server API endpoint or key is not set."""

    def __init__(self) -> None:
        super().__init__(
            "CAMPUS_CENTRIFUGO_API_URL and CAMPUS_CENTRIFUGO_API_KEY are required"
        )


@asynccontextmanager
async def centrifugo_client(settings: Settings) -> AsyncIterator[AsyncClient]:
    """A server API client of Centrifugo over HTTP.

    The server API is reachable only by the server processes; clients use the
    public transports only. The client is closed with the context.
    """
    if settings.centrifugo_api_url is None or settings.centrifugo_api_key is None:
        raise CentrifugoNotConfiguredError
    async with AsyncClient(
        api_endpoint=settings.centrifugo_api_url,
        api_key=settings.centrifugo_api_key.get_secret_value(),
        request_timeout=settings.centrifugo_api_timeout,
    ) as client:
        yield client
