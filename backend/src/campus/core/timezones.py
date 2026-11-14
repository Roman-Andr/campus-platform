"""City wall-clock rules, with aware UTC instants at their boundaries.

Intervals include their start and exclude their end; equal ends are empty.
Ambiguous wall times use the first occurrence. Nonexistent wall times are
rejected for input and skipped when finding a recurring weekly occurrence.
"""

from calendar import SUNDAY
from datetime import UTC, date, datetime, time, timedelta
from zoneinfo import ZoneInfo

from campus.core import clock


def as_utc(moment: datetime) -> datetime:
    """Normalize an instant; never interpret a naive datetime as device time."""
    if moment.utcoffset() is None:
        raise ValueError("An instant must include a UTC offset.")
    return moment.astimezone(UTC)


def local_to_utc(day: date, local_time: time, timezone: str) -> datetime:
    """Interpret a date and wall time in an IANA city zone."""
    if local_time.tzinfo is not None:
        raise ValueError("A wall time must not include an offset.")
    wall = datetime.combine(day, local_time)
    zone = ZoneInfo(timezone)
    instant = wall.replace(tzinfo=zone, fold=0).astimezone(UTC)
    if instant.astimezone(zone).replace(tzinfo=None) != wall:
        raise ValueError("This wall time does not exist in the city time zone.")
    return instant


def in_local_interval(moment: datetime, start: time, end: time, timezone: str) -> bool:
    """Whether an instant falls in a daily interval, including overnight ones."""
    if start.tzinfo is not None or end.tzinfo is not None:
        raise ValueError("Interval bounds must be wall times without offsets.")
    local = as_utc(moment).astimezone(ZoneInfo(timezone)).time()
    if start <= end:
        return start <= local < end
    return local >= start or local < end


def next_weekly(
    weekday: int, local_time: time, timezone: str, *, after: datetime | None = None
) -> datetime:
    """Next occurrence strictly after ``after`` (default: clock.now()).

    Weekdays follow Python's convention: Monday is 0, Sunday is 6.
    """
    if not 0 <= weekday <= SUNDAY:
        raise ValueError("Weekday must be between 0 and 6.")
    if local_time.tzinfo is not None:
        raise ValueError("A wall time must not include an offset.")
    current = as_utc(after if after is not None else clock.now())
    day = current.astimezone(ZoneInfo(timezone)).date()
    day += timedelta(days=(weekday - day.weekday()) % 7)
    while True:
        try:
            candidate = local_to_utc(day, local_time, timezone)
        except ValueError:
            pass  # A weekly occurrence in a DST gap is skipped.
        else:
            if candidate > current:
                return candidate
        day += timedelta(weeks=1)
