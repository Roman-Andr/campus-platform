import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/core/l10n/l10n.dart';
import 'package:campus/src/core/widgets/api_error_view.dart';
import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';

void main() {
  late FakeHttpAdapter server;
  late ProviderContainer container;

  setUp(() {
    server = FakeHttpAdapter();
    container = ProviderContainer(overrides: apiOverrides(adapter: server));
    addTearDown(container.dispose);
  });

  /// Makes a request the server answers with [code], returns the error.
  Future<Object> failedRequest(
    WidgetTester tester,
    int status,
    String code,
  ) async {
    server.replyProblem(status, code);
    final error = await tester.runAsync(
      () => container
          .read(campusApiProvider)
          .university
          .listCities()
          .then<Object?>((_) => null, onError: (Object e) => e),
    );
    return error!;
  }

  Future<void> show(
    WidgetTester tester,
    Object error, {
    required String locale,
    VoidCallback? onRetry,
  }) => tester.pumpWidget(
    MaterialApp(
      locale: Locale(locale),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: ApiErrorView(error: error, onRetry: onRetry),
      ),
    ),
  );

  for (final (locale, text) in [
    ('ru', 'На сервере что-то пошло не так. Попробуйте позже.'),
    ('en', 'Something went wrong on the server. Please try again later.'),
  ]) {
    testWidgets('shows a server error in $locale without technical details', (
      tester,
    ) async {
      final error = await failedRequest(tester, 500, 'internal_error');

      await show(tester, error, locale: locale);

      expect(find.text(text), findsOneWidget);
      for (final technical in [
        'internal_error',
        'req-123',
        'Server title',
        'Server detail',
        '500',
      ]) {
        expect(find.textContaining(technical), findsNothing);
      }
    });
  }

  testWidgets('offers to try again', (tester) async {
    final error = await failedRequest(tester, 404, 'not_found');
    var retried = 0;

    await show(tester, error, locale: 'en', onRetry: () => retried++);
    expect(find.text('Not found: it may have been deleted.'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    expect(retried, 1);
  });

  testWidgets('explains a network failure', (tester) async {
    await show(tester, const NetworkFailure(), locale: 'en');

    expect(find.textContaining("Can't reach the server"), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });
}
