import 'package:clock/clock.dart';

/// The offset between the device clock and the server clock, with the online
/// QR lifetime the server reported.
///
/// An online QR code is accepted only while its issue time is within
/// `-clock_skew .. ttl` of the server receipt time (ТЗ п. 5.1.1, модуль 5).
/// A device clock that is off by more than the accepted skew would make every
/// code unusable, so codes are signed with [now], the device time corrected by
/// [offset].
class ServerClock {
  const ServerClock({required this.offset, required this.onlineTtl});

  /// Estimates the offset from one round trip.
  ///
  /// The server instant is compared with the middle of the request, so the
  /// estimate is off by at most half of the network delay instead of all of
  /// it.
  factory ServerClock.measure({
    required DateTime deviceSentAt,
    required DateTime deviceReceivedAt,
    required DateTime serverNow,
    required Duration onlineTtl,
  }) {
    final trip = deviceReceivedAt.difference(deviceSentAt);
    final midpoint = deviceSentAt.add(trip ~/ 2);
    return ServerClock(
      offset: serverNow.difference(midpoint),
      onlineTtl: onlineTtl,
    );
  }

  /// Server time minus device time.
  final Duration offset;

  /// How long the server accepts an online code after its issue time.
  final Duration onlineTtl;

  /// The server instant now, corrected from the device clock.
  DateTime now({DateTime? deviceNow}) =>
      (deviceNow ?? clock.now()).toUtc().add(offset);

  /// The device instant at which a code issued at [issuedAt] expires.
  DateTime validUntilDevice(DateTime issuedAt) =>
      issuedAt.add(onlineTtl).subtract(offset);

  /// The device instant at which the code must be replaced.
  ///
  /// Replacement happens [refreshLead] before the expiry, so the screen never
  /// shows an expired code while the next one is fetched.
  DateTime refreshAtDevice(DateTime issuedAt) =>
      issuedAt.add(onlineTtl - refreshLead).subtract(offset);

  /// The lead kept for a refresh: at most five seconds, or half of a shorter
  /// lifetime.
  Duration get refreshLead {
    final half = onlineTtl ~/ 2;
    return half < const Duration(seconds: 5)
        ? half
        : const Duration(seconds: 5);
  }
}
