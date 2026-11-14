import 'package:material_ui/material_ui.dart';
import 'package:timezone/timezone.dart' as tz;

import '../l10n/l10n.dart';
import '../time/city_time.dart';

/// A reusable editor whose value and callback are UTC instants.
/// Calendar and clock fields always belong to [timezone], not the device.
class CityDateTimePicker extends StatefulWidget {
  const CityDateTimePicker({
    required this.value,
    required this.timezone,
    required this.city,
    required this.firstDate,
    required this.lastDate,
    required this.onChanged,
    super.key,
  });

  final DateTime value;
  final String timezone;
  final String city;

  /// Bounds are calendar dates in the city, without conversion to device time.
  final DateTime firstDate;
  final DateTime lastDate;
  final ValueChanged<DateTime> onChanged;

  @override
  State<CityDateTimePicker> createState() => _CityDateTimePickerState();
}

class _CityDateTimePickerState extends State<CityDateTimePicker> {
  bool _invalid = false;

  Future<void> _pick() async {
    final local = tz.TZDateTime.from(
      widget.value,
      cityLocation(widget.timezone),
    );
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime(local.year, local.month, local.day),
      firstDate: widget.firstDate,
      lastDate: widget.lastDate,
      helpText: context.l10n.cityDateTimeHelp(widget.city),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: local.hour, minute: local.minute),
      helpText: context.l10n.cityDateTimeHelp(widget.city),
    );
    if (time == null || !mounted) return;
    try {
      final instant = cityTimeToUtc(
        timezone: widget.timezone,
        year: date.year,
        month: date.month,
        day: date.day,
        hour: time.hour,
        minute: time.minute,
      );
      setState(() => _invalid = false);
      widget.onChanged(instant);
    } on ArgumentError {
      setState(() => _invalid = true);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        formatCityTime(
          widget.value,
          timezone: widget.timezone,
          city: widget.city,
          l10n: context.l10n,
          includeDate: true,
        ),
      ),
      TextButton(
        onPressed: _pick,
        child: Text(context.l10n.chooseCityDateTime),
      ),
      if (_invalid) Text(context.l10n.cityTimeDoesNotExist),
    ],
  );
}
