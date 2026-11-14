"""Client address and scheme behind a reverse proxy (CAMPUS_TRUSTED_PROXIES)."""

import httpx2
import pytest
from fastapi import Request

from campus.api.app import create_app
from campus.core.config import Settings

PROXY = "172.18.0.5"


async def seen(
    trusted_proxies: str, peer: str, headers: dict[str, str]
) -> tuple[str | None, str]:
    """The client host and URL scheme a handler sees for a request."""
    app = create_app(Settings(trusted_proxies=trusted_proxies))

    @app.get("/whoami")
    async def whoami(request: Request) -> dict[str, str | None]:
        host = request.client.host if request.client else None
        return {"host": host, "scheme": request.url.scheme}

    transport = httpx2.ASGITransport(app=app, client=(peer, 40000))
    async with httpx2.AsyncClient(transport=transport, base_url="http://test") as c:
        body = (await c.get("/whoami", headers=headers)).json()
    return body["host"], body["scheme"]


@pytest.mark.parametrize(
    ("trusted", "peer", "headers", "expected"),
    [
        # Default: only the loopback proxy is trusted.
        ("127.0.0.1", "127.0.0.1", {"X-Forwarded-For": "198.51.100.1"}, "198.51.100.1"),
        ("127.0.0.1", PROXY, {"X-Forwarded-For": "198.51.100.1"}, PROXY),
        # A network of proxies, e.g. the compose networks.
        ("172.16.0.0/12", PROXY, {"X-Forwarded-For": "198.51.100.1"}, "198.51.100.1"),
        # Spoofed entries to the left of the proxy-added address are ignored.
        (
            "172.16.0.0/12",
            PROXY,
            {"X-Forwarded-For": "203.0.113.9, 198.51.100.1"},
            "198.51.100.1",
        ),
        # Proxies along the chain are skipped.
        (
            "172.16.0.0/12",
            PROXY,
            {"X-Forwarded-For": "198.51.100.1, 172.20.0.2"},
            "198.51.100.1",
        ),
        ("172.16.0.0/12", PROXY, {}, PROXY),
        ("172.16.0.0/12", "203.0.113.7", {"X-Forwarded-For": "1.2.3.4"}, "203.0.113.7"),
        ("*", "203.0.113.7", {"X-Forwarded-For": "198.51.100.1"}, "198.51.100.1"),
    ],
)
async def test_client_address(
    trusted: str, peer: str, headers: dict[str, str], expected: str
) -> None:
    host, _ = await seen(trusted, peer, headers)

    assert host == expected


@pytest.mark.parametrize(
    ("peer", "scheme"), [(PROXY, "https"), ("203.0.113.7", "http")]
)
async def test_scheme_only_from_trusted_proxy(peer: str, scheme: str) -> None:
    _, seen_scheme = await seen("172.16.0.0/12", peer, {"X-Forwarded-Proto": "https"})

    assert seen_scheme == scheme
