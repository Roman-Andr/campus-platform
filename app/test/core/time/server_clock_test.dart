import 'package:campus/src/core/time/server_clock.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ServerClock', () {
    test('the measured offset uses the middle of the round trip', () {
      final sent = DateTime.utc(2027, 1, 15, 12);
      final received = sent.add(const Duration(seconds: 4));
      final clock = ServerClock.measure(
        deviceSentAt: sent,
        deviceReceivedAt: received,
        serverNow: DateTime.utc(2027, 1, 15, 12, 5, 2),
        onlineTtl: const Duration(seconds: 30),
      );

      // The server was asked at 12:00:02 of its own clock, so it is five
      // minutes and two seconds ahead of the device.
      expect(clock.offset, const Duration(minutes: 5));
    });

    test('a slow device is corrected into server time', () {
      final deviceNow = DateTime.utc(2027, 1, 15, 12);
      const clock = ServerClock(
        offset: Duration(minutes: 3),
        onlineTtl: Duration(seconds: 30),
      );

      expect(clock.now(deviceNow: deviceNow), DateTime.utc(2027, 1, 15, 12, 3));
    });

    test('a fast device is corrected back into server time', () {
      final deviceNow = DateTime.utc(2027, 1, 15, 12, 10);
      const clock = ServerClock(
        offset: Duration(minutes: -7),
        onlineTtl: Duration(seconds: 30),
      );

      expect(clock.now(deviceNow: deviceNow), DateTime.utc(2027, 1, 15, 12, 3));
    });

    test('expiry and refresh are expressed in device time', () {
      final issuedAt = DateTime.utc(2027, 1, 15, 12, 3);
      const clock = ServerClock(
        offset: Duration(minutes: 3),
        onlineTtl: Duration(seconds: 30),
      );

      // The server issued the code at 12:03 of its own clock, which is
      // 12:00 on this device. It expires 30 seconds later and is replaced
      // 5 seconds before that.
      expect(
        clock.validUntilDevice(issuedAt),
        DateTime.utc(2027, 1, 15, 12, 0, 30),
      );
      expect(
        clock.refreshAtDevice(issuedAt),
        DateTime.utc(2027, 1, 15, 12, 0, 25),
      );
    });

    test('the refresh lead shrinks with a short lifetime', () {
      const clock = ServerClock(
        offset: Duration.zero,
        onlineTtl: Duration(seconds: 6),
      );

      expect(clock.refreshLead, const Duration(seconds: 3));
      expect(
        clock.refreshAtDevice(DateTime.utc(2027, 1, 15, 12)),
        DateTime.utc(2027, 1, 15, 12, 0, 3),
      );
    });

    test('a code is never refreshed after its expiry', () {
      const clock = ServerClock(
        offset: Duration.zero,
        onlineTtl: Duration(seconds: 30),
      );
      final issuedAt = DateTime.utc(2027, 1, 15, 12);

      expect(
        clock
            .refreshAtDevice(issuedAt)
            .isBefore(clock.validUntilDevice(issuedAt)),
        isTrue,
      );
    });

    test('the default now reads the corrected device clock', () {
      final deviceNow = DateTime.utc(2027, 1, 15, 12);
      const clock = ServerClock(
        offset: Duration(seconds: 5),
        onlineTtl: Duration(seconds: 30),
      );

      final measured = withClock(Clock(() => deviceNow), () => clock.now());
      expect(measured, DateTime.utc(2027, 1, 15, 12, 0, 5));
    });
  });
}
