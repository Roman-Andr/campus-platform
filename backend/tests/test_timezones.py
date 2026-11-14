from datetime import UTC, date, datetime, time

import pytest
import time_machine

from campus.core.timezones import in_local_interval, local_to_utc, next_weekly

PERM = "Asia/Yekaterinburg"
MOSCOW = "Europe/Moscow"


def test_perm_input_is_utc() -> None:
    assert local_to_utc(date(2026, 11, 16), time(18), PERM) == datetime(
        2026, 11, 16, 13, tzinfo=UTC
    )


@pytest.mark.parametrize(
    ("hour", "minute", "inside"),
    [(18, 0, True), (18, 30, True), (3, 0, False), (3, 30, False), (17, 59, False)],
)
def test_overnight_interval(hour: int, minute: int, inside: bool) -> None:
    assert (
        in_local_interval(
            datetime(2026, 11, 16, hour, minute, tzinfo=UTC), time(23), time(8), PERM
        )
        is inside
    )


def test_daytime_and_empty_intervals() -> None:
    moment = datetime(2026, 11, 16, 5, tzinfo=UTC)
    assert in_local_interval(moment, time(9), time(11), PERM)
    assert not in_local_interval(moment, time(10), time(10), PERM)


def test_next_monday_uses_city_and_controlled_clock() -> None:
    with time_machine.travel("2026-11-15T12:00:00Z", tick=False):
        perm = next_weekly(0, time(10), PERM)
        moscow = next_weekly(0, time(10), MOSCOW)
    assert perm == datetime(2026, 11, 16, 5, tzinfo=UTC)
    assert (moscow - perm).total_seconds() == 2 * 3600
    assert next_weekly(0, time(10), PERM, after=perm) == datetime(
        2026, 11, 23, 5, tzinfo=UTC
    )


def test_dst_gap_is_rejected_and_weekly_gap_skipped() -> None:
    with pytest.raises(ValueError, match="does not exist"):
        local_to_utc(date(2026, 3, 29), time(2, 30), "Europe/Berlin")
    assert next_weekly(
        6,
        time(2, 30),
        "Europe/Berlin",
        after=datetime(2026, 3, 28, tzinfo=UTC),
    ) == datetime(2026, 4, 5, 0, 30, tzinfo=UTC)


def test_dst_overlap_uses_first_occurrence() -> None:
    assert local_to_utc(date(2026, 10, 25), time(2, 30), "Europe/Berlin") == datetime(
        2026, 10, 25, 0, 30, tzinfo=UTC
    )


def test_invalid_helper_inputs() -> None:
    with pytest.raises(ValueError, match="offset"):
        in_local_interval(datetime(2026, 1, 1), time(23), time(8), PERM)  # noqa: DTZ001
    with pytest.raises(ValueError, match="offset"):
        local_to_utc(date(2026, 1, 1), time(10, tzinfo=UTC), PERM)
    with pytest.raises(ValueError, match="offset"):
        in_local_interval(
            datetime(2026, 1, 1, tzinfo=UTC), time(1, tzinfo=UTC), time(2), PERM
        )
    with pytest.raises(ValueError, match="Weekday"):
        next_weekly(7, time(10), PERM)
    with pytest.raises(ValueError, match="offset"):
        next_weekly(0, time(10, tzinfo=UTC), PERM)
