import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:timezone/timezone.dart' as tz;

import '../api/network_status.dart';
import '../l10n/l10n.dart';
import '../time/city_time.dart';
import 'realtime_failure.dart';
import 'realtime_models.dart';
import 'realtime_service.dart';

/// Shows a strip above [child] while realtime subscriptions are degraded:
/// reconnecting, reloading state or rejected by the server.
///
/// The strip is hidden when the device is offline: the offline banner of the
/// network layer already says so, and a second bar would repeat it.
class RealtimeStatusBanner extends ConsumerWidget {
  const RealtimeStatusBanner({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(realtimeServiceProvider);
    if (!status.isDegraded || !ref.watch(networkStatusProvider)) {
      return child;
    }
    final (text, icon, background, foreground) = _banner(context, status);
    return Column(
      children: [
        Material(
          color: background,
          child: SafeArea(
            bottom: false,
            child: Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 18, color: foreground),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(text, style: TextStyle(color: foreground)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // The strip already takes the status bar area.
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: child,
          ),
        ),
      ],
    );
  }

  (String, IconData, Color, Color) _banner(
    BuildContext context,
    RealtimeStatus status,
  ) {
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    final failure = status.failure;
    if (failure != null) {
      final error = failure.kind == RealtimeFailureKind.historyLost
          ? colors.tertiaryContainer
          : colors.errorContainer;
      final foreground = failure.kind == RealtimeFailureKind.historyLost
          ? colors.onTertiaryContainer
          : colors.onErrorContainer;
      return (
        realtimeFailureMessage(l10n, failure),
        _iconFor(failure.kind),
        error,
        foreground,
      );
    }
    if (status.stale) {
      return (
        l10n.realtimeUpdating,
        Icons.sync,
        colors.secondaryContainer,
        colors.onSecondaryContainer,
      );
    }
    return switch (status.phase) {
      RealtimeConnectionPhase.connecting => (
        l10n.realtimeConnecting,
        Icons.sync,
        colors.secondaryContainer,
        colors.onSecondaryContainer,
      ),
      RealtimeConnectionPhase.reconnecting => (
        l10n.realtimeReconnecting,
        Icons.sync,
        colors.secondaryContainer,
        colors.onSecondaryContainer,
      ),
      RealtimeConnectionPhase.disconnected => (
        l10n.realtimeOffline,
        Icons.cloud_off_outlined,
        colors.secondaryContainer,
        colors.onSecondaryContainer,
      ),
      RealtimeConnectionPhase.connected => (
        l10n.realtimeUpdating,
        Icons.sync,
        colors.secondaryContainer,
        colors.onSecondaryContainer,
      ),
    };
  }

  static IconData _iconFor(RealtimeFailureKind kind) => switch (kind) {
    RealtimeFailureKind.unauthorized => Icons.lock_outline,
    RealtimeFailureKind.forbidden => Icons.block,
    RealtimeFailureKind.invalidChannel => Icons.error_outline,
    RealtimeFailureKind.unavailable => Icons.cloud_off_outlined,
    RealtimeFailureKind.historyLost => Icons.history,
    RealtimeFailureKind.network => Icons.wifi_off,
    RealtimeFailureKind.unexpected => Icons.error_outline,
  };
}

/// The state of one realtime channel, with the time of its last event in the
/// city time zone (the helper of #44).
///
/// Intended for a chat or notification header; the caller passes the city
/// from the profile.
class RealtimeStatusView extends StatelessWidget {
  const RealtimeStatusView({
    required this.status,
    required this.timezone,
    required this.city,
    this.deviceLocation,
    super.key,
  });

  final RealtimeChannelStatus status;

  /// IANA time zone of the city whose local time is shown.
  final String timezone;

  /// Localized city name for the time annotation.
  final String city;

  /// The device zone, passed by tests to make the annotation deterministic;
  /// the device offset is used when omitted.
  final tz.Location? deviceLocation;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final failure = status.failure;
    final label = failure != null
        ? realtimeFailureMessage(l10n, failure)
        : switch (status.phase) {
            RealtimeSubscriptionPhase.subscribing =>
              status.stale ? l10n.realtimeUpdating : l10n.realtimeConnecting,
            RealtimeSubscriptionPhase.subscribed =>
              status.stale ? l10n.realtimeUpdating : l10n.realtimeConnected,
            RealtimeSubscriptionPhase.unsubscribed => l10n.realtimeOffline,
          };
    final lastEventAt = status.lastEventAt;
    return Semantics(
      label: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            failure != null ? Icons.error_outline : Icons.circle,
            size: failure != null ? 16 : 8,
            color: failure != null
                ? Theme.of(context).colorScheme.error
                : status.phase == RealtimeSubscriptionPhase.subscribed &&
                      !status.stale
                ? Colors.green
                : Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(width: 6),
          Flexible(child: Text(label)),
          if (lastEventAt != null) ...[
            const SizedBox(width: 8),
            Text(
              l10n.realtimeLastEvent(
                formatCityTime(
                  lastEventAt,
                  timezone: timezone,
                  city: city,
                  l10n: l10n,
                  deviceLocation: deviceLocation,
                ),
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
