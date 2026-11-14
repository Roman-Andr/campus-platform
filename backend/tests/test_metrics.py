"""Prometheus metrics on real PostgreSQL/Redis and a controlled wall clock."""

import asyncio
import socket
from datetime import UTC, datetime, timedelta
from typing import Any
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import httpx2
import pytest
import time_machine
from prometheus_client import CollectorRegistry, generate_latest
from prometheus_client.parser import text_string_to_metric_families
from pydantic import SecretStr, ValidationError
from redis.asyncio import Redis
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession
from taskiq import InMemoryBroker, TaskiqMessage, TaskiqResult

from campus.api.app import create_app
from campus.core.config import Settings
from campus.core.db import create_session_factory
from campus.core.deadlines import (
    Deadline,
    deadline_handlers,
    process_due_deadlines,
    schedule_deadline,
)
from campus.core.jobs import JobInfo
from campus.core.metrics import (
    Metrics,
    TaskMetricsMiddleware,
    exporter_app,
    metrics_server,
    queue_snapshot,
)
from campus.core.outbox import add_message, outbox_handlers, process_outbox
from campus.core.queue_names import CONSUMER_GROUP, QUEUE_NAME
from tests.web_app import serve

START = datetime(2027, 3, 1, 12, tzinfo=UTC)


def samples(body: bytes) -> dict[tuple[str, tuple[tuple[str, str], ...]], float]:
    return {
        (sample.name, tuple(sorted(sample.labels.items()))): sample.value
        for family in text_string_to_metric_families(body.decode())
        for sample in family.samples
    }


def value(body: bytes, name: str, **labels: str) -> float:
    return samples(body)[name, tuple(sorted(labels.items()))]


@pytest.mark.parametrize("process", ["api", "worker", "scheduler"])
async def test_valid_scrape_and_fresh_registry(process: str) -> None:
    metrics = Metrics(Settings(), process)
    metrics.sent.labels("test").inc()
    async with httpx2.AsyncClient(
        transport=httpx2.ASGITransport(app=exporter_app(metrics)),
        base_url="http://test",
    ) as client:
        response = await client.get("/metrics")
    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/plain; version=0.0.4")
    assert value(response.content, "campus_task_enqueued_total", task="test") == 1
    fresh = await Metrics(Settings(), process).render()
    assert "test" not in fresh.decode()
    assert value(fresh, "campus_process_uptime_seconds", process=process) >= 0


@pytest.mark.parametrize(("method", "expected"), [("GET", 200), ("POST", 405)])
async def test_http_metrics_use_templates(method: str, expected: int) -> None:
    app = create_app(Settings())

    @app.get("/objects/{object_id}")
    async def object_route(object_id: str) -> dict[str, str]:
        return {"id": object_id}

    async with serve(app) as client:
        for _ in range(2):
            response = await client.request(method, f"/objects/{uuid4()}")
            assert response.status_code == expected
        await client.get(f"/unknown/{uuid4()}?email=private@example.com")
        await client.request("ARBITRARY", "/unknown")
    body = await app.state.metrics.render()
    assert (
        value(
            body,
            "campus_http_request_duration_seconds_count",
            method=method,
            route="/objects/{object_id}",
            status=str(expected),
        )
        == 2
    )
    assert "private" not in body.decode()
    assert "/unknown/" not in body.decode()
    assert "ARBITRARY" not in body.decode()
    assert 'le="0.15"' in body.decode()
    assert 'le="0.3"' in body.decode()


async def test_unhandled_error_is_counted() -> None:
    app = create_app(Settings())

    @app.get("/crash")
    async def crash() -> None:
        raise RuntimeError("private exception")

    async with serve(app) as client:
        assert (await client.get("/crash")).status_code == 500
    assert (
        value(
            await app.state.metrics.render(),
            "campus_http_request_duration_seconds_count",
            method="GET",
            route="/crash",
            status="500",
        )
        == 1
    )


@pytest.mark.parametrize("authorized", [False, True])
async def test_business_api_has_no_metrics_route(authorized: bool) -> None:
    # The same result for anonymous and authenticated callers: only the
    # internal listener serves metrics, never the public business router.
    app = create_app(Settings())
    async with serve(app) as client:
        if authorized:
            client.headers["Authorization"] = "Bearer test"
        for path in ("/metrics", "/api/v1/metrics"):
            assert (await client.get(path)).status_code == 404
    assert "/metrics" not in app.openapi()["paths"]


