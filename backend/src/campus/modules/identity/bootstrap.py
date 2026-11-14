"""One-time, transactional administrator bootstrap for deployment."""

from pydantic import BaseModel, EmailStr, Field, field_validator
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from campus.core import clock
from campus.modules.identity.models import User, UserEmail
from campus.modules.identity.roles import Role, RoleAssignment
from campus.modules.university import EmailDomain


class FirstAdminInput(BaseModel):
    email: EmailStr
    first_name: str = Field(min_length=1, max_length=100)
    last_name: str = Field(min_length=1, max_length=100)

    @field_validator("email", "first_name", "last_name", mode="before")
    @classmethod
    def normalize(cls, value: str) -> str:
        return value.strip()

    @field_validator("email")
    @classmethod
    def lowercase(cls, value: str) -> str:
        return value.lower()


async def create_first_admin(session: AsyncSession, data: FirstAdminInput) -> User:
    """Create or reuse an account; caller owns the transaction.

    Serialize bootstrap attempts, including on an empty database. The lock
    also conflicts with role inserts so another bootstrap cannot pass the
    empty-admin check concurrently.
    """
    await session.execute(text("LOCK TABLE identity_role_assignment IN EXCLUSIVE MODE"))
    if (
        await session.scalar(
            select(RoleAssignment.id)
            .where(RoleAssignment.role == Role.ADMINISTRATOR)
            .limit(1)
        )
        is not None
    ):
        raise ValueError("An administrator already exists.")
    domain = await session.scalar(
        select(EmailDomain).where(EmailDomain.domain == data.email.rpartition("@")[2])
    )
    if domain is None:
        raise ValueError("E-mail domain is not allowed.")
    user = await session.scalar(
        select(User)
        .join(UserEmail, UserEmail.user_id == User.id)
        .where(UserEmail.email == data.email)
    )
    if user is None:
        user = User(
            email=data.email,
            first_name=data.first_name,
            last_name=data.last_name,
            account_type=domain.account_type.value,
        )
        session.add(user)
        await session.flush()
        session.add(
            UserEmail(
                user_id=user.id,
                email=data.email,
                kind="corporate",
                verified_at=clock.now(),
            )
        )
    session.add(RoleAssignment(user_id=user.id, role=Role.ADMINISTRATOR))
    await session.flush()
    return user
