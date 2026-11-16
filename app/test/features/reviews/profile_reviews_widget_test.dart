@Timeout(Duration(seconds: 120))
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/fake_api.dart';
import 'fixtures.dart';
import 'review_helpers.dart';

Map<String, Object?> page(List<Object?> items, {String? next}) => {
  'items': items,
  'next_page': next,
};

/// The public reviews of a user and the refusals of a fake server.
class FakeReviewsBackend {
  FakeReviewsBackend({this.viewer = reviewAuthorId});

  final String viewer;
  final reviews = <Map<String, Object?>>[];
  int requests = 0;
  int pageSize = 2;

  /// A problem the list answers instead of the reviews.
  String? problem;
  int problemStatus = 500;

  String get path => '/api/v1/users/$viewer/reviews';

  ResponseBody reply(RequestOptions options) {
    final base = realtimeReply(options);
    if (base != null) return base;
    final method = options.method;
    final path = options.path;
    if (method == 'GET' && path == '/api/v1/university/cities') {
      return jsonBody(200, citiesJson);
    }
    if (method == 'GET' && path == this.path) {
      requests++;
      final problem = this.problem;
      if (problem != null) return problemBody(problemStatus, problem);
      final cursor = options.queryParameters['cursor'] as String?;
      if (cursor == null) {
        return jsonBody(
          200,
          page(
            reviews.take(pageSize).toList(),
            next: reviews.length > pageSize ? 'page-2' : null,
          ),
        );
      }
      return jsonBody(200, page(reviews.skip(pageSize).toList()));
    }
    throw StateError('No reply for $method $path');
  }
}

String reviewsPath([String? userId]) =>
    '/users/${userId ?? reviewAuthorId}/reviews';

void main() {
  testWidgets('shows the published reviews with their answers and pages them', (
    tester,
  ) async {
    final backend = FakeReviewsBackend()
      ..reviews.addAll([
        reviewJson(
          id: 'review-1',
          authorName: 'Petr Petrov',
          tags: ['punctual', 'friendly'],
          text: 'Everything as agreed',
          publishedAt: '2026-11-21T12:00:00Z',
          reply: reviewReplyJson(),
        ),
        reviewJson(
          id: 'review-2',
          authorName: 'Petr Petrov',
          rating: 3,
          tags: ['friendly'],
          text: 'It took longer than agreed',
          publishedAt: '2026-11-22T12:00:00Z',
        ),
        reviewJson(
          id: 'review-3',
          authorName: 'Petr Petrov',
          rating: 4,
          tags: ['punctual'],
          text: 'Second page review',
          publishedAt: '2026-11-23T12:00:00Z',
        ),
      ]);
    final (_, server) = await open(
      tester,
      backend.reply,
      reviewsPath(),
      viewer: reviewAuthorId,
    );

    expect(find.byKey(const Key('profile-review-review-1')), findsOneWidget);
    expect(find.byKey(const Key('profile-review-review-2')), findsOneWidget);
    expect(find.byKey(const Key('profile-review-review-3')), findsNothing);
    expect(find.text('Everything as agreed'), findsOneWidget);
    expect(find.text('Thanks, it was a pleasure.'), findsOneWidget);
    expect(find.text('Punctual'), findsWidgets);

    await tester.tap(find.byKey(const Key('profile-reviews-more')));
    await settle(tester);

    expect(find.byKey(const Key('profile-review-review-3')), findsOneWidget);
    final second = sentTo(server, 'GET', backend.path).last;
    expect(second.query['cursor'], 'page-2');
    expect(find.byKey(const Key('profile-reviews-more')), findsNothing);
  });

  testWidgets('explains an empty list of reviews', (tester) async {
    final backend = FakeReviewsBackend();
    await open(tester, backend.reply, reviewsPath(), viewer: reviewAuthorId);

    expect(find.byKey(const Key('profile-reviews-empty')), findsOneWidget);
    expect(
      find.text(
        'Published reviews about you. Hidden and unrevealed reviews '
        'are not shown here.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('offers a retry after a failed load', (tester) async {
    final backend = FakeReviewsBackend()
      ..problem = 'internal_error'
      ..reviews.add(reviewJson(id: 'review-1'));
    await open(tester, backend.reply, reviewsPath(), viewer: reviewAuthorId);

    expect(
      find.text('Something went wrong on the server. Please try again later.'),
      findsOneWidget,
    );

    backend.problem = null;
    await tester.tap(find.text('Try again'));
    await settle(tester);

    expect(find.byKey(const Key('profile-review-review-1')), findsOneWidget);
  });

  testWidgets('reloads the list after a reveal published in realtime', (
    tester,
  ) async {
    final backend = FakeReviewsBackend()
      ..reviews.add(reviewJson(id: 'review-1'));
    final (client, _) = await open(
      tester,
      backend.reply,
      reviewsPath(),
      viewer: reviewAuthorId,
    );
    final before = backend.requests;

    expect(find.byKey(const Key('profile-review-review-2')), findsNothing);
    backend.reviews.add(reviewJson(id: 'review-2', text: 'A new review'));
    await wakeup(tester, client, {
      'kind': 'published',
      'listing_id': 'listing-1',
      'interaction_id': 'request-1',
      'version': 2,
    }, userId: reviewAuthorId);

    expect(backend.requests, greaterThan(before));
    expect(find.byKey(const Key('profile-review-review-2')), findsOneWidget);
    expect(find.text('A new review'), findsOneWidget);
  });
}
