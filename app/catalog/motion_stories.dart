import 'package:campus/src/core/design_system/components/components.dart';
import 'package:campus/src/core/design_system/motion/campus_motion.dart';
import 'package:material_ui/material_ui.dart';
import 'package:widgetbook/widgetbook.dart';

import 'story_support.dart';

final motionStories = WidgetbookComponent(
  name: 'Motion',
  useCases: [
    WidgetbookUseCase(
      name: 'Content feedback and modals',
      builder: (_) => const MotionStory(),
    ),
  ],
);

class MotionStory extends StatefulWidget {
  const MotionStory({super.key});
  @override
  State<MotionStory> createState() => _MotionStoryState();
}

class _MotionStoryState extends State<MotionStory> {
  bool selected = false;
  @override
  Widget build(BuildContext context) => CampusMotionVisibility(
    child: StoryPage(
      children: [
        Text(
          fixture(
            context,
            'Toggle Reduced motion above to compare. No API request is made.',
            'Сравните с Reduced motion выше. Запросов к API нет.',
          ),
        ),
        FilledButton(
          key: const Key('motion-toggle'),
          onPressed: () => setState(() => selected = !selected),
          child: Text(fixture(context, 'Change content', 'Сменить содержимое')),
        ),
        CampusContentSwitch(
          stateKey: ValueKey(selected),
          child: StatePanel(
            title: fixture(
              context,
              selected ? 'Second state' : 'First state',
              selected ? 'Второе состояние' : 'Первое состояние',
            ),
            description: fixture(
              context,
              'State supplied by the caller.',
              'Состояние передано вызывающим кодом.',
            ),
            icon: selected ? Icons.check : Icons.info_outline,
          ),
        ),
        CampusSelectionFeedback(
          selected: selected,
          child: Text(
            fixture(context, 'Selection feedback', 'Обратная связь выбора'),
          ),
        ),
        FilledButton(
          onPressed: () => showCampusSheet<void>(
            context: context,
            builder: (ctx) => StatePanel(
              title: fixture(ctx, 'Sheet', 'Панель'),
              description: fixture(
                ctx,
                'Native Back and keyboard.',
                'Стандартные Назад и клавиатура.',
              ),
              icon: Icons.layers_outlined,
            ),
          ),
          child: Text(fixture(context, 'Open sheet', 'Открыть панель')),
        ),
        OutlinedButton(
          onPressed: () => showCampusDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(fixture(ctx, 'Dialog', 'Диалог')),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(fixture(ctx, 'Close', 'Закрыть')),
                ),
              ],
            ),
          ),
          child: Text(fixture(context, 'Open dialog', 'Открыть диалог')),
        ),
      ],
    ),
  );
}
