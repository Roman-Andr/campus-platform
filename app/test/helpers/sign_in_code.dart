import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Waits for an editable code field and restores focus after a busy frame.
///
/// On a device, disabling the field closes the IME connection without
/// clearing the test binding's focusedEditable cache. enterText alone then
/// skips requestKeyboard for the same field and silently loses the input.
Future<void> enterSignInCode(WidgetTester tester, String code) async {
  final field = find.byKey(const Key('sign-in-code'));
  final editable = find.descendant(
    of: field,
    matching: find.byType(EditableText),
  );
  bool ready() =>
      field.evaluate().isNotEmpty &&
      tester.widget<TextFormField>(field).enabled == true &&
      !tester.widget<EditableText>(editable).readOnly &&
      tester.widget<EditableText>(editable).focusNode.canRequestFocus;

  for (var i = 0; i < 100 && !ready(); i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(ready(), isTrue, reason: 'The code field must accept input');
  // Bypass WidgetTester.showKeyboard's cached focusedEditable check.
  tester.state<EditableTextState>(editable).requestKeyboard();
  await tester.pump();
  expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
  await tester.enterText(field, code);
  expect(tester.widget<EditableText>(editable).controller.text, code);
}
