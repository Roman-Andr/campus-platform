import 'package:campus/src/features/chat/presentation/chat_input_limit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const formatter = ChatMessageLengthFormatter(4000);

  test('counts Unicode code points, not UTF-16 units', () {
    final emoji = '👍' * 4000;
    expect(emoji.length, 8000);

    final accepted = formatter.formatEditUpdate(
      TextEditingValue.empty,
      TextEditingValue(text: emoji),
    );
    expect(accepted.text, emoji);
  });

  test('truncates a paste at the server code-point limit', () {
    final tooLong = '👍' * 4001;
    final limited = formatter.formatEditUpdate(
      TextEditingValue.empty,
      TextEditingValue(text: tooLong),
    );

    expect(limited.text.runes.length, 4000);
    expect(limited.text, '👍' * 4000);
    expect(limited.selection.baseOffset, limited.text.length);
  });

  test('a family emoji counts all of its code points', () {
    const family = '👨‍👩‍👧‍👦';
    expect(family.runes.length, 7);
    const small = ChatMessageLengthFormatter(7);

    final limited = small.formatEditUpdate(
      TextEditingValue.empty,
      TextEditingValue(text: family * 2),
    );
    expect(limited.text.runes.length, 7);
  });
}
