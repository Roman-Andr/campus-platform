"""Application settings read from environment variables."""

import base64
import binascii
import math
from datetime import time, timedelta
from enum import StrEnum
from functools import lru_cache
from ipaddress import ip_address, ip_network
from typing import Annotated, Literal, Self
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

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

    metrics_host: str = "127.0.0.1"
    metrics_port: int | None = Field(default=None, ge=1, le=65535)
    metrics_scrape_timeout: float = Field(default=3.0, gt=0)
    metrics_http_buckets: tuple[float, ...] = (
        0.005,
        0.01,
        0.025,
        0.05,
        0.075,
        0.1,
        0.15,
        0.2,
        0.3,
        0.5,
        1,
        2.5,
        5,
    )

    @field_validator("metrics_http_buckets")
    @classmethod
    def _check_metrics_buckets(cls, value: tuple[float, ...]) -> tuple[float, ...]:
        if not value or any(not math.isfinite(v) or v <= 0 for v in value):
            raise ValueError("Metrics buckets must be finite and positive")
        if tuple(sorted(set(value))) != value:
            raise ValueError("Metrics buckets must be strictly increasing")
        return value

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
    # How long an accepted item reservation lasts until a meeting is scheduled
    # (appendix 4); a scheduled meeting extends it to the meeting time.
    listing_reservation_timeout: timedelta = Field(
        default=timedelta(hours=48), gt=timedelta(0)
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
    # How long a queue member has to confirm an offered place (appendix 4).
    listing_offer_timeout: timedelta = Field(
        default=timedelta(hours=2), gt=timedelta(0)
    )
    # Closer to the start than this, places are not offered by queue: they
    # open to everyone and the whole queue is notified at once.
    listing_open_to_all_before: timedelta = Field(
        default=timedelta(hours=1), gt=timedelta(0)
    )

    # How many time options a skill lesson offers (specification, 5.1.1).
    lesson_options_min: int = Field(default=2, ge=1)
    lesson_options_max: int = Field(default=3, ge=1)

    meeting_place_max_length: int = Field(default=200, ge=1)
    return_reminder_before: timedelta = Field(
        default=timedelta(hours=24),
        gt=timedelta(0),
        description="How long before a return deadline to notify its participants.",
    )
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

    # Notification settings (specification, 5.1.1, module 7): the defaults
    # for a user who has not changed them. Quiet hours are wall-clock times
    # of the user's city; the fallback zone is used until the profile has one.
    notification_quiet_hours_enabled: bool = Field(
        default=True,
        description="Quiet hours are on by default (specification, appendix 4).",
    )
    notification_quiet_hours_start: time = Field(
        default=time(23, 0),
        description="Start of quiet hours as a wall time in the user's city.",
    )
    notification_quiet_hours_end: time = Field(
        default=time(8, 0),
        description="End of quiet hours as a wall time in the user's city.",
    )
    notification_default_timezone: str = Field(
        default="Europe/Moscow",
        description=(
            "IANA time zone used for quiet hours until the user's city is known."
        ),
    )

    # FCM HTTP v1 (specification, 5.1.1, module 7): Android push. The service
    # account credentials are optional as a group; without them the adapter
    # reports a permanent configuration error and drops no stored notification.
    fcm_project_id: str | None = Field(
        default=None, description="Firebase project ID for FCM HTTP v1 messages."
    )
    fcm_client_email: str | None = Field(
        default=None, description="Service account e-mail used for FCM OAuth."
    )
    fcm_private_key: SecretStr | None = Field(
        default=None, description="Service account private key in PEM form."
    )
    fcm_api_url: str = Field(
        default="https://fcm.googleapis.com",
        description="Base URL of the FCM HTTP v1 API.",
    )
    fcm_timeout: float = Field(
        default=5.0, gt=0, description="Seconds to wait for FCM or its OAuth endpoint."
    )

    # Centrifugo (specification, 4.4, 4.6): the API issues JWT tokens signed
    # with the shared HMAC secret and talks to the server API for history and
    # forced unsubscribe. Clients reach only the public transports.
    centrifugo_token_hmac_secret: SecretStr | None = Field(
        default=None,
        description=(
            "Shared with Centrifugo client.token.hmac_secret_key; signs"
            " connection and subscription tokens. Required to issue tokens."
        ),
    )
    centrifugo_api_url: str | None = Field(
        default=None,
        description=(
            "Centrifugo server API endpoint including /api, e.g."
            " http://centrifugo:8000/api. Used by history and forced"
            " unsubscribe; the server API is not exposed to clients."
        ),
    )
    centrifugo_api_key: SecretStr | None = Field(
        default=None,
        description="Value of the Centrifugo X-API-Key header (http_api.key).",
    )
    centrifugo_api_timeout: float = Field(
        default=5.0, gt=0, description="Seconds to wait for the server API."
    )
    centrifugo_connection_token_ttl: timedelta = Field(
        default=timedelta(minutes=5),
        gt=timedelta(0),
        description=(
            "Lifetime of a connection token; a client refreshes it before"
            " expiry. Short enough to stop a revoked session from reconnecting"
            " soon after a forced disconnect."
        ),
    )
    centrifugo_subscription_token_ttl: timedelta = Field(
        default=timedelta(minutes=5),
        gt=timedelta(0),
        description=(
            "Lifetime of a channel subscription token; rights are rechecked"
            " when the client refreshes it."
        ),
    )
    centrifugo_history_limit: int = Field(
        default=100,
        ge=1,
        le=300,
        description=(
            "Publications returned by one realtime recovery request; Centrifugo"
            " caps client history at 300 by default."
        ),
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

    @model_validator(mode="after")
    def _check_lesson_options(self) -> Self:
        if self.lesson_options_min > self.lesson_options_max:
            msg = "lesson_options_min exceeds lesson_options_max"
            raise ValueError(msg)
        return self

    @model_validator(mode="after")
    def _check_quiet_hours(self) -> Self:
        if self.notification_quiet_hours_start == self.notification_quiet_hours_end:
            msg = "notification quiet hours must not be empty"
            raise ValueError(msg)
        return self

    @field_validator("notification_quiet_hours_start", "notification_quiet_hours_end")
    @classmethod
    def _check_wall_time(cls, value: time) -> time:
        if value.tzinfo is not None:
            msg = "notification quiet hours must be wall times without an offset"
            raise ValueError(msg)
        return value

    @field_validator("notification_default_timezone")
    @classmethod
    def _check_default_timezone(cls, value: str) -> str:
        try:
            ZoneInfo(value)
        except ZoneInfoNotFoundError:
            msg = f"{value!r} is not an IANA time zone"
            raise ValueError(msg) from None
        return value

    @model_validator(mode="after")
    def _check_fcm_credentials(self) -> Self:
        configured = (
            bool(self.fcm_project_id),
            bool(self.fcm_client_email),
            self.fcm_private_key is not None
            and bool(self.fcm_private_key.get_secret_value()),
        )
        if any(configured) and not all(configured):
            msg = (
                "fcm_project_id, fcm_client_email and fcm_private_key are"
                " required together"
            )
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
