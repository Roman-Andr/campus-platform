"""Read API of the university reference data for clients.

The lists are short and change rarely, so each is returned whole (clients
cache them) rather than page by page. Names are in the language of the
request (``Accept-Language``); the language is echoed in
``Content-Language``. The data is public: it is needed before sign-in,
e.g. to pick a city at registration.
"""

from typing import Annotated, Any
from uuid import UUID

from fastapi import Query, Request, Response
from pydantic import BaseModel, Field
from sqlalchemy import Select, select
from sqlalchemy.ext.asyncio import AsyncSession

from campus.core.config import Locale
from campus.core.web import DbSession, api_router, request_locale
from campus.modules.university.models import (
    AccountType,
    City,
    Dormitory,
    EmailDomain,
    Faculty,
)

router = api_router(prefix="/university", tags=["university"])


class CityOut(BaseModel):
    """A campus city."""

    id: UUID
    code: str = Field(examples=["moscow"])
    name: str = Field(description="In the request language.", examples=["Moscow"])
    timezone: str = Field(
        description="IANA time zone; times in the city are shown in it.",
        examples=["Europe/Moscow"],
    )


class CityPlaceOut(BaseModel):
    """A dormitory or faculty of a campus city."""

    id: UUID
    city_id: UUID
    city_timezone: str
    code: str = Field(examples=["dubki"])
    name: str = Field(description="In the request language.", examples=["Dubki"])


class EmailDomainOut(BaseModel):
    """An e-mail domain allowed to register."""

    domain: str = Field(examples=["edu.hse.ru"])
    account_type: AccountType = Field(
        description="Type of the accounts registered with addresses of the domain."
    )


class CityList(BaseModel):
    items: list[CityOut]


class CityPlaceList(BaseModel):
    items: list[CityPlaceOut]


class EmailDomainList(BaseModel):
    items: list[EmailDomainOut]


CityFilter = Annotated[UUID | None, Query(description="Only those of this city.")]


def _localized(request: Request, response: Response) -> Locale:
    locale = request_locale(request)
    response.headers["Content-Language"] = locale
    response.headers["Vary"] = "Accept-Language"
    return locale


type Reference = City | Dormitory | Faculty


def _by_name[Q: Select[Any]](query: Q, model: type[Reference], locale: Locale) -> Q:
    return query.order_by(model.name_column(locale), model.id)


@router.get("/cities")
async def list_cities(
    request: Request, response: Response, session: DbSession
) -> CityList:
    """All campus cities, by name."""
    locale = _localized(request, response)
    cities = await session.scalars(_by_name(select(City), City, locale))
    return CityList(
        items=[
            CityOut(
                id=city.id,
                code=city.code,
                name=city.name_in(locale),
                timezone=city.timezone,
            )
            for city in cities
        ]
    )


async def _places(
    session: AsyncSession,
    model: type[Dormitory | Faculty],
    locale: Locale,
    city_id: UUID | None,
) -> CityPlaceList:
    query: Select[Dormitory | Faculty] = select(model)
    if city_id is not None:
        query = query.where(model.city_id == city_id)
    places = await session.scalars(_by_name(query, model, locale))
    city_zones = await session.execute(select(City.id, City.timezone))
    timezones = dict(city_zones.all())
    return CityPlaceList(
        items=[
            CityPlaceOut(
                id=place.id,
                city_id=place.city_id,
                city_timezone=timezones[place.city_id],
                code=place.code,
                name=place.name_in(locale),
            )
            for place in places
        ]
    )


@router.get("/dormitories")
async def list_dormitories(
    request: Request,
    response: Response,
    session: DbSession,
    city_id: CityFilter = None,
) -> CityPlaceList:
    """Dormitories of all cities or of one city, by name."""
    locale = _localized(request, response)
    return await _places(session, Dormitory, locale, city_id)


@router.get("/faculties")
async def list_faculties(
    request: Request,
    response: Response,
    session: DbSession,
    city_id: CityFilter = None,
) -> CityPlaceList:
    """Faculties of all cities or of one city, by name."""
    locale = _localized(request, response)
    return await _places(session, Faculty, locale, city_id)


@router.get("/email-domains")
async def list_email_domains(session: DbSession) -> EmailDomainList:
    """E-mail domains whose addresses may register, by domain."""
    domains = await session.scalars(select(EmailDomain).order_by(EmailDomain.domain))
    return EmailDomainList(
        items=[
            EmailDomainOut(domain=domain.domain, account_type=domain.account_type)
            for domain in domains
        ]
    )
