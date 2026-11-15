"""Read endpoint of the derived profile rating and counters."""

from typing import Literal
from uuid import UUID

from fastapi import Request
from pydantic import BaseModel, Field

from campus.core.web import CurrentUser, DbSession, Problem, api_router
from campus.modules.reputation.aggregates import (
    ProfileReputation,
    profile_reputation,
)

reputation_router = api_router(
    prefix="/users/{user_id}/reputation",
    tags=["Reputation"],
    responses={
        401: {"model": Problem},
        404: {"model": Problem},
        422: {"model": Problem},
    },
)


class TagCountOutput(BaseModel):
    """How many public reviews about the profile carry one ready-made tag."""

    tag: str = Field(description="Stable tag code of the review scenario.")
    count: int = Field(ge=0)


class ProfileReputationOutput(BaseModel):
    """The aggregates a profile page may show; never a contact address."""

    user_id: UUID
    rating: float | None = Field(
        description=(
            "Smoothed rating R = (C*m + sum(w*r)) / (C + sum(w)); null when"
            " fewer than 4 eligible ratings exist or no average can be formed."
        )
    )
    rating_state: Literal["rated", "few_reviews"] = Field(
        description=(
            "``few_reviews`` while the profile has up to 3 eligible ratings:"
            " the client shows the label instead of a number."
        )
    )
    rating_count: int = Field(
        ge=0,
        description=(
            "Eligible ratings: published, not hidden by moderation and within"
            " the pair limit of the UTC calendar month."
        ),
    )
    completed_interactions: int = Field(
        ge=0, description="Completed interactions of either side of the profile."
    )
    no_shows: int = Field(
        ge=0,
        description=(
            "Counted no-shows only: a disputed or removed mark is not final"
            " and is not included."
        ),
    )
    cancelled_after_acceptance: int = Field(
        ge=0, description="Cancellations the user made after the acceptance."
    )
    late_cancellations: int = Field(
        ge=0, description="Late cancellations charged to the user."
    )
    tags: list[TagCountOutput] = Field(
        description=(
            "Tag counters of the public reviews about the user, most used first."
        )
    )


def output(value: ProfileReputation) -> ProfileReputationOutput:
    ordered = sorted(value.tag_counts.items(), key=lambda item: (-item[1], item[0]))
    return ProfileReputationOutput(
        user_id=value.user_id,
        rating=value.rating,
        rating_state=value.rating_state,
        rating_count=value.rating_count,
        completed_interactions=value.completed_interactions,
        no_shows=value.no_shows,
        cancelled_after_acceptance=value.cancelled_after_acceptance,
        late_cancellations=value.late_cancellations,
        tags=[TagCountOutput(tag=tag, count=count) for tag, count in ordered],
    )


@reputation_router.get("")
async def read_profile_reputation(
    user_id: UUID,
    request: Request,
    session: DbSession,
    principal: CurrentUser,  # noqa: ARG001 - the sign-in check is the dependency
) -> ProfileReputationOutput:
    """The public aggregates of a profile: any signed-in user sees the same.

    The response carries no contact data, and the counters never include a
    review that is not published or is hidden by moderation, so the rating
    and the tags cannot reveal such a review. A profile without enough
    eligible ratings reports ``few_reviews`` and no number.
    """
    value = await profile_reputation(session, user_id, request.app.state.settings)
    return output(value)
