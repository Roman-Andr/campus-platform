import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_client.dart';
import '../../../core/l10n/l10n.dart';
import '../application/listings.dart';
import '../application/no_meeting.dart';
import 'interaction_timeline_screen.dart';
import 'status_labels.dart';

/// The status of an interaction and, once it is rejected or cancelled, the
/// reason the server recorded. An author cancellation carries its reason;
/// a participant cancellation has none, so only the status is shown then.
class InteractionStatusText extends ConsumerWidget {
  const InteractionStatusText({required this.item, super.key});
  final InteractionOutput item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    if (item.status == InteractionStatus.completed &&
        interactionWithoutMeeting(item)) {
      return Text(
        l.noMeetingCompletedStatus,
        key: Key('interaction-without-meeting-${item.id}'),
      );
    }
    final status = interactionStatusLabel(l, item.status);
    final authorReason =
        item.status == InteractionStatus.cancelled &&
            item.cancelledBy?.toJson() == 'author'
        ? item.cancellationReason?.trim()
        : null;
    if (authorReason != null && authorReason.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(status),
          Text(
            l.listingCancelledByAuthor(authorReason),
            key: Key('author-cancellation-${item.id}'),
          ),
        ],
      );
    }
    if (item.status != InteractionStatus.rejected &&
        item.status != InteractionStatus.cancelled) {
      return Text(status);
    }
    final provider = interactionReasonProvider((item.listingId, item.id));
    final rejected = item.status == InteractionStatus.rejected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(status),
        ref
            .watch(provider)
            .when(
              loading: () => rejected
                  ? const LinearProgressIndicator()
                  : const SizedBox.shrink(),
              error: (e, _) => rejected
                  ? TextButton(
                      onPressed: () => ref.invalidate(provider),
                      child: Text(l.errorRetry),
                    )
                  : const SizedBox.shrink(),
              data: (reason) {
                final label = rejected
                    ? interactionRejectionLabel(l, reason)
                    : interactionReasonLabel(l, reason);
                if (label == null) {
                  return rejected
                      ? Text(l.reservationRejectedAuthor)
                      : const SizedBox.shrink();
                }
                return Text(label);
              },
            ),
      ],
    );
  }
}

/// Opens the history from a request or reservation row.
class TimelineButton extends StatelessWidget {
  const TimelineButton({required this.item, super.key});
  final InteractionOutput item;
  @override
  Widget build(BuildContext context) => TextButton.icon(
    key: Key('timeline-open-${item.id}'),
    onPressed: () => context.push(
      interactionTimelinePath(item.listingId, item.id),
      extra: item.participantName,
    ),
    icon: const Icon(Icons.history),
    label: Text(context.l10n.timelineOpen),
  );
}
