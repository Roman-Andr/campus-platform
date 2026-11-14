import 'dart:typed_data';

import 'package:campus/src/core/photos/photo_upload.dart';
import 'package:campus/src/core/router/app_router.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';
import 'profile_fixtures.dart';

final _tags = [
  tagJson('guitar', 'Гитара'),
  tagJson('chess', 'Шахматы'),
  tagJson('chinese', 'Китайский язык'),
];

Finder _inSection(String section, Finder finder) =>
    find.descendant(of: find.byKey(Key(section)), matching: finder);

void main() {
  late FakeHttpAdapter server;
  late FakePhotoPicker picker;
  var fileStatus = 'ready';

  /// Answers of `PUT /me/skills` and `PUT /me/name`; `null`: accept.
  ResponseBody? skillsReply;
  ResponseBody? nameReply;

  setUp(() {
    fileStatus = 'ready';
    skillsReply = null;
    nameReply = null;
    picker = FakePhotoPicker();
    server = FakeHttpAdapter(
      skills: {
        'can': [_tags.first],
        'wants': <Object?>[],
      },
    );
    server.route(
      (options) =>
          photoFlow(options, server, status: fileStatus) ??
          switch ((options.method, options.path)) {
            ('GET', '/api/v1/skill-tags') => jsonBody(200, {
              'items': [
                for (final tag in _tags)
                  if ((tag['name']! as String).toLowerCase().startsWith(
                    ((options.queryParameters['q'] as String?) ?? '')
                        .toLowerCase(),
                  ))
                    tag,
              ],
            }),
            ('PUT', '/api/v1/me/skills') =>
              skillsReply ??
                  () {
                    final body = SentRequest(options).json;
                    List<Object?> tags(String key) => [
                      for (final id in (body[key]! as List<Object?>))
                        _tags.firstWhere((tag) => tag['id'] == id),
                    ];
                    server.skills = {
                      'can': tags('can'),
                      'wants': tags('wants'),
                    };
                    return jsonBody(200, server.skills);
                  }(),
            ('PUT', '/api/v1/me/name') =>
              nameReply ??
                  () {
                    server.me = {
                      ...server.me!,
                      ...SentRequest(options).json,
                      'name_change_available_at': '2030-02-01T12:00:00Z',
                    };
                    return jsonBody(200, server.me);
                  }(),
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

  List<SentRequest> sent(String method, String path) => [
    for (final request in server.sent)
      if (request.method == method && request.path == path) request,
  ];

  Future<ProviderContainer> start(
    WidgetTester tester, {
    String location = AppRoutes.profile,
  }) async {
    tester.platformDispatcher.localesTestValue = [const Locale('ru')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    tester.view.physicalSize = const Size(1080, 3600);
    addTearDown(tester.view.resetPhysicalSize);
    final container = await tester.pumpCampusApp(
      InMemorySettingsRepository(),
      adapter: server,
      overrides: [
        photoPickerProvider.overrideWithValue(picker),
        photoConfigProvider.overrideWithValue(testPhotoConfig),
      ],
    );
    container.read(appRouterProvider).go(location);
    await tester.pumpAndSettle();
    return container;
  }

  String location(ProviderContainer container) => container
      .read(appRouterProvider)
      .routerDelegate
      .currentConfiguration
      .uri
      .path;

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  group('photo', () {
    testWidgets('the profile shows the photo, the name and the skills', (
      tester,
    ) async {
      server.photo = photoJson('file-old');
      await start(tester);

      expect(find.byKey(const Key('profile-photo-image')), findsOneWidget);
      expect(find.text('Заменить фото'), findsOneWidget);
      expect(find.text('Иван Иванов'), findsOneWidget);
      expect(
        _inSection('profile-skills-can', find.text('Гитара')),
        findsOneWidget,
      );
      expect(
        _inSection('profile-skills-wants', find.text('Не указаны')),
        findsOneWidget,
      );
    });

    testWidgets('a chosen photo is uploaded and becomes the profile photo', (
      tester,
    ) async {
      await start(tester);
      expect(find.byKey(const Key('profile-photo-image')), findsNothing);
      expect(find.byKey(const Key('profile-photo-remove')), findsNothing);

      await tap(tester, find.byKey(const Key('profile-photo-gallery')));

      expect(picker.picks, 1);
      expect(sent('POST', storageUrl), hasLength(1));
      expect(sent('PUT', '/api/v1/me/photo').single.json, {
        'file_id': 'file-new',
      });
      expect(find.byKey(const Key('profile-photo-image')), findsOneWidget);
      expect(find.byKey(const Key('profile-photo-error')), findsNothing);
    });

    testWidgets('the camera is offered where there is one', (tester) async {
      picker = FakePhotoPicker(null, true);
      await start(tester);

      await tap(tester, find.byKey(const Key('profile-photo-camera')));

      expect(sent('PUT', '/api/v1/me/photo'), hasLength(1));
    });

    testWidgets('a rejected photo is explained and not set', (tester) async {
      fileStatus = 'rejected';
      await start(tester);

      await tap(tester, find.byKey(const Key('profile-photo-gallery')));

      expect(
        find.text(
          'Это не похоже на фото: выберите изображение JPEG, PNG, WebP '
          'или HEIC.',
        ),
        findsOneWidget,
      );
      expect(sent('PUT', '/api/v1/me/photo'), isEmpty);
      expect(find.byKey(const Key('profile-photo-image')), findsNothing);
    });

    testWidgets('a file over the limit is not uploaded', (tester) async {
      picker = FakePhotoPicker(Uint8List(1024 * 1024 + 1));
      await start(tester);

      await tap(tester, find.byKey(const Key('profile-photo-gallery')));

      expect(
        find.text('Файл больше 1 МБ — выберите фото поменьше.'),
        findsOneWidget,
      );
      expect(sent('POST', '/api/v1/files/photo-uploads'), isEmpty);
    });

    testWidgets('the photo can be removed', (tester) async {
      server.photo = photoJson('file-old');
      await start(tester);

      await tap(tester, find.byKey(const Key('profile-photo-remove')));

      expect(sent('DELETE', '/api/v1/me/photo'), hasLength(1));
      expect(find.byKey(const Key('profile-photo-image')), findsNothing);
      expect(find.text('Выбрать фото'), findsOneWidget);
    });
  });

  group('skills', () {
    Future<void> add(WidgetTester tester, String section, String query) async {
      await tap(
        tester,
        _inSection(section, find.byKey(const Key('skills-add'))),
      );
      await tester.enterText(find.byKey(const Key('skills-search')), query);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    }

    testWidgets('skills are chosen from the reference by search', (
      tester,
    ) async {
      final container = await start(tester);
      await tap(tester, find.byKey(const Key('profile-skills-edit')));
      expect(find.text('Изменить навыки'), findsOneWidget);

      await add(tester, 'skills-wants', 'ш');
      expect(find.text('Китайский язык'), findsNothing);
      await tap(tester, find.byKey(const Key('skill-option-chess')));
      await tap(tester, find.byTooltip('Убрать «Гитара»'));
      await tap(tester, find.byKey(const Key('skills-save')));

      expect(sent('PUT', '/api/v1/me/skills').single.json, {
        'can': <Object?>[],
        'wants': ['tag-chess'],
      });
      expect(location(container), AppRoutes.profile);
      expect(
        _inSection('profile-skills-wants', find.text('Шахматы')),
        findsOneWidget,
      );
      expect(
        _inSection('profile-skills-can', find.text('Не указаны')),
        findsOneWidget,
      );
    });

    testWidgets('chosen skills are not offered again', (tester) async {
      await start(tester, location: AppRoutes.profileSkills);

      await add(tester, 'skills-can', 'г');

      expect(find.byKey(const Key('skill-option-guitar')), findsNothing);
      expect(find.text('Ничего не найдено'), findsOneWidget);
    });

    testWidgets('skills gone from the reference are reported', (tester) async {
      skillsReply = problemBody(
        422,
        'validation_failed',
        errors: [
          {'detail': 'x', 'code': 'not_found', 'pointer': '#/can/0'},
        ],
      );
      final container = await start(tester, location: AppRoutes.profileSkills);

      await tap(tester, find.byKey(const Key('skills-save')));

      expect(
        find.text(
          'Некоторых навыков больше нет в справочнике — уберите их и '
          'сохраните снова.',
        ),
        findsOneWidget,
      );
      expect(location(container), AppRoutes.profileSkills);
    });
  });

  group('name', () {
    Future<void> rename(WidgetTester tester, String first, String last) async {
      await tap(tester, find.byKey(const Key('profile-name-change')));
      await tester.enterText(find.byKey(const Key('name-first')), first);
      await tester.enterText(find.byKey(const Key('name-last')), last);
      await tap(tester, find.byKey(const Key('name-save')));
    }

    testWidgets('a change shows the date of the next one', (tester) async {
      await start(tester);

      await rename(tester, ' Пётр ', 'Петров-Водкин');

      expect(sent('PUT', '/api/v1/me/name').single.json, {
        'first_name': 'Пётр',
        'last_name': 'Петров-Водкин',
      });
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Пётр Петров-Водкин'), findsOneWidget);
      expect(
        find.textContaining('Следующая смена имени — не раньше 1 февраля 2030'),
        findsOneWidget,
      );
      final button = tester.widget<IconButton>(
        find.byKey(const Key('profile-name-change')),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('a change too soon is refused with the date', (tester) async {
      nameReply = jsonBody(409, {
        'type': 'urn:problem:campus:name_change_too_soon',
        'title': 't',
        'status': 409,
        'code': 'name_change_too_soon',
        'available_at': '2030-03-05T10:00:00Z',
      });
      await start(tester);

      await rename(tester, 'Пётр', 'Петров');

      expect(
        find.textContaining(
          'Имя недавно менялось. Следующая смена — не раньше 5 марта 2030',
        ),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('an invalid name is not sent', (tester) async {
      await start(tester);

      await rename(tester, 'R2D2', 'Петров');

      expect(sent('PUT', '/api/v1/me/name'), isEmpty);
      expect(find.byType(AlertDialog), findsOneWidget);
    });
  });

  group('first sign-in', () {
    testWidgets('photo and skills follow the profile and may be filled', (
      tester,
    ) async {
      final container = await start(
        tester,
        location: AppRoutes.profileSetupPhoto,
      );
      expect(find.text('Фото профиля'), findsOneWidget);

      await tap(tester, find.byKey(const Key('profile-photo-gallery')));
      expect(sent('PUT', '/api/v1/me/photo'), hasLength(1));
      await tap(tester, find.byKey(const Key('profile-step-next')));
      expect(location(container), AppRoutes.profileSetupSkills);

      await tap(
        tester,
        _inSection('skills-wants', find.byKey(const Key('skills-add'))),
      );
      await tester.enterText(find.byKey(const Key('skills-search')), 'кит');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const Key('skill-option-chinese')));
      await tap(tester, find.byKey(const Key('skills-save')));

      expect(sent('PUT', '/api/v1/me/skills').single.json['wants'], [
        'tag-chinese',
      ]);
      expect(location(container), AppRoutes.home);
    });

    testWidgets('photo and skills steps may be skipped', (tester) async {
      final container = await start(
        tester,
        location: AppRoutes.profileSetupPhoto,
      );

      await tap(tester, find.byKey(const Key('profile-step-skip')));
      expect(location(container), AppRoutes.profileSetupSkills);
      await tap(tester, find.byKey(const Key('profile-step-skip')));

      expect(location(container), AppRoutes.home);
      expect(sent('POST', '/api/v1/files/photo-uploads'), isEmpty);
      expect(sent('PUT', '/api/v1/me/skills'), isEmpty);
    });
  });
}
