from datetime import UTC, datetime

import time_machine

from campus.core import clock


def test_now_is_timezone_aware_utc() -> None:
    assert clock.now().tzinfo is UTC


def test_now_follows_controlled_time() -> None:
    moment = datetime(2027, 3, 1, 12, 30, tzinfo=UTC)

    with time_machine.travel(moment, tick=False):
        assert clock.now() == moment
