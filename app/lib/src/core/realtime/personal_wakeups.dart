import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/profile/application/my_profile.dart';
import '../auth/auth_session.dart';
import 'realtime_channel.dart';
import 'realtime_models.dart';
import 'realtime_service.dart';

/// Subscribes to the wakeups of the personal channel and reloads on them.
///
/// A publication of the personal channel is a hint only: the payload never
/// carries the change itself, so the owner of the state reloads it through
/// the API. The subscription is best effort: the state works without it and
/// the screen can reload it explicitly.
class PersonalWakeups {
  PersonalWakeups(this._ref);

  final Ref _ref;
  RealtimeSubscription? _subscription;
  final _events = <StreamSubscription<Object?>>[];
  bool _started = false;

  /// Tells a subscription of a closed provider from one of a reopened one.
  int _generation = 0;

  /// Subscribes to the personal channel of the signed-in user.
  ///
  /// [reload] is called on every reconnect and [onEvent] on every
  /// publication. A failure to subscribe is ignored: realtime is a hint.
  Future<void> start({
    required Future<void> Function() reload,
    required void Function(RealtimeEvent event) onEvent,
  }) async {
    if (_started) return;
    _started = true;
    if (_ref.read(authStatusProvider).value !=
        AuthenticationStatus.authenticated) {
      return;
    }
    final generation = ++_generation;
    try {
      final user = await _ref.read(myProfileProvider.future);
      if (!_ref.mounted || generation != _generation || user == null) return;
      final subscription = _ref
          .read(realtimeServiceProvider.notifier)
          .subscribe(RealtimeChannel.personal(user.id), reload: reload);
      if (!_ref.mounted || generation != _generation) {
        await subscription.close();
        return;
      }
      _events.add(subscription.events.listen(onEvent));
      _subscription = subscription;
    } on Object {
      // Realtime is a wakeup only: the state works without it and the screen
      // can refresh it explicitly.
    }
  }

  /// Drops the subscription, if any.
  Future<void> stop() async {
    _generation++;
    final events = _events.toList();
    final subscription = _subscription;
    _events.clear();
    _subscription = null;
    for (final listener in events) {
      await listener.cancel();
    }
    await subscription?.close();
  }
}

/// Whether a publication of the personal channel is about the watched
/// interaction.
///
/// The personal channel also carries the other listings of the user, so a
/// publication with another `listing_id` (or `interaction_id`, when it has
/// one) is ignored. A publication without a readable payload still wakes the
/// screen up: a lost wakeup is worse than one extra request.
bool matchesInteractionWakeup(
  RealtimeEvent event, {
  required String listingId,
  String? interactionId,
}) {
  final data = event.data;
  if (data is! Map<String, Object?>) return true;
  final otherListing = data['listing_id'];
  if (otherListing is String && otherListing != listingId) return false;
  final otherInteraction = data['interaction_id'];
  if (interactionId != null &&
      otherInteraction is String &&
      otherInteraction != interactionId) {
    return false;
  }
  return true;
}
