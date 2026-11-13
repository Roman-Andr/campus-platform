"""Client platform and version headers; outdated clients must update."""

import httpx2
import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from campus.api.app import API_PREFIX
from campus.core.config import ClientPlatform, Settings
from tests.web_app import NOTES_URL

ECHO_URL = f"{NOTES_URL}/echo"


def client_headers(platform: str, version: str) -> dict[str, str]:
    return {"X-Client-Platform": platform, "X-Client-Version": version}


@pytest.mark.parametrize(
    "headers",
    [
        client_headers("android", "1.2.0"),  # the minimum itself
        client_headers("android", "1.10.0"),  # compared as versions, not text
        client_headers("android", "2.0"),
        client_headers("web", "0.0.1"),  # no minimum for the platform
    ],
)
async def test_supported_client_is_served(
    api_without_database: httpx2.AsyncClient, headers: dict[str, str]
) -> None:
    response = await api_without_database.get(
        ECHO_URL, params={"number": 1}, headers=headers
    )

    assert response.status_code == 200


@pytest.mark.parametrize("version", ["1.1.9", "1.2.0rc1", "0.9"])
async def test_outdated_client_must_update(
    api_without_database: httpx2.AsyncClient, version: str
) -> None:
    response = await api_without_database.get(
        ECHO_URL,
        # Invalid parameters too: the version is checked first.
        params={"number": "many"},
        headers={**client_headers("android", version), "Accept-Language": "en"},
    )

    assert response.status_code == 426
    problem = response.json()
    assert problem["code"] == "client_update_required"
    assert problem["min_version"] == "1.2.0"
    assert "1.2.0" in problem["detail"]


@pytest.mark.parametrize("missing", ["X-Client-Platform", "X-Client-Version"])
async def test_request_without_client_headers_is_rejected(
    api_without_database: httpx2.AsyncClient, missing: str
) -> None:
    headers = client_headers("android", "1.2.0")
    del headers[missing]
    api_without_database.headers.pop(missing)

    response = await api_without_database.get(
        ECHO_URL, params={"number": 1}, headers=headers
    )

    assert response.status_code == 400
    assert response.json()["code"] == "client_version_missing"


@pytest.mark.parametrize(
    "headers",
    [
        client_headers("ios", "1.2.0"),
        client_headers("Android", "1.2.0"),
        client_headers("android", "latest"),
    ],
)
async def test_unrecognized_client_is_rejected(
    api_without_database: httpx2.AsyncClient, headers: dict[str, str]
) -> None:
    response = await api_without_database.get(
        ECHO_URL, params={"number": 1}, headers=headers
    )

    assert response.status_code == 400
    assert response.json()["code"] == "client_version_invalid"


@pytest.mark.parametrize("path", ["/health", "/openapi.json", "/docs", "/redoc"])
def test_health_and_docs_need_no_client_headers(client: TestClient, path: str) -> None:
    assert client.get(f"{API_PREFIX}{path}").status_code == 200


def test_minimum_versions_are_read_from_json(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("CAMPUS_CLIENT_MIN_VERSIONS", '{"android": "1.2.0"}')

    settings = Settings()

    assert str(settings.client_min_version(ClientPlatform.ANDROID)) == "1.2.0"
    assert settings.client_min_version(ClientPlatform.WEB) is None


@pytest.mark.parametrize("value", ['{"android": "new"}', '{"ios": "1.0"}'])
def test_invalid_minimum_versions_are_rejected(
    monkeypatch: pytest.MonkeyPatch, value: str
) -> None:
    monkeypatch.setenv("CAMPUS_CLIENT_MIN_VERSIONS", value)

    with pytest.raises(ValidationError):
        Settings()
