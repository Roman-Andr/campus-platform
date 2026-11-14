"""Bootstrap the first administrator with ``python -m campus.admin``."""

import argparse
import asyncio
from collections.abc import Sequence

from pydantic import ValidationError

from campus.core.config import Settings, get_settings
from campus.core.db import create_engine, create_session_factory
from campus.modules.identity import FirstAdminInput, create_first_admin


async def bootstrap(settings: Settings, data: FirstAdminInput) -> None:
    engine = create_engine(settings, pooled=False)
    try:
        async with create_session_factory(engine)() as session, session.begin():
            await create_first_admin(session, data)
    finally:
        await engine.dispose()


def main(argv: Sequence[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description="Bootstrap the first administrator.")
    commands = parser.add_subparsers(dest="command", required=True)
    command = commands.add_parser("create-first-admin")
    command.add_argument("--email", required=True)
    command.add_argument("--first-name", required=True)
    command.add_argument("--last-name", required=True)
    args = parser.parse_args(argv)
    try:
        data = FirstAdminInput(
            email=args.email, first_name=args.first_name, last_name=args.last_name
        )
        asyncio.run(bootstrap(get_settings(), data))
    except (ValueError, ValidationError) as exc:
        parser.exit(1, f"{exc}\n")


if __name__ == "__main__":
    main()
