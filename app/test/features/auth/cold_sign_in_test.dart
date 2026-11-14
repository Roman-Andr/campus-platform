import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/sign_in_code.dart';
import '../../helpers/test_app.dart';

const _signIn = '/api/v1/auth/sign-in';
final _code = find.byKey(const Key('sign-in-code'));

// Integration tests use the real IME, so clearClient does not reset the
// binding's cached focusedEditable. Keep that behavior with a stub IME.
class _DeviceKeyboardBinding extends AutomatedTestWidgetsFlutterBinding {
  final stubIme = TestTextInput();

  @override
  bool get registerTestTextInput => false;

  @override
  TestTextInput get testTextInput => stubIme;
}

void main() {
  final binding = _DeviceKeyboardBinding();
  testWidgets('a correct code after a delayed wrong-code response is sent', (
    tester,
  ) async {
    final server = _DelayedSignInAdapter();
    binding.stubIme.register();
    addTearDown(binding.stubIme.unregister);
    await tester.pumpCampusApp(
      InMemorySettingsRepository(),
      adapter: server,
      secure: const {},
    );
    server
      ..reply(202, null)
      ..replyProblem(401, 'sign_in_code_invalid')
      ..replyProblem(422, 'registration_required');
    await tester.enterText(
      find.byKey(const Key('sign-in-email')),
      'it@edu.hse.ru',
    );
    await tester.tap(find.byKey(const Key('sign-in-get-code')));
    await tester.pumpAndSettle();

    EditableText editable() => tester.widget<EditableText>(
      find.descendant(of: _code, matching: find.byType(EditableText)),
    );

    await tester.enterText(_code, '000000');
    await tester.pump();
    expect(tester.widget<TextFormField>(_code).enabled, isFalse);
    expect(editable().focusNode.hasFocus, isFalse);
    expect(server.sent.where((r) => r.path == _signIn), hasLength(1));
    expect(find.byKey(const Key('auth-error')), findsNothing);

    server.releaseResponse.complete();
    for (var i = 0; i < 100; i++) {
      if (find.byKey(const Key('auth-error')).evaluate().isNotEmpty) break;
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('auth-error')), findsOneWidget);
    expect(tester.widget<TextFormField>(_code).enabled, isTrue);
    expect(server.sent.where((r) => r.path == _signIn), hasLength(1));
    expect(editable().focusNode.hasFocus, isFalse);

    // Negative control: the old integration-test action loses this input.
    expect(
      binding.focusedEditable,
      tester.state(
        find.descendant(of: _code, matching: find.byType(EditableText)),
      ),
    );
    await tester.enterText(_code, '123456');
    await tester.pumpAndSettle();
    expect(editable().controller.text, '000000');
    expect(editable().focusNode.hasFocus, isFalse);
    expect(server.sent.where((r) => r.path == _signIn), hasLength(1));

    await enterSignInCode(tester, '123456');
    await tester.pumpAndSettle();
    expect(
      server.sent.where((r) => r.path == _signIn).map((r) => r.json['code']),
      ['000000', '123456'],
    );
    expect(find.byKey(const Key('sign-in-first-name')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

/// Holds the first sign-in response until the busy field has lost focus.
class _DelayedSignInAdapter extends FakeHttpAdapter {
  final releaseResponse = Completer<void>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final response = await super.fetch(options, requestStream, cancelFuture);
    if (options.path == _signIn) await releaseResponse.future;
    return response;
  }
}
