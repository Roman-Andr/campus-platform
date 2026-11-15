import 'package:uuid/uuid.dart';

/// Keys of mutating requests that the user may repeat.
///
/// A repeat after a dropped connection must send the key of the same intent
/// (`Idempotency-Key`), so the server applies the change once. A different
/// intent (another code, mode, participant or reason) starts a new key, and a
/// successful operation drops it.
class MutationKeys {
  MutationKeys({String Function()? generate})
    : _generate = generate ?? const Uuid().v7;

  final String Function() _generate;
  String? _intent;
  String? _key;

  /// The key of [intent], created on first use and kept while it repeats.
  String of(String intent) {
    if (_intent != intent || _key == null) {
      _intent = intent;
      _key = _generate();
    }
    return _key!;
  }

  /// Forgets the key of [intent] once it succeeded.
  void done(String intent) {
    if (_intent != intent) return;
    _intent = null;
    _key = null;
  }
}
