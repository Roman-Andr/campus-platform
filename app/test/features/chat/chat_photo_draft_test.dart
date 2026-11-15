import 'dart:async';

import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/core/auth/auth_service.dart';
import 'package:campus/src/core/auth/auth_session.dart';
import 'package:campus/src/core/auth/auth_token.dart';
import 'package:campus/src/core/database/app_database.dart';
import 'package:campus/src/core/photos/photo_upload.dart';
import 'package:campus/src/features/chat/application/chat_config.dart';
import 'package:campus/src/features/chat/application/chat_photo_draft.dart';
import 'package:campus/src/features/chat/data/chat_photo_uploader.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';
import 'chat_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeChatPhotoUploader uploader;
  late FakeChatApi chatApi;
  late FakeHttpAdapter server;
  late ProviderContainer container;
  late ProviderSubscription<List<ChatPhotoSlot>> listener;

  Future<void> create({
    int maxPhotos = 3,
    int maxBytes = 1000,
    bool realUploader = false,
  }) async {
    uploader = FakeChatPhotoUploader();
    chatApi = FakeChatApi();
    server = FakeHttpAdapter();
    final config = PhotoConfig(
      maxBytes: maxBytes,
      listingLimit: 10,
      pollInterval: Duration.zero,
      processingTimeout: const Duration(seconds: 1),
    );
    final photoUploader = realUploader
        ? StorageChatPhotoUploader(
            api: chatApi,
            storage: Dio()..httpClientAdapter = server,
            config: config,
          )
        : uploader;
    container = ProviderContainer(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(createTestDatabase()),
        chatConfigProvider.overrideWithValue(
          ChatConfig(
            maxMessageLength: 4000,
            maxPhotos: maxPhotos,
            retryDelays: const [],
          ),
        ),
        photoConfigProvider.overrideWithValue(config),
        chatPhotoUploaderProvider.overrideWithValue(photoUploader),
        ...apiOverrides(adapter: server, secure: signedInStorage),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authStatusProvider.future);
    listener = container.listen(chatPhotoDraftProvider(testChatId), (_, _) {});
    addTearDown(listener.close);
  }

  ChatPhotoDraft draft() =>
      container.read(chatPhotoDraftProvider(testChatId).notifier);

  List<ChatPhotoSlot> slots() =>
      container.read(chatPhotoDraftProvider(testChatId));

  test('a processed photo becomes a ready file id', () async {
    await create();
    final result = await draft().add([testImage('one.png')]);
    await pumpEventQueue(times: 40);

    expect(result.ok, isTrue);
    expect(slots().single.phase, ChatPhotoPhase.ready);
    expect(draft().readyIds, ['upload-1']);
    expect(draft().busy, isFalse);
    expect(uploader.calls.single.chatId, testChatId);
  });

  test('a rejected photo is never ready and blocks the send', () async {
    await create();
    uploader
      ..statuses.add('rejected')
      ..rejectionReasons.add('invalid_image');

    await draft().add([testImage('bad.png')]);
    await pumpEventQueue(times: 40);

    expect(slots().single.phase, ChatPhotoPhase.rejected);
    expect(slots().single.rejectionReason, 'invalid_image');
    expect(draft().readyIds, isEmpty);
    expect(draft().failed, isTrue);
  });

  test('a failed upload can be retried without losing the slot', () async {
    await create();
    uploader.error = const NetworkFailure();

    await draft().add([testImage('one.png')]);
    await pumpEventQueue(times: 40);
    final failed = slots().single;
    expect(failed.phase, ChatPhotoPhase.failed);

    draft().retry(failed.key);
    await pumpEventQueue(times: 40);

    expect(slots().single.phase, ChatPhotoPhase.ready);
    expect(draft().readyIds, ['upload-1']);
    expect(uploader.calls, hasLength(2));
  });

  test('respects the photo count and the file size', () async {
    await create(maxPhotos: 1, maxBytes: 10);
    final result = await draft().add([
      testImage('large.png'),
      testImage('second.png'),
    ]);

    expect(result.tooLarge, hasLength(2));
    expect(slots(), isEmpty);
  });

  test('an expired form starts a new upload with fresh keys', () async {
    await create();
    uploader.error = const ChatPhotoFormExpired();

    await draft().add([testImage('one.png')]);
    await pumpEventQueue(times: 40);
    final failed = slots().single;
    expect(failed.phase, ChatPhotoPhase.failed);
    final first = uploader.attempts.single.uploadKey;

    draft().retry(failed.key);
    await pumpEventQueue(times: 40);

    expect(slots().single.phase, ChatPhotoPhase.ready);
    expect(uploader.attempts, hasLength(2));
    expect(uploader.attempts.last.uploadKey, isNot(first));
    expect(uploader.attempts.last.formFileId, isNull);
  });

  test('an upload of the previous account is dropped after a switch', () async {
    await create();
    final gate = Completer<void>();
    uploader.gate = gate;

    await draft().add([testImage('one.png')]);
    await pumpEventQueue();
    expect(slots().single.phase, ChatPhotoPhase.processing);

    server.reply(204);
    await container.read(authServiceProvider).signOut();
    await container
        .read(authStorageProvider)
        .write(const AuthToken.restored('account-b-refresh'));
    container.invalidate(authStatusProvider);
    await container.read(authStatusProvider.future);

    gate.complete();
    await pumpEventQueue(times: 40);

    expect(slots(), isEmpty);
    expect(draft().readyIds, isEmpty);
  });

  test('an account switch cancels a pending form API request', () async {
    await create(realUploader: true);
    final gate = Completer<void>();
    chatApi.photoRequestGate = gate;

    await draft().add([testImage('one.png')]);
    await pumpEventQueue();
    expect(chatApi.photoRequestKeys, hasLength(1));
    final cancel = chatApi.photoRequestCancels.single;
    expect(cancel, isNotNull);
    expect(slots().single.uploadKey, chatApi.photoRequestKeys.single);

    server.reply(204);
    await container.read(authServiceProvider).signOut();
    await container
        .read(authStorageProvider)
        .write(const AuthToken.restored('account-b-refresh'));
    container.invalidate(authStatusProvider);
    await container.read(authStatusProvider.future);

    expect(cancel!.isCancelled, isTrue);
    expect(slots(), isEmpty);
    expect(draft().readyIds, isEmpty);

    gate.complete();
    await pumpEventQueue(times: 40);
    expect(slots(), isEmpty);
  });
}
