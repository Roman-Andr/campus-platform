import 'dart:convert';

// Real API acceptance of listing photos. Run via
// backend/tests/test_photo_client.py, which provisions two accounts, a
// disposable PostgreSQL/Redis stand, RustFS storage and a photo worker.
import 'package:campus/src/app.dart';
import 'package:campus/src/core/api/client_info.dart';
import 'package:campus/src/core/auth/auth_session.dart';
import 'package:campus/src/core/auth/auth_storage.dart';
import 'package:campus/src/core/photos/photo_upload.dart';
import 'package:campus/src/features/settings/application/settings_controller.dart';
import 'package:campus/src/features/settings/domain/app_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// A 2×2 PNG the server can transcode.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGP4z8AARAwQCgAf7gP9i18U1AAAAABJRU5ErkJggg==',
);

/// Stands in for the system picker, which a test can't drive.
class _Picker implements PhotoPicker {
  @override
  bool get hasCamera => false;
  @override
  Future<List<XFile>> gallery({required int limit}) async => [
    XFile.fromData(_png, name: 'desk.png', path: 'desk.png'),
  ];
  @override
  Future<XFile?> camera() async => null;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const storage = FlutterSecureStorage();
  testWidgets('a photo uploaded by the author is seen by another user', (
    tester,
  ) async {
    const ownerRefresh = String.fromEnvironment('CAMPUS_TEST_OWNER_REFRESH');
    const viewerRefresh = String.fromEnvironment('CAMPUS_TEST_VIEWER_REFRESH');
    expect(ownerRefresh, isNotEmpty);
    ProviderContainer? container;

    Future<void> until(Finder finder) async {
      for (var i = 0; i < 200 && finder.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(finder, findsWidgets);
    }

    Future<void> start(String refresh) async {
      await tester.pumpWidget(const SizedBox());
      container?.dispose();
      await storage.deleteAll();
      await storage.write(
        key: AuthStorage.deviceIdKey,
        value: const String.fromEnvironment('CAMPUS_TEST_DEVICE'),
      );
      await storage.write(key: AuthStorage.refreshTokenKey, value: refresh);
      final package = await PackageInfo.fromPlatform();
      final next = ProviderContainer(
        overrides: [
          clientInfoProvider.overrideWithValue(ClientInfo.current(package)),
          photoPickerProvider.overrideWithValue(_Picker()),
        ],
      );
      container = next;
      await next.read(settingsControllerProvider.future);
      await next
          .read(settingsControllerProvider.notifier)
          .setLanguage(AppLanguage.english);
      await next.read(authStatusProvider.future);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: next, child: const CampusApp()),
      );
      await until(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
    }

    try {
      await start(ownerRefresh);
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await until(find.byKey(const Key('listing-category')));
      await tester.ensureVisible(find.byKey(const Key('listing-category')));
      await tester.tap(find.byKey(const Key('listing-category')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byType(DropdownMenuItem<String>).hitTestable().first,
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('listing-title')),
        'Photo desk',
      );
      await tester.enterText(
        find.byKey(const Key('listing-description')),
        'With a photo',
      );
      await tester.ensureVisible(find.byKey(const Key('photo-gallery')));
      await tester.tap(find.byKey(const Key('photo-gallery')));
      await until(find.text('Photos: 1 of 10'));
      // Uploaded to storage and processed by the worker: no status left.
      for (var i = 0; i < 300; i++) {
        if (find.byKey(const Key('photo-status-0')).evaluate().isEmpty) break;
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const Key('photo-status-0')), findsNothing);
      await tester.ensureVisible(find.text('Publish'));
      await tester.tap(find.text('Publish'));
      await until(find.byIcon(Icons.add));
      await until(find.text('Photo desk'));

      await start(viewerRefresh);
      await until(find.text('Photo desk'));
      await tester.tap(find.text('Photo desk'));
      await until(find.byKey(const Key('listing-gallery')));
      final image = find.descendant(
        of: find.byKey(const Key('listing-gallery')),
        matching: find.byType(RawImage),
      );
      await until(image);
      for (var i = 0; i < 200; i++) {
        if (tester.widgetList<RawImage>(image).any((w) => w.image != null)) {
          break;
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        tester.widgetList<RawImage>(image).any((w) => w.image != null),
        isTrue,
      );
      expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox());
      container?.dispose();
      await storage.deleteAll();
    }
  });
}
