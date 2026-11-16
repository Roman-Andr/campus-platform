import 'package:campus/src/core/design_system/components/components.dart';
import 'package:campus/src/core/design_system/foundations/tokens.dart';
import 'package:campus/src/core/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:widgetbook/widgetbook.dart';

import 'pattern_stories.dart';
import 'story_support.dart';

final catalogStories = <WidgetbookNode>[
  patternStories,
  WidgetbookComponent(
    name: 'Controls',
    useCases: [
      WidgetbookUseCase(
        name: 'Actions',
        builder: (context) => StoryPage(
          children: [
            BusyAction(
              label: fixture(context, 'Save', 'Сохранить'),
              onPressed: () {},
            ),
            BusyAction(
              label: fixture(context, 'Save', 'Сохранить'),
              onPressed: () {},
              busy: true,
            ),
            BusyAction(
              label: fixture(context, 'Save', 'Сохранить'),
              onPressed: null,
            ),
            BusyAction(
              label: fixture(
                context,
                'Save this long description and continue editing the publication',
                'Сохранить длинное описание и продолжить редактировать публикацию',
              ),
              onPressed: () {},
            ),
            OutlinedButton(
              onPressed: () {},
              child: Text(fixture(context, 'Cancel', 'Отмена')),
            ),
            TextButton(
              onPressed: () {},
              child: Text(fixture(context, 'Cancel', 'Отмена')),
            ),
            IconButton(
              tooltip: context.l10n.settingsTitle,
              onPressed: () {},
              icon: const Icon(Icons.settings_outlined),
            ),
            CampusAvatar(
              label: fixture(context, 'Hidden profile', 'Скрытый профиль'),
            ),
            Text(
              fixture(
                context,
                'Use Tab/Shift+Tab, Enter and pointer to inspect focus/hover/pressed.',
                'Проверьте Tab/Shift+Tab, Enter и указатель: focus/hover/pressed.',
              ),
            ),
          ],
        ),
      ),
      WidgetbookUseCase(
        name: 'Fields and filters',
        builder: (_) => const FieldStory(),
      ),
      WidgetbookUseCase(
        name: 'Sheets and dialogs',
        builder: (context) => StoryPage(
          children: [
            FilledButton(
              onPressed: () => showCampusSheet<void>(
                context: context,
                builder: (ctx) => StatePanel(
                  title: ctx.l10n.settingsTitle,
                  description: fixture(
                    ctx,
                    'Keyboard and Back remain native.',
                    'Клавиатура и Назад работают стандартно.',
                  ),
                  icon: Icons.settings,
                ),
              ),
              child: Text(context.l10n.settingsTitle),
            ),
            OutlinedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(ctx.l10n.settingsTitle),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(fixture(ctx, 'Cancel', 'Отмена')),
                    ),
                  ],
                ),
              ),
              child: Text(fixture(context, 'Cancel', 'Отмена')),
            ),
          ],
        ),
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Feedback',
    useCases: [
      WidgetbookUseCase(
        name: 'Retained content',
        builder: (context) => StoryPage(
          children: [
            for (final tone in NoticeTone.values)
              InlineNotice(
                tone: tone,
                message: fixture(
                  context,
                  'Saved content stays visible. The server owns the final state.',
                  'Сохранённые данные доступны. Итоговое состояние определяет сервер.',
                ),
                action: TextButton(
                  onPressed: () {},
                  child: Text(fixture(context, 'Retry', 'Повторить')),
                ),
              ),
          ],
        ),
      ),
      WidgetbookUseCase(
        name: 'Empty error loading',
        builder: (context) => StoryPage(
          children: [
            StatePanel(
              title: fixture(context, 'Nothing here yet', 'Пока ничего нет'),
              description: fixture(
                context,
                'Try another filter.',
                'Попробуйте другой фильтр.',
              ),
              icon: Icons.search,
            ),
            StatePanel(
              title: fixture(context, 'Could not load', 'Не удалось загрузить'),
              description: fixture(
                context,
                'Retry when you are ready.',
                'Повторите, когда будете готовы.',
              ),
              icon: Icons.cloud_off,
              action: BusyAction(
                label: fixture(context, 'Retry', 'Повторить'),
                onPressed: () {},
              ),
            ),
            const LinearProgressIndicator(),
          ],
        ),
      ),
    ],
  ),
];

class FieldStory extends StatefulWidget {
  const FieldStory({super.key});
  @override
  State<FieldStory> createState() => _FieldStoryState();
}

class _FieldStoryState extends State<FieldStory> {
  int selected = 0;
  bool chip = false;
  @override
  Widget build(BuildContext context) => StoryPage(
    children: [
      TextField(
        autofocus: true,
        decoration: InputDecoration(labelText: context.l10n.settingsTitle),
      ),
      TextField(
        decoration: InputDecoration(
          labelText: context.l10n.settingsTitle,
          errorText: fixture(context, 'Check this value', 'Проверьте значение'),
        ),
      ),
      TextField(
        enabled: false,
        decoration: InputDecoration(labelText: context.l10n.settingsTitle),
      ),
      SearchBar(
        hintText: fixture(context, 'Search the campus', 'Поиск по кампусу'),
        leading: const Icon(Icons.search),
      ),
      SegmentedButton<int>(
        segments: [
          ButtonSegment(value: 0, label: Text(context.l10n.settingsThemeLight)),
          ButtonSegment(value: 1, label: Text(context.l10n.settingsThemeDark)),
        ],
        selected: {selected},
        onSelectionChanged: (s) => setState(() => selected = s.single),
      ),
      Wrap(
        spacing: CampusSpace.sm,
        children: [
          FilterChip(
            selected: chip,
            label: Text(context.l10n.settingsTitle),
            onSelected: (v) => setState(() => chip = v),
          ),
          InputChip(label: Text(context.l10n.settingsTitle), onDeleted: () {}),
          ChoiceChip(label: Text(context.l10n.settingsTitle), selected: false),
        ],
      ),
    ],
  );
}
