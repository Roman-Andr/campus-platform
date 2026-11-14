import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_client.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/widgets/api_error_view.dart';
import '../../auth/application/sign_in_flow.dart';
import '../application/account_emails.dart';
import 'account_email_failure.dart';

/// Corporate and backup e-mail addresses of the account.
class AccountEmailsScreen extends ConsumerStatefulWidget {
  const AccountEmailsScreen({super.key});

  @override
  ConsumerState<AccountEmailsScreen> createState() =>
      _AccountEmailsScreenState();
}

class _AccountEmailsScreenState extends ConsumerState<AccountEmailsScreen> {
  var _busy = false;

  Future<void> _add(AddressInputKind kind, {required bool replacing}) async {
    final added = await showDialog<bool>(
      context: context,
      builder: (context) => _AddEmailDialog(kind: kind, replacing: replacing),
    );
    if (added != true || !mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(context.l10n.emailsSaved)));
  }

  Future<void> _delete(AddressOutput address) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.emailsDelete),
        content: Text(l10n.emailsDeleteConfirm(address.email)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.emailsCancel),
          ),
          FilledButton(
            key: const Key('emails-confirm-delete'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.emailsDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(accountEmailActionsProvider.notifier).delete(address);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.l10n.emailsDeleted)));
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(accountEmailFailureMessage(context.l10n, error)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final emails = ref.watch(accountEmailsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileEmails)),
      body: switch (emails) {
        AsyncValue(value: final addresses?) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(accountEmailsProvider);
            await ref.read(accountEmailsProvider.future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (_busy) const LinearProgressIndicator(),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline),
                        const SizedBox(width: 12),
                        Expanded(child: Text(l10n.emailsBackupHint)),
                      ],
                    ),
                  ),
                ),
              ),
              for (final address in addresses)
                ListTile(
                  key: ValueKey('email-${address.id}'),
                  leading: Icon(
                    address.kind == AddressOutputKind.backup
                        ? Icons.alternate_email
                        : Icons.school_outlined,
                  ),
                  title: Text(address.email),
                  subtitle: Text(
                    address.kind == AddressOutputKind.backup
                        ? l10n.emailsKindBackup
                        : l10n.emailsKindCorporate,
                  ),
                  trailing: canDeleteAddress(address, addresses)
                      ? IconButton(
                          key: ValueKey('email-delete-${address.id}'),
                          tooltip: l10n.emailsDelete,
                          onPressed: _busy ? null : () => _delete(address),
                          icon: const Icon(Icons.delete_outline),
                        )
                      : null,
                ),
              if (addresses
                      .where((row) => row.kind == AddressOutputKind.corporate)
                      .length ==
                  1)
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: Text(l10n.emailsLastCorporateNote),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.tonal(
                      key: const Key('emails-add-corporate'),
                      onPressed: _busy
                          ? null
                          : () => _add(
                              AddressInputKind.corporate,
                              replacing: false,
                            ),
                      child: Text(l10n.emailsAddCorporate),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                      key:
                          addresses.any(
                            (row) => row.kind == AddressOutputKind.backup,
                          )
                          ? const Key('emails-replace-backup')
                          : const Key('emails-add-backup'),
                      onPressed: _busy
                          ? null
                          : () => _add(
                              AddressInputKind.backup,
                              replacing: addresses.any(
                                (row) => row.kind == AddressOutputKind.backup,
                              ),
                            ),
                      child: Text(
                        addresses.any(
                              (row) => row.kind == AddressOutputKind.backup,
                            )
                            ? l10n.emailsReplaceBackup
                            : l10n.emailsAddBackup,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        AsyncValue(:final error?) => ApiErrorView(
          error: error,
          onRetry: () => ref.invalidate(accountEmailsProvider),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

/// Two steps of adding or replacing an address: the address, then the
/// code sent to it. Only the code accepted by the server adds the address.
class _AddEmailDialog extends ConsumerStatefulWidget {
  const _AddEmailDialog({required this.kind, required this.replacing});

  final AddressInputKind kind;
  final bool replacing;

  @override
  ConsumerState<_AddEmailDialog> createState() => _AddEmailDialogState();
}

class _AddEmailDialogState extends ConsumerState<_AddEmailDialog> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  var _awaitingCode = false;
  var _busy = false;
  String? _emailError;
  String? _codeError;

  bool get _isBackup => widget.kind == AddressInputKind.backup;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_busy) return;
    final l10n = context.l10n;
    final email = normalizeEmail(_email.text);
    if (!isEmail(email)) {
      setState(() => _emailError = l10n.signInEmailInvalid);
      return;
    }
    setState(() {
      _busy = true;
      _emailError = null;
      _codeError = null;
    });
    try {
      await ref
          .read(accountEmailActionsProvider.notifier)
          .requestCode(email: email, kind: widget.kind);
      if (!mounted) return;
      setState(() {
        _email.text = email;
        _awaitingCode = true;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _emailError = accountEmailFailureMessage(
            l10n,
            error,
            kind: widget.kind,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    if (_busy) return;
    final l10n = context.l10n;
    if (_code.text.length != signInCodeLength) {
      setState(() => _codeError = l10n.signInCodeIncomplete);
      return;
    }
    final email = normalizeEmail(_email.text);
    setState(() {
      _busy = true;
      _codeError = null;
    });
    try {
      await ref
          .read(accountEmailActionsProvider.notifier)
          .confirm(email: email, kind: widget.kind, code: _code.text);
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        if (isAddressRejected(error)) {
          _awaitingCode = false;
          _emailError = accountEmailFailureMessage(
            l10n,
            error,
            kind: widget.kind,
          );
        } else {
          _codeError = accountEmailFailureMessage(
            l10n,
            error,
            kind: widget.kind,
          );
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _changeEmail() {
    setState(() {
      _awaitingCode = false;
      _code.clear();
      _codeError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = _isBackup
        ? (widget.replacing ? l10n.emailsReplaceBackup : l10n.emailsAddBackup)
        : l10n.emailsAddCorporate;
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_awaitingCode) ...[
              Text(l10n.emailsCodeSent(_email.text)),
              const SizedBox(height: 16),
              TextField(
                key: const Key('email-code-input'),
                controller: _code,
                enabled: !_busy,
                autofocus: true,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(signInCodeLength),
                ],
                decoration: InputDecoration(
                  labelText: l10n.signInCodeLabel,
                  errorText: _codeError,
                  errorMaxLines: 3,
                ),
                onChanged: (_) {
                  if (_codeError != null) setState(() => _codeError = null);
                },
                onSubmitted: (_) => _confirm(),
              ),
            ] else
              TextField(
                key: const Key('email-input'),
                controller: _email,
                enabled: !_busy,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: l10n.emailsEmailLabel,
                  errorText: _emailError,
                  errorMaxLines: 3,
                ),
                onChanged: (_) {
                  if (_emailError != null) setState(() => _emailError = null);
                },
                onSubmitted: (_) => _sendCode(),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('email-cancel'),
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.emailsCancel),
        ),
        if (_awaitingCode) ...[
          TextButton(
            key: const Key('email-change'),
            onPressed: _busy ? null : _changeEmail,
            child: Text(l10n.signInChangeEmail),
          ),
          FilledButton(
            key: const Key('email-confirm'),
            onPressed: _busy ? null : _confirm,
            child: Text(l10n.emailsConfirm),
          ),
        ] else
          FilledButton(
            key: const Key('email-get-code'),
            onPressed: _busy ? null : _sendCode,
            child: Text(l10n.emailsGetCode),
          ),
      ],
    );
  }
}
