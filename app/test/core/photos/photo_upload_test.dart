import 'package:campus/src/core/photos/photo_upload.dart';
import 'package:campus/src/features/listings/application/listing_photo_draft.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/listings/photo_fixtures.dart';
import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  (ProviderContainer, FakeHttpAdapter) setUp(
    PhotoServer server, {
    PhotoConfig config = testPhotoConfig,
  }) {
    final adapter = FakeHttpAdapter()
      ..route((options) => server.handle(options)!);
    final container = ProviderContainer(
      overrides: [
        ...apiOverrides(adapter: adapter, secure: signedInStorage),
        photoConfigProvider.overrideWithValue(config),
      ],
    );
    addTearDown(container.dispose);
    return (container, adapter);
  }

  test('uploads by the signed form, then waits for processing', () async {
    final server = PhotoServer();
    final (container, adapter) = setUp(server);
    final progress = <double>[];
    var processing = false;
    final file = await container
        .read(photoUploaderProvider)
        .upload(
          transparentPng,
          filename: 'a.png',
          onProgress: progress.add,
          onProcessing: () => processing = true,
        );
    expect(file.id, 'file-1');
    expect(photoFileStatus(file), PhotoFileStatus.ready);
    expect(processing, isTrue);
    expect(progress.last, 1);
    final post = server.storagePosts.single;
    final form = post.data! as FormData;
    expect(form.fields.map((f) => f.key), ['key', 'policy']);
    expect(form.files.single.key, 'file');
    expect(post.headers['Authorization'], isNull);
    expect(
      adapter.sent.map((r) => '${r.method} ${r.path}'),
      containsAllInOrder([
        'POST /api/v1/files/photo-uploads',
        'POST $storageUrl',
        'POST /api/v1/files/file-1/complete',
        'GET /api/v1/files/file-1',
      ]),
    );
  });

  test('returns a rejection with its reason', () async {
    final (container, _) = setUp(
      PhotoServer(verdicts: {'file-1': 'unsupported_image'}),
    );
    final file = await container
        .read(photoUploaderProvider)
        .upload(transparentPng, filename: 'a.gif');
    expect(photoFileStatus(file), PhotoFileStatus.rejected);
    expect(file.rejectionReason, 'unsupported_image');
  });

  test('gives up when processing takes too long', () async {
    final adapter = FakeHttpAdapter()
      ..route((options) {
        if (options.path.startsWith('/api/v1/files/file-1') &&
            options.method == 'GET') {
          return jsonBody(200, fileJson('file-1', status: 'processing'));
        }
        return PhotoServer().handle(options)!;
      });
    final container = ProviderContainer(
      overrides: [
        ...apiOverrides(adapter: adapter, secure: signedInStorage),
        photoConfigProvider.overrideWithValue(
          const PhotoConfig(
            maxBytes: 100,
            listingLimit: 10,
            pollInterval: Duration(milliseconds: 1),
            processingTimeout: Duration(milliseconds: 20),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await expectLater(
      container
          .read(photoUploaderProvider)
          .upload(transparentPng, filename: 'a.png'),
      throwsA(isA<PhotoProcessingTimeout>()),
    );
  });

  group('listing photo draft', () {
    Future<List<PhotoSlot>> settled(ProviderContainer container) async {
      final sub = container.listen(listingPhotoDraftProvider, (_, _) {});
      addTearDown(sub.close);
      for (var i = 0; i < 100; i++) {
        if (!container.read(listingPhotoDraftProvider).any((s) => s.busy)) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      return container.read(listingPhotoDraftProvider);
    }

    test('refuses files over the limit and over 10 MB', () async {
      final (container, _) = setUp(PhotoServer());
      final sub = container.listen(listingPhotoDraftProvider, (_, _) {});
      addTearDown(sub.close);
      final draft = container.read(listingPhotoDraftProvider.notifier);
      final result = await draft.add([
        photoFile('big.jpg', size: 10 * 1024 * 1024 + 1),
        for (var i = 0; i < 11; i++) photoFile('p$i.png'),
      ]);
      expect(result.tooLarge, ['big.jpg']);
      expect(result.overLimit, 1);
      final slots = await settled(container);
      expect(slots, hasLength(10));
      expect(draft.room, 0);
      final more = await draft.add([photoFile('extra.png')]);
      expect(more.overLimit, 1);
      expect(container.read(listingPhotoDraftProvider), hasLength(10));
    });

    test('a rejected photo stays visible and is left out', () async {
      final (container, _) = setUp(
        PhotoServer(verdicts: {'file-2': 'invalid_image'}),
      );
      final sub = container.listen(listingPhotoDraftProvider, (_, _) {});
      addTearDown(sub.close);
      final draft = container.read(listingPhotoDraftProvider.notifier);
      await draft.add([photoFile('a.png'), photoFile('b.png')]);
      final slots = await settled(container);
      expect(slots.map((s) => s.phase), [
        PhotoSlotPhase.ready,
        PhotoSlotPhase.rejected,
      ]);
      expect(slots[1].rejectionReason, 'invalid_image');
      expect(draft.readyIds, ['file-1']);
    });

    test('a failed upload can be retried', () async {
      final (container, _) = setUp(PhotoServer(verdicts: {'file-1': null}));
      final sub = container.listen(listingPhotoDraftProvider, (_, _) {});
      addTearDown(sub.close);
      final draft = container.read(listingPhotoDraftProvider.notifier);
      await draft.add([photoFile('a.png')]);
      var slot = (await settled(container)).single;
      expect(slot.phase, PhotoSlotPhase.failed);
      draft.retry(slot.key);
      slot = (await settled(container)).single;
      expect(slot.phase, PhotoSlotPhase.ready);
      expect(draft.readyIds, ['file-2']);
    });

    test('reorders and removes photos', () async {
      final (container, _) = setUp(PhotoServer());
      final sub = container.listen(listingPhotoDraftProvider, (_, _) {});
      addTearDown(sub.close);
      final draft = container.read(listingPhotoDraftProvider.notifier);
      await draft.add([photoFile('a'), photoFile('b'), photoFile('c')]);
      await settled(container);
      expect(draft.readyIds, ['file-1', 'file-2', 'file-3']);
      draft.move(0, 2);
      expect(draft.readyIds, ['file-2', 'file-3', 'file-1']);
      draft.move(2, 1);
      expect(draft.readyIds, ['file-2', 'file-1', 'file-3']);
      draft.remove(container.read(listingPhotoDraftProvider).first.key);
      expect(draft.readyIds, ['file-1', 'file-3']);
    });
  });
}
