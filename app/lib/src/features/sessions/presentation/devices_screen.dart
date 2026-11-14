import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_failure_message.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/widgets/api_error_view.dart';
import '../application/device_sessions.dart';

class DevicesScreen extends ConsumerStatefulWidget {
  const DevicesScreen({super.key});

  @override
  ConsumerState<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends ConsumerState<DevicesScreen> {
  bool _busy = false;

  Future<void> _revoke([SessionOutput? device]) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(device == null ? l10n.devicesSignOutAll : l10n.signOut),
        content: Text(
          device == null
              ? l10n.devicesConfirmAll
              : l10n.devicesConfirmOne(
                  device.deviceName ?? l10n.devicesUnknown,
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.devicesCancel),
          ),
          FilledButton(
            key: const Key('confirm-revoke'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.signOut),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(endDeviceSessionsProvider)(device);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiFailureMessage(context.l10n, error))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final devices = ref.watch(deviceSessionsProvider);
    String date(DateTime instant) =>
        DateFormat.yMd(l10n.localeName).add_Hm().format(instant.toLocal());
    return Scaffold(
      appBar: AppBar(title: Text(l10n.devicesTitle)),
      body: switch (devices) {
        AsyncValue(value: final items?) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(deviceSessionsProvider);
            await ref.read(deviceSessionsProvider.future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (_busy) const LinearProgressIndicator(),
              for (final device in items)
                ListTile(
                  key: ValueKey(device.id),
                  leading: const Icon(Icons.devices),
                  title: Text(device.deviceName ?? l10n.devicesUnknown),
                  subtitle: Text(
                    [
                      l10n.devicesPlatform(device.platform),
                      if (device.current) l10n.devicesCurrent,
                      l10n.devicesSignedIn(date(device.signedInAt)),
                      l10n.devicesLastActive(date(device.lastActiveAt)),
                    ].join('\n'),
                  ),
                  trailing: IconButton(
                    tooltip: l10n.signOut,
                    onPressed: _busy ? null : () => _revoke(device),
                    icon: const Icon(Icons.logout),
                  ),
                ),
              if (items.isEmpty) ListTile(title: Text(l10n.devicesEmpty)),
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.tonal(
                  key: const Key('revoke-all'),
                  onPressed: _busy ? null : _revoke,
                  child: Text(l10n.devicesSignOutAll),
                ),
              ),
            ],
          ),
        ),
        AsyncValue(:final error?) => ApiErrorView(
          error: error,
          onRetry: () => ref.invalidate(deviceSessionsProvider),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}
