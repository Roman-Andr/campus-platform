"""Every API error is Problem Details with a code, in the request language."""

from typing import Any

import httpx2
import pytest
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from starlette.exceptions import HTTPException

from campus.api.app import API_PREFIX
from campus.core.web.problems import (
    PROBLEM_MEDIA_TYPE,
    ProblemType,
    field_error,
    install_problem_handlers,
)
from tests.conftest import web_settings
from tests.web_app import NOTES_URL, serve

ECHO_URL = f"{NOTES_URL}/echo"


def assert_problem(response: httpx2.Response, status: int, code: str) -> dict[str, Any]:
    assert response.status_code == status
    assert response.headers["content-type"] == PROBLEM_MEDIA_TYPE
    problem: dict[str, Any] = response.json()
    assert problem["status"] == status
    assert problem["code"] == code
    assert problem["type"] == f"urn:problem:campus:{code}"
    assert problem["title"]
    return problem


async def test_success_is_not_a_problem(
    api_without_database: httpx2.AsyncClient,
) -> None:
    response = await api_without_database.get(ECHO_URL, params={"number": 3})

    assert response.status_code == 200
    assert response.json() == {"number": 3}


async def test_unknown_path_is_not_found(
    api_without_database: httpx2.AsyncClient,
) -> None:
    response = await api_without_database.get(f"{API_PREFIX}/nowhere")

    problem = assert_problem(response, 404, "not_found")
    assert problem["request_id"] == response.headers["X-Request-ID"]


async def test_wrong_method_is_not_allowed(
    api_without_database: httpx2.AsyncClient,
) -> None:
    response = await api_without_database.put(f"{API_PREFIX}/health")

    assert_problem(response, 405, "method_not_allowed")
    assert response.headers["Allow"] == "GET"


@pytest.mark.parametrize(
    ("accept_language", "title"),
    [
        ("en-US,en;q=0.9", "Invalid request"),
        ("ru-RU,ru;q=0.9,en;q=0.8", "Неверные данные запроса"),
        ("de", "Неверные данные запроса"),  # unsupported: the default, ru
        (None, "Неверные данные запроса"),
    ],
)
async def test_query_validation_error_is_localized(
    api_without_database: httpx2.AsyncClient,
    accept_language: str | None,
    title: str,
) -> None:
    headers = {"Accept-Language": accept_language} if accept_language else {}

    response = await api_without_database.get(
        ECHO_URL, params={"number": 11}, headers=headers
    )

    problem = assert_problem(response, 422, "validation_failed")
    assert problem["title"] == title
    [error] = problem["errors"]
    assert error["parameter"] == "number"
    assert error["code"] == "less_than_equal"
    assert "10" in error["detail"]


async def test_body_validation_errors_point_into_the_body(
    api: httpx2.AsyncClient,
) -> None:
    response = await api.post(
        NOTES_URL,
        json={"title": "", "extra": {"a/b": 1}},
        headers={"Idempotency-Key": "0193a0c4-7b8e-7d3c-9f1e-2a4b6c8d0e1f"},
    )

    problem = assert_problem(response, 422, "validation_failed")
    assert problem["errors"] == [
        {
            "pointer": "#/title",
            "code": "string_too_short",
            "detail": "Минимальная длина — 1.",
        }
    ]


async def test_malformed_json_body(api: httpx2.AsyncClient) -> None:
    response = await api.post(
        NOTES_URL,
        content=b"{not json",
        headers={
            "Idempotency-Key": "0193a0c4-7b8e-7d3c-9f1e-2a4b6c8d0e1f",
            "Content-Type": "application/json",
            "Accept-Language": "en",
        },
    )

    problem = assert_problem(response, 422, "validation_failed")
    assert problem["errors"][0]["code"] == "json_invalid"
    assert problem["errors"][0]["detail"] == "The request body is not valid JSON."


async def test_internal_error_hides_details(
    api_without_database: httpx2.AsyncClient,
) -> None:
    response = await api_without_database.get(f"{NOTES_URL}/crash")

    problem = assert_problem(response, 500, "internal_error")
    assert "secret" not in response.text
    assert "Traceback" not in response.text
    assert set(problem) == {"type", "title", "status", "detail", "code", "request_id"}


def test_field_error_locations() -> None:
    def locate(*location: object) -> dict[str, str]:
        error = field_error({"type": "missing", "loc": location}, "en")
        return error.model_dump(exclude_none=True, exclude={"detail", "code"})

    assert locate("body") == {"pointer": "#"}
    assert locate("body", "tags", 0, "a~b/c") == {"pointer": "#/tags/0/a~0b~1c"}
    assert locate("query", "size") == {"parameter": "size"}
    assert locate("path", "id") == {"parameter": "id"}
    assert locate("header", "X-Client-Version") == {"header": "X-Client-Version"}


def test_unknown_validation_error_keeps_pydantic_message() -> None:
    error = field_error(
        {"type": "value_error", "loc": ("body", "x"), "msg": "Value error, bad"}, "ru"
    )

    assert error.detail == "Value error, bad"


def test_problem_codes_are_unique() -> None:
    with pytest.raises(ValueError, match="already registered"):
        ProblemType("not_found", 404, "Not found")


async def test_other_http_errors_keep_their_status() -> None:
    app = FastAPI()
    app.state.settings = web_settings()
    install_problem_handlers(app)

    @app.get("/teapot")
    async def teapot() -> None:
        raise HTTPException(418, headers={"X-Extra": "1"})

    @app.get("/bad")
    async def bad(request: Request) -> None:
        del request
        raise HTTPException(400)

    @app.get("/invalid")
    async def invalid() -> None:
        raise RequestValidationError([])

    async with serve(app) as client:
        teapot_response = await client.get("/teapot")
        bad_response = await client.get("/bad")
        invalid_response = await client.get("/invalid")

    assert_problem(teapot_response, 418, "http_error")
    assert teapot_response.headers["X-Extra"] == "1"
    assert_problem(bad_response, 400, "bad_request")
    assert "errors" not in assert_problem(invalid_response, 422, "validation_failed")


async def test_endpoint_needing_database_fails_without_one(
    api_without_database: httpx2.AsyncClient,
) -> None:
    response = await api_without_database.get(NOTES_URL)

    assert_problem(response, 500, "internal_error")
