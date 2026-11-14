import 'package:campus/src/core/router/app_router.dart';
import 'package:campus/src/features/profile/application/my_profile.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';

const _profile = '/api/v1/me/profile';

final _city = find.byKey(const Key('profile-city'));
final _course = find.byKey(const Key('profile-course'));
final _save = find.byKey(const Key('profile-save'));

/// A field of the place lists, whose key changes with the city.
Finder _field(String prefix) => find.byWidgetPredicate(
  (widget) =>
      widget.key is ValueKey<String> &&
      (widget.key! as ValueKey<String>).value.startsWith(prefix),
);

final _dormitory = _field('profile-dormitory-');
final _faculty = _field('profile-faculty-');

/// Reference data of two cities, as the server lists them.
const _cities = {
  'items': [
    {
      'id': 'city-moscow',
      'code': 'moscow',
      'name': 'Москва',
      'timezone': 'Europe/Moscow',
    },
    {
      'id': 'city-perm',
      'code': 'perm',
      'name': 'Пермь',
      'timezone': 'Asia/Yekaterinburg',
    },
  ],
};

const _dormitories = {
  'city-moscow': [('dorm-dubki', 'Дубки')],
  'city-perm': [('dorm-perm', 'Общежитие №1')],
};

const _faculties = {
  'city-moscow': [('faculty-economics', 'Экономика')],
  'city-perm': [('faculty-law', 'Право')],
};

