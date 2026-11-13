import 'package:campus/src/core/database/app_database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated/schema.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('current schema version is exported to drift_schemas/', () {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    expect(
      GeneratedHelper.versions.last,
      database.schemaVersion,
      reason: 'Run `dart run drift_dev make-migrations` after a schema change.',
    );
  });

  test('fresh install creates the exported schema of its version', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    // Runs onCreate on an empty database and compares the result with
    // drift_schemas/: catches schema changes that were not exported.
    await verifier.migrateAndValidate(database, database.schemaVersion);
    final userVersion = await database
        .customSelect('PRAGMA user_version')
        .getSingle();
    expect(userVersion.read<int>('user_version'), database.schemaVersion);
  });

  // Every exported version must upgrade to every later one.
  group('upgrade', () {
    const versions = GeneratedHelper.versions;
    for (final (i, fromVersion) in versions.indexed) {
      for (final toVersion in versions.skip(i + 1)) {
        test('from v$fromVersion to v$toVersion', () async {
          final schema = await verifier.schemaAt(fromVersion);
          final database = AppDatabase(schema.newConnection());
          addTearDown(database.close);

          await verifier.migrateAndValidate(database, toVersion);
        });
      }
    }
  });
}
