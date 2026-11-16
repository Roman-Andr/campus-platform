import 'package:campus/src/core/api/generated/listings/models/listing_status.dart';
import 'package:campus/src/core/design_system/components/components.dart';
import 'package:campus/src/core/design_system/patterns/patterns.dart';
import 'package:campus/src/core/l10n/l10n.dart';
import 'package:campus/src/features/listings/presentation/components/listing_card.dart';
import 'package:campus/src/features/listings/presentation/view_data/listing_card_data.dart';
import 'package:campus/src/features/listings/presentation/view_data/listing_status_data.dart';
import 'package:material_ui/material_ui.dart';
import 'package:widgetbook/widgetbook.dart';

import 'story_support.dart';

final patternStories = WidgetbookComponent(
  name: 'Patterns',
  useCases: [
    WidgetbookUseCase(
      name: 'Listing families and redaction',
      builder: (context) => StoryPage(
        children: [
          for (final title in [
            fixture(
              context,
              'Giveaway: a reading lamp',
              'Отдам: настольная лампа',
            ),
            fixture(
              context,
              'Help: a long request title that grows naturally without a fixed-height card',
              'Помощь: длинный заголовок запроса без фиксированной высоты карточки',
            ),
          ])
            ListingCard(
              data: ListingCardData(
                title: title,
                summary: fixture(
                  context,
                  'Synthetic fixture. Actions come from the feature controller.',
                  'Тестовые данные. Действия передаёт контроллер сценария.',
                ),
                author: AuthorViewData(
                  redactedLabel: fixture(
                    context,
                    'Profile hidden',
                    'Профиль скрыт',
                  ),
                  detail: 'Must never be shown',
                ),
                status: listingStatusData(
                  context.l10n,
                  ListingStatus.fromJson('future-status'),
                ),
                scope: fixture(context, 'Campus audience', 'Аудитория кампуса'),
              ),
              onOpen: () {},
              actions: [
                BusyAction(
                  label: fixture(context, 'Open', 'Открыть'),
                  onPressed: () {},
                ),
              ],
            ),
        ],
      ),
    ),
    WidgetbookUseCase(
      name: 'Photo lifecycle',
      builder: (context) => StoryPage(
        children: [
          PhotoStrip(
            children: [
              for (final stage in PhotoStage.values)
                PhotoTile(
                  stage: stage,
                  label: photoLabel(context, stage),
                  action: stage == PhotoStage.failed
                      ? TextButton(
                          onPressed: () {},
                          child: Text(context.l10n.errorRetry),
                        )
                      : null,
                ),
            ],
          ),
        ],
      ),
    ),
    WidgetbookUseCase(
      name: 'Timeline and retained state',
      builder: (context) => StoryPage(
        children: [
          DeadlineBanner(
            message: fixture(
              context,
              'An offer deadline comes from server data.',
              'Срок предложения получен от сервера.',
            ),
          ),
          TimelineEntry(
            title: fixture(context, 'Request received', 'Запрос получен'),
            detail: fixture(
              context,
              'Synthetic chronology',
              'Тестовая хронология',
            ),
            icon: Icons.check_circle_outline,
          ),
          TimelineEntry(
            title: fixture(
              context,
              'Waiting for confirmation',
              'Ожидается подтверждение',
            ),
            detail: fixture(
              context,
              'The UI does not infer completion.',
              'UI не определяет завершение самостоятельно.',
            ),
            icon: Icons.schedule,
          ),
          InlineNotice(
            message: fixture(
              context,
              'A conflict occurred. Your draft is retained.',
              'Возник конфликт. Ваш черновик сохранён.',
            ),
            tone: NoticeTone.error,
            action: TextButton(
              onPressed: () {},
              child: Text(context.l10n.errorRetry),
            ),
          ),
        ],
      ),
    ),
    WidgetbookUseCase(
      name: 'Example editor',
      builder: (_) => const ExampleEditor(),
    ),
  ],
);

String photoLabel(BuildContext context, PhotoStage stage) => switch (stage) {
  PhotoStage.empty => fixture(context, 'No photo', 'Нет фото'),
  PhotoStage.local => fixture(context, 'On device', 'На устройстве'),
  PhotoStage.uploading => fixture(context, 'Uploading', 'Загрузка'),
  PhotoStage.processing => fixture(context, 'Processing', 'Обработка'),
  PhotoStage.ready => fixture(context, 'Ready', 'Готово'),
  PhotoStage.failed => fixture(context, 'Failed', 'Ошибка'),
};

/// Small reference composition. The next screen's container supplies providers.
class ExampleEditor extends StatefulWidget {
  const ExampleEditor({super.key});
  @override
  State<ExampleEditor> createState() => _ExampleEditorState();
}

class _ExampleEditorState extends State<ExampleEditor> {
  final description = TextEditingController();
  bool campus = true;
  @override
  void dispose() {
    description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => EditorScaffold(
    title: fixture(context, 'Example publication', 'Пример публикации'),
    sections: [
      FormSection(
        title: fixture(context, 'Description', 'Описание'),
        child: TextField(
          controller: description,
          maxLines: null,
          decoration: InputDecoration(
            labelText: fixture(context, 'Text', 'Текст'),
          ),
        ),
      ),
      FormSection(
        title: fixture(context, 'Photos', 'Фото'),
        child: PhotoStrip(
          children: [
            PhotoTile(
              stage: PhotoStage.empty,
              label: photoLabel(context, PhotoStage.empty),
            ),
          ],
        ),
      ),
      FormSection(
        title: fixture(context, 'Visibility', 'Видимость'),
        description: fixture(
          context,
          'The feature supplies authorized audiences.',
          'Разрешённые аудитории передаёт feature.',
        ),
        child: SwitchListTile(
          title: Text(fixture(context, 'Campus audience', 'Аудитория кампуса')),
          value: campus,
          onChanged: (v) => setState(() => campus = v),
        ),
      ),
    ],
    actions: [BusyAction(label: context.l10n.profileSave, onPressed: () {})],
  );
}
