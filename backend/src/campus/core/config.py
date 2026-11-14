"""Application settings read from environment variables."""

from datetime import timedelta
from enum import StrEnum
from functools import lru_cache
from typing import Literal, Self

from packaging.version import InvalidVersion, Version
from pydantic import Field, SecretStr, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy.engine import make_url
from sqlalchemy.exc import ArgumentError

type Environment = Literal["development", "test", "staging", "production"]
type LogLevel = Literal["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]
type LogFormat = Literal["json", "console"]
type Locale = Literal["ru", "en"]
type SmtpSecurity = Literal["none", "starttls", "tls"]


class ClientPlatform(StrEnum):
    """Client applications, sent in the ``X-Client-Platform`` header."""

    ANDROID = "android"
    WEB = "web"
    DESKTOP = "desktop"
    TELEGRAM = "telegram"
    ADMIN = "admin"


class Settings(BaseSettings):
    """All runtime parameters of the API, worker and scheduler.

    Every field is read from a ``CAMPUS_``-prefixed environment variable,
    e.g. ``CAMPUS_LOG_LEVEL``. A local ``.env`` file is read as a fallback.
    An empty value means "not set", so the default applies.
    """

    model_config = SettingsConfigDict(
        env_prefix="CAMPUS_",
        env_file=".env",
        env_file_encoding="utf-8",
        env_ignore_empty=True,
        extra="ignore",
        frozen=True,
    )

    environment: Environment = "development"
    release: str | None = Field(
        default=None, description="Build identifier, e.g. a git commit SHA."
    )

    log_level: LogLevel = "INFO"
    log_format: LogFormat = Field(
        default="json", description="'console' is for local development only."
    )

    api_host: str = "127.0.0.1"
    api_port: int = Field(default=8000, ge=1, le=65535)

    database_url: SecretStr | None = Field(
        default=None,
        description=(
            "PostgreSQL URL, e.g. postgresql+asyncpg://user:password@host:5432/db;"
            " a postgresql:// URL is switched to the asyncpg driver."
        ),
    )
    database_pool_size: int = Field(default=10, ge=1)
    database_max_overflow: int = Field(default=10, ge=0)
    database_pool_timeout: float = Field(
        default=30.0, gt=0, description="Seconds to wait for a free connection."
    )

    default_locale: Locale = Field(
        default="ru",
        description="Language of messages when Accept-Language matches none.",
    )
    client_min_versions: dict[ClientPlatform, str] = Field(
        default_factory=dict,
        description=(
            "Oldest supported client version per platform, as JSON, e.g."
            ' {"android": "1.2.0"}; older clients must update.'
        ),
    )
    idempotency_key_ttl: timedelta = Field(
        default=timedelta(hours=24),
        gt=timedelta(0),
        description="How long an Idempotency-Key and its response are kept.",
    )
    page_size_default: int = Field(default=20, ge=1)
    page_size_max: int = Field(default=100, ge=1)
    redis_url: SecretStr | None = Field(
        default=None,
        description=(
            "Redis URL of the task broker, e.g. redis://:password@host:6379/0;"
            " required by the worker and the scheduler."
        ),
    )

    # Background jobs: outbox messages and deadlines (specification, 4.3, 5.2).
    outbox_poll_interval: float = Field(
        default=1.0, gt=0, description="Seconds between outbox polls when idle."
    )
    job_batch_size: int = Field(
        default=100, ge=1, description="Jobs run per pass before polling again."
    )
    job_max_attempts: int = Field(
        default=10, ge=1, description="Attempts before a job is marked failed."
    )
    job_retry_base_delay: timedelta = Field(
        default=timedelta(seconds=10),
        gt=timedelta(0),
        description="Delay before the first retry; doubles with every attempt.",
    )
    job_retry_max_delay: timedelta = Field(
        default=timedelta(hours=1),
        gt=timedelta(0),
        description="Upper bound of the retry delay.",
    )
    outbox_retention: timedelta = Field(
        default=timedelta(days=7),
        gt=timedelta(0),
        description="How long finished outbox messages are kept.",
    )
    deadline_retention: timedelta = Field(
        default=timedelta(days=7),
        gt=timedelta(0),
        description="How long finished deadlines are kept.",
    )
    deadlines_cron: str = Field(
        default="* * * * *", description="When due deadlines are processed (UTC)."
    )
    cleanup_cron: str = Field(
        default="30 3 * * *", description="When expired records are deleted (UTC)."
    )

    smtp_host: str | None = Field(
        default=None, description="Outgoing mail server; sending fails when empty."
    )
    smtp_port: int = Field(default=587, ge=1, le=65535)
    smtp_security: SmtpSecurity = Field(
        default="starttls",
        description="'starttls' upgrades a plain connection, 'tls' is implicit TLS.",
    )
    smtp_username: str | None = None
    smtp_password: SecretStr | None = None
    smtp_timeout: float = Field(default=30.0, gt=0, description="Seconds.")
    mail_from: str = Field(
        default="Campus <noreply@campus.localhost>",
        description="Sender of outgoing mail, 'Name <address>'.",
    )

    sentry_dsn: SecretStr | None = Field(
        default=None, description="Error reporting is disabled when empty."
    )
    sentry_traces_sample_rate: float = Field(default=0.0, ge=0.0, le=1.0)

    @field_validator("client_min_versions")
    @classmethod
    def _check_versions(
        cls, value: dict[ClientPlatform, str]
    ) -> dict[ClientPlatform, str]:
        for platform, version in value.items():
            try:
                Version(version)
            except InvalidVersion as error:
                msg = f"{platform}: {version!r} is not a version"
                raise ValueError(msg) from error
        return value

    @model_validator(mode="after")
    def _check_page_sizes(self) -> Self:
        if self.page_size_default > self.page_size_max:
            msg = "page_size_default exceeds page_size_max"
            raise ValueError(msg)
        return self

    def client_min_version(self, platform: ClientPlatform) -> Version | None:
        """Oldest supported version of ``platform``, if one is configured."""
        version = self.client_min_versions.get(platform)
        return None if version is None else Version(version)

    @field_validator("database_url", mode="before")
    @classmethod
    def _use_asyncpg_driver(cls, value: object) -> object:
        if not isinstance(value, str):
            return value
        try:
            url = make_url(value)
        except ArgumentError as error:
            msg = "not a database URL"
            raise ValueError(msg) from error
        if url.get_backend_name() not in {"postgresql", "postgres"}:
            msg = "not a PostgreSQL URL"
            raise ValueError(msg)
        return url.set(drivername="postgresql+asyncpg").render_as_string(
            hide_password=False
        )


@lru_cache
def get_settings() -> Settings:
    """Return the process-wide settings, read once on first use."""
    return Settings()
