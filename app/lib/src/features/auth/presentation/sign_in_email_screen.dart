import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_router.dart';
import '../application/sign_in_flow.dart';
import 'auth_failure_message.dart';
import 'auth_layout.dart';

/// First step of signing in: the university e-mail to send a code to.
class SignInEmailScreen extends ConsumerStatefulWidget {
  const SignInEmailScreen({super.key});

  @override
  ConsumerState<SignInEmailScreen> createState() => _SignInEmailScreenState();
}

class _SignInEmailScreenState extends ConsumerState<SignInEmailScreen> {
  final _form = GlobalKey<FormState>();
  late final _email = TextEditingController(
    text: ref.read(signInFlowProvider).email,
  );
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    final email = normalizeEmail(_email.text);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).requestCode(email);
      if (!mounted) return;
      ref.read(signInFlowProvider.notifier).codeSent(email);
      context.go(AppRoutes.signInCode);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = authFailureMessage(context.l10n, error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AuthLayout(
      title: l10n.signInTitle,
      children: [
        Text(l10n.signInEmailIntro),
        authGap,
        Form(
          key: _form,
          child: TextFormField(
            key: const Key('sign-in-email'),
            controller: _email,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(labelText: l10n.signInEmailLabel),
            validator: (value) => isEmail(normalizeEmail(value ?? ''))
                ? null
                : l10n.signInEmailInvalid,
            onFieldSubmitted: (_) => _submit(),
          ),
        ),
        AuthError(_error),
        authGap,
        FilledButton(
          key: const Key('sign-in-get-code'),
          onPressed: _busy ? null : _submit,
          child: Text(l10n.signInGetCode),
        ),
      ],
    );
  }
}
