import 'package:campus/src/core/l10n/l10n.dart';
import 'package:campus/src/core/widgets/city_date_time_picker.dart';
import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Future<void> pumpPicker(
    WidgetTester tester,
    ValueChanged<DateTime> onChanged, {
    String locale = 'en',
  }) async {
    await tester.pumpWidget(
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
          body: CityDateTimePicker(
            value: DateTime.utc(2026, 11, 16, 13),
            timezone: 'Asia/Yekaterinburg',
            city: locale == 'ru' ? 'Пермь' : 'Perm',
            firstDate: DateTime(2026),
            lastDate: DateTime(2027),
            onChanged: onChanged,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('picker edits city calendar fields and returns UTC', (
    tester,
  ) async {
    DateTime? selected;
    await pumpPicker(tester, (value) => selected = value);
    expect(find.textContaining('18:00'), findsOneWidget);
    await tester.tap(find.text('Choose date and time'));
    await tester.pumpAndSettle();
    expect(find.text('Date and time: Perm'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Date and time: Perm'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '7');
    await tester.enterText(fields.at(1), '15');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(selected, DateTime.utc(2026, 11, 16, 14, 15));
    expect(selected!.isUtc, isTrue);
  });

  testWidgets('cancel leaves value unchanged', (tester) async {
    DateTime? selected;
    await pumpPicker(tester, (value) => selected = value);
    await tester.tap(find.text('Choose date and time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
  });

  testWidgets('Russian city annotation and picker label', (tester) async {
    await pumpPicker(tester, (_) {}, locale: 'ru');
    expect(find.textContaining('18:00, Пермь, UTC+5'), findsOneWidget);
    expect(find.text('Выбрать дату и время'), findsOneWidget);
  });
}
