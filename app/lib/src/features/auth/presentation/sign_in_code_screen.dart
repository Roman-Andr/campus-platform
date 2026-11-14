import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_failure.dart';
import '../../../core/auth/auth_config.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_router.dart';
import '../application/sign_in_flow.dart';
import 'auth_failure_message.dart';
import 'auth_layout.dart';

/// Second step of signing in: the code from the e-mail, with a timer
/// before the code can be sent again.
class SignInCodeScreen extends ConsumerStatefulWidget {
  const SignInCodeScreen({super.key});

  @override
  ConsumerState<SignInCodeScreen> createState() => _SignInCodeScreenState();
}

class _SignInCodeScreenState extends ConsumerState<SignInCodeScreen> {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController();
  Timer? _timer;
  var _resendIn = Duration.zero;
  var _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // The code was just sent.
    _startTimer(ref.read(authConfigProvider).resendDelay);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  String get _email => ref.read(signInFlowProvider).email!;

  void _startTimer(Duration wait) {
    _timer?.cancel();
    setState(() => _resendIn = wait);
    if (wait <= Duration.zero) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final left = _resendIn - const Duration(seconds: 1);
      setState(() => _resendIn = left > Duration.zero ? left : Duration.zero);
      if (_resendIn == Duration.zero) timer.cancel();
    });
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    final code = _code.text;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).signIn(email: _email, code: code);
      // The router leaves the sign-in screens once the session starts.
      ref.read(signInFlowProvider.notifier).reset();
    } on Object catch (error) {
      if (!mounted) return;
      if (isRegistrationRequired(error)) {
        ref.read(signInFlowProvider.notifier).namesRequired(code);
        context.go(AppRoutes.signInName);
        return;
      }
      setState(() => _error = authFailureMessage(context.l10n, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).requestCode(_email);
      _code.clear();
      _startTimer(ref.read(authConfigProvider).resendDelay);
      messenger.showSnackBar(SnackBar(content: Text(l10n.signInResent)));
    } on Object catch (error) {
      if (!mounted) return;
      if (ApiFailure.from(error) case ProblemFailure(:final retryAfter?)) {
        _startTimer(retryAfter);
      }
      setState(() => _error = authFailureMessage(l10n, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final email = ref.watch(signInFlowProvider).email ?? '';
    return AuthLayout(
      title: l10n.signInCodeTitle,
      leading: BackButton(onPressed: () => context.go(AppRoutes.signIn)),
      children: [
        Text(l10n.signInCodeSent(email)),
        authGap,
        Form(
          key: _form,
          child: TextFormField(
            key: const Key('sign-in-code'),
            controller: _code,
            enabled: !_busy,
            autofocus: true,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(signInCodeLength),
            ],
            decoration: InputDecoration(labelText: l10n.signInCodeLabel),
            validator: (value) => (value ?? '').length == signInCodeLength
                ? null
                : l10n.signInCodeIncomplete,
            onChanged: (value) {
              if (value.length == signInCodeLength) unawaited(_submit());
            },
            onFieldSubmitted: (_) => _submit(),
          ),
        ),
        AuthError(_error),
        authGap,
        FilledButton(
          key: const Key('sign-in-submit'),
          onPressed: _busy ? null : _submit,
          child: Text(l10n.signInSubmit),
        ),
        const SizedBox(height: 8),
        TextButton(
          key: const Key('sign-in-resend'),
          onPressed: _busy || _resendIn > Duration.zero ? null : _resend,
          child: Text(
            _resendIn > Duration.zero
                ? l10n.signInResendIn(_countdown(_resendIn))
                : l10n.signInResend,
          ),
        ),
        TextButton(
          onPressed: _busy ? null : () => context.go(AppRoutes.signIn),
          child: Text(l10n.signInChangeEmail),
        ),
      ],
    );
  }

  /// `m:ss`, as on a timer.
  static String _countdown(Duration left) {
    final seconds = left.inSeconds;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}
