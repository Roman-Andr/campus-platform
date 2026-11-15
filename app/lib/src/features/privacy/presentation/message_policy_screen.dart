import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/widgets/api_error_view.dart';
import '../../profile/application/my_profile.dart';
import '../application/privacy.dart';
import '../domain/privacy.dart';
import 'privacy_labels.dart';

/// The incoming personal message policy of the signed-in user.
///
/// The choice is confirmed by the server before it is shown as selected; a
/// failed request keeps the old choice and shows a localized error. The
/// idempotency key of a failed change is reused when the user retries it.
class MessagePolicyScreen extends ConsumerStatefulWidget {
  const MessagePolicyScreen({super.key});

  @override
  ConsumerState<MessagePolicyScreen> createState() =>
      _MessagePolicyScreenState();
}

class _MessagePolicyScreenState extends ConsumerState<MessagePolicyScreen> {
  bool _busy = false;
  String? _error;
  MessagePolicy? _failedPolicy;
  String? _idempotencyKey;

  Future<void> _save(MessagePolicy policy) async {
    if (_busy) return;
    final current = ref.read(messagePolicyControllerProvider).value;
    if (current == policy) return;
    if (_failedPolicy != policy) {
      _idempotencyKey = const Uuid().v7();
      _failedPolicy = policy;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(messagePolicyControllerProvider.notifier)
          .set(policy, idempotencyKey: _idempotencyKey!);
      if (!mounted) return;
      ref.invalidate(myProfileProvider);
      setState(() {
        _error = null;
        _failedPolicy = null;
        _idempotencyKey = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = privacyFailureMessage(context.l10n, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final policy = ref.watch(messagePolicyControllerProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.messagePolicyTitle)),
      body: switch (policy) {
        AsyncValue(value: final current?) => _body(l10n, current),
        AsyncValue(:final error?) => ApiErrorView(
          error: error,
          message: privacyFailureMessage,
          onRetry: () => ref.invalidate(messagePolicyControllerProvider),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _body(AppLocalizations l10n, MessagePolicy current) => ListView(
    padding: const EdgeInsets.symmetric(vertical: 8),
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Text(l10n.messagePolicyIntro),
      ),
      RadioGroup<MessagePolicy>(
        groupValue: current,
        onChanged: (value) {
          if (!_busy && value != null) unawaited(_save(value));
        },
        child: Column(
          children: [
            for (final option in MessagePolicy.values)
              RadioListTile<MessagePolicy>(
                key: ValueKey('policy-${option.name}'),
                value: option,
                title: Text(messagePolicyLabel(l10n, option)),
                subtitle: Text(messagePolicyHint(l10n, option)),
              ),
          ],
        ),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            key: const Key('policy-error'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              if (_failedPolicy != null)
                TextButton(
                  key: const Key('policy-retry'),
                  onPressed: _busy
                      ? null
                      : () => unawaited(_save(_failedPolicy!)),
                  child: Text(l10n.errorRetry),
                ),
            ],
          ),
        ),
      if (_busy)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
    ],
  );
}
