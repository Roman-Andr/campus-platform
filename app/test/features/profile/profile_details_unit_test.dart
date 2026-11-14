import 'dart:typed_data';

import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/core/auth/auth_session.dart';
import 'package:campus/src/core/photos/photo_upload.dart';
import 'package:campus/src/features/profile/application/my_profile.dart';
import 'package:campus/src/features/profile/application/profile_photo.dart';
import 'package:campus/src/features/profile/application/skills.dart';
import 'package:campus/src/features/profile/presentation/name_change_dialog.dart';
import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';
import 'profile_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeHttpAdapter server;
  var fileStatus = 'ready';

  setUp(() {
    fileStatus = 'ready';
    server = FakeHttpAdapter();
    server.route(
      (options) =>
          photoFlow(options, server, status: fileStatus) ??
          switch ((options.method, options.path)) {
            ('PUT', '/api/v1/me/skills') => () {
              final body = SentRequest(options).json;
              List<Object?> tags(String key) => [
                for (final id in (body[key]! as List<Object?>).cast<String>())
                  tagJson(id.substring(4), id),
              ];
              return jsonBody(200, {
                'can': tags('can'),
                'wants': tags('wants'),
              });
            }(),
            ('GET', '/api/v1/skill-tags') => jsonBody(200, {
              'items': [tagJson('guitar', 'Гитара')],
            }),
            ('PUT', '/api/v1/me/name') => jsonBody(200, {
              ...userJson,
              ...filledProfileJson,
              ...SentRequest(options).json,
              'name_change_available_at': '2030-01-01T00:00:00Z',
            }),
            ('POST', '/api/v1/auth/token/refresh') => jsonBody(
              200,
              tokensJson(1),
            ),
            _ => throw StateError(
              'Unexpected ${options.method} ${options.path}',
            ),
          },
    );
  });

  Future<ProviderContainer> start({
    Map<String, String> secure = signedInStorage,
  }) async {
    final container = ProviderContainer(
      overrides: [
        ...apiOverrides(adapter: server, secure: secure),
        photoConfigProvider.overrideWithValue(testPhotoConfig),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authStatusProvider.future);
    return container;
  }

  List<SentRequest> sent(String method, String path) => [
    for (final request in server.sent)
      if (request.method == method && request.path == path) request,
  ];

  XFile file([int size = 3]) => XFile.fromData(Uint8List(size), name: 'me.jpg');

  group('profile photo', () {
    test('none without a photo or a signed-in user', () async {
      expect(await (await start()).read(myPhotoProvider.future), isNull);
      server.sent.clear();
      final signedOut = await start(secure: const {});
      expect(await signedOut.read(myPhotoProvider.future), isNull);
      expect(server.sent, isEmpty);
    });

    test('an uploaded photo becomes the profile photo', () async {
      final container = await start();
      await container.read(myPhotoProvider.future);
      var processing = false;

      await container
          .read(myPhotoProvider.notifier)
          .upload(file(), onProcessing: () => processing = true);

      expect(processing, isTrue);
      expect(sent('PUT', '/api/v1/me/photo').single.json, {
        'file_id': 'file-new',
      });
      expect(container.read(myPhotoProvider).value!.id, 'file-new');
    });

    test('a rejected photo is not set', () async {
      fileStatus = 'rejected';
      final container = await start();
      await container.read(myPhotoProvider.future);

      await expectLater(
        container.read(myPhotoProvider.notifier).upload(file()),
        throwsA(
          isA<ProfilePhotoRejected>().having(
            (error) => error.reason,
            'reason',
            'invalid_image',
          ),
        ),
      );
      expect(sent('PUT', '/api/v1/me/photo'), isEmpty);
      expect(container.read(myPhotoProvider).value, isNull);
    });

    test('a file over the limit is not uploaded', () async {
      final container = await start();
      await container.read(myPhotoProvider.future);

      await expectLater(
        container.read(myPhotoProvider.notifier).upload(file(1024 * 1024 + 1)),
        throwsA(isA<ProfilePhotoTooLarge>()),
      );
      expect(sent('POST', '/api/v1/files/photo-uploads'), isEmpty);
    });

    test('removing deletes it on the server', () async {
      server.photo = photoJson('file-old');
      final container = await start();
      expect((await container.read(myPhotoProvider.future))!.id, 'file-old');

      await container.read(myPhotoProvider.notifier).remove();

      expect(sent('DELETE', '/api/v1/me/photo'), hasLength(1));
      expect(container.read(myPhotoProvider).value, isNull);
    });
  });

  group('skills', () {
    test('both lists are saved whole', () async {
      final container = await start();
      expect((await container.read(mySkillsProvider.future))!.can, isEmpty);
      final guitar = SkillTagOutput.fromJson(tagJson('guitar', 'Гитара'));
      final chess = SkillTagOutput.fromJson(tagJson('chess', 'Шахматы'));

      await container
          .read(mySkillsProvider.notifier)
          .save(can: [guitar], wants: [chess]);

      expect(sent('PUT', '/api/v1/me/skills').single.json, {
        'can': ['tag-guitar'],
        'wants': ['tag-chess'],
      });
      expect(
        container.read(mySkillsProvider).value!.wants.single.code,
        'chess',
      );
    });

    test('search asks the server by the beginning of the name', () async {
      final container = await start();

      final tags = await container.read(skillTagSearchProvider(' гит ').future);

      expect(tags.single.name, 'Гитара');
      final request = server.sent.lastWhere(
        (request) => request.path == '/api/v1/skill-tags',
      );
      expect(request.query['q'], 'гит');
    });
  });

  group('name', () {
    test('a change updates the profile with the next possible date', () async {
      final container = await start();
      await container.read(myProfileProvider.future);

      await container
          .read(myProfileProvider.notifier)
          .changeName(firstName: 'Пётр', lastName: 'Петров');

      expect(sent('PUT', '/api/v1/me/name').single.json, {
        'first_name': 'Пётр',
        'last_name': 'Петров',
      });
      final user = container.read(myProfileProvider).value!;
      expect(user.firstName, 'Пётр');
      expect(user.nameChangeAvailableAt, DateTime.utc(2030));
    });

    test('the next change is due only while in the future', () {
      final user = UserOutput.fromJson({
        ...userJson,
        ...filledProfileJson,
        'name_change_available_at': '2030-01-01T00:00:00Z',
      });
      withClock(Clock.fixed(DateTime.utc(2029, 12, 31)), () {
        expect(nextNameChange(user), DateTime.utc(2030));
      });
      withClock(Clock.fixed(DateTime.utc(2030, 1, 2)), () {
        expect(nextNameChange(user), isNull);
      });
    });
  });
}
