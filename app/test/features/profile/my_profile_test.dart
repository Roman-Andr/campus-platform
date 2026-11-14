import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/core/auth/auth_service.dart';
import 'package:campus/src/core/auth/auth_session.dart';
import 'package:campus/src/features/profile/application/my_profile.dart';
import 'package:campus/src/features/profile/application/profile_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeHttpAdapter server;

  setUp(() {
    server = FakeHttpAdapter(me: {...userJson, ...emptyProfileJson});
    server.route(
      (options) => switch (options.path) {
        '/api/v1/auth/token/refresh' => jsonBody(200, tokensJson(1)),
        '/api/v1/me/profile' => jsonBody(200, {
          ...userJson,
          ...filledProfileJson,
        }),
        _ => jsonBody(204, null),
      },
    );
  });

  Future<ProviderContainer> start({
    Map<String, String> secure = signedInStorage,
  }) async {
    final container = ProviderContainer(
      overrides: apiOverrides(adapter: server, secure: secure),
    );
    addTearDown(container.dispose);
    await container.read(authStatusProvider.future);
    return container;
  }

  int requestsTo(String path) =>
      server.sent.where((request) => request.path == path).length;

  test('nobody signed in has no profile and asks nothing', () async {
    final container = await start(secure: const {});

    expect(await container.read(myProfileProvider.future), isNull);
    expect(requestsTo(mePath), 0);
  });

  test('the profile comes from the server', () async {
    final container = await start();

    final user = await container.read(myProfileProvider.future);

    expect(user!.profileComplete, isFalse);
    expect(requestsTo(mePath), 1);
  });

  test('a saved profile replaces the loaded one', () async {
    final container = await start();
    await container.read(myProfileProvider.future);

    await container
        .read(myProfileProvider.notifier)
        .save(
          const ProfileInput(
            cityId: 'city-moscow',
            dormitoryId: 'dorm-dubki',
            facultyId: 'faculty-economics',
            course: 2,
          ),
        );

    final user = container.read(myProfileProvider).value!;
    expect(user.profileComplete, isTrue);
    expect(user.course, 2);
    final sent = server.sent.singleWhere(
      (request) => request.path == '/api/v1/me/profile',
    );
    expect(sent.method, 'PUT');
    expect(sent.headers['Idempotency-Key'], isNotNull);
  });

  test('signing out forgets the profile', () async {
    final container = await start();
    await container.read(myProfileProvider.future);

    await container.read(authServiceProvider).signOut();

    expect(await container.read(myProfileProvider.future), isNull);
  });

  test('only students give a course', () {
    expect(hasCourse(AccountType.student), isTrue);
    expect(hasCourse(AccountType.employee), isFalse);
  });

  test('the highest course defaults to the server default', () {
    expect(ProfileConfig.fromEnvironment().maxCourse, 6);
  });
}
