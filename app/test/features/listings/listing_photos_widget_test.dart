import 'dart:async';

import 'package:campus/src/core/photos/photo_upload.dart';
import 'package:campus/src/core/router/app_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Visibility;

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';
import 'fixtures.dart';
import 'photo_fixtures.dart';

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.localesTestValue = const [Locale('en')];
    binding.platformDispatcher.views.first.physicalSize = const Size(
      1200,
      2400,
    );
  });
  tearDown(() {
    final binding = TestWidgetsFlutterBinding.instance;
    binding.platformDispatcher.clearLocalesTestValue();
    binding.platformDispatcher.views.first.resetPhysicalSize();
  });

  Future<void> fillForm(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('listing-title')), 'A desk');
    await tester.enterText(
      find.byKey(const Key('listing-description')),
      'Collect on campus',
    );
    await tester.tap(find.byKey(const Key('listing-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Items').last);
    await tester.pumpAndSettle();
  }

  testWidgets('rejected photo shows its reason and the rest is attached', (
    tester,
  ) async {
    final photos = PhotoServer(verdicts: {'file-2': 'invalid_image'});
    final server = FakeHttpAdapter()
      ..route(
        (options) => photos.handle(options) ?? jsonBody(201, listingJson()),
      );
    final picker = FakePhotoPicker(
      files: [photoFile('a.png'), photoFile('b.png'), photoFile('c.png')],
    );
    await tester.pumpCampusApp(
      InMemorySettingsRepository(),
      adapter: server,
      overrides: [
        photoPickerProvider.overrideWithValue(picker),
        photoConfigProvider.overrideWithValue(testPhotoConfig),
      ],
    );
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await fillForm(tester);
    await tester.tap(find.byKey(const Key('photo-gallery')));
    await tester.pumpAndSettle();
    expect(picker.lastLimit, 10);
    expect(find.text('Photos: 3 of 10'), findsOneWidget);
    expect(
      find.text('Rejected: the file is damaged or not an image'),
      findsOneWidget,
    );
    // The last photo goes first; the order reaches the server.
    await tester.tap(find.byKey(const Key('photo-earlier-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('photo-earlier-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();
    expect(
      server.sent.where((r) => r.path.endsWith('/giveaways')),
      hasLength(1),
    );
    expect(photos.attached, [
      ['file-3', 'file-1'],
    ]);
  });

  testWidgets('form refuses an 11th photo and files over 10 MB', (
    tester,
  ) async {
    final photos = PhotoServer();
    final server = FakeHttpAdapter()
      ..route(
        (options) => photos.handle(options) ?? jsonBody(201, listingJson()),
      );
    final picker = FakePhotoPicker(
      files: [
        photoFile('huge.jpg', size: 10 * 1024 * 1024 + 1),
        for (var i = 0; i < 11; i++) photoFile('p$i.png'),
      ],
    );
    await tester.pumpCampusApp(
      InMemorySettingsRepository(),
      adapter: server,
      overrides: [
        photoPickerProvider.overrideWithValue(picker),
        photoConfigProvider.overrideWithValue(testPhotoConfig),
      ],
    );
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('photo-gallery')));
    await tester.pumpAndSettle();
    expect(find.text('Photos: 10 of 10'), findsOneWidget);
    expect(find.text('You can add up to 10 photos'), findsOneWidget);
    expect(
      find.text('huge.jpg: the file is larger than 10 MB'),
      findsOneWidget,
    );
    expect(photos.storagePosts, hasLength(10));
    for (final key in ['photo-gallery', 'photo-camera']) {
      expect(
        tester.widget<ButtonStyleButton>(find.byKey(Key(key))).onPressed,
        isNull,
      );
    }
    await tester.tap(find.byKey(const Key('photo-remove-0')));
    await tester.pumpAndSettle();
    expect(find.text('Photos: 9 of 10'), findsOneWidget);
    expect(
      tester
          .widget<ButtonStyleButton>(find.byKey(const Key('photo-gallery')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('publishing waits for uploads; a failed upload is retried', (
    tester,
  ) async {
    final photos = PhotoServer(verdicts: {'file-1': null});
    final server = FakeHttpAdapter()
      ..route(
        (options) => photos.handle(options) ?? jsonBody(201, listingJson()),
      );
    await tester.pumpCampusApp(
      InMemorySettingsRepository(),
      adapter: server,
      overrides: [
        photoPickerProvider.overrideWithValue(
          FakePhotoPicker(files: [photoFile('a.png')], hasCamera: false),
        ),
        photoConfigProvider.overrideWithValue(testPhotoConfig),
      ],
    );
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('photo-camera')), findsNothing);
    await tester.tap(find.byKey(const Key('photo-gallery')));
    await tester.pump();
    await tester.pump();
    expect(find.text('Wait until the photos finish uploading'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Publish'))
          .onPressed,
      isNull,
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        "Can't reach the server. Check your internet connection and try again.",
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('photo-retry-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('photo-status-0')), findsNothing);
    await fillForm(tester);
    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();
    expect(photos.attached, [
      ['file-2'],
    ]);
  });

  testWidgets('card shows a gallery and the feed shows a preview', (
    tester,
  ) async {
    final server =
        FakeHttpAdapter(
          feed: pageJson([listingJson(author: 'other')]),
          photos: {
            'items': [photoJson('file-1'), photoJson('file-2')],
          },
        )..route(
          (options) => options.path.endsWith('/token/refresh')
              ? jsonBody(200, tokensJson(1))
              : jsonBody(200, listingJson(author: 'other')),
        );
    final container = await tester.pumpCampusApp(
      InMemorySettingsRepository(),
      adapter: server,
    );
    expect(
      find.byKey(const Key('listing-thumbnail-listing-1')),
      findsOneWidget,
    );
    unawaited(container.read(appRouterProvider).push('/listings/listing-1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('listing-gallery')), findsOneWidget);
    expect(find.text('Photo 1 of 2'), findsOneWidget);
    await tester.drag(
      find.byKey(const Key('listing-gallery')),
      const Offset(-800, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('Photo 2 of 2'), findsOneWidget);
  });

  testWidgets('card without photos has no gallery', (tester) async {
    final server = FakeHttpAdapter()
      ..route(
        (options) => options.path.endsWith('/token/refresh')
            ? jsonBody(200, tokensJson(1))
            : jsonBody(200, listingJson(author: 'other')),
      );
    final container = await tester.pumpCampusApp(
      InMemorySettingsRepository(),
      adapter: server,
    );
    unawaited(container.read(appRouterProvider).push('/listings/listing-1'));
    await tester.pumpAndSettle();
    expect(find.text('A desk'), findsOneWidget);
    expect(find.byKey(const Key('listing-gallery')), findsNothing);
  });

  testWidgets('editing a draft shows attached photos and saves the order', (
    tester,
  ) async {
    final photos = PhotoServer();
    final server =
        FakeHttpAdapter(
          photos: {
            'items': [photoJson('file-9')],
          },
        )..route((options) {
          if (options.path.endsWith('/mine')) {
            return jsonBody(200, pageJson([listingJson(status: 'draft')]));
          }
          if (options.method == 'PATCH') {
            return jsonBody(200, {
              ...listingJson(status: 'draft'),
              'version': 2,
            });
          }
          return photos.handle(options) ??
              jsonBody(200, listingJson(status: 'draft'));
        });
    final container = await tester.pumpCampusApp(
      InMemorySettingsRepository(),
      adapter: server,
      overrides: [
        photoPickerProvider.overrideWithValue(
          FakePhotoPicker(files: [photoFile('a.png')], hasCamera: false),
        ),
        photoConfigProvider.overrideWithValue(testPhotoConfig),
      ],
    );
    unawaited(container.read(appRouterProvider).push('/my-listings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('my-section-drafts')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit draft'));
    await tester.pumpAndSettle();
    // The form opens with the photo already attached on the server.
    expect(find.text('Photos: 1 of 10'), findsOneWidget);
    await tester.tap(find.byKey(const Key('photo-gallery')));
    await tester.pumpAndSettle();
    expect(find.text('Photos: 2 of 10'), findsOneWidget);
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(server.sent.where((r) => r.method == 'PATCH'), hasLength(1));
    expect(photos.attached, [
      ['file-9', 'file-1'],
    ]);
  });
}
