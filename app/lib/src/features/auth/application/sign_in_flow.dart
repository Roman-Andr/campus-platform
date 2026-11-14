import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'sign_in_flow.g.dart';

/// What the user has entered so far on the sign-in screens.
@immutable
class SignInDraft {
  const SignInDraft({this.email, this.code});

  /// The address a code was sent to; set once the code is requested.
  final String? email;

  /// A code accepted by the server for an address without an account;
  /// set when the names are still needed.
  final String? code;

  /// Never includes the code: it must not reach logs.
  @override
  String toString() => 'SignInDraft(codeSent: ${email != null})';
}

/// Steps of signing in: e-mail, code, then names for a new account.
@Riverpod(keepAlive: true)
class SignInFlow extends _$SignInFlow {
  @override
  SignInDraft build() => const SignInDraft();

  void codeSent(String email) => state = SignInDraft(email: email);

  void namesRequired(String code) =>
      state = SignInDraft(email: state.email, code: code);

  void reset() => state = const SignInDraft();
}

/// Normalizes an address as the server does: trimmed, lower case.
String normalizeEmail(String email) => email.trim().toLowerCase();

final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

bool isEmail(String value) => _email.hasMatch(value);

/// Letters, spaces, hyphens and apostrophes, with at least one letter —
/// the names the server accepts.
bool isName(String value) {
  final name = value.trim();
  return name.isNotEmpty &&
      _letter.hasMatch(name) &&
      _nameCharacters.hasMatch(name);
}

final _letter = RegExp(r'\p{L}', unicode: true);
final _nameCharacters = RegExp(r"^[\p{L}\p{M} \-'’]+$", unicode: true);

/// Length of sign-in codes.
const signInCodeLength = 6;
