@Timeout(Duration(seconds: 120))
library;

import 'dart:convert';

import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/features/reviews/presentation/review_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/fake_api.dart';
import '../listings/fixtures.dart' show listingJson, pageJson;
import 'fixtures.dart';
import 'review_helpers.dart';

/// The review of one interaction and the refusals of a fake server.
class FakeReviewBackend {
  FakeReviewBackend({
    this.kind = 'giveaway',
    this.cityTimezone = 'Europe/Moscow',
    this.viewer = reviewAuthorId,
    DateTime? completedAt,
    DateTime? windowClosesAt,
  }) : completedAt =
           completedAt ??
           DateTime.now().toUtc().subtract(const Duration(days: 2)),
       windowClosesAt =
           windowClosesAt ??
           DateTime.now().toUtc().add(const Duration(days: 12));

  final String listingId = 'listing-1';
  final String interactionId = 'request-1';
  final String kind;
  final String cityTimezone;
  final String viewer;
  final DateTime completedAt;
  final DateTime windowClosesAt;

  String status = 'completed';
  bool oneWay = false;
  bool revealed = false;
  bool eligible = true;
  bool canReview = true;
  bool canEdit = false;
  bool canReply = false;
  List<String> tags = reviewTagsJson;
  Map<String, Object?>? mine;
  Map<String, Object?>? theirs;

  int stateRequests = 0;
  int createRequests = 0;
  int editRequests = 0;
  int replyRequests = 0;

  /// How many write attempts fail like a dropped connection.
  int networkFailures = 0;

  /// A problem the next write answers instead of writing.
  String? writeProblem;
  int writeProblemStatus = 409;

  /// A problem the next answer answers instead of answering.
  String? replyProblem;
  int replyProblemStatus = 409;

  String get statePath =>
      '/api/v1/listings/$listingId/interactions/$interactionId/review';

  Map<String, Object?> listing() => {
    ...listingJson(id: listingId, author: reviewAuthorId, kind: kind),
    'city_timezone': cityTimezone,
  };

  Map<String, Object?> state() => reviewStateJson(
    kind: kind,
    status: status,
    oneWay: oneWay,
    completedAt: completedAt.toIso8601String(),
    windowClosesAt: windowClosesAt.toIso8601String(),
    revealed: revealed,
    eligible: eligible,
    canReview: canReview,
    canEdit: canEdit,
    canReply: canReply,
    tags: tags,
    mine: mine,
    theirs: theirs,
  );

  /// Writes or replaces the own review, the way the server does.
  void write({
    required int rating,
    required List<String> tags,
    required String? text,
  }) {
    final subject = viewer == reviewAuthorId ? reviewParticipantId : null;
    mine = reviewJson(
      author: viewer,
      subject: subject,
      kind: kind,
      rating: rating,
      tags: tags,
      text: text,
    );
    canReview = false;
    canEdit = true;
  }

  /// Answers the revealed review of the other side.
  void answer(String text) {
    final review = theirs!;
    theirs = {
      ...review,
      'reply': reviewReplyJson(
        reviewId: review['id']! as String,
        author: viewer,
        authorName: 'Ivan Ivanov',
        text: text,
      ),
    };
    canReply = false;
  }

