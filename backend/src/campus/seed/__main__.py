"""Entry point of ``campus-seed``: load the initial data of a stand.

Loads the university reference data (cities, dormitories, faculties,
e-mail domains) into the database at ``CAMPUS_DATABASE_URL``, after the
migrations. Safe to repeat: only missing rows are added, in one
transaction.
"""

import argparse
import asyncio
from collections.abc import Sequence
from pathlib import Path

import structlog

from campus.core.config import Settings, get_settings
from campus.core.db import create_engine, create_session_factory
from campus.core.observability import configure_observability
from campus.modules import university

logger = structlog.get_logger(__name__)


def parse_arguments(argv: Sequence[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="campus-seed", description="Load the initial data of a stand."
    )
    parser.add_argument(
        "--university",
        type=Path,
        default=university.DEFAULT_SEED_FILE,
        metavar="FILE",
        help="TOML file of the university reference data (default: HSE campuses)",
    )
    return parser.parse_args(argv)


async def seed(settings: Settings, university_file: Path) -> university.SeedReport:
    """Load the data in one transaction and return what was created."""
    data = university.read_seed_file(university_file)
    engine = create_engine(settings, pooled=False)
    try:
        async with create_session_factory(engine)() as session, session.begin():
            return await university.seed_reference_data(session, data)
    finally:
        await engine.dispose()


def main(argv: Sequence[str] | None = None) -> None:
    """Run ``campus-seed``."""
    arguments = parse_arguments(argv)
    settings = get_settings()
    configure_observability(settings, process="seed")
    report = asyncio.run(seed(settings, arguments.university))
    logger.info("seed_loaded", created=report.created)


if __name__ == "__main__":
    main()