@pytest.mark.parametrize("outcome", ["success", "retry", "failed"])
async def test_durable_states_and_original_due_time(
    engine: AsyncEngine,
    outcome: str,
) -> None:
    sessions = create_session_factory(engine)
    settings = Settings(job_max_attempts=1 if outcome == "failed" else 3)
    metrics = Metrics(settings, "scheduler")
    calls = 0

    async def handler(_session: AsyncSession, _job: JobInfo) -> None:
        nonlocal calls
        calls += 1
        if outcome != "success":
            raise ValueError("private text")

    topic = "test.metrics"
    deadline_handlers.register(topic)(handler)
    outbox_handlers.register(topic)(handler)
    try:
        with time_machine.travel(START, tick=False) as traveller:
            async with sessions() as session, session.begin():
                await schedule_deadline(session, topic, START, {}, key="test")
                add_message(session, topic, {})
            traveller.shift(timedelta(seconds=60))
            before = await metrics.render(sessions)
            assert value(before, "campus_deadline_overdue_seconds") == 60
            assert (
                value(before, "campus_job_oldest_pending_age_seconds", queue="outbox")
                == 60
            )
            # Competing runners claim each durable operation only once.
            await asyncio.gather(
                process_due_deadlines(sessions, settings),
                process_due_deadlines(sessions, settings),
                process_outbox(sessions, settings),
                process_outbox(sessions, settings),
            )
            after = await metrics.render(sessions)
            state = {"success": "processed", "retry": "pending", "failed": "failed"}[
                outcome
            ]
            for queue in ("outbox", "deadlines"):
                assert value(after, "campus_jobs", queue=queue, state=state) == 1
            assert calls == 2
            if outcome == "retry":
                traveller.shift(timedelta(seconds=5))
                assert (
                    value(
                        await metrics.render(sessions),
                        "campus_deadline_overdue_seconds",
                    )
                    == 65
                )
                async with sessions() as session:
                    row = await session.scalar(select(Deadline))
                    assert row is not None
                    assert row.due_at == START
                    assert row.available_at == START + timedelta(seconds=70)
                # A reschedule deliberately replaces the original deadline.
                async with sessions() as session, session.begin():
                    await schedule_deadline(
                        session, topic, START + timedelta(hours=1), {}, key="test"
                    )
                assert (
                    value(
                        await metrics.render(sessions),
                        "campus_deadline_overdue_seconds",
                    )
                    == 0
                )
            else:
                assert value(after, "campus_deadline_overdue_seconds") == 0
                assert (
                    value(
                        after, "campus_job_oldest_pending_age_seconds", queue="outbox"
                    )
                    == 0
                )
            assert "private" not in after.decode()
            # Independent exporters observe the same durable counts, not attempts.
            assert (
                value(
                    await Metrics(settings, "scheduler").render(sessions),
                    "campus_jobs",
                    queue="outbox",
                    state=state,
                )
                == 1
            )
    finally:
        deadline_handlers.remove(topic)
        outbox_handlers.remove(topic)


async def test_queue_waiting_pending_age_and_ack(redis_url: str) -> None:
    async with Redis.from_url(redis_url, decode_responses=True) as redis:
        await redis.delete(QUEUE_NAME)
        try:

            async def scrape() -> bytes:
                registry = CollectorRegistry()
                await queue_snapshot(registry, redis)
                return generate_latest(registry)

            assert (
                value(await scrape(), "campus_task_queue_messages", state="waiting")
                == 0
            )
            with time_machine.travel(START, tick=False) as traveller:
                first = await redis.xadd(
                    QUEUE_NAME,
                    {"data": "secret"},
                    id=f"{int(START.timestamp() * 1000)}-0",
                )
                traveller.shift(timedelta(seconds=60))
                assert (
                    value(await scrape(), "campus_task_queue_oldest_age_seconds") == 60
                )
                await redis.xgroup_create(QUEUE_NAME, CONSUMER_GROUP, id="0")
                await redis.xreadgroup(
                    CONSUMER_GROUP, "test", {QUEUE_NAME: ">"}, count=1
                )
                body = await scrape()
                assert value(body, "campus_task_queue_messages", state="pending") == 1
                assert value(body, "campus_task_queue_messages", state="waiting") == 0
                second = await redis.xadd(
                    QUEUE_NAME,
                    {"data": "secret"},
                    id=f"{int((START + timedelta(seconds=60)).timestamp() * 1000)}-0",
                )
                await redis.xclaim(QUEUE_NAME, CONSUMER_GROUP, "another", 0, [first])
                traveller.shift(timedelta(seconds=60))
                body = await scrape()
                assert value(body, "campus_task_queue_oldest_age_seconds") == 120
                assert value(body, "campus_task_queue_messages", state="waiting") == 1
                assert value(body, "campus_task_queue_messages", state="pending") == 1
                await redis.xack(QUEUE_NAME, CONSUMER_GROUP, first)
                body = await scrape()
                assert value(body, "campus_task_queue_oldest_age_seconds") == 60
                assert value(body, "campus_task_queue_messages", state="pending") == 0
                await redis.xreadgroup(
                    CONSUMER_GROUP, "test", {QUEUE_NAME: ">"}, count=1
                )
                await redis.xack(QUEUE_NAME, CONSUMER_GROUP, second)
                assert (
                    value(await scrape(), "campus_task_queue_oldest_age_seconds") == 0
                )
                # XLEN still includes the acked items: it is not queue length.
                assert await redis.xlen(QUEUE_NAME) == 2
        finally:
            await redis.delete(QUEUE_NAME)


