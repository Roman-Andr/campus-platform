"""Process-local instrumentation and an isolated, pull-only metrics listener."""

import asyncio
import contextlib
import time
from collections.abc import AsyncIterator, Iterator
from contextlib import asynccontextmanager
from typing import Any

import uvicorn
from prometheus_client import (
    CollectorRegistry,
    Counter,
    Gauge,
    Histogram,
    generate_latest,
)
from redis.asyncio import Redis
from redis.exceptions import ResponseError
from sqlalchemy import ColumnElement, func, select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker
from starlette.applications import Starlette
from starlette.requests import Request
from starlette.responses import JSONResponse, Response
from starlette.routing import Route
from starlette.types import ASGIApp, Message, Receive, Scope, Send
from taskiq import TaskiqMessage, TaskiqMiddleware, TaskiqResult

from campus.core import clock
from campus.core.config import Settings
from campus.core.db import create_engine, create_session_factory
from campus.core.deadlines import Deadline
from campus.core.outbox import OutboxMessage
from campus.core.queue_names import CONSUMER_GROUP, QUEUE_NAME

CONTENT_TYPE = "text/plain; version=0.0.4; charset=utf-8"


class Metrics:
    """A fresh registry per process; no shared files or global default registry."""

    def __init__(self, settings: Settings, process: str) -> None:
        self.registry = CollectorRegistry()
        self.settings = settings
        self.process = process
        self.started = time.monotonic()
        self.http = Histogram(
            "campus_http_request_duration_seconds",
            "HTTP duration including response streaming; count includes errors.",
            ["method", "route", "status"],
            buckets=settings.metrics_http_buckets,
            registry=self.registry,
        )
        self.tasks = Counter(
            "campus_task_executions_total",
            "Taskiq executions (attempts, not domain operations).",
            ["task", "status"],
            registry=self.registry,
        )
        self.sent = Counter(
            "campus_task_enqueued_total",
            "Successfully enqueued Taskiq messages.",
            ["task"],
            registry=self.registry,
        )

    async def render(
        self,
        sessions: async_sessionmaker[AsyncSession] | None = None,
        redis: Redis | None = None,
    ) -> bytes:
        snapshot = CollectorRegistry()
        Gauge(
            "campus_process_uptime_seconds",
            "Process uptime.",
            ["process"],
            registry=snapshot,
        ).labels(self.process).set(time.monotonic() - self.started)
        # Shared state has ONE owner: scheduler. Never sum replicas of it.
        if self.process == "scheduler":
            async with asyncio.timeout(self.settings.metrics_scrape_timeout):
                if sessions is not None:
                    await database_snapshot(snapshot, sessions)
                if redis is not None:
                    await queue_snapshot(snapshot, redis)
        return generate_latest(self.registry) + generate_latest(snapshot)


class HttpMetricsMiddleware:
    """Use resolved route templates and bounded method/status labels only."""

    def __init__(self, app: ASGIApp, metrics: Metrics) -> None:
        self.app, self.metrics = app, metrics

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        started, status = time.perf_counter(), 500

        async def record(message: Message) -> None:
            nonlocal status
            if message["type"] == "http.response.start":
                status = message["status"]
            await send(message)

        try:
            await self.app(scope, receive, record)
        finally:
            method = scope["method"]
            if method not in {
                "GET",
                "POST",
                "PUT",
                "PATCH",
                "DELETE",
                "HEAD",
                "OPTIONS",
            }:
                method = "OTHER"
            route = getattr(scope.get("route"), "path", "unmatched")
            self.metrics.http.labels(method, route, str(status)).observe(
                time.perf_counter() - started
            )


class TaskMetricsMiddleware(TaskiqMiddleware):
    def __init__(self, metrics: Metrics) -> None:
        super().__init__()
        self.metrics = metrics

    def task_label(self, message: TaskiqMessage) -> str:
        # Task names are code registrations, never arbitrary broker input.
        return (
            message.task_name if self.broker.find_task(message.task_name) else "unknown"
        )

    def post_send(self, message: TaskiqMessage) -> None:
        self.metrics.sent.labels(self.task_label(message)).inc()

    def post_execute(self, message: TaskiqMessage, result: TaskiqResult[Any]) -> None:
        self.metrics.tasks.labels(
            self.task_label(message), "error" if result.is_err else "success"
        ).inc()


