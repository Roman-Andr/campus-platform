# syntax=docker/dockerfile:1
# Server image: one image for the API, the worker, the scheduler and the
# migrations; the process is chosen by the command (`campus-api` by default).
# Build context is backend/: `docker build -t campus-backend backend`.

ARG PYTHON_IMAGE=docker.io/library/python:3.14.10-slim-trixie
ARG UV_IMAGE=ghcr.io/astral-sh/uv:0.13.8

FROM ${UV_IMAGE} AS uv

# --- Build stage: resolve the locked dependencies into /app/.venv ----------
FROM ${PYTHON_IMAGE} AS build

COPY --from=uv /uv /usr/local/bin/uv

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never \
    UV_PYTHON=/usr/local/bin/python3 \
    UV_PROJECT_ENVIRONMENT=/app/.venv

WORKDIR /app

# Dependencies first: this layer is rebuilt only when the lock file changes.
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --locked --no-dev --no-install-project

COPY . /app
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-dev --no-editable

# --- Runtime stage: the virtual environment and sources, no build tools -----
FROM ${PYTHON_IMAGE} AS runtime

RUN groupadd --system --gid 10001 campus \
    && useradd --system --uid 10001 --gid campus --home-dir /app \
        --no-create-home --shell /usr/sbin/nologin campus

# Owned by root and read-only for the service user. The sources are kept
# next to the environment for Alembic (alembic.ini and migration scripts).
COPY --from=build /app /app

ENV PATH="/app/.venv/bin:${PATH}" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    CAMPUS_API_HOST=0.0.0.0 \
    CAMPUS_API_PORT=8000

WORKDIR /app
USER campus:campus
EXPOSE 8000

CMD ["campus-api"]