void main() {
  late FakeHttpAdapter server;

  /// Answers of `PUT /me/profile`, in order; the last one repeats.
  late List<ResponseBody Function(Map<String, Object?> body)> saves;

  setUp(() {
    server = FakeHttpAdapter(me: {...userJson, ...emptyProfileJson});
    saves = [];
    server.route((options) {
      final city = options.queryParameters['city_id'] as String?;
      List<Map<String, Object?>> places(
        Map<String, List<(String, String)>> all,
      ) => [
        for (final (id, name) in all[city] ?? const <(String, String)>[])
          {
            'id': id,
            'city_id': city,
            'city_timezone': city == 'city-perm'
                ? 'Asia/Yekaterinburg'
                : 'Europe/Moscow',
            'code': id,
            'name': name,
          },
      ];
      return switch (options.path) {
        '/api/v1/university/cities' => jsonBody(200, _cities),
        '/api/v1/university/dormitories' => jsonBody(200, {
          'items': places(_dormitories),
        }),
        '/api/v1/university/faculties' => jsonBody(200, {
          'items': places(_faculties),
        }),
        _profile => () {
          final body = SentRequest(options).json;
          final reply = saves.length > 1 ? saves.removeAt(0) : saves.single;
          return reply(body);
        }(),
        '/api/v1/auth/token/refresh' => jsonBody(200, tokensJson(1)),
        '/api/v1/auth/sign-out' => jsonBody(204, null),
        _ => throw StateError('Unexpected request to ${options.path}'),
      };
    });
  });

  /// The server accepts the profile and returns the user with it.
  ResponseBody accept(Map<String, Object?> body) => jsonBody(200, {
    ...server.me!,
    'city_id': body['city_id'],
    'city_timezone': body['city_id'] == 'city-perm'
        ? 'Asia/Yekaterinburg'
        : 'Europe/Moscow',
    'dormitory_id': body['dormitory_id'],
    'faculty_id': body['faculty_id'],
    'course': body['course'],
    'profile_complete': true,
  });

  List<SentRequest> sentTo(String path) =>
      server.sent.where((request) => request.path == path).toList();

  Future<ProviderContainer> start(WidgetTester tester) {
    tester.platformDispatcher.localesTestValue = [const Locale('ru')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    return tester.pumpCampusApp(InMemorySettingsRepository(), adapter: server);
  }

  Future<void> choose(WidgetTester tester, Finder field, String option) async {
    await tester.ensureVisible(field);
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.tap(find.text(option).last);
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(_save);
    await tester.tap(_save);
    await tester.pumpAndSettle();
  }

  String location(ProviderContainer container) => container
      .read(appRouterProvider)
      .routerDelegate
      .currentConfiguration
      .uri
      .path;

  testWidgets('a new user fills in the profile before anything else', (
    tester,
  ) async {
    saves = [accept];
    final container = await start(tester);

    expect(find.text('Ваш профиль'), findsOneWidget);
    container.read(appRouterProvider).go(AppRoutes.settings);
    await tester.pumpAndSettle();
    expect(location(container), AppRoutes.profileSetup);

    await choose(tester, _city, 'Москва');
    await choose(tester, _dormitory, 'Не живу в общежитии');
    await choose(tester, _faculty, 'Экономика');
    await choose(tester, _course, '3 курс');
    await save(tester);

    expect(sentTo(_profile).single.json, {
      'city_id': 'city-moscow',
      'faculty_id': 'faculty-economics',
      'course': 3,
    });
    expect(location(container), AppRoutes.home);
    expect(find.text('Пока ничего нет'), findsOneWidget);
    expect(container.read(myProfileProvider).value!.profileComplete, isTrue);
  });

  testWidgets('dormitories and faculties are those of the chosen city', (
    tester,
  ) async {
    saves = [accept];
    await start(tester);

    await choose(tester, _city, 'Москва');
    await choose(tester, _dormitory, 'Дубки');
    await choose(tester, _faculty, 'Экономика');
    await choose(tester, _city, 'Пермь');

    // The choices of the previous city are dropped.
    expect(find.text('Дубки'), findsNothing);
    expect(find.text('Экономика'), findsNothing);
    await tester.tap(_dormitory);
    await tester.pumpAndSettle();
    expect(find.text('Дубки'), findsNothing);
    expect(find.text('Общежитие №1'), findsWidgets);
    await tester.tap(find.text('Общежитие №1').last);
    await tester.pumpAndSettle();
    await choose(tester, _faculty, 'Право');
    await choose(tester, _course, '1 курс');
    await save(tester);

    final requested = server.sent
        .where((request) => request.path.endsWith('/dormitories'))
        .toList();
    expect(requested, hasLength(2));
    expect(sentTo(_profile).single.json, {
      'city_id': 'city-perm',
      'dormitory_id': 'dorm-perm',
      'faculty_id': 'faculty-law',
      'course': 1,
    });
  });

  testWidgets('every field must be chosen', (tester) async {
    await start(tester);

    await save(tester);

    expect(find.text('Выберите из списка.'), findsNWidgets(4));
    expect(sentTo(_profile), isEmpty);
  });

  testWidgets('employees give no course', (tester) async {
    server.me = {...userJson, ...emptyProfileJson, 'account_type': 'employee'};
    saves = [accept];
    await start(tester);

    expect(_course, findsNothing);
    await choose(tester, _city, 'Москва');
    await choose(tester, _dormitory, 'Не живу в общежитии');
    await choose(tester, _faculty, 'Экономика');
    await save(tester);

    expect(sentTo(_profile).single.json, {
      'city_id': 'city-moscow',
      'faculty_id': 'faculty-economics',
    });
  });

  testWidgets('a place the server rejects can be chosen again', (tester) async {
    saves = [
      (_) => problemBody(
        422,
        'validation_failed',
        errors: [
          {
            'detail': 'Must be one of the chosen city.',
            'code': 'not_of_city',
            'pointer': '#/faculty_id',
          },
        ],
      ),
      accept,
    ];
    final container = await start(tester);

    await choose(tester, _city, 'Москва');
    await choose(tester, _dormitory, 'Дубки');
    await choose(tester, _faculty, 'Экономика');
    await choose(tester, _course, '2 курс');
    await save(tester);

    expect(
      find.text('Этого варианта больше нет, выберите другой.'),
      findsOneWidget,
    );
    expect(location(container), AppRoutes.profileSetup);

    await save(tester);
    expect(sentTo(_profile), hasLength(2));
    expect(location(container), AppRoutes.home);
  });

  testWidgets('a failed save is explained and keeps the screen', (
    tester,
  ) async {
    saves = [(_) => problemBody(500, 'internal_error')];
    final container = await start(tester);

    await choose(tester, _city, 'Москва');
    await choose(tester, _dormitory, 'Дубки');
    await choose(tester, _faculty, 'Экономика');
    await choose(tester, _course, '2 курс');
    await save(tester);

    expect(find.byKey(const Key('auth-error')), findsOneWidget);
    expect(location(container), AppRoutes.profileSetup);
  });

  testWidgets('a user can sign out instead of filling in the profile', (
    tester,
  ) async {
    final container = await start(tester);

    await tester.tap(find.byKey(const Key('profile-sign-out')));
    await tester.pumpAndSettle();

    expect(location(container), AppRoutes.signIn);
    expect(container.read(myProfileProvider).value, isNull);
  });

  testWidgets('a profile filled in on another device opens the home screen', (
    tester,
  ) async {
    server.me = {...userJson, ...filledProfileJson};
    final container = await start(tester);

    expect(location(container), AppRoutes.home);
    container.read(appRouterProvider).go(AppRoutes.profileSetup);
    await tester.pumpAndSettle();
    expect(location(container), AppRoutes.home);
  });

  testWidgets('the own profile shows the choices and can be changed', (
    tester,
  ) async {
    server.me = {...userJson, ...filledProfileJson};
    saves = [accept];
    await start(tester);

    await tester.tap(find.byKey(const Key('home-profile')));
    await tester.pumpAndSettle();
    expect(find.text('Иван Иванов'), findsOneWidget);
    expect(find.text('Студент'), findsOneWidget);
    expect(find.text('ivanov@edu.hse.ru'), findsOneWidget);
    expect(find.text('Москва'), findsOneWidget);
    expect(find.text('Дубки'), findsOneWidget);
    expect(find.text('Экономика'), findsOneWidget);
    expect(find.text('2 курс'), findsOneWidget);

    await tester.tap(find.byKey(const Key('profile-edit')));
    await tester.pumpAndSettle();
    expect(find.text('Изменить профиль'), findsOneWidget);
    await choose(tester, _dormitory, 'Не живу в общежитии');
    await choose(tester, _course, '4 курс');
    await save(tester);

    expect(sentTo(_profile).single.json, {
      'city_id': 'city-moscow',
      'faculty_id': 'faculty-economics',
      'course': 4,
    });
    // Back on the profile, with the saved choices.
    expect(find.text('Изменить профиль'), findsNothing);
    expect(find.text('Профиль'), findsOneWidget);
    expect(find.text('Не живу в общежитии'), findsOneWidget);
    expect(find.text('4 курс'), findsOneWidget);
  });

  testWidgets('the profile of an employee has no course', (tester) async {
    server.me = {
      ...userJson,
      ...filledProfileJson,
      'account_type': 'employee',
      'course': null,
    };
    final container = await start(tester);

    container.read(appRouterProvider).go(AppRoutes.profile);
    await tester.pumpAndSettle();

    expect(find.text('Сотрудник'), findsOneWidget);
    expect(find.text('Курс'), findsNothing);
  });

  testWidgets('a profile that fails to load can be loaded again', (
    tester,
  ) async {
    server.me = null;
    final container = await start(tester);

    // Without the profile the user stays on the home screen.
    expect(location(container), AppRoutes.home);
    container.read(appRouterProvider).go(AppRoutes.profile);
    await tester.pumpAndSettle();
    expect(find.text('Повторить'), findsOneWidget);

    server.me = {...userJson, ...filledProfileJson};
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    expect(find.text('Иван Иванов'), findsOneWidget);
  });
}