  ResponseBody reply(RequestOptions options) {
    final base = realtimeReply(options);
    if (base != null) return base;
    final path = options.path;
    final method = options.method;
    if (method == 'GET' && path == '/api/v1/university/cities') {
      return jsonBody(200, citiesJson);
    }
    if (method == 'GET' && path == '/api/v1/listings/$listingId') {
      return jsonBody(200, listing());
    }
    if (method == 'GET' && path == '/api/v1/listings/reservations/mine') {
      return jsonBody(200, pageJson([]));
    }
    if (method == 'GET' && path == '/api/v1/listings/$listingId/interactions') {
      return jsonBody(200, pageJson([]));
    }
    if (method == 'GET' && path == '/api/v1/listings/$listingId/waitlist/me') {
      return problemBody(404, 'not_found');
    }
    if (method == 'GET' && path == statePath) {
      stateRequests++;
      return jsonBody(200, state());
    }
    if ((method == 'POST' || method == 'PATCH') && path == statePath) {
      if (method == 'POST') {
        createRequests++;
      } else {
        editRequests++;
      }
      if (networkFailures > 0) {
        networkFailures--;
        throw DioException.connectionError(
          requestOptions: options,
          reason: 'Connection reset by peer',
        );
      }
      final problem = writeProblem;
      if (problem != null) {
        return problemBody(writeProblemStatus, problem);
      }
      final body = jsonDecode(options.data! as String) as Map<String, Object?>;
      write(
        rating: body['rating']! as int,
        tags: (body['tags']! as List<Object?>).cast<String>(),
        text: body['text'] as String?,
      );
      return jsonBody(method == 'POST' ? 201 : 200, state());
    }
    if (method == 'POST' && path == '$statePath/reply') {
      replyRequests++;
      if (networkFailures > 0) {
        networkFailures--;
        throw DioException.connectionError(
          requestOptions: options,
          reason: 'Connection reset by peer',
        );
      }
      final problem = replyProblem;
      if (problem != null) {
        return problemBody(replyProblemStatus, problem);
      }
      final body = jsonDecode(options.data! as String) as Map<String, Object?>;
      answer(body['text']! as String);
      return jsonBody(201, state());
    }
    throw StateError('No reply for $method $path');
  }
}

/// The route of the review of the fixture interaction.
const reviewPath = '/listings/listing-1/interactions/request-1/review';

/// An event interaction: it carries no completion of its own, the end of the
/// event is the completion for the server.
InteractionOutput eventInteraction() => InteractionOutput.fromJson(
  interactionJson(status: 'accepted', completedAt: null),
);

Future<void> writeReview(
  WidgetTester tester, {
  int stars = 4,
  String? tag,
  String? text,
}) async {
  await tester.tap(find.byKey(Key('review-star-$stars')));
  await settle(tester);
  if (tag != null) {
    await tester.tap(find.byKey(Key('review-tag-$tag')));
    await settle(tester);
  }
  if (text != null) {
    await tester.enterText(find.byKey(const Key('review-text')), text);
  }
  await tester.tap(find.byKey(const Key('review-submit')));
  await settle(tester);
}

Future<void> answerReview(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('review-reply-text')), text);
  await tester.tap(find.byKey(const Key('review-reply-submit')));
  await settle(tester);
}

