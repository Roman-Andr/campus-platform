from datetime import UTC, datetime

import httpx2
import pytest
from pydantic import BaseModel, ValidationError

from campus.api.app import create_app
from campus.core.web.datetimes import Instant
from tests.conftest import web_settings
from tests.test_web_problems import assert_problem
from tests.web_app import serve


class Moment(BaseModel):
    at: Instant


@pytest.mark.parametrize("value", ["2026-11-16T18:00:00+05:00", "2026-11-16T13:00:00Z"])
def test_shared_instant_normalizes_to_utc(value: str) -> None:
    moment = Moment(at=value)  # type: ignore[arg-type]
    assert moment.at == datetime(2026, 11, 16, 13, tzinfo=UTC)
    assert moment.at.tzinfo is UTC
    assert moment.model_dump_json() == '{"at":"2026-11-16T13:00:00Z"}'


@pytest.mark.parametrize(
    "value",
    [
        "2026-11-16T18:00:00",
        "2026-11-16",
        1794841200,
        "1794841200",
        "2026-11-16 18:00:00+05:00",
    ],
)
async def test_invalid_wire_instant_is_validation_failed(value: object) -> None:
    app = create_app(web_settings())

    @app.post("/moment")
    async def echo(moment: Moment) -> Moment:
        return moment

    async with serve(app) as client:
        response = await client.post("/moment", json={"at": value})
    assert_problem(response, 422, "validation_failed")


def test_naive_python_datetime_is_rejected() -> None:
    with pytest.raises(ValidationError):
        Moment(at=datetime(2026, 11, 16))  # noqa: DTZ001


async def test_http_response_uses_utc() -> None:
    app = create_app(web_settings())

    @app.get("/moment")
    async def get() -> Moment:
        return Moment(at="2026-11-16T18:00:00+05:00")  # type: ignore[arg-type]

    async with serve(app) as client:
        response: httpx2.Response = await client.get("/moment")
    assert response.json() == {"at": "2026-11-16T13:00:00Z"}
