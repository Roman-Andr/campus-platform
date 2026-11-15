import 'dart:convert';

/// Encodes [bytes] as unpadded base64url, the encoding of the API and of QR
/// payloads.
String base64UrlNoPadding(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

final _base64UrlAlphabet = RegExp(r'^[A-Za-z0-9_-]+={0,2}$');

/// Decodes unpadded (or padded) base64url strictly; `null` when the value is
/// not valid base64url.
List<int>? tryBase64UrlDecode(String value) {
  if (!_base64UrlAlphabet.hasMatch(value)) return null;
  try {
    return base64Url.decode(base64Url.normalize(value));
  } on FormatException {
    return null;
  }
}
