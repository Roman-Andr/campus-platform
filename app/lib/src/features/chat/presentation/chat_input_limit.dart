import 'package:flutter/services.dart';

/// Limits a chat message by Unicode code points, as the server counts them.
///
/// Flutter's [LengthLimitingTextInputFormatter] counts grapheme clusters, so
/// a message of 3000 emoji would fit there while the server sees 3000 code
/// points (and some mixed text sees many more). Counting runes keeps the
/// composer and the queue consistent with Python's `len`.
class ChatMessageLengthFormatter extends TextInputFormatter {
  const ChatMessageLengthFormatter(this.maxLength);

  final int maxLength;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.runes.length <= maxLength) return newValue;
    final truncated = String.fromCharCodes(newValue.text.runes.take(maxLength));
    return TextEditingValue(
      text: truncated,
      selection: TextSelection.collapsed(offset: truncated.length),
    );
  }
}
