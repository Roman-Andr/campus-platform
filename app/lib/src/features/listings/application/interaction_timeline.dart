import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api/api_client.dart';
import 'listings.dart';

part 'interaction_timeline.g.dart';

/// Loaded events of one interaction, oldest first, and the cursor of the
/// next page.
class TimelinePage {
  const TimelinePage(this.events, this.nextPage);
  final List<EventOutput> events;
  final String? nextPage;
}

/// The append-only history of an interaction as the server orders it
/// (time, then id). Pages are merged by event id, so a page boundary that
/// moves between requests never shows an event twice.
@Riverpod(retry: listingRetry)
class InteractionTimeline extends _$InteractionTimeline {
  bool _loading = false;

  @override
  Future<TimelinePage> build(String listingId, String interactionId) async {
    final page = await _fetch(null);
    return TimelinePage(page.items, page.nextPage);
  }

  Future<PageEventOutput> _fetch(String? cursor) => ref
      .read(campusApiProvider)
      .listings
      .interactionEvents(
        listingId: listingId,
        interactionId: interactionId,
        cursor: cursor,
      );

  /// Appends the next page; errors are left to the caller to show.
  Future<void> more() async {
    final previous = state.value;
    if (_loading || previous == null || previous.nextPage == null) return;
    _loading = true;
    try {
      final page = await _fetch(previous.nextPage);
      if (!ref.mounted) return;
      final seen = {for (final event in previous.events) event.id};
      state = AsyncData(
        TimelinePage([
          ...previous.events,
          for (final event in page.items)
            if (seen.add(event.id)) event,
        ], page.nextPage),
      );
    } finally {
      _loading = false;
    }
  }
}
