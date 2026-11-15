import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_router.dart';
import '../../profile/application/my_profile.dart';
import '../application/chats.dart';
import 'chat_labels.dart';

/// Opens the dialog of the signed-in user with the author of a listing,
/// creating it on the first use. The server owns the access rules: an
/// alumni gets a localized refusal for a new dialog and keeps writing in
/// dialogs that already exist, which are reachable from the chats list.
class ListingChatButton extends ConsumerStatefulWidget {
  const ListingChatButton({
    required this.recipientId,
    required this.listingId,
    super.key,
  });

  final String recipientId;
  final String listingId;

  @override
  ConsumerState<ListingChatButton> createState() => _ListingChatButtonState();
}

class _ListingChatButtonState extends ConsumerState<ListingChatButton> {
  bool _busy = false;
  String? _error;

  Future<void> _open() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final chat = await ref
          .read(chatStarterProvider)
          .start(recipientId: widget.recipientId, listingId: widget.listingId);
      if (!mounted) return;
      await context.push(AppRoutes.chatOf(chat.id));
    } on Object catch (error) {
      if (!mounted) return;
      final alumni =
          ref.read(myProfileProvider).value?.accountType.toJson() ==
          'former_employee';
      setState(
        () => _error = chatFailureMessage(context.l10n, error, alumni: alumni),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton.icon(
          key: const Key('listing-chat'),
          onPressed: _busy ? null : () => unawaited(_open()),
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          icon: _busy
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.chat_bubble_outline, size: 18),
          label: Text(l10n.chatStart),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _error!,
              key: const Key('listing-chat-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}