@pytest.mark.parametrize("is_err", [False, True])
def test_task_attempts_are_separate_from_domain_operations(is_err: bool) -> None:
    metrics = Metrics(Settings(), "worker")
    broker = InMemoryBroker()
    broker.register_task(AsyncMock(), task_name="registered")
    middleware = TaskMetricsMiddleware(metrics)
    middleware.set_broker(broker)
    for name, label in (("registered", "registered"), ("secret-input", "unknown")):
        message = TaskiqMessage(
            task_id="private", task_name=name, labels={}, args=[], kwargs={}
        )
        middleware.post_send(message)
        middleware.post_execute(
            message,
            TaskiqResult[Any](is_err=is_err, return_value=None, execution_time=0),
        )
        body = generate_latest(metrics.registry)
        assert (
            value(
                body,
                "campus_task_executions_total",
                task=label,
                status="error" if is_err else "success",
            )
            == 1
        )
        assert value(body, "campus_task_enqueued_total", task=label) == 1
    assert "secret-input" not in body.decode()


async def test_failed_scrape_has_no_stale_snapshot_and_does_not_break_api() -> None:
    metrics = Metrics(Settings(metrics_scrape_timeout=0.01), "scheduler")
    broken = MagicMock()
    broken.side_effect = ConnectionError("private database URL")
    async with httpx2.AsyncClient(
        transport=httpx2.ASGITransport(app=exporter_app(metrics, broken)),
        base_url="http://test",
    ) as client:
        response = await client.get("/metrics")
    assert response.status_code == 503
    assert response.headers["content-type"] == "application/problem+json"
    assert "private" not in response.text
    async with serve(create_app(Settings())) as client:
        assert (await client.get("/api/v1/health")).status_code == 200


@pytest.mark.parametrize(
    "buckets", [(), (0.3, 0.15), (0.1, 0.1), (-1,), (float("inf"),)]
)
def test_invalid_buckets(buckets: tuple[float, ...]) -> None:
    with pytest.raises(ValidationError):
        Settings(metrics_http_buckets=buckets)


@pytest.mark.parametrize("process", ["api", "worker", "scheduler"])
async def test_listener_lifecycle_and_disabled_mode(
    process: str, database_url: str, redis_url: str
) -> None:
    async with metrics_server(Metrics(Settings(), "worker")):
        pass
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    async with (
        metrics_server(
            Metrics(
                Settings(
                    metrics_port=port,
                    database_url=SecretStr(database_url),
                    redis_url=SecretStr(redis_url),
                ),
                process,
            )
        ),
        httpx2.AsyncClient() as client,
    ):
        for _ in range(100):
            try:
                response = await client.get(f"http://127.0.0.1:{port}/metrics")
                break
            except httpx2.ConnectError:
                await asyncio.sleep(0.01)
        else:
            pytest.fail("Exporter did not start")

    assert response.status_code == 200


async def test_scrape_timeout(monkeypatch: pytest.MonkeyPatch) -> None:
    async def slow(*_args: object) -> None:
        await asyncio.sleep(10)

    monkeypatch.setattr("campus.core.metrics.database_snapshot", slow)
    metrics = Metrics(Settings(metrics_scrape_timeout=0.01), "scheduler")
    async with httpx2.AsyncClient(
        transport=httpx2.ASGITransport(app=exporter_app(metrics, MagicMock())),
        base_url="http://test",
    ) as client:
        response = await client.get("/metrics")
    assert response.status_code == 503
