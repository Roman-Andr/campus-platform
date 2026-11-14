"""Account downgrades hide discovery, preserving private interactions."""

from uuid import UUID, uuid4

import httpx2
import pytest
from sqlalchemy import update

from campus.modules.identity import User
from tests.test_listings import (
    borrower,
    move,
    owner,
    publish,
    request,
    reserve,
    staff,
)
from tests.test_profile import Account, auth, places

__all__ = ["auth", "borrower", "owner", "places", "staff"]


def problem(response: httpx2.Response, status: int, code: str) -> None:
    assert response.status_code == status, response.text
    assert response.headers["content-type"] == "application/problem+json"
    assert response.json()["status"] == status
    assert response.json()["code"] == code


@pytest.mark.parametrize("account_type", ["alumni", "former_employee"])
@pytest.mark.parametrize(
    "scope",
    [("city", "students"), ("dormitory", "students"), ("dormitory", "community")],
)
async def test_downgrade_preserves_only_existing_interactions(
    *,
    owner: Account,
    borrower: Account,
    staff: Account,
    account_type: str,
    scope: tuple[str, str],
) -> None:
    visibility, audience = scope
    listing = await publish(owner, visibility=visibility, audience=audience)
    other = await publish(owner, visibility=visibility, audience=audience)
    # A previous participant's private events must stay private.
    previous = (await reserve(staff, await publish(owner, audience="community"))).json()
    # Use another student for a previous interaction on this listing.
    visitor = Account(
        owner.auth, await owner.auth.login(email="visitor@university.example")
    )
    profile = (await owner.auth.client.get("/api/v1/me", headers=owner.headers)).json()
    assert (
        await visitor.put(
            {
                key: profile[key]
                for key in ("city_id", "dormitory_id", "faculty_id", "course")
            }
        )
    ).status_code == 200
    old = (await reserve(visitor, listing)).json()
    assert (await move(visitor, listing, old, "cancelled")).status_code == 200
    interaction = (await reserve(borrower, listing)).json()
    assert (await move(owner, listing, interaction, "accepted")).status_code == 200
    # Retain the student course to isolate visibility from #240
    # (former employee profiles without a course cannot transition yet).
    await owner.auth.db.execute(
        update(User)
        .where(
            User.id.in_(
                [
                    UUID(account.tokens["user"]["id"])
                    for account in (owner, borrower, staff)
                ]
            )
        )
        .values(account_type=account_type)
    )
    await owner.auth.db.commit()

    for account in (owner, borrower):
        assert (await request(account, "GET", f"/{listing['id']}")).status_code == 200
        assert (
            await request(account, "GET", f"/{listing['id']}/events")
        ).status_code == 200
        assert (
            await request(
                account,
                "GET",
                f"/{listing['id']}/interactions/{interaction['id']}/events",
            )
        ).status_code == 200
    events = (await request(borrower, "GET", f"/{listing['id']}/events")).json()[
        "items"
    ]
    assert all(event["interaction_id"] in (None, interaction["id"]) for event in events)
    for path in ("", "?area=dormitory"):
        ids = {
            item["id"]
            for item in (await request(borrower, "GET", path)).json()["items"]
        }
        assert listing["id"] not in ids
    for account in (borrower, staff):
        problem(await request(account, "GET", f"/{other['id']}"), 404, "not_found")
    problem(await request(staff, "GET", f"/{listing['id']}"), 404, "not_found")
    problem(await request(borrower, "GET", f"/{uuid4()}"), 404, "not_found")
    problem(
        await request(staff, "GET", f"/{listing['id']}/events"),
        403,
        "listing_forbidden",
    )
    problem(
        await request(
            borrower, "GET", f"/{listing['id']}/interactions/{old['id']}/events"
        ),
        403,
        "listing_forbidden",
    )
    problem(
        await request(
            borrower, "GET", f"/{listing['id']}/interactions/{previous['id']}/events"
        ),
        404,
        "not_found",
    )
    problem(
        await move(visitor, listing, interaction, "cancelled"), 403, "listing_forbidden"
    )
    problem(await reserve(borrower, listing), 403, "listing_forbidden")
    assert (await move(borrower, listing, interaction, "cancelled")).status_code == 200
    # The historical card remains available after finishing the interaction.
    assert (await request(borrower, "GET", f"/{listing['id']}")).status_code == 200
