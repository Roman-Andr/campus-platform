import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/core/auth/auth_session.dart';
import 'package:campus/src/core/router/app_router.dart';
import 'package:campus/src/core/router/notification_route.dart';
import 'package:campus/src/features/listings/application/waitlist.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';
import 'fixtures.dart';

WaitlistEntryOutput entry({
  String status = 'waiting',
  int? position,
  DateTime? expires,
}) => WaitlistEntryOutput.fromJson(
  waitlistJson(status: status, position: position, expires: expires),
);

FakeHttpAdapter serverWith(Reply reply) => FakeHttpAdapter()..route(reply);

ProviderContainer signedInContainer(FakeHttpAdapter server) =>
    ProviderContainer(
      overrides: apiOverrides(adapter: server, secure: signedInStorage),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('remaining time is counted from the server expiry instant', () {
    final expires = DateTime.utc(2026, 11, 14, 12, 10);
    final offer = entry(status: 'offered', position: 1, expires: expires);
    expect(
      offerRemaining(offer, DateTime.utc(2026, 11, 14, 12)),
      const Duration(minutes: 10),
    );
    expect(
      offerRemaining(offer, DateTime.utc(2026, 11, 14, 12, 10)),
      Duration.zero,
    );
    expect(
      offerRemaining(offer, DateTime.utc(2026, 11, 14, 12, 10, 1)),
      Duration.zero,
    );
    expect(offerRemaining(entry(), DateTime.utc(2026, 11, 14)), Duration.zero);
  });

  test('countdown text keeps hours only when they remain', () {
    expect(formatOfferCountdown(const Duration(seconds: 3)), '00:03');
    expect(
      formatOfferCountdown(const Duration(minutes: 5, seconds: 1)),
      '05:01',
    );
    expect(
      formatOfferCountdown(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '1:02:03',
    );
    expect(formatOfferCountdown(Duration.zero), '00:00');
    expect(formatOfferCountdown(const Duration(seconds: -1)), '00:00');
  });

  test('only waiting and offered entries are active', () {
    for (final status in ['waiting', 'offered']) {
      expect(waitlistIsActive(WaitlistStatus.fromJson(status)), isTrue);
    }
    for (final status in [
      'claimed',
      'declined',
      'expired',
      'left',
      'removed',
    ]) {
      expect(waitlistIsActive(WaitlistStatus.fromJson(status)), isFalse);
    }
  });

  test('a missing own entry means the user is not queued', () async {
    final server = serverWith(
      (options) => options.path.endsWith('/token/refresh')
          ? jsonBody(200, tokensJson(1))
          : problemBody(404, 'not_found'),
    );
    final container = signedInContainer(server);
    addTearDown(container.dispose);
    await container.read(authStatusProvider.future);
    final sub = container.listen(
      myWaitlistEntryProvider('listing-1'),
      (_, _) {},
    );
    addTearDown(sub.close);

    expect(
      await container.read(myWaitlistEntryProvider('listing-1').future),
      isNull,
    );
    expect(
      server.sent.lastWhere((r) => r.path.endsWith('/waitlist/me')).path,
      '/api/v1/listings/listing-1/waitlist/me',
    );
  });

  test('the own entry returns its place in the queue', () async {
    final server = serverWith(
      (options) => options.path.endsWith('/token/refresh')
          ? jsonBody(200, tokensJson(1))
          : jsonBody(200, waitlistJson(position: 2)),
    );
    final container = signedInContainer(server);
    addTearDown(container.dispose);
    await container.read(authStatusProvider.future);
    final sub = container.listen(
      myWaitlistEntryProvider('listing-1'),
      (_, _) {},
    );
    addTearDown(sub.close);

    final own = await container.read(
      myWaitlistEntryProvider('listing-1').future,
    );
    expect(own!.position, 2);
    expect(own.status, WaitlistStatus.waiting);
  });

  test('a place offer notification opens the offer card', () {
    expect(
      notificationRoute('listing.offer', {'listing_id': 'listing-1'}),
      '/offers/listing-1',
    );
    expect(
      notificationRoute('listing.offer', {'listing_id': 'a b'}),
      '/offers/a%20b',
    );
    expect(
      notificationRoute('listing.waitlist_joined', {'listing_id': 'listing-1'}),
      '/listings/listing-1',
    );
    expect(notificationRoute('listing.offer', const {}), isNull);
    expect(notificationRoute('listing.offer', {'listing_id': 1}), isNull);
    expect(
      notificationRoute('unknown.type', {'listing_id': 'listing-1'}),
      isNull,
    );
    expect(AppRoutes.placeOfferOf('listing-1'), '/offers/listing-1');
  });
}
