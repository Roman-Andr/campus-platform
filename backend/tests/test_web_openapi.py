"""The OpenAPI schema documents the conventions on every API endpoint."""

from typing import Any

import pytest
from fastapi import FastAPI
from fastapi.routing import APIRoute, iter_route_contexts

from campus.api.app import create_app
from campus.core.config import Settings
from campus.core.web import ApiRoute, ProblemType
from campus.core.web.routing import MUTATING_METHODS
from tests.web_app import create_test_app

PROBLEM = "application/problem+json"


@pytest.fixture(params=["production", "with_test_router"])
def app(request: pytest.FixtureRequest, settings: Settings) -> FastAPI:
    """The real application, and one with the test router mounted."""
    if request.param == "production":
        return create_app(settings)
    return create_test_app(settings)


def operations(app: FastAPI) -> list[tuple[APIRoute, str, dict[str, Any]]]:
    """Documented operations: (route, method, OpenAPI operation)."""
    schema = app.openapi()
    result = []
    for context in iter_route_contexts(app.routes):
        route = context.original_route
        if not isinstance(route, APIRoute) or not route.include_in_schema:
            continue
        # The context carries the path with the prefixes of included routers.
        path_item = schema["paths"][context.path_format]
        methods = route.methods or set()
        result += [(route, method, path_item[method.lower()]) for method in methods]
    return result


def header_parameters(operation: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {
        parameter["name"]: parameter
        for parameter in operation.get("parameters", [])
        if parameter["in"] == "header"
    }


def test_every_mutating_operation_requires_idempotency_key(app: FastAPI) -> None:
    for route, method, operation in operations(app):
        if method not in MUTATING_METHODS:
            continue
        assert isinstance(route, ApiRoute), route.path_format
        key = header_parameters(operation).get("Idempotency-Key")
        assert key is not None, f"{method} {route.path}"
        assert key["required"] is True
        assert key["schema"]["format"] == "uuid"


def test_every_api_operation_documents_client_headers_and_426(app: FastAPI) -> None:
    api_operations = [
        (route, operation)
        for route, _, operation in operations(app)
        if isinstance(route, ApiRoute)
    ]
    for route, operation in api_operations:
        headers = header_parameters(operation)
        assert headers["X-Client-Platform"]["required"] is True, route.path
        assert headers["X-Client-Version"]["required"] is True, route.path
        assert "426" in operation["responses"], route.path


def test_error_responses_are_problems(app: FastAPI) -> None:
    for route, _, operation in operations(app):
        for status, response in operation["responses"].items():
            if status[0] in "45":
                assert list(response["content"]) == [PROBLEM], (route.path, status)
                schema = response["content"][PROBLEM]["schema"]
                assert schema == {"$ref": "#/components/schemas/Problem"}


@pytest.mark.parametrize(
    ("path", "model"),
    [
        ("/api/v1/chats", "ChatOutput"),
        ("/api/v1/chats/{chat_id}/messages", "MessageOutput"),
    ],
)
def test_chat_success_responses_document_models(
    app: FastAPI, path: str, model: str
) -> None:
    responses = app.openapi()["paths"][path]["post"]["responses"]

    assert {"200", "201"} <= set(responses)
    for status in ("200", "201"):
        assert responses[status]["content"]["application/json"]["schema"] == {
            "$ref": f"#/components/schemas/{model}"
        }


def test_problem_codes_are_listed(settings: Settings) -> None:
    schema = create_test_app(settings).openapi()

    codes = schema["components"]["schemas"]["Problem"]["properties"]["code"]["enum"]

    assert codes == sorted(ProblemType.registry)
    assert {"client_update_required", "idempotency_key_reused"} <= set(codes)


def test_test_router_is_covered(settings: Settings) -> None:
    # Guards the tests above against passing vacuously.
    app = create_test_app(settings)
    methods = {method for _, method, _ in operations(app)}

    assert {"GET", "POST", "DELETE"} <= methods


def test_schema_is_generated_once(settings: Settings) -> None:
    app = create_app(settings)

    assert app.openapi() is app.openapi()
