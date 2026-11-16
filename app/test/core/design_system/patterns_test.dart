import 'package:campus/src/core/api/generated/listings/models/listing_status.dart';
import 'package:campus/src/core/design_system/foundations/palette.dart';
import 'package:campus/src/core/design_system/patterns/patterns.dart';
import 'package:campus/src/core/design_system/theme/campus_theme.dart';
import 'package:campus/src/core/l10n/l10n.dart';
import 'package:campus/src/features/listings/presentation/components/listing_card.dart';
import 'package:campus/src/features/listings/presentation/view_data/listing_card_data.dart';
import 'package:campus/src/features/listings/presentation/view_data/listing_status_data.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../../catalog/pattern_stories.dart';

Widget host(Widget child, {double scale = 1}) => MaterialApp(
  theme: CampusTheme.build(PaletteId.sage, Brightness.light),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: child,
  ),
);

void main() {
  testWidgets(
    'unknown status, no photo and redacted author do not infer actions',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => Scaffold(
              body: ListView(
                children: [
                  ListingCard(
                    data: ListingCardData(
                      title: 'A very long title that must grow in a narrow card without ellipsis',
                      author: const AuthorViewData(
                        redactedLabel: 'Profile hidden',
                        detail: 'Private detail',
                      ),
                      status: listingStatusData(
                        context.l10n,
                        ListingStatus.fromJson('future-status'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          scale: 2,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Profile hidden'), findsOneWidget);
      expect(find.text('Private detail'), findsNothing);
      expect(find.text('Status unavailable'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('editor sections preserve typed text after audience changes', (
    tester,
  ) async {
    await tester.pumpWidget(host(const ExampleEditor()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Draft remains mine');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    expect(find.text('Draft remains mine'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
  testWidgets('all photo stages are explicit and retry is caller owned', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      host(
        Scaffold(
          body: SingleChildScrollView(
            child: PhotoStrip(
              children: [
                for (final stage in PhotoStage.values)
                  PhotoTile(
                    stage: stage,
                    label: stage.name,
                    action: stage == PhotoStage.failed
                        ? TextButton(
                            onPressed: () => calls++,
                            child: const Text('Retry'),
                          )
                        : null,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Retry'));
    expect(calls, 1);
    expect(find.byType(PhotoTile), findsNWidgets(6));
  });
  testWidgets('representative listing composition golden', (tester) async {
    final fonts = FontLoader('Manrope');
    for (final w in [400, 500, 600, 700]) {
      fonts.addFont(rootBundle.load('assets/fonts/manrope/Manrope-$w.ttf'));
    }
    await fonts.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await tester.binding.setSurfaceSize(const Size(390, 680));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      host(
        const RepaintBoundary(
          key: Key('pattern'),
          child: Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  ListingCard(
                    data: ListingCardData(
                      title: 'Лампа для чтения · Reading lamp',
                      summary: 'Без фото · No photo',
                      author: AuthorViewData(
                        redactedLabel: 'Профиль скрыт · Profile hidden',
                      ),
                      status: StatusViewData(
                        label: 'Статус неизвестен · Unknown status',
                      ),
                      scope: 'Кампус · Campus',
                    ),
                  ),
                  TimelineEntry(
                    title: 'Ожидается ответ · Awaiting reply',
                    detail: 'Тестовые данные · Synthetic fixture',
                    icon: Icons.schedule,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const Key('pattern')),
      matchesGoldenFile('goldens/pattern.png'),
    );
  });
}
