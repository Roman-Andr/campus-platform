import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_failure_message.dart';
import '../../../core/api/interceptors.dart';
import '../../../core/l10n/l10n.dart';
import '../domain/help.dart';
import '../domain/skills.dart';
import 'listings.dart';
import 'meeting.dart';

part 'no_meeting.g.dart';

/// Whether the interaction may be completed by mutual confirmation without a
/// meeting: an accepted online lesson with a scheduled time, or an accepted
/// help interaction without any meeting.
///
/// Items, events, offline lessons and help with a proposed or scheduled
/// meeting are rejected by the server and never offered by the client.
bool noMeetingAvailable(String kind, InteractionOutput item) {
  if (item.status != InteractionStatus.accepted) return false;
  if (kind == skillKind) {
    final meeting = meetingOf(item);
    return meeting != null && meeting.online && meeting.scheduledAt != null;
  }
  if (kind == helpKind) return meetingOf(item) == null;
  return false;
}

/// Whether the interaction was completed with the no-meeting method.
bool interactionWithoutMeeting(InteractionOutput item) =>
    item.withoutMeeting ||
    switch (item.completionMethod) {
      InteractionOutputCompletionMethodCompletionMethod(
        value: CompletionMethodKnown(value: CompletionMethodValue.noMeeting),
      ) =>
        true,
      _ => false,
    };

/// Whether a failed request means that no-meeting confirmation is not allowed
/// for the interaction any more.
bool noMeetingIsUnavailable(Object error) => switch (ApiFailure.from(error)) {
  ProblemFailure(
    code: ProblemCodeKnown(value: ProblemCodeValue.listingNoMeetingUnavailable),
  ) =>
    true,
  _ => false,
};

/// A message for a failed no-meeting request.
String noMeetingFailureMessage(AppLocalizations l, Object error) =>
    switch (ApiFailure.from(error)) {
      ProblemFailure(
        code: ProblemCodeKnown(
          value: ProblemCodeValue.listingNoMeetingUnavailable,
        ),
      ) =>
        l.noMeetingUnavailable,
      ProblemFailure(status: 403) => l.noMeetingForbidden,
      ProblemFailure(status: 404) => l.listingUnavailable,
      _ => apiFailureMessage(l, error),
    };

/// Both consents and the completion state of one interaction.
///
/// The state always comes from the server, so a screen restored after a
/// network failure, an app restart or on another device shows the same
/// consents and completion. [confirm] stores the server response, so the
/// caller sees the waiting or completed state without a second request.
@Riverpod(retry: listingRetry)
class NoMeetingState extends _$NoMeetingState {
  @override
  Future<NoMeetingOutput> build((String, String) ids) async {
    final api = ref.watch(campusApiProvider).listings;
    return api.noMeetingState(listingId: ids.$1, interactionId: ids.$2);
  }

  /// Records the current user's consent and returns the updated state.
  ///
  /// The caller keeps [idempotencyKey] while retrying the same consent, so a
  /// repeat after a dropped connection is applied once by the server.
  Future<NoMeetingOutput> confirm({required String idempotencyKey}) async {
    final output = await ref
        .read(campusApiProvider)
        .listings
        .confirmWithoutMeeting(
          listingId: ids.$1,
          interactionId: ids.$2,
          options: Options(headers: {idempotencyKeyHeader: idempotencyKey}),
        );
    state = AsyncData(output);
    return output;
  }
}
