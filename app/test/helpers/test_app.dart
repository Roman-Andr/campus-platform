import 'package:campus/src/app.dart';
import 'package:campus/src/core/database/app_database.dart';
import 'package:campus/src/features/settings/application/settings_controller.dart';
import 'package:campus/src/features/settings/data/settings_repository.dart';
import 'package:campus/src/features/settings/domain/app_settings.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Creates an in-memory database closed at the end of the test.
AppDatabase createTestDatabase() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final database = AppDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  return database;
}

/// Creates a container backed by [database] and disposed after the test.
ProviderContainer createTestContainer(AppDatabase database) {
  final container = ProviderContainer(
    overrides: [appDatabaseProvider.overrideWithValue(database)],
  );
  addTearDown(container.dispose);
  return container;
}

/// Keeps settings in memory: widget tests run in a fake-async zone where
/// real database I/O does not complete. Drift storage is covered by unit
/// tests.
class InMemorySettingsRepository implements SettingsRepository {
  InMemorySettingsRepository([this.saved = const AppSettings()]);

  AppSettings saved;

  @override
  Future<AppSettings> load() async => saved;

  @override
  Future<void> save(AppSettings settings) async => saved = settings;
}

extension PumpCampusApp on WidgetTester {
  /// Starts the app the way `main` does: settings are loaded first.
  Future<ProviderContainer> pumpCampusApp(SettingsRepository repository) async {
    final container = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await container.read(settingsControllerProvider.future);
    await pumpWidget(
      UncontrolledProviderScope(container: container, child: const CampusApp()),
    );
    await pumpAndSettle();
    return container;
  }
}