async def database_snapshot(
    registry: CollectorRegistry, sessions: async_sessionmaker[AsyncSession]
) -> None:
    jobs = Gauge(
        "campus_jobs",
        "Retained durable jobs by state (not a counter).",
        ["queue", "state"],
        registry=registry,
    )
    age = Gauge(
        "campus_job_oldest_pending_age_seconds",
        "Age since creation, including retries.",
        ["queue"],
        registry=registry,
    )
    overdue = Gauge(
        "campus_deadline_overdue_seconds",
        "Oldest pending original due_at lateness.",
        registry=registry,
    )
    now = clock.now()
    async with sessions() as session, session.begin():
        # One aggregate query per table, no payloads or identifiers loaded.
        for name, model in (("outbox", OutboxMessage), ("deadlines", Deadline)):
            pending = model.is_pending()
            columns: list[ColumnElement[Any]] = [
                func.count().filter(pending),
                func.count().filter(model.processed_at.is_not(None)),
                func.count().filter(model.failed_at.is_not(None)),
                func.min(model.created_at).filter(pending),
            ]
            if model is Deadline:
                columns.append(func.min(Deadline.due_at).filter(pending))
            row = (await session.execute(select(*columns))).one()
            for state, count in zip(
                ("pending", "processed", "failed"), row[:3], strict=True
            ):
                jobs.labels(name, state).set(count)
            age.labels(name).set(
                max(0, (now - row[3]).total_seconds()) if row[3] else 0
            )
            if model is Deadline:
                overdue.set(max(0, (now - row[4]).total_seconds()) if row[4] else 0)


async def queue_snapshot(registry: CollectorRegistry, redis: Redis) -> None:
    size = Gauge(
        "campus_task_queue_messages",
        "Unacknowledged or undelivered stream entries.",
        ["state"],
        registry=registry,
    )
    age = Gauge(
        "campus_task_queue_oldest_age_seconds",
        "Age from oldest unhandled stream ID.",
        registry=registry,
    )
    try:
        groups = await redis.xinfo_groups(QUEUE_NAME)
    except ResponseError as error:
        if "no such key" not in str(error):
            raise
        groups = []
    group = next((g for g in groups if g["name"] == CONSUMER_GROUP), None)
    if group is None:
        # A stream may already exist before the first worker creates its group.
        waiting = await redis.xlen(QUEUE_NAME)
        first = await redis.xrange(QUEUE_NAME, count=1)
        pending = 0
        oldest = str(first[0][0]) if first else None
    else:
        if group["lag"] is None:
            raise ValueError("Redis stream lag is unknown; cannot report queue size")
        waiting, pending = group["lag"], group["pending"]
        first = await redis.xrange(
            QUEUE_NAME, min=f"({group['last-delivered-id']}", count=1
        )
        unacked = await redis.xpending_range(QUEUE_NAME, CONSUMER_GROUP, "-", "+", 1)
        ids = [str(entry[0]) for entry in (first or [])]
        ids.extend(str(entry["message_id"]) for entry in unacked)
        oldest = min(ids, key=lambda value: int(value.split("-")[0])) if ids else None
    size.labels("waiting").set(waiting)
    size.labels("pending").set(pending)
    age.set(
        max(0, clock.now().timestamp() - int(oldest.split("-")[0]) / 1000)
        if oldest
        else 0
    )


def exporter_app(
    metrics: Metrics,
    sessions: async_sessionmaker[AsyncSession] | None = None,
    redis: Redis | None = None,
) -> Starlette:
    async def scrape(_request: Request) -> Response:
        try:
            body = await metrics.render(sessions, redis)
        except Exception:
            # No stale zeroes; Prometheus marks the target down on collection failure.
            return JSONResponse(
                {"type": "about:blank", "title": "Metrics unavailable", "status": 503},
                status_code=503,
                media_type="application/problem+json",
            )
        return Response(body, headers={"Content-Type": CONTENT_TYPE})

    return Starlette(routes=[Route("/metrics", scrape)])


class ExporterServer(uvicorn.Server):
    @contextlib.contextmanager
    def capture_signals(self) -> Iterator[None]:
        yield


@asynccontextmanager
async def metrics_server(metrics: Metrics) -> AsyncIterator[None]:
    """Run on a separate internal port; scrape never runs in a business request."""
    settings = metrics.settings
    if settings.metrics_port is None:
        yield
        return
    engine = (
        create_engine(settings)
        if metrics.process == "scheduler" and settings.database_url
        else None
    )
    redis = (
        Redis.from_url(settings.redis_url.get_secret_value(), decode_responses=True)
        if metrics.process == "scheduler" and settings.redis_url
        else None
    )
    app = exporter_app(
        metrics, create_session_factory(engine) if engine else None, redis
    )
    server = ExporterServer(
        uvicorn.Config(
            app,
            host=settings.metrics_host,
            port=settings.metrics_port,
            log_config=None,
            access_log=False,
            lifespan="off",
        )
    )
    # The outer process owns signals; the exporter must not replace them.
    server_task = asyncio.create_task(server.serve(), name="metrics")
    try:
        yield
    finally:
        server.should_exit = True
        with contextlib.suppress(asyncio.CancelledError):
            await server_task
        if redis:
            await redis.aclose()
        if engine:
            await engine.dispose()
