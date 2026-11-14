"""Replay retained notification events: python -m campus.worker.replay_notifications."""

import asyncio

import structlog

from campus import modules
from campus.core.config import get_settings
from campus.core.db import create_engine, create_session_factory
from campus.core.observability import configure_observability
from campus.modules.notifications import replay_notification_events


async def replay() -> None:
    modules.import_all()
    engine = create_engine(get_settings())
    try:
        async with create_session_factory(engine)() as session, session.begin():
            count = await replay_notification_events(session)
        structlog.get_logger(__name__).info("notification_events_replayed", count=count)
    finally:
        await engine.dispose()


def main() -> None:
    configure_observability(get_settings(), process="notification-replay")
    asyncio.run(replay())


if __name__ == "__main__":
    main()
