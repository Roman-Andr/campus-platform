import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_failure_message.dart';
import '../../../core/l10n/l10n.dart';
import '../../auth/application/sign_in_flow.dart';
import '../application/my_profile.dart';

/// When [user] may change the name next; `null` when now.
DateTime? nextNameChange(UserOutput user) {
  final at = user.nameChangeAvailableAt;
  return at != null && at.isAfter(clock.now()) ? at : null;
}

/// A date for the user, in the interface language and local time.
String formatDate(BuildContext context, DateTime date) =>
    DateFormat.yMMMMd(Localizations.localeOf(context).toLanguageTag())
        .format(date.toLocal());

/// Changing the real name (ТЗ п. 5.1.1, модуль 1, п. 2); the server allows
/// it once in a while and records every change.
class NameChangeDialog extends ConsumerStatefulWidget {
  const NameChangeDialog({required this.user, super.key});

  final UserOutput user;

  @override
  ConsumerState<NameChangeDialog> createState() => _NameChangeDialogState();
}

class _NameChangeDialogState extends ConsumerState<NameChangeDialog> {
  final _form = GlobalKey<FormState>();
  late final _firstName = TextEditingController(text: widget.user.firstName);
  late final _lastName = TextEditingController(text: widget.user.lastName);
  var _busy = false;
  String? _error;
  var _invalid = <String>{};

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _invalid = {});
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(myProfileProvider.notifier)
          .changeName(
            firstName: _firstName.text.trim(),
            lastName: _lastName.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (!mounted) return;
      final l10n = context.l10n;
      final failure = ApiFailure.from(error);
      setState(() {
        switch (failure) {
          case ProblemFailure(
            code: ProblemCode.nameChangeTooSoon,
            problem: Problem(:final availableAt?),
          ):
            _error = l10n.profileNameTooSoon(formatDate(context, availableAt));
            // The profile shows the date from now on.
            ref.invalidate(myProfileProvider);
          case ProblemFailure(:final fieldErrors) when fieldErrors.isNotEmpty:
            _invalid = {
              for (final field in fieldErrors) ?field.pointer?.split('/').last,
            };
          case _:
            _error = apiFailureMessage(l10n, error);
        }
      });
      _form.currentState!.validate();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _validate(String field, String? value) {
    final l10n = context.l10n;
    if ((value ?? '').trim().isEmpty) return l10n.signInNameRequired;
    if (!isName(value!) || _invalid.contains(field)) {
      return l10n.signInNameInvalid;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final error = _error;
    return AlertDialog(
      title: Text(l10n.profileNameChange),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.profileNameRule),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('name-first'),
              controller: _firstName,
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: l10n.signInFirstName),
              validator: (value) => _validate('first_name', value),
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: const Key('name-last'),
              controller: _lastName,
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: l10n.signInLastName),
              validator: (value) => _validate('last_name', value),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  error,
                  key: const Key('name-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          key: const Key('name-save'),
          onPressed: _busy ? null : () => unawaited(_submit()),
          child: Text(l10n.profileSave),
        ),
      ],
    );
  }
}
