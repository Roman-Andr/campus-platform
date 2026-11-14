"""Shared HTTP conventions of the API (specification, 4.6).

Problem Details errors, client version checks, idempotent mutating
requests in a request transaction, and cursor pagination. Domain modules
build their routers with :func:`api_router`.
"""

from campus.core.web.auth import CurrentUser, Principal
from campus.core.web.pagination import Page, PageParams, PageQuery, paginate, sort_by
from campus.core.web.problems import (
    FieldError,
    Problem,
    ProblemError,
    ProblemType,
    install_problem_handlers,
    request_locale,
    use_problem_media_type,
)
from campus.core.web.routing import ApiRoute, DbSession, api_router

__all__ = [
    "ApiRoute",
    "CurrentUser",
    "DbSession",
    "FieldError",
    "Page",
    "PageParams",
    "PageQuery",
    "Principal",
    "Problem",
    "ProblemError",
    "ProblemType",
    "api_router",
    "install_problem_handlers",
    "paginate",
    "request_locale",
    "sort_by",
    "use_problem_media_type",
]
