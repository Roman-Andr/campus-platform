from datetime import timedelta
from pathlib import Path

import pytest
from pydantic import ValidationError

from campus.core.config import Settings, get_settings

ENV_EXAMPLE = Path(__file__).parents[1] / ".env.example"


def test_defaults_need_no_environment() -> None:
    settings = Settings()

    assert settings.environment == "development"
    assert settings.log_format == "json"
    assert settings.sentry_dsn is None


def test_values_are_read_from_prefixed_environment_variables(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("CAMPUS_ENVIRONMENT", "production")
    monkeypatch.setenv("CAMPUS_LOG_LEVEL", "DEBUG")
    monkeypatch.setenv("CAMPUS_API_HOST", "0.0.0.0")  # noqa: S104
    monkeypatch.setenv("CAMPUS_API_PORT", "9000")
    monkeypatch.setenv("CAMPUS_SENTRY_DSN", "https://key@errors.example.org/1")
    monkeypatch.setenv("CAMPUS_SENTRY_TRACES_SAMPLE_RATE", "0.5")
    monkeypatch.setenv("CAMPUS_RELEASE", "abc123")

    settings = Settings()

    assert settings.environment == "production"
    assert settings.log_level == "DEBUG"
    assert settings.api_host == "0.0.0.0"  # noqa: S104
    assert settings.api_port == 9000
    assert settings.sentry_dsn is not None
    assert settings.sentry_dsn.get_secret_value() == "https://key@errors.example.org/1"
    assert settings.sentry_traces_sample_rate == 0.5
    assert settings.release == "abc123"


def test_values_are_read_from_dotenv_file(tmp_path: Path) -> None:
    (tmp_path / ".env").write_text("CAMPUS_LOG_FORMAT=console\n")

    assert Settings().log_format == "console"


def test_environment_variable_overrides_dotenv_file(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    (tmp_path / ".env").write_text("CAMPUS_API_PORT=9000\n")
    monkeypatch.setenv("CAMPUS_API_PORT", "9001")

    assert Settings().api_port == 9001


@pytest.mark.parametrize(
    ("name", "value"),
    [
        ("CAMPUS_ENVIRONMENT", "qa"),
        ("CAMPUS_LOG_LEVEL", "LOUD"),
        ("CAMPUS_API_PORT", "0"),
        ("CAMPUS_SENTRY_TRACES_SAMPLE_RATE", "1.5"),
    ],
)
def test_invalid_values_are_rejected(
    monkeypatch: pytest.MonkeyPatch, name: str, value: str
) -> None:
    monkeypatch.setenv(name, value)

    with pytest.raises(ValidationError):
        Settings()


def test_sentry_dsn_is_hidden_from_repr(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("CAMPUS_SENTRY_DSN", "https://key@errors.example.org/1")

    assert "key@" not in repr(Settings())


def test_settings_are_read_once_per_process(monkeypatch: pytest.MonkeyPatch) -> None:
    first = get_settings()
    monkeypatch.setenv("CAMPUS_API_PORT", "9000")

    assert get_settings() is first


def test_env_example_lists_every_setting() -> None:
    names = {
        line.split("=", 1)[0]
        for line in ENV_EXAMPLE.read_text().splitlines()
        if line and not line.startswith("#")
    }

    assert names == {f"CAMPUS_{field.upper()}" for field in Settings.model_fields}


def test_env_example_gives_working_defaults(tmp_path: Path) -> None:
    (tmp_path / ".env").write_text(ENV_EXAMPLE.read_text())

    settings = Settings()

    assert settings == Settings(_env_file=None)
    assert settings.sentry_dsn is None
    assert settings.release is None


def test_empty_value_means_default(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("CAMPUS_SENTRY_DSN", "")

    assert Settings().sentry_dsn is None


def test_api_convention_defaults() -> None:
    settings = Settings()

    assert settings.default_locale == "ru"
    assert settings.client_min_versions == {}
    assert settings.idempotency_key_ttl == timedelta(hours=24)
    assert (settings.page_size_default, settings.page_size_max) == (20, 100)


def test_idempotency_key_ttl_accepts_iso_duration(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("CAMPUS_IDEMPOTENCY_KEY_TTL", "PT1H")

    assert Settings().idempotency_key_ttl == timedelta(hours=1)


def test_default_page_size_must_not_exceed_maximum(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("CAMPUS_PAGE_SIZE_DEFAULT", "50")
    monkeypatch.setenv("CAMPUS_PAGE_SIZE_MAX", "40")

    with pytest.raises(ValidationError, match="page_size_default"):
        Settings()
