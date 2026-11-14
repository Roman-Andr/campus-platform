import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'help_config.g.dart';

/// Limits of a help request (ТЗ, Приложение 4).
///
/// A relevance deadline cannot outlive the listing itself: the value mirrors
/// the server's `CAMPUS_LISTING_LIFETIME` and is set at build time with
/// `--dart-define=CAMPUS_LISTING_LIFETIME_DAYS=30`.
class HelpConfig {
  const HelpConfig({required this.listingLifetimeDays})
    : assert(listingLifetimeDays > 0, 'a listing must live at least a day');

  factory HelpConfig.fromEnvironment() => const HelpConfig(
    listingLifetimeDays: int.fromEnvironment(
      'CAMPUS_LISTING_LIFETIME_DAYS',
      defaultValue: 30,
    ),
  );

  /// How long a listing stays alive, in days.
  final int listingLifetimeDays;

  /// The same lifetime as a duration.
  Duration get listingLifetime => Duration(days: listingLifetimeDays);
}

@Riverpod(keepAlive: true)
HelpConfig helpConfig(Ref ref) => HelpConfig.fromEnvironment();
