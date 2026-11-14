import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'hardcoded_strings.dart';

void main() {
  group('interface strings', () {
    test('are not hardcoded in lib/', () {
      final sources = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .where((file) => !file.path.endsWith('.g.dart'))
          .where((file) => !file.path.contains('/l10n/generated/'))
          .where((file) => !file.path.contains('/api/generated/'));

      final found = [
        for (final file in sources)
          ...findHardcodedStrings(file.path, file.readAsStringSync()),
      ];

      expect(found, isEmpty, reason: 'Move these strings to lib/l10n/*.arb');
    });

    test('checker detects hardcoded interface text', () {
      const source = '''
        import 'package:material_ui/material_ui.dart';
        final a = Text('Hello');
        final b = const Text('Hello');
        final c = IconButton(onPressed: null, tooltip: 'Open', icon: x);
        final d = 'Привет';
        final e = Text('Hi, \$name');
        final ok1 = Text(l10n.title);
        final ok2 = GoRoute(path: '/settings');
        final ok3 = ValueKey('settings.language');
        final ok4 = Text('42');
      ''';

      final found = findHardcodedStrings('sample.dart', source);

      expect(found.map((s) => s.line), [2, 3, 4, 5, 6]);
    });
  });

  test('every locale defines the same messages', () {
    Set<String> keysOf(String locale) {
      final file = File('lib/l10n/app_$locale.arb');
      final arb = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      return arb.keys.where((key) => !key.startsWith('@')).toSet();
    }

    expect(keysOf('en'), keysOf('ru'));
  });
}
