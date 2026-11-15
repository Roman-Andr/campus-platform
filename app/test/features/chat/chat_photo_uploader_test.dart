import 'dart:async';

import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/core/photos/photo_upload.dart';
import 'package:campus/src/features/chat/data/chat_photo_uploader.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_api.dart';
import 'chat_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeChatApi api;
  late FakeHttpAdapter server;
  late StorageChatPhotoUploader uploader;

  setUp(() {
    api = FakeChatApi();
    server = FakeHttpAdapter();
    uploader = StorageChatPhotoUploader(
      api: api,
      storage: Dio()..httpClientAdapter = server,
      config: const PhotoConfig(
        maxBytes: 1024 * 1024,
        listingLimit: 10,
        pollInterval: Duration.zero,
        processingTimeout: Duration(seconds: 1),
      ),
    );
  });

  test(
    'a lost form response retries the same key and gets the same file',
    () async {
      const uploadKey = '01890a5d-ac96-774b-bcce-b302099a8101';
      const completeKey = '01890a5d-ac96-774b-bcce-b302099a8102';
      api.photoRequestError = const NetworkFailure();

      await expectLater(
        uploader.upload(
          testChatId,
          await testImage('one.png').readAsBytes(),
          filename: 'one.png',
          uploadKey: uploadKey,
          completeKey: completeKey,
          onForm: (_) {},
        ),
        throwsA(isA<NetworkFailure>()),
      );

      server.reply(204);
      ChatPhotoForm? saved;
      final result = await uploader.upload(
        testChatId,
        await testImage('one.png').readAsBytes(),
        filename: 'one.png',
        uploadKey: uploadKey,
        completeKey: completeKey,
        onForm: (form) => saved = form,
      );

      expect(api.photoRequestKeys, [uploadKey, uploadKey]);
      expect(saved, isNotNull);
      expect(result.form.fileId, 'file-1');
      expect(result.file.status, 'ready');
      expect(api.completePhotoCalls.single.key, completeKey);
    },
  );

  test(
    'a lost completion response is resolved by GET, not a repeated POST',
    () async {
      const uploadKey = '01890a5d-ac96-774b-bcce-b302099a8103';
      const completeKey = '01890a5d-ac96-774b-bcce-b302099a8104';
      server.reply(204);
      api.completePhotoError = const NetworkFailure();
      ChatPhotoForm? saved;

      await expectLater(
        uploader.upload(
          testChatId,
          await testImage('one.png').readAsBytes(),
          filename: 'one.png',
          uploadKey: uploadKey,
          completeKey: completeKey,
          onForm: (form) => saved = form,
        ),
        throwsA(isA<NetworkFailure>()),
      );
      expect(saved, isNotNull);
      expect(api.completePhotoCalls, hasLength(1));

      // The completion committed before the response was lost; the status
      // GET sees it and the retry must not POST the same key again.
      api.photoFiles[saved!.fileId] = ChatFileOutput(
        id: saved!.fileId,
        purpose: 'chat_photo',
        status: 'ready',
        size: 1,
        rejectionReason: null,
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      server.reply(204);
      final result = await uploader.upload(
        testChatId,
        await testImage('one.png').readAsBytes(),
        filename: 'one.png',
        uploadKey: uploadKey,
        completeKey: completeKey,
        form: saved,
        onForm: (_) {},
      );

      expect(result.file.status, 'ready');
      expect(api.completePhotoCalls, hasLength(1));
      expect(api.photoStatusCalls, isNotEmpty);
    },
  );

  test('an expired cached form is never reused', () async {
    final expired = ChatPhotoForm(
      url: 'https://storage.test/upload',
      fields: const {},
      fileId: 'file-old',
      expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
    );

    await expectLater(
      uploader.upload(
        testChatId,
        await testImage('one.png').readAsBytes(),
        filename: 'one.png',
        uploadKey: '01890a5d-ac96-774b-bcce-b302099a8107',
        completeKey: '01890a5d-ac96-774b-bcce-b302099a8108',
        form: expired,
        onForm: (_) {},
      ),
      throwsA(isA<ChatPhotoFormExpired>()),
    );
    expect(api.photoRequests, isEmpty);
  });

  test('cancelling the token aborts the in-flight form request', () async {
    final gate = Completer<void>();
    api.photoRequestGate = gate;
    final cancel = CancelToken();

    final request = uploader.upload(
      testChatId,
      await testImage('one.png').readAsBytes(),
      filename: 'one.png',
      uploadKey: '01890a5d-ac96-774b-bcce-b302099a8105',
      completeKey: '01890a5d-ac96-774b-bcce-b302099a8106',
      onForm: (_) {},
      cancel: cancel,
    );
    await pumpEventQueue();
    expect(api.photoRequestCancels.single, same(cancel));

    cancel.cancel();
    gate.complete();

    await expectLater(request, throwsA(isA<DioException>()));
  });
}
