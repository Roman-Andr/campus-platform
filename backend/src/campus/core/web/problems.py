"""Errors as Problem Details (RFC 9457) with machine-readable codes.

Every error response of the API is a :class:`Problem`: ``code`` is stable
and meant for programs, ``title`` and ``detail`` are in the language of the
request (``Accept-Language``). Domain code raises :class:`ProblemError`
with one of the registered :class:`ProblemType` values; modules declare
their own types next to the code that raises them.

Unhandled exceptions become ``internal_error`` without any details; they
still reach the logs and error reporting.
"""

from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from http import HTTPStatus
from typing import Any, ClassVar

from asgi_correlation_id import correlation_id
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from starlette.exceptions import HTTPException as StarletteHTTPException

from campus.core.config import Locale, Settings
from campus.core.i18n import N_, negotiate, translate

PROBLEM_MEDIA_TYPE = "application/problem+json"
TYPE_PREFIX = "urn:problem:campus:"


@dataclass(frozen=True, slots=True)
class ProblemType:
    """A kind of error: its code, HTTP status and title.

    ``title`` and ``detail`` are English message IDs marked with ``N_``;
    ``detail`` may refer to parameters of :class:`ProblemError` as
    ``{name}``. Creating a type registers its code.
    """

    code: str
    status: int
    title: str
    detail: str | None = None

    registry: ClassVar[dict[str, ProblemType]] = {}

    def __post_init__(self) -> None:
        if self.code in ProblemType.registry:
            msg = f"problem code {self.code!r} is already registered"
            raise ValueError(msg)
        ProblemType.registry[self.code] = self

    @property
    def uri(self) -> str:
        """The ``type`` member of the problem."""
        return TYPE_PREFIX + self.code


BAD_REQUEST = ProblemType("bad_request", 400, N_("Bad request"))
NOT_FOUND = ProblemType(
    "not_found", 404, N_("Not found"), N_("The requested resource does not exist.")
)
METHOD_NOT_ALLOWED = ProblemType(
    "method_not_allowed",
    405,
    N_("Method not allowed"),
    N_("The resource does not support this method."),
)
HTTP_ERROR = ProblemType("http_error", 400, N_("Request failed"))
VALIDATION_FAILED = ProblemType(
    "validation_failed",
    422,
    N_("Invalid request"),
    N_("Some fields of the request are invalid."),
)
INTERNAL_ERROR = ProblemType(
    "internal_error",
    500,
    N_("Internal error"),
    N_("Something went wrong on our side. Please try again later."),
)


class FieldError(BaseModel):
    """One invalid part of the request.

    Exactly one of ``pointer`` (JSON Pointer into the body, RFC 6901, as a
    URI fragment), ``parameter`` (query or path parameter) and ``header``
    names the part.
    """

    detail: str = Field(description="What is wrong, in the request language.")
    code: str = Field(description="Machine-readable reason, e.g. 'missing'.")
    pointer: str | None = Field(default=None, examples=["#/title"])
    parameter: str | None = Field(default=None, examples=["size"])
    header: str | None = Field(default=None, examples=["Idempotency-Key"])


class Problem(BaseModel):
    """Error response (RFC 9457 Problem Details)."""

    type: str = Field(examples=["urn:problem:campus:not_found"])
    title: str = Field(description="Short summary in the request language.")
    status: int
    detail: str | None = Field(
        default=None, description="Explanation in the request language."
    )
    code: str = Field(description="Machine-readable error code.")
    request_id: str | None = Field(
        default=None, description="X-Request-ID of the request, for support."
    )
    errors: list[FieldError] | None = None
    current_version: int | None = Field(
        default=None, description="Current aggregate version after a stale edit."
    )
    min_version: str | None = Field(
        default=None,
        description="Oldest supported client version (client_update_required).",
    )


class ProblemError(Exception):
    """Raise to answer with a problem of ``problem_type``.

    ``params`` fill the ``{name}`` placeholders of the type's detail;
    ``min_version`` and ``errors`` become members of the problem, ``headers``
    are added to the response.
    """

    def __init__(
        self,
        problem_type: ProblemType,
        *,
        errors: Sequence[FieldError] = (),
        min_version: str | None = None,
        headers: Mapping[str, str] | None = None,
        **params: object,
    ) -> None:
        super().__init__(problem_type.code)
        self.problem_type = problem_type
        self.errors = list(errors)
        self.min_version = min_version
        self.headers = dict(headers or {})
        self.params = params


class ProblemResponse(JSONResponse):
    """JSON response with the ``application/problem+json`` media type."""

    media_type = PROBLEM_MEDIA_TYPE


def request_locale(request: Request) -> Locale:
    """Language of messages for ``request``, from ``Accept-Language``."""
    settings: Settings = request.app.state.settings
    return negotiate(request.headers.get("accept-language"), settings.default_locale)


def problem_response(  # noqa: PLR0913 - the members of a problem
    request: Request,
    problem_type: ProblemType,
    *,
    status: int | None = None,
    errors: Sequence[FieldError] = (),
    min_version: str | None = None,
    headers: Mapping[str, str] | None = None,
    params: Mapping[str, object] | None = None,
    current_version: int | None = None,
) -> ProblemResponse:
    """Render ``problem_type`` in the language of ``request``."""
    locale = request_locale(request)
    status = status or problem_type.status
    problem = Problem(
        type=problem_type.uri,
        title=translate(problem_type.title, locale),
        status=status,
        detail=(
            translate(problem_type.detail, locale, **(params or {}))
            if problem_type.detail
            else None
        ),
        code=problem_type.code,
        request_id=correlation_id.get(),
        errors=list(errors) or None,
        min_version=min_version,
        current_version=current_version,
    )
    return ProblemResponse(
        problem.model_dump(mode="json", exclude_none=True),
        status_code=status,
        headers=dict(headers or {}),
    )


