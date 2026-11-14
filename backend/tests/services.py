"""Pytest plugin: Redis and Mailpit containers for tests.

Images are kept in step with infra/compose.yaml and compose.override.yaml.
One container of each per test session, started on first use.
"""

from collections.abc import Iterator
from dataclasses import dataclass

import pytest
from testcontainers.community.redis import RedisContainer
from testcontainers.core.container import DockerContainer
from testcontainers.core.wait_strategies import LogMessageWaitStrategy

REDIS_IMAGE = "docker.io/library/redis:7.4.12-alpine"
MAILPIT_IMAGE = "docker.io/axllent/mailpit:v1.33.1"


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
