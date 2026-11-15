"""Bootstrap the first administrator and the maintenance commands.

``python -m campus.admin create-first-admin`` creates the first account;
``python -m campus.admin recompute-reputation`` rebuilds the derived profile
aggregates from the primary data, all profiles or the ``--user`` ones.
"""

import argparse
import asyncio
import sys
from collections.abc import Sequence
from uuid import UUID

from pydantic import ValidationError

from campus.core.config import Settings, get_settings
from campus.core.db import create_engine, create_session_factory
from campus.modules.identity import FirstAdminInput, create_first_admin
from campus.modules.reputation import rebuild_aggregates, refresh_aggregates


async def bootstrap(settings: Settings, data: FirstAdminInput) -> None:
    engine = create_engine(settings, pooled=False)
    try:
        async with create_session_factory(engine)() as session, session.begin():
            await create_first_admin(session, data)
    finally:
        await engine.dispose()


async def recompute(settings: Settings, users: Sequence[UUID]) -> int:
    """Rebuild every profile aggregate, or only the given users."""
    engine = create_engine(settings, pooled=False)
    try:
        async with create_session_factory(engine)() as session, session.begin():
            if users:
                return await refresh_aggregates(session, users, settings)
            return await rebuild_aggregates(session, settings)
    finally:
        await engine.dispose()


def main(argv: Sequence[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description="Campus maintenance commands.")
    commands = parser.add_subparsers(dest="command", required=True)
    command = commands.add_parser("create-first-admin")
    command.add_argument("--email", required=True)
    command.add_argument("--first-name", required=True)
    command.add_argument("--last-name", required=True)
    recompute_command = commands.add_parser(
        "recompute-reputation",
        help="Rebuild the derived profile aggregates from the primary data.",
    )
    recompute_command.add_argument(
        "--user",
        action="append",
        default=[],
        type=UUID,
        dest="users",
        help="Rebuild only this user; repeat for several. Default: everyone.",
    )
    args = parser.parse_args(argv)
    try:
        if args.command == "recompute-reputation":
            count = asyncio.run(recompute(get_settings(), args.users))
            sys.stdout.write(f"profiles recomputed: {count}\n")
            return
        data = FirstAdminInput(
            email=args.email, first_name=args.first_name, last_name=args.last_name
        )
        asyncio.run(bootstrap(get_settings(), data))
    except (ValueError, ValidationError) as exc:
        parser.exit(1, f"{exc}\n")


if __name__ == "__main__":
    main()
