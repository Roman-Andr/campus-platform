import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_failure_message.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/widgets/api_error_view.dart';
import '../application/skills.dart';

/// The two skill lists of the profile, "can" and "wants to learn", each
/// filled from the common tag reference; saved together.
class SkillsForm extends ConsumerWidget {
  const SkillsForm({
    required this.submitLabel,
    required this.onSaved,
    this.secondary,
    super.key,
  });

  final String submitLabel;

  /// Called after the server saved the lists.
  final VoidCallback onSaved;

  /// An extra action next to saving, e.g. skipping the step.
  final Widget? secondary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skills = ref.watch(mySkillsProvider);
    return switch (skills) {
      AsyncValue(:final error?, hasValue: false) => ApiErrorView(
        error: error,
        onRetry: () => ref.invalidate(mySkillsProvider),
      ),
      AsyncValue(hasValue: true) => _SkillsEditor(
        initial: skills.value,
        submitLabel: submitLabel,
        onSaved: onSaved,
        secondary: secondary,
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _SkillsEditor extends ConsumerStatefulWidget {
  const _SkillsEditor({
    required this.initial,
    required this.submitLabel,
    required this.onSaved,
    this.secondary,
  });

  final SkillsOutput? initial;
  final String submitLabel;
  final VoidCallback onSaved;
  final Widget? secondary;

  @override
  ConsumerState<_SkillsEditor> createState() => _SkillsEditorState();
}

class _SkillsEditorState extends ConsumerState<_SkillsEditor> {
  late List<SkillTagOutput> _can = [...?widget.initial?.can];
  late List<SkillTagOutput> _wants = [...?widget.initial?.wants];
  var _busy = false;
  String? _error;

  Future<void> _add(bool can) async {
    final chosen = can ? _can : _wants;
    final tag = await showModalBottomSheet<SkillTagOutput>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) =>
          SkillSearchSheet(exclude: {for (final tag in chosen) tag.id}),
    );
    if (tag == null || !mounted) return;
    setState(() => can ? _can = [..._can, tag] : _wants = [..._wants, tag]);
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(mySkillsProvider.notifier).save(can: _can, wants: _wants);
      if (mounted) widget.onSaved();
    } on Object catch (error) {
      if (!mounted) return;
      final l10n = context.l10n;
      final outdated = switch (ApiFailure.from(error)) {
        ProblemFailure(:final fieldErrors) => fieldErrors.any(
          (field) => field.code == 'not_found',
        ),
        _ => false,
      };
      setState(
        () => _error = outdated
            ? l10n.profileSkillsUnavailable
            : apiFailureMessage(l10n, error),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final error = _error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SkillSection(
          key: const Key('skills-can'),
          title: l10n.profileSkillsCan,
          tags: _can,
          enabled: !_busy,
          onAdd: () => unawaited(_add(true)),
          onRemove: (tag) => setState(
            () => _can = [..._can.where((other) => other.id != tag.id)],
          ),
        ),
        const SizedBox(height: 16),
        _SkillSection(
          key: const Key('skills-wants'),
          title: l10n.profileSkillsWants,
          tags: _wants,
          enabled: !_busy,
          onAdd: () => unawaited(_add(false)),
          onRemove: (tag) => setState(
            () => _wants = [..._wants.where((other) => other.id != tag.id)],
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              error,
              key: const Key('skills-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 24),
        FilledButton(
          key: const Key('skills-save'),
          onPressed: _busy ? null : () => unawaited(_save()),
          child: Text(widget.submitLabel),
        ),
        if (widget.secondary case final secondary?) ...[
          const SizedBox(height: 8),
          secondary,
        ],
      ],
    );
  }
}

class _SkillSection extends StatelessWidget {
  const _SkillSection({
    required this.title,
    required this.tags,
    required this.enabled,
    required this.onAdd,
    required this.onRemove,
    super.key,
  });

  final String title;
  final List<SkillTagOutput> tags;
  final bool enabled;
  final VoidCallback onAdd;
  final ValueChanged<SkillTagOutput> onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tag in tags)
              InputChip(
                key: Key('skill-${tag.code}'),
                label: Text(tag.name),
                deleteButtonTooltipMessage: l10n.profileSkillRemove(tag.name),
                onDeleted: enabled ? () => onRemove(tag) : null,
              ),
            ActionChip(
              key: const Key('skills-add'),
              avatar: const Icon(Icons.add),
              label: Text(l10n.profileSkillsAdd),
              onPressed: enabled ? onAdd : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// Search of the skill tag reference by the beginning of a name; pops the
/// chosen tag.
class SkillSearchSheet extends ConsumerStatefulWidget {
  const SkillSearchSheet({this.exclude = const {}, super.key});

  /// Ids of tags already chosen; they are not offered.
  final Set<String> exclude;

  @override
  ConsumerState<SkillSearchSheet> createState() => _SkillSearchSheetState();
}

class _SkillSearchSheetState extends ConsumerState<SkillSearchSheet> {
  var _query = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _search(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = text.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final results = ref.watch(skillTagSearchProvider(_query));
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Column(
          children: [
            TextField(
              key: const Key('skills-search'),
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.profileSkillsSearch,
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: _search,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: switch (results) {
                AsyncValue(:final error?, hasValue: false) => ApiErrorView(
                  error: error,
                  onRetry: () => ref.invalidate(skillTagSearchProvider(_query)),
                ),
                AsyncValue(value: final tags?) => () {
                  final offered = [
                    for (final tag in tags)
                      if (!widget.exclude.contains(tag.id)) tag,
                  ];
                  if (offered.isEmpty) {
                    return Center(child: Text(l10n.profileSkillsNotFound));
                  }
                  return ListView(
                    children: [
                      for (final tag in offered)
                        ListTile(
                          key: Key('skill-option-${tag.code}'),
                          title: Text(tag.name),
                          onTap: () => Navigator.of(context).pop(tag),
                        ),
                    ],
                  );
                }(),
                _ => const Center(child: CircularProgressIndicator()),
              },
            ),
          ],
        ),
      ),
    );
  }
}
