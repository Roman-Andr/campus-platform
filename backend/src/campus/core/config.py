"""Application settings read from environment variables."""

from functools import lru_cache
from typing import Literal

from pydantic import Field, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict

type Environment = Literal["development", "test", "staging", "production"]
type LogLevel = Literal["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]
type LogFormat = Literal["json", "console"]


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

    sentry_dsn: SecretStr | None = Field(
        default=None, description="Error reporting is disabled when empty."
    )
    sentry_traces_sample_rate: float = Field(default=0.0, ge=0.0, le=1.0)


@lru_cache
def get_settings() -> Settings:
    """Return the process-wide settings, read once on first use."""
    return Settings()
