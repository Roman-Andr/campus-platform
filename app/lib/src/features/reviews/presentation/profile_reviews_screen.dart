import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/realtime/realtime_status_view.dart';
import '../../../core/widgets/api_error_view.dart';
import '../../profile/application/my_profile.dart';
import '../application/review.dart';
import '../domain/review.dart';
import 'review_view.dart';

/// The published reviews about a user: revealed and not hidden ones only.
///
/// The server paginates the list by a cursor; the loaded pages are kept while
/// more are requested, and a realtime publication about a review or its
/// answer reloads the first page. The times are shown in the city zone of the
/// signed-in user (#44), the only one the profile knows.
class ProfileReviewsScreen extends ConsumerStatefulWidget {
  const ProfileReviewsScreen({required this.userId, super.key});

  final String userId;

  @override
  ConsumerState<ProfileReviewsScreen> createState() =>
      _ProfileReviewsScreenState();
}

class _ProfileReviewsScreenState extends ConsumerState<ProfileReviewsScreen> {
  bool _loadingMore = false;
  String? _moreError;

  UserReviewsProvider get _provider => userReviewsProvider(widget.userId);

  Future<void> _refresh() async {
    setState(() => _moreError = null);
    await ref.read(_provider.notifier).sync();
  }

  Future<void> _more() async {
    setState(() {
      _loadingMore = true;
      _moreError = null;
    });
    try {
      await ref.read(_provider.notifier).more();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _moreError = reviewFailureMessage(context.l10n, error));
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final me = ref.watch(myProfileProvider).value;
    final own = me != null && me.id == widget.userId;
    final reviews = ref.watch(_provider);
    final timezone = me?.cityTimezone;
    final city = ref
        .watch(citiesProvider)
        .value
        ?.where((place) => place.id == me?.cityId)
        .firstOrNull
        ?.name;
    String cityTime(DateTime instant) =>
        reviewTimeLabel(l, instant, timezone: timezone, city: city);
    return Scaffold(
      appBar: AppBar(
        title: Text(own ? l.profileReviewsTitle : l.profileReviews),
      ),
      body: switch (reviews) {
        AsyncData(value: final page) => RealtimeStatusBanner(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Text(l.profileReviewsIntro),
                const SizedBox(height: 12),
                if (page.items.isEmpty)
                  Text(
                    l.profileReviewsEmpty,
                    key: const Key('profile-reviews-empty'),
                  )
                else
                  for (final review in page.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ReviewView(
                        key: Key('profile-review-${review.id}'),
                        review: review,
                        cityTime: cityTime,
                        showOwner: true,
                      ),
                    ),
                if (_moreError != null)
                  Text(_moreError!, key: const Key('profile-reviews-error')),
                if (page.nextPage != null)
                  TextButton(
                    key: const Key('profile-reviews-more'),
                    onPressed: _loadingMore ? null : () => unawaited(_more()),
                    child: Text(l.profileReviewsMore),
                  ),
              ],
            ),
          ),
        ),
        AsyncError(:final error) => ApiErrorView(
          error: error,
          message: reviewFailureMessage,
          onRetry: () => ref.invalidate(_provider),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}
