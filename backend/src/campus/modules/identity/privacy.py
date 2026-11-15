"""Owner-scoped contact preferences and the directional personal block.

The block table is directional, but every domain check treats a block as
mutual: messages and new responses are refused in both directions, while the
started interaction paths keep working. The advisory lock serializes a block
change with a concurrent message or response, so no request can observe the
old state and commit after the new one.
"""

from uuid import UUID

from sqlalchemy import and_, exists, or_, select, text
from sqlalchemy.ext.asyncio import AsyncSession

from campus.modules.identity.models import Block


async def serialize_contact_pair(
    session: AsyncSession, first: UUID, second: UUID
) -> None:
    """Queue contact-changing requests of one pair in a stable order.

    A message and a block of the same pair take the same lock, so either the
    message commits before the block or it observes the committed block.
    """
    low, high = (first, second) if first < second else (second, first)
    await session.execute(
        text("SELECT pg_advisory_xact_lock(hashtextextended(:key, 0))"),
        {"key": f"identity-contact:{low}:{high}"},
    )


async def blocked_between(session: AsyncSession, first: UUID, second: UUID) -> bool:
    """Whether either user has blocked the other."""
    found = await session.scalar(
        select(
            exists().where(
                or_(
                    and_(
                        Block.blocker_id == first,
                        Block.blocked_id == second,
                    ),
                    and_(
                        Block.blocker_id == second,
                        Block.blocked_id == first,
                    ),
                )
            )
        )
    )
    return bool(found)
