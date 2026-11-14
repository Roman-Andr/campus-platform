"""Pytest plugin: Redis, Mailpit and Centrifugo containers for tests.

Images are kept in step with infra/compose.yaml and compose.override.yaml.
One container of each per test session, started on first use.
"""

from collections.abc import Iterator
from dataclasses import dataclass

import pytest
from testcontainers.community.redis import RedisContainer
from testcontainers.core.container import DockerContainer
from testcontainers.core.wait_strategies import HttpWaitStrategy, LogMessageWaitStrategy

REDIS_IMAGE = "docker.io/library/redis:7.4.12-alpine"
MAILPIT_IMAGE = "docker.io/axllent/mailpit:v1.33.1"
CENTRIFUGO_IMAGE = "docker.io/centrifugo/centrifugo:v6.10.3"
CENTRIFUGO_TOKEN_SECRET = "testing-centrifugo-token-secret-0123456789"  # noqa: S105
CENTRIFUGO_API_KEY = "testing-centrifugo-api-key"


@dataclass(frozen=True)
class Mailpit:
    smtp_host: str
    smtp_port: int
    api_url: str


@pytest.fixture(scope="session")
def redis_url() -> Iterator[str]:
    """URL of a Redis server shared by the test session."""
    with RedisContainer(REDIS_IMAGE) as container:
        host = container.get_container_host_ip()
        yield f"redis://{host}:{container.get_exposed_port(6379)}/0"


@pytest.fixture(scope="session")
def mailpit() -> Iterator[Mailpit]:
    """A Mailpit server: SMTP without authentication and its HTTP API."""
    container = (
        DockerContainer(MAILPIT_IMAGE)
        .with_exposed_ports(1025, 8025)
        .waiting_for(LogMessageWaitStrategy("accessible via"))
    )
    with container:
        host = container.get_container_host_ip()
        yield Mailpit(
            smtp_host=host,
            smtp_port=int(container.get_exposed_port(1025)),
            api_url=f"http://{host}:{container.get_exposed_port(8025)}/api/v1",
        )


@dataclass(frozen=True)
class CentrifugoConfig:
    """Endpoints and credentials the API under test uses for Centrifugo."""

    token_secret: str
    api_url: str
    api_key: str


@pytest.fixture
def centrifugo_config() -> CentrifugoConfig:
    """Centrifugo settings for unit tests; integration tests override this."""
    return CentrifugoConfig(
        token_secret=CENTRIFUGO_TOKEN_SECRET,
        api_url="http://centrifugo.test/api",
        api_key=CENTRIFUGO_API_KEY,
    )


@dataclass(frozen=True)
class CentrifugoService:
    """Public transports and server API credentials of one Centrifugo."""

    api_url: str
    ws_url: str
    token_secret: str
    api_key: str


@pytest.fixture(scope="session")
def centrifugo_service() -> Iterator[CentrifugoService]:
    """A Centrifugo server with the production channel and token settings."""
    container = (
        DockerContainer(CENTRIFUGO_IMAGE)
        .with_exposed_ports(8000)
        .with_env("CENTRIFUGO_CLIENT_TOKEN_HMAC_SECRET_KEY", CENTRIFUGO_TOKEN_SECRET)
        .with_env("CENTRIFUGO_HTTP_API_KEY", CENTRIFUGO_API_KEY)
        .with_env("CENTRIFUGO_CLIENT_ALLOWED_ORIGINS", "*")
        .with_env("CENTRIFUGO_HEALTH_ENABLED", "true")
        .with_env("CENTRIFUGO_CHANNEL_WITHOUT_NAMESPACE_HISTORY_SIZE", "100")
        .with_env("CENTRIFUGO_CHANNEL_WITHOUT_NAMESPACE_HISTORY_TTL", "5m")
        .with_env("CENTRIFUGO_CHANNEL_WITHOUT_NAMESPACE_FORCE_RECOVERY", "true")
        .with_env("CENTRIFUGO_CHANNEL_WITHOUT_NAMESPACE_FORCE_POSITIONING", "true")
        .with_env(
            "CENTRIFUGO_CHANNEL_WITHOUT_NAMESPACE_ALLOW_USER_LIMITED_CHANNELS", "true"
        )
        .with_env(
            "CENTRIFUGO_CHANNEL_NAMESPACES",
            '[{"name":"chat","history_size":100,"history_ttl":"5m",'
            '"force_recovery":true,"force_positioning":true}]',
        )
        .waiting_for(HttpWaitStrategy(8000, "/health"))
    )
    with container:
        host = container.get_container_host_ip()
        port = int(container.get_exposed_port(8000))
        yield CentrifugoService(
            api_url=f"http://{host}:{port}/api",
            ws_url=f"ws://{host}:{port}/connection/websocket",
            token_secret=CENTRIFUGO_TOKEN_SECRET,
            api_key=CENTRIFUGO_API_KEY,
        )
