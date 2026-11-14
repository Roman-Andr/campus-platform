import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_router.dart';
import '../../consents/application/consents.dart';
import '../../consents/presentation/consent_documents.dart';
import '../application/sign_in_flow.dart';
import 'auth_failure_message.dart';
import 'auth_layout.dart';

/// Last step for a new user: first and last names to create the account.
class SignInNameScreen extends ConsumerStatefulWidget {
  const SignInNameScreen({super.key});

  @override
  ConsumerState<SignInNameScreen> createState() => _SignInNameScreenState();
}

class _SignInNameScreenState extends ConsumerState<SignInNameScreen> {
  final _form = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  var _busy = false;
  var _accepted = false;
  var _crossBorder = false;
  String? _error;

  /// Fields the server rejected, by name.
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
    final documents = ref.read(documentsProvider).asData?.value;
    if (!_accepted ||
        documents == null ||
        requiredDocumentIds(documents).isEmpty) {
      return;
    }
    final draft = ref.read(signInFlowProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authServiceProvider)
          .signIn(
            email: draft.email!,
            code: draft.code!,
            firstName: _firstName.text.trim(),
            lastName: _lastName.text.trim(),
            acceptedDocumentIds: requiredDocumentIds(documents),
            crossBorderDocumentId: _crossBorder
                ? crossBorderDocument(documents)?.id
                : null,
          );
      ref.read(signInFlowProvider.notifier).reset();
    } on Object catch (error) {
      if (!mounted) return;
      if (ApiFailure.from(error) case ProblemFailure(
        code: ProblemCode.consentRequired || ProblemCode.consentInvalid,
      )) {
        ref.invalidate(documentsProvider);
        setState(() {
          _accepted = false;
          _crossBorder = false;
          _error = context.l10n.consentUpdateIntro;
        });
        return;
      }
      final fields = switch (ApiFailure.from(error)) {
        ProblemFailure(:final fieldErrors) => {
          for (final field in fieldErrors) ?field.pointer?.split('/').last,
        },
        _ => <String>{},
      };
      setState(() {
        _invalid = fields;
        _error = fields.isEmpty
            ? authFailureMessage(context.l10n, error)
            : null;
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
    final documents = ref.watch(documentsProvider).asData?.value;
    final canDecide =
        !_busy &&
        documents != null &&
        requiredDocumentIds(documents).isNotEmpty;
    return AuthLayout(
      title: l10n.signInNameTitle,
      leading: BackButton(onPressed: () => context.go(AppRoutes.signIn)),
      children: [
        Text(l10n.signInNameIntro),
        authGap,
        Form(
          key: _form,
          child: Column(
            children: [
              TextFormField(
                key: const Key('sign-in-first-name'),
                controller: _firstName,
                enabled: !_busy,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.givenName],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: l10n.signInFirstName),
                validator: (value) => _validate('first_name', value),
              ),
              authGap,
              TextFormField(
                key: const Key('sign-in-last-name'),
                controller: _lastName,
                enabled: !_busy,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.familyName],
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(labelText: l10n.signInLastName),
                validator: (value) => _validate('last_name', value),
                onFieldSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
        const ConsentDocuments(),
        ConsentCheckboxes(
          requiredAccepted: _accepted,
          crossBorderAccepted: _crossBorder,
          onRequiredChanged: !canDecide
              ? null
              : (value) => setState(() => _accepted = value),
          onCrossBorderChanged: !canDecide
              ? null
              : (value) => setState(() => _crossBorder = value),
        ),
        AuthError(_error),
        authGap,
        FilledButton(
          key: const Key('sign-in-finish'),
          onPressed: _busy ? null : _submit,
          child: Text(l10n.signInFinish),
        ),
      ],
    );
  }
}
