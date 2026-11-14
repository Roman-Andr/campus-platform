import 'package:campus/src/core/l10n/l10n.dart';
import 'package:campus/src/core/time/city_time.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
    await initializeDateFormatting('en');
  });
  const perm = 'Asia/Yekaterinburg';
  final moscow = cityLocation('Europe/Moscow');

  test('Perm 18:00 is 13:00 UTC on a Moscow device', () {
    final instant = cityTimeToUtc(
      timezone: perm,
      year: 2026,
      month: 11,
      day: 16,
      hour: 18,
      minute: 0,
    );
    expect(instant, DateTime.utc(2026, 11, 16, 13));
    final ru = lookupAppLocalizations(const Locale('ru'));
    expect(
      formatCityTime(
        instant,
        timezone: perm,
        city: 'Пермь',
        l10n: ru,
        deviceLocation: moscow,
      ),
      '18:00, Пермь, UTC+5',
    );
  });

  test('annotation is localized in English', () {
    expect(
      formatCityTime(
        DateTime.utc(2026, 11, 16, 13),
        timezone: perm,
        city: 'Perm',
        l10n: lookupAppLocalizations(const Locale('en')),
        deviceLocation: moscow,
      ),
      '18:00, Perm, UTC+5',
    );
  });

  test('matching device zone has no annotation', () {
    expect(
      formatCityTime(
        DateTime.utc(2026, 11, 16, 13),
        timezone: perm,
        city: 'Perm',
        l10n: lookupAppLocalizations(const Locale('en')),
        deviceLocation: cityLocation(perm),
      ),
      '18:00',
    );
  });

  test('calendar rollover and fractional offsets', () {
    final instant = cityTimeToUtc(
      timezone: 'Asia/Kolkata',
      year: 2026,
      month: 11,
      day: 16,
      hour: 0,
      minute: 15,
    );
    expect(instant, DateTime.utc(2026, 11, 15, 18, 45));
    expect(utcOffset(const Duration(hours: 5, minutes: 30)), 'UTC+5:30');
    expect(utcOffset(const Duration(hours: -3, minutes: -30)), 'UTC-3:30');
  });

  test('device daylight saving is evaluated at the displayed instant', () {
    final en = lookupAppLocalizations(const Locale('en'));
    expect(
      formatCityTime(
        DateTime.utc(2026, 7, 1, 12),
        timezone: 'Europe/Berlin',
        city: 'Berlin',
        l10n: en,
        deviceLocation: cityLocation('Europe/Paris'),
      ),
      '14:00',
    );
  });

  test('DST gap is rejected and overlap chooses the first occurrence', () {
    expect(
      () => cityTimeToUtc(
        timezone: 'Europe/Berlin',
        year: 2026,
        month: 3,
        day: 29,
        hour: 2,
        minute: 30,
      ),
      throwsArgumentError,
    );
    expect(
      cityTimeToUtc(
        timezone: 'Europe/Berlin',
        year: 2026,
        month: 10,
        day: 25,
        hour: 2,
        minute: 30,
      ),
      DateTime.utc(2026, 10, 25, 0, 30),
    );
    expect(
      () => cityTimeToUtc(
        timezone: perm,
        year: 2026,
        month: 2,
        day: 30,
        hour: 18,
        minute: 0,
      ),
      throwsArgumentError,
    );
  });
}
