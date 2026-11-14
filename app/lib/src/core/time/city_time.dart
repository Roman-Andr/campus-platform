import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as data;
import 'package:timezone/timezone.dart' as tz;

import '../l10n/generated/app_localizations.dart';

bool _initialized = false;

/// Loads the bundled IANA database once, on every supported platform.
tz.Location cityLocation(String timezone) {
  if (!_initialized) {
    data.initializeTimeZones();
    _initialized = true;
  }
  return tz.getLocation(timezone);
}

/// Interprets calendar fields in the city's zone, independently of the device.
/// Rejects DST gaps; for repeated times selects the earlier occurrence.
DateTime cityTimeToUtc({
  required String timezone,
  required int year,
  required int month,
  required int day,
  required int hour,
  required int minute,
}) {
  final location = cityLocation(timezone);
  final wall = DateTime.utc(year, month, day, hour, minute);
  if (wall.year != year ||
      wall.month != month ||
      wall.day != day ||
      wall.hour != hour ||
      wall.minute != minute) {
    throw ArgumentError('Invalid calendar date or wall time');
  }
  final candidates = <DateTime>[];
  for (final offset in location.zones.map((z) => z.offset).toSet()) {
    final instant = wall.subtract(offset);
    final local = tz.TZDateTime.from(instant, location);
    if (local.year == year &&
        local.month == month &&
        local.day == day &&
        local.hour == hour &&
        local.minute == minute) {
      candidates.add(instant);
    }
  }
  if (candidates.isEmpty) {
    throw ArgumentError('This wall time does not exist in the city time zone');
  }
  candidates.sort();
  return candidates.first;
}

String utcOffset(Duration offset) {
  final minutes = offset.inMinutes.abs();
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  final sign = offset.isNegative ? '-' : '+';
  return 'UTC$sign$hours${remainder == 0 ? '' : ':${remainder.toString().padLeft(2, '0')}'}';
}

/// Formats in the city zone. Compare device offsets at the displayed instant,
/// so the annotation also respects daylight saving on the device.
String formatCityTime(
  DateTime instant, {
  required String timezone,
  required String city,
  required AppLocalizations l10n,
  bool includeDate = false,
  tz.Location? deviceLocation,
}) {
  final local = tz.TZDateTime.from(instant, cityLocation(timezone));
  final deviceOffset = deviceLocation == null
      ? instant.toLocal().timeZoneOffset
      : tz.TZDateTime.from(instant, deviceLocation).timeZoneOffset;
  final time = DateFormat.Hm(l10n.localeName).format(local);
  final text = includeDate
      ? '${DateFormat.yMd(l10n.localeName).format(local)}, $time'
      : time;
  return local.timeZoneOffset == deviceOffset
      ? text
      : l10n.cityTimeZone(text, city, utcOffset(local.timeZoneOffset));
}
