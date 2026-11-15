import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/core/l10n/l10n.dart';
import 'package:campus/src/features/chat/presentation/chat_labels.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const forbidden = ProblemFailure(
    Problem(
      type: 'urn:problem:campus:chat_forbidden',
      title: 'Forbidden',
      status: 403,
      detail: 'Personal messaging with this user is not available.',
      code: ProblemCode.chatForbidden,
    ),
  );

  test('an unavailable dialog never names a block', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(
      chatFailureMessage(l10n, forbidden),
      'Personal messaging with this user is unavailable.',
    );
    expect(chatFailureMessage(l10n, forbidden), isNot(contains('block')));
  });

  test('an alumni refusal still explains the alumni rule', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(
      chatFailureMessage(l10n, forbidden, alumni: true),
      'Alumni can write only in existing chats.',
    );
  });
}
