import 'dart:convert';

import 'package:campus/src/app.dart';
import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/core/api/api_config.dart';
import 'package:campus/src/core/api/client_info.dart';
import 'package:campus/src/core/api/network_status.dart';
import 'package:campus/src/core/auth/auth_session.dart';
import 'package:campus/src/core/auth/auth_storage.dart';
import 'package:campus/src/core/database/app_database.dart';
import 'package:campus/src/core/photos/photo_image.dart';
import 'package:campus/src/features/listings/data/listings_repository.dart';
import 'package:campus/src/features/settings/application/settings_controller.dart';
import 'package:campus/src/features/settings/data/settings_repository.dart';
import 'package:campus/src/features/settings/domain/app_settings.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show MemoryImage;

import 'fake_api.dart';

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

/// Refresh token of a signed-in user in tests.
const testRefreshToken = 'refresh-token-secret';

/// Contents of the secure storage of a device with a signed-in user.
const signedInStorage = {
  AuthStorage.refreshTokenKey: testRefreshToken,
  AuthStorage.cacheNamespaceKey: 'test-session-cache',
  AuthStorage.deviceIdKey: '01890a5d-ac96-774b-bcce-b302099a8057',
};

/// Replaces the server, the device network and the settings storage:
/// requests go to [adapter], network changes come from [network] (none by
/// default), settings are kept in [settings], the secure storage starts
/// with [secure] (no session by default).
List<Override> apiOverrides({
  FakeHttpAdapter? adapter,
  ListingsCache? cache,
  Stream<bool>? network,
  SettingsRepository? settings,
  Map<String, String> secure = const {},
}) {
  FlutterSecureStorage.setMockInitialValues(Map.of(secure));
  return _overrides(adapter, network, settings, cache);
}

List<Override> _overrides(
  FakeHttpAdapter? adapter,
  Stream<bool>? network,
  SettingsRepository? settings,
  ListingsCache? cache,
) => [
  listingsCacheProvider.overrideWithValue(cache ?? InMemoryListingsCache()),
  settingsRepositoryProvider.overrideWithValue(
    settings ?? InMemorySettingsRepository(),
  ),
  apiConfigProvider.overrideWithValue(testApiConfig),
  photoImageProvider.overrideWithValue(
    (url, {required cacheKey}) => MemoryImage(transparentPng),
  ),
  clientInfoProvider.overrideWithValue(testClientInfo),
  apiHttpAdapterProvider.overrideWithValue(adapter ?? FakeHttpAdapter()),
  networkAvailabilityProvider.overrideWith(
    (ref) => network ?? const Stream.empty(),
  ),
];

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
  /// Starts the app the way `main` does: settings and the session are
  /// loaded first. A user is signed in unless [secure] says otherwise.
  Future<ProviderContainer> pumpCampusApp(
    SettingsRepository repository, {
    FakeHttpAdapter? adapter,
    ListingsCache? cache,
    Stream<bool>? network,
    Map<String, String> secure = signedInStorage,
    List<Override> overrides = const [],
  }) async {
    final container = ProviderContainer(
      overrides: [
        ...apiOverrides(
          adapter: adapter,
          cache: cache,
          network: network,
          settings: repository,
          secure: secure,
        ),
        ...overrides,
      ],
    );
    addTearDown(container.dispose);
    await container.read(settingsControllerProvider.future);
    await container.read(authStatusProvider.future);
    await pumpWidget(
      UncontrolledProviderScope(container: container, child: const CampusApp()),
    );
    await pumpAndSettle();
    return container;
  }
}

/// Cache double for widget tests; real Drift is exercised in unit tests.
class InMemoryListingsCache implements ListingsCache {
  final pages = <String, PageListingOutput>{};
  @override
  Future<PageListingOutput?> load(String owner, Visibility area) async =>
      pages['$owner/${area.toJson()}'];
  @override
  Future<void> save(
    String owner,
    Visibility area,
    PageListingOutput page,
  ) async {
    pages['$owner/${area.toJson()}'] = page;
  }

  @override
  Future<void> clear() async => pages.clear();
}

/// A 1×1 transparent PNG: network photos are not fetched in widget tests.
final transparentPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);
