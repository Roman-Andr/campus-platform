"""Application settings read from environment variables."""

import base64
import binascii
from datetime import timedelta
from enum import StrEnum
from functools import lru_cache
from ipaddress import ip_address, ip_network
from typing import Annotated, Literal, Self

from limits import parse_many
from packaging.version import InvalidVersion, Version
from pydantic import Field, SecretStr, field_validator, model_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict
from sqlalchemy.engine import make_url
from sqlalchemy.exc import ArgumentError

ENCRYPTION_KEY_SIZE = 32
# Specification, 5.3.2: moderation and audit records are kept for three years.
# Three calendar years span at most 1096 days; the purge function in the
# database refuses anything shorter.
AUDIT_RETENTION_MINIMUM = timedelta(days=1096)


def encryption_key(value: SecretStr) -> bytes:
    """Decode a base64 AES-256 key of the settings."""
    try:
        key = base64.b64decode(value.get_secret_value(), validate=True)
    except binascii.Error:
        raise ValueError("An encryption key must be base64") from None
    if len(key) != ENCRYPTION_KEY_SIZE:
        msg = f"An encryption key must be {ENCRYPTION_KEY_SIZE} bytes"
        raise ValueError(msg)
    return key


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
    trusted_proxies: str = Field(
        default="127.0.0.1",
        description=(
            "Reverse proxies whose X-Forwarded-For and X-Forwarded-Proto are"
            " trusted: comma-separated addresses and networks, e.g."
            " 127.0.0.1,172.16.0.0/12, or * for any peer. Requests from other"
            " peers keep their socket address."
        ),
    )

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
    idempotency_encryption_keys: Annotated[list[SecretStr], NoDecode] = Field(
        default_factory=list,
        description=(
            "Keys that encrypt stored idempotent responses (AES-256-GCM):"
            " comma-separated base64 32-byte keys. The first one encrypts, all"
            " decrypt; required by endpoints that change data."
        ),
    )
    page_size_default: int = Field(default=20, ge=1)
    page_size_max: int = Field(default=100, ge=1)
    cursor_secret_key: SecretStr | None = Field(
        default=None,
        min_length=32,
        description=(
            "Key that signs list page cursors with HMAC-SHA256, at least 32"
            " characters; required by list endpoints. Generate with"
            " `openssl rand -hex 32`."
        ),
    )
    feed_snapshot_ttl: timedelta = Field(
        default=timedelta(minutes=15),
        gt=timedelta(0),
        description=(
            "How long a feed snapshot stays valid; a cursor with an older"
            " snapshot is rejected."
        ),
    )
    redis_url: SecretStr | None = Field(
        default=None,
        description=(
            "Redis URL of the task broker, e.g. redis://:password@host:6379/0;"
            " required by the worker and the scheduler."
        ),
    )

    auth_secret_key: SecretStr | None = Field(default=None, min_length=32)
    access_token_ttl: timedelta = Field(default=timedelta(minutes=15), gt=timedelta(0))
    refresh_token_ttl: timedelta = Field(default=timedelta(days=30), gt=timedelta(0))
    sign_in_code_ttl: timedelta = Field(default=timedelta(minutes=10), gt=timedelta(0))
    sign_in_code_max_attempts: int = Field(default=5, ge=1)
    sign_in_email_limits: str = "3/15 minutes;10/day"
    sign_in_ip_limits: str = "60/minute"
    # Retention of credentials, deleted by the cleanup task (CLEANUP_CRON).
    sign_in_code_retention: timedelta = Field(
        default=timedelta(days=1),
        ge=timedelta(0),
        description="How long a sign-in code is kept after it expires.",
    )
    refresh_token_reuse_window: timedelta = Field(
        default=timedelta(days=30),
        ge=timedelta(0),
        description=(
            "How long a used refresh token of a live session is kept after it"
            " expires: its reuse within this window revokes the session."
        ),
    )
    session_retention: timedelta = Field(
        default=timedelta(days=7),
        ge=timedelta(0),
        description=(
            "How long a revoked or expired session is kept with its refresh tokens."
        ),
    )

    profile_max_course: int = Field(
        default=6,
        ge=1,
        description="Highest year of study a student may give in the profile.",
    )
    profile_skills_max: int = Field(
        default=30,
        ge=1,
        description="Most skill tags in each skill list of a profile.",
    )
    name_change_interval: timedelta = Field(
        default=timedelta(days=90),
        ge=timedelta(0),
        description="Shortest time between two name changes (Appendix 4).",
    )

    @field_validator("trusted_proxies")
    @classmethod
    def _check_trusted_proxies(cls, value: str) -> str:
        entries = [entry.strip() for entry in value.split(",")]
        if entries == ["*"]:
            return "*"
        for entry in entries:
            # uvicorn silently treats malformed entries as host names.
            if "/" in entry:
                ip_network(entry)
            else:
                ip_address(entry)
        return ",".join(entries)

    @field_validator("idempotency_encryption_keys", mode="before")
    @classmethod
    def _split_encryption_keys(cls, value: object) -> object:
        if isinstance(value, str):
            return [key.strip() for key in value.split(",") if key.strip()]
        return value

    @field_validator("idempotency_encryption_keys")
    @classmethod
    def _check_encryption_keys(cls, value: list[SecretStr]) -> list[SecretStr]:
        keys = [encryption_key(key) for key in value]
        if len(set(keys)) != len(keys):
            raise ValueError("Encryption keys must be different")
        return value

    @field_validator("sign_in_email_limits", "sign_in_ip_limits")
    @classmethod
    def _check_rate_limits(cls, value: str) -> str:
        if not parse_many(value):
            raise ValueError("At least one rate limit is required")
        return value

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
    audit_retention: timedelta = Field(
        default=AUDIT_RETENTION_MINIMUM,
        ge=AUDIT_RETENTION_MINIMUM,
        description=(
            "How long records of moderator and administrator actions are"
            " kept; three years at least (the database refuses less)."
        ),
    )
    deadlines_cron: str = Field(
        default="* * * * *", description="When due deadlines are processed (UTC)."
    )
    cleanup_cron: str = Field(
        default="30 3 * * *", description="When expired records are deleted (UTC)."
    )
    worker_shutdown_timeout: timedelta = Field(
        default=timedelta(seconds=20),
        ge=timedelta(0),
        description="How long a stopping worker waits for running jobs and tasks "
        "before cancelling them; below the stop grace period of the container.",
    )

    s3_endpoint_url: str | None = None
    s3_region: str = "us-east-1"
    s3_bucket: str = "campus-private"
    s3_access_key: SecretStr | None = None
    s3_secret_key: SecretStr | None = None
    photo_max_bytes: int = Field(default=10 * 1024 * 1024, ge=1, le=10 * 1024 * 1024)
    photo_max_pixels: int = Field(default=40_000_000, ge=1)
    photo_listing_limit: int = Field(default=10, ge=1, le=10)
    photo_preview_size: int = Field(default=480, ge=1)
    photo_jpeg_quality: int = Field(default=85, ge=1, le=95)
    photo_upload_ttl: timedelta = Field(
        default=timedelta(minutes=15), ge=timedelta(seconds=1), le=timedelta(days=7)
    )
    photo_read_ttl: timedelta = Field(
        default=timedelta(minutes=5), ge=timedelta(seconds=1), le=timedelta(days=7)
    )
    photo_unattached_ttl: timedelta = Field(default=timedelta(days=1), gt=timedelta(0))

    listing_lifetime: timedelta = Field(default=timedelta(days=30), gt=timedelta(0))
    listing_archive_retention: timedelta = Field(
        default=timedelta(days=365),
        gt=timedelta(0),
        description=(
            "How long an expired, completed or cancelled listing keeps its"
            " description and photos; counted from when it entered the archive."
        ),
    )
    listing_archive_cleanup_batch: int = Field(
        default=50,
        ge=1,
        description="Archived listings selected per cleanup batch.",
    )
    listing_archive_cleanup_limit: int = Field(
        default=1000,
        ge=1,
        description="Most archived listings cleaned in one cleanup run.",
    )
    listing_response_timeout: timedelta = Field(
        default=timedelta(hours=24), gt=timedelta(0)
    )
    listing_publication_limit: int = Field(default=10, ge=1)
    listing_publication_window: timedelta = Field(
        default=timedelta(days=1), gt=timedelta(0)
    )
    listing_response_limit: int = Field(default=30, ge=1)
    listing_response_window: timedelta = Field(
        default=timedelta(hours=1), gt=timedelta(0)
    )
    listing_title_max_length: int = Field(default=100, ge=1)
    listing_description_max_length: int = Field(default=5000, ge=1)
    meeting_place_max_length: int = Field(default=200, ge=1)
    meeting_reminder_long: timedelta = Field(
        default=timedelta(hours=24),
        gt=timedelta(0),
        description="First reminder before a scheduled meeting, e.g. 24 hours.",
    )
    meeting_reminder_short: timedelta = Field(
        default=timedelta(hours=1),
        gt=timedelta(0),
        description="Last reminder before a scheduled meeting, e.g. 1 hour.",
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

    @model_validator(mode="after")
    def _check_meeting_reminders(self) -> Self:
        if self.meeting_reminder_long <= self.meeting_reminder_short:
            msg = "meeting_reminder_long must be longer than meeting_reminder_short"
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
