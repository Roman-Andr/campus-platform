from fastapi.testclient import TestClient


def test_health_returns_ok(client: TestClient) -> None:
    response = client.get("/api/v1/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_openapi_schema_is_served_under_api_prefix(client: TestClient) -> None:
    response = client.get("/api/v1/openapi.json")

    assert response.status_code == 200
    schema = response.json()
    assert schema["info"]["title"] == "Campus API"
    assert schema["paths"]["/api/v1/health"]["get"]["operationId"] == "get_health"


def test_interactive_docs_are_served_under_api_prefix(client: TestClient) -> None:
    for path in ("/api/v1/docs", "/api/v1/redoc"):
        response = client.get(path)

        assert response.status_code == 200
        assert "text/html" in response.headers["content-type"]


def test_docs_are_not_served_outside_api_prefix(client: TestClient) -> None:
    for path in ("/docs", "/openapi.json"):
        assert client.get(path).status_code == 404


def test_response_carries_request_id(client: TestClient) -> None:
    response = client.get("/api/v1/health", headers={"X-Request-ID": "a" * 32})

    assert response.headers["X-Request-ID"] == "a" * 32
    assert client.get("/api/v1/health").headers["X-Request-ID"]
