"""First-admin deployment command and its transactional invariants."""

import asyncio
import os
import sys

import pytest
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from campus.modules.identity import (
    FirstAdminInput,
    Role,
    RoleAssignment,
    User,
    create_first_admin,
)
from campus.modules.university import AccountType, EmailDomain

EMAIL = "admin@university.example"


@pytest.fixture
async def allowed(session: AsyncSession) -> AsyncSession:
    session.add(
        EmailDomain(domain="university.example", account_type=AccountType.EMPLOYEE)
    )
    await session.commit()
    return session


async def command(database_url: str, email: str = EMAIL) -> tuple[int, str]:
    process = await asyncio.create_subprocess_exec(
        sys.executable,
        "-m",
        "campus.admin",
        "create-first-admin",
        "--email",
        email,
        "--first-name",
        "First",
        "--last-name",
        "Admin",
        env={**os.environ, "CAMPUS_DATABASE_URL": database_url},
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    try:
        _, stderr = await asyncio.wait_for(process.communicate(), timeout=30)
    finally:
        if process.returncode is None:
            process.kill()
            await process.wait()
    assert process.returncode is not None
    return process.returncode, stderr.decode()


async def test_command_creates_admin_then_refuses_without_changes(
    database_url: str,
    allowed: AsyncSession,
) -> None:
    code, error = await command(database_url)
    assert code == 0, error
    user = await allowed.scalar(select(User))
    assert user is not None
    assert (user.email, user.first_name, user.last_name, user.account_type) == (
        EMAIL,
        "First",
        "Admin",
        "employee",
    )
    assignment = await allowed.scalar(select(RoleAssignment))
    assert assignment is not None
    assert assignment.role == Role.ADMINISTRATOR
    assert assignment.dormitory_id is None
    assert assignment.faculty_id is None
    await allowed.rollback()
    code, error = await command(database_url, "other@university.example")
    assert code != 0
    assert "already exists" in error
    assert await allowed.scalar(select(func.count()).select_from(User)) == 1
    assert await allowed.scalar(select(func.count()).select_from(RoleAssignment)) == 1


async def test_concurrent_commands_create_exactly_one_admin(
    database_url: str,
    allowed: AsyncSession,
) -> None:
    results = await asyncio.gather(
        command(database_url),
        command(database_url, "other@university.example"),
    )
    assert sorted(code for code, _ in results) == [0, 1], results
    assert await allowed.scalar(select(func.count()).select_from(User)) == 1
    assert await allowed.scalar(select(func.count()).select_from(RoleAssignment)) == 1


@pytest.mark.parametrize("email", ["not-an-email", "admin@outside.example"])
async def test_command_rejects_invalid_or_disallowed_email(
    database_url: str,
    allowed: AsyncSession,
    email: str,
) -> None:
    code, _ = await command(database_url, email)
    assert code != 0
    assert await allowed.scalar(select(func.count()).select_from(User)) == 0
    assert await allowed.scalar(select(func.count()).select_from(RoleAssignment)) == 0


async def test_bootstrap_reuses_account_and_preserves_profile(
    allowed: AsyncSession,
) -> None:
    user = User(
        email=EMAIL, first_name="Original", last_name="Name", account_type="employee"
    )
    allowed.add(user)
    await allowed.commit()
    user_id = user.id
    data = FirstAdminInput(email=EMAIL.upper(), first_name="New", last_name="Name")
    result = await create_first_admin(allowed, data)
    await allowed.commit()
    assert result.id == user_id
    assert result.first_name == "Original"
    with pytest.raises(ValueError, match="already exists"):
        await create_first_admin(allowed, data)
    await allowed.rollback()


async def test_bootstrap_domain_check_and_new_user(allowed: AsyncSession) -> None:
    with pytest.raises(ValueError, match="not allowed"):
        await create_first_admin(
            allowed,
            FirstAdminInput(
                email="admin@outside.example",
                first_name="First",
                last_name="Admin",
            ),
        )
    await allowed.rollback()
    user = await create_first_admin(
        allowed,
        FirstAdminInput(
            email=EMAIL,
            first_name="First",
            last_name="Admin",
        ),
    )
    await allowed.commit()
    assert user.account_type == "employee"