# Messages of common validation errors (pydantic error types); others keep
# pydantic's English message.
VALIDATION_MESSAGES = {
    "missing": N_("This field is required."),
    "extra_forbidden": N_("This field is not allowed."),
    "string_type": N_("Must be a string."),
    "string_too_short": N_("Must be at least {min_length} characters long."),
    "string_too_long": N_("Must be at most {max_length} characters long."),
    "string_pattern_mismatch": N_("Has an invalid format."),
    "too_short": N_("Must have at least {min_length} items."),
    "too_long": N_("Must have at most {max_length} items."),
    "int_type": N_("Must be an integer."),
    "int_parsing": N_("Must be an integer."),
    "int_from_float": N_("Must be an integer."),
    "float_type": N_("Must be a number."),
    "float_parsing": N_("Must be a number."),
    "bool_type": N_("Must be true or false."),
    "bool_parsing": N_("Must be true or false."),
    "greater_than": N_("Must be greater than {gt}."),
    "greater_than_equal": N_("Must be at least {ge}."),
    "less_than": N_("Must be less than {lt}."),
    "less_than_equal": N_("Must be at most {le}."),
    "uuid_type": N_("Must be a UUID."),
    "uuid_parsing": N_("Must be a UUID."),
    "enum": N_("Must be one of: {expected}."),
    "literal_error": N_("Must be one of: {expected}."),
    "datetime_offset": N_("Use RFC 3339 with an explicit UTC offset."),
    "timezone_aware": N_("Use RFC 3339 with an explicit UTC offset."),
    "datetime_type": N_("Must be a date and time."),
    "datetime_parsing": N_("Must be a date and time."),
    "datetime_from_date_parsing": N_("Must be a date and time."),
    "date_type": N_("Must be a date."),
    "date_parsing": N_("Must be a date."),
    "json_invalid": N_("The request body is not valid JSON."),
    "model_attributes_type": N_("Must be an object."),
    "dict_type": N_("Must be an object."),
    "list_type": N_("Must be a list."),
}


def _escape_pointer_token(token: object) -> str:
    return str(token).replace("~", "~0").replace("/", "~1")


def field_error(error: Mapping[str, Any], locale: Locale) -> FieldError:
    """Turn one pydantic validation error into a localized field error."""
    error_type = str(error.get("type", "value_error"))
    template = VALIDATION_MESSAGES.get(error_type)
    if template is None:
        detail = str(error.get("msg", ""))
    else:
        detail = translate(template, locale, **error.get("ctx", {}))
    location: tuple[Any, ...] = tuple(error.get("loc", ()))
    source, path = (location[0], location[1:]) if location else ("body", ())
    if source == "body":
        pointer = "#" + "".join(f"/{_escape_pointer_token(token)}" for token in path)
        return FieldError(detail=detail, code=error_type, pointer=pointer)
    name = str(path[0]) if path else ""
    if source == "header":
        return FieldError(detail=detail, code=error_type, header=name)
    return FieldError(detail=detail, code=error_type, parameter=name)


async def _handle_problem(request: Request, exc: Exception) -> ProblemResponse:
    assert isinstance(exc, ProblemError)  # noqa: S101 - registered for it
    return problem_response(
        request,
        exc.problem_type,
        errors=exc.errors,
        min_version=exc.min_version,
        headers=exc.headers,
        params=exc.params,
    )


async def _handle_http_exception(request: Request, exc: Exception) -> ProblemResponse:
    assert isinstance(exc, StarletteHTTPException)  # noqa: S101 - registered for it
    by_status = {
        HTTPStatus.BAD_REQUEST.value: BAD_REQUEST,
        HTTPStatus.NOT_FOUND.value: NOT_FOUND,
        HTTPStatus.METHOD_NOT_ALLOWED.value: METHOD_NOT_ALLOWED,
    }
    problem_type = by_status.get(exc.status_code, HTTP_ERROR)
    return problem_response(
        request, problem_type, status=exc.status_code, headers=exc.headers
    )


async def _handle_validation_error(request: Request, exc: Exception) -> ProblemResponse:
    assert isinstance(exc, RequestValidationError)  # noqa: S101 - registered for it
    locale = request_locale(request)
    errors = [field_error(error, locale) for error in exc.errors()]
    return problem_response(request, VALIDATION_FAILED, errors=errors)


async def _handle_unexpected(request: Request, _exc: Exception) -> ProblemResponse:
    # The traceback goes to the server log and error reporting, not to clients.
    return problem_response(request, INTERNAL_ERROR)


def install_problem_handlers(app: FastAPI) -> None:
    """Answer every error of ``app`` with a :class:`Problem`."""
    app.add_exception_handler(ProblemError, _handle_problem)
    app.add_exception_handler(StarletteHTTPException, _handle_http_exception)
    app.add_exception_handler(RequestValidationError, _handle_validation_error)
    app.add_exception_handler(Exception, _handle_unexpected)


def use_problem_media_type(schema: dict[str, Any]) -> dict[str, Any]:
    """Document error responses (4xx, 5xx) as ``application/problem+json``.

    Also lists the registered problem codes as the enum of ``Problem.code``.
    """
    for path_item in schema.get("paths", {}).values():
        for operation in path_item.values():
            for status, response in operation.get("responses", {}).items():
                content = response.get("content", {})
                if status[0] in "45" and "application/json" in content:
                    content[PROBLEM_MEDIA_TYPE] = content.pop("application/json")
    problem = schema.get("components", {}).get("schemas", {}).get("Problem")
    if problem is not None:
        problem["properties"]["code"]["enum"] = sorted(ProblemType.registry)
    return schema