void main() {
  group('writing a review', () {
    testWidgets(
      'sends the stars, the tags and the text and rereads the state',
      (tester) async {
        final backend = FakeReviewBackend();
        final (_, server) = await open(
          tester,
          backend.reply,
          reviewPath,
          viewer: reviewAuthorId,
        );

        expect(find.byKey(const Key('review-form')), findsOneWidget);
        expect(find.byKey(const Key('review-tag-punctual')), findsOneWidget);

        await writeReview(tester, tag: 'friendly', text: 'Nice desk');

        final post = sentTo(server, 'POST', backend.statePath).single;
        expect(post.json['rating'], 4);
        expect(post.json['tags'], ['friendly']);
        expect(post.json['text'], 'Nice desk');
        expect(post.headers['Idempotency-Key'], isA<String>());
        // The state is read back after the review, not just taken from the answer.
        expect(backend.stateRequests, greaterThanOrEqualTo(2));
        expect(find.text('The review is saved.'), findsOneWidget);
        expect(find.byKey(const Key('review-mine')), findsOneWidget);
        expect(find.byKey(const Key('review-waiting')), findsOneWidget);
        expect(find.byKey(const Key('review-form')), findsNothing);
      },
    );

    testWidgets('requires the stars before sending', (tester) async {
      final backend = FakeReviewBackend();
      final (_, server) = await open(
        tester,
        backend.reply,
        reviewPath,
        viewer: reviewAuthorId,
      );

      await tester.tap(find.byKey(const Key('review-submit')));
      await settle(tester);

      expect(find.text('Choose a rating from 1 to 5.'), findsOneWidget);
      expect(sentTo(server, 'POST', backend.statePath), isEmpty);
    });

    testWidgets('a refusal is localized and followed by the server state', (
      tester,
    ) async {
      final backend = FakeReviewBackend()..writeProblem = 'review_published';
      await open(tester, backend.reply, reviewPath, viewer: reviewAuthorId);
      final before = backend.stateRequests;

      await writeReview(tester, stars: 3);

      expect(
        find.text('A review cannot be changed after the reveal.'),
        findsOneWidget,
      );
      expect(backend.stateRequests, greaterThan(before));
    });

    testWidgets('a repeat after a lost connection keeps the idempotency key', (
      tester,
    ) async {
      final backend = FakeReviewBackend()..networkFailures = 4;
      final (_, server) = await open(
        tester,
        backend.reply,
        reviewPath,
        viewer: reviewAuthorId,
      );

      await writeReview(tester, stars: 5, tag: 'punctual', text: 'Great');

      expect(find.byKey(const Key('review-error')), findsOneWidget);
      final attempts = sentTo(server, 'POST', backend.statePath);
      expect(attempts, hasLength(4));
      expect(
        attempts.map((request) => request.headers['Idempotency-Key']).toSet(),
        hasLength(1),
      );
      expect(backend.mine, isNull);
      expect(find.byKey(const Key('review-mine')), findsNothing);

      await tester.tap(find.byKey(const Key('review-submit')));
      await settle(tester);

      final all = sentTo(server, 'POST', backend.statePath);
      expect(all, hasLength(5));
      expect(
        all.map((request) => request.headers['Idempotency-Key']).toSet(),
        hasLength(1),
      );
      expect(backend.mine, isNotNull);
      expect(find.byKey(const Key('review-mine')), findsOneWidget);
      expect(find.text('The review is saved.'), findsOneWidget);
    });
  });

  group('before the reveal', () {
    testWidgets('the own review is shown and waits for the other side', (
      tester,
    ) async {
      final backend =
          FakeReviewBackend(
              cityTimezone: 'Asia/Tokyo',
              windowClosesAt: DateTime.utc(2026, 12, 4, 12),
            )
            ..canReview = false
            ..canEdit = true
            ..mine = reviewJson(text: 'All good');
      await open(tester, backend.reply, reviewPath, viewer: reviewAuthorId);

      expect(find.byKey(const Key('review-mine')), findsOneWidget);
      expect(find.text('All good'), findsOneWidget);
      expect(find.byKey(const Key('review-theirs')), findsNothing);
      expect(find.byKey(const Key('review-waiting')), findsOneWidget);
      // 12:00 UTC is 21:00 in Tokyo, not the device time.
      final notice = find.descendant(
        of: find.byKey(const Key('review-waiting')),
        matching: find.byType(Text),
      );
      expect(tester.widget<Text>(notice).data, contains('21:00'));
      expect(
        find.textContaining('The review becomes visible after the other side'),
        findsOneWidget,
      );
    });

    testWidgets('the own review may be changed with the same fields', (
      tester,
    ) async {
      final backend = FakeReviewBackend()
        ..canReview = false
        ..canEdit = true
        ..mine = reviewJson(rating: 2, tags: ['punctual'], text: 'Old text');
      final (_, server) = await open(
        tester,
        backend.reply,
        reviewPath,
        viewer: reviewAuthorId,
      );

      await tester.tap(find.byKey(const Key('review-edit')));
      await settle(tester);
      expect(find.byKey(const Key('review-form')), findsOneWidget);

      await tester.tap(find.byKey(const Key('review-star-5')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('review-submit')));
      await settle(tester);

      final patch = sentTo(server, 'PATCH', backend.statePath).single;
      expect(patch.json['rating'], 5);
      expect(patch.json['tags'], ['punctual']);
      expect(patch.json['text'], 'Old text');
      expect(patch.headers['Idempotency-Key'], isA<String>());
      expect(find.text('The review is saved.'), findsOneWidget);
    });
  });

  group('after the reveal', () {
    testWidgets('both published reviews are shown and the editing is closed', (
      tester,
    ) async {
      final backend = FakeReviewBackend()
        ..canReview = false
        ..revealed = true
        ..mine = reviewJson(publishedAt: '2026-11-21T12:00:00Z')
        ..theirs = reviewJson(
          id: 'review-theirs',
          author: reviewParticipantId,
          authorName: 'Petr Petrov',
          rating: 4,
          tags: ['friendly'],
          text: 'Good meeting',
          publishedAt: '2026-11-21T12:00:00Z',
        );
      await open(tester, backend.reply, reviewPath, viewer: reviewAuthorId);

      expect(find.byKey(const Key('review-mine')), findsOneWidget);
      expect(find.byKey(const Key('review-theirs')), findsOneWidget);
      expect(find.text('Petr Petrov'), findsOneWidget);
      expect(find.text('Good meeting'), findsOneWidget);
      expect(find.byKey(const Key('review-revealed')), findsOneWidget);
      expect(find.byKey(const Key('review-form')), findsNothing);
      expect(find.byKey(const Key('review-edit')), findsNothing);
      expect(find.byKey(const Key('review-reply-form')), findsNothing);
    });

    testWidgets('the addressee answers once and the answer is shown', (
      tester,
    ) async {
      final backend = FakeReviewBackend()
        ..canReview = false
        ..canReply = true
        ..revealed = true
        ..theirs = reviewJson(
          id: 'review-theirs',
          author: reviewAuthorId,
          publishedAt: '2026-11-21T12:00:00Z',
        );
      final (_, server) = await open(
        tester,
        backend.reply,
        reviewPath,
        viewer: reviewParticipantId,
      );

      expect(find.byKey(const Key('review-reply-form')), findsOneWidget);
      await answerReview(tester, 'Thanks, come again');

      final post = sentTo(server, 'POST', '${backend.statePath}/reply').single;
      expect(post.json['text'], 'Thanks, come again');
      expect(post.headers['Idempotency-Key'], isA<String>());
      expect(backend.replyRequests, 1);
      expect(find.text('The answer is saved.'), findsOneWidget);
      expect(find.text('Thanks, come again'), findsOneWidget);
      expect(find.byKey(const Key('review-reply-form')), findsNothing);
    });

    testWidgets('a second answer is refused with its own message', (
      tester,
    ) async {
      final backend = FakeReviewBackend()
        ..canReview = false
        ..canReply = true
        ..revealed = true
        ..replyProblem = 'review_reply_exists'
        ..theirs = reviewJson(
          id: 'review-theirs',
          author: reviewAuthorId,
          publishedAt: '2026-11-21T12:00:00Z',
        );
      await open(
        tester,
        backend.reply,
        reviewPath,
        viewer: reviewParticipantId,
      );

      await answerReview(tester, 'Thanks');

      expect(
        find.text('The review has already been answered.'),
        findsOneWidget,
      );
    });
  });

  group('the event one-way rule', () {
    testWidgets('the organiser answers but writes no review', (tester) async {
      final backend = FakeReviewBackend(kind: 'event')
        ..oneWay = true
        ..canReview = false
        ..revealed = true
        ..canReply = true
        ..theirs = reviewJson(
          id: 'review-theirs',
          author: reviewParticipantId,
          authorName: 'Petr Petrov',
          kind: 'event',
          publishedAt: '2026-11-21T12:00:00Z',
        );
      await open(tester, backend.reply, reviewPath, viewer: reviewAuthorId);

      expect(
        find.textContaining('Participants of the event review the organiser'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('review-form')), findsNothing);
      expect(find.byKey(const Key('review-theirs')), findsOneWidget);
      expect(find.byKey(const Key('review-reply-form')), findsOneWidget);
    });

    testWidgets('a participant reviews the organiser', (tester) async {
      final backend = FakeReviewBackend(
        kind: 'event',
        viewer: reviewParticipantId,
      )..oneWay = true;
      await open(
        tester,
        backend.reply,
        reviewPath,
        viewer: reviewParticipantId,
      );

      expect(find.byKey(const Key('review-form')), findsOneWidget);
      expect(find.byKey(const Key('review-reply-form')), findsNothing);
    });
  });

  group('the entry card of a review', () {
    testWidgets('appears only for a completed interaction of a reviewed kind', (
      tester,
    ) async {
      final item = InteractionOutput.fromJson(interactionJson());
      await pumpCard(
        tester,
        ReviewSummary(item: item, kind: 'giveaway', authorId: reviewAuthorId),
      );
      expect(find.byKey(const Key('review-summary-request-1')), findsOneWidget);
      expect(find.byKey(const Key('review-open-request-1')), findsOneWidget);

      await pumpCard(
        tester,
        ReviewSummary(
          item: InteractionOutput.fromJson(
            interactionJson(status: 'accepted', completedAt: null),
          ),
          kind: 'giveaway',
          authorId: reviewAuthorId,
        ),
      );
      expect(find.byKey(const Key('review-open-request-1')), findsNothing);

      await pumpCard(
        tester,
        ReviewSummary(
          item: item,
          kind: 'publication',
          authorId: reviewAuthorId,
        ),
      );
      expect(find.byKey(const Key('review-open-request-1')), findsNothing);
    });

    testWidgets('tells the organiser of an ended event who reviews whom', (
      tester,
    ) async {
      final backend = FakeReviewBackend(kind: 'event')
        ..oneWay = true
        ..canReview = false
        ..eligible = false;
      await pumpCard(
        tester,
        ReviewSummary(
          item: eventInteraction(),
          kind: 'event',
          authorId: reviewAuthorId,
          eventEndsAt: DateTime.now().toUtc().subtract(
            const Duration(minutes: 5),
          ),
        ),
        route: backend.reply,
      );

      expect(
        find.text(
          'Participants review the organiser; you answer their reviews.',
        ),
        findsOneWidget,
      );

      // The organiser gets no form of their own, only the answer.
      await tester.tap(find.byKey(const Key('review-open-request-1')));
      await settle(tester);
      expect(find.byKey(const Key('review-form')), findsNothing);
      expect(find.byKey(const Key('review-unavailable')), findsOneWidget);
    });

    testWidgets('an event participant gets the card after the end', (
      tester,
    ) async {
      final backend = FakeReviewBackend(
        kind: 'event',
        viewer: reviewParticipantId,
      )..oneWay = true;
      final item = eventInteraction();

      // Before the event ends the server will not accept a review.
      await pumpCard(
        tester,
        ReviewSummary(
          item: item,
          kind: 'event',
          authorId: reviewAuthorId,
          eventEndsAt: DateTime.now().toUtc().add(const Duration(hours: 2)),
        ),
        viewer: reviewParticipantId,
        route: backend.reply,
      );
      expect(find.byKey(const Key('review-open-request-1')), findsNothing);

      // After the end the card appears and opens the form.
      await pumpCard(
        tester,
        ReviewSummary(
          item: item,
          kind: 'event',
          authorId: reviewAuthorId,
          eventEndsAt: DateTime.now().toUtc().subtract(
            const Duration(minutes: 5),
          ),
        ),
        viewer: reviewParticipantId,
        route: backend.reply,
      );
      expect(find.byKey(const Key('review-open-request-1')), findsOneWidget);

      await tester.tap(find.byKey(const Key('review-open-request-1')));
      await settle(tester);
      expect(find.byKey(const Key('review-form')), findsOneWidget);
    });
  });
}
