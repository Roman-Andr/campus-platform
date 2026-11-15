import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' hide Visibility;

import '../../../core/api/api_client.dart';
import '../../../core/api/api_failure_message.dart';
import '../../../core/l10n/l10n.dart';
import '../../profile/application/my_profile.dart';
import '../application/listings.dart';
import '../domain/skills.dart';
import 'listings_screens.dart';

/// The form of a skill listing: what the author can teach or wants to learn
/// (ТЗ п. 5.1.1, модуль 4, п. 10).
class CreateSkillScreen extends ConsumerStatefulWidget {
  const CreateSkillScreen({super.key});

  @override
  ConsumerState<CreateSkillScreen> createState() => _CreateSkillScreenState();
}

class _CreateSkillScreenState extends ConsumerState<CreateSkillScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  SkillDirection _direction = SkillDirection.teach;
  Visibility _scope = Visibility.city;
  Audience _audience = Audience.students;
  String? _categoryId;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final l = context.l10n;
    final user = ref.read(myProfileProvider).value;
    final employee = user?.accountType == UserOutputAccountType.employee;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final messenger = ScaffoldMessenger.maybeOf(context);
      await ref
          .read(campusApiProvider)
          .listings
          .publishSkill(
            body: SkillInput(
              title: _title.text.trim(),
              description: _description.text.trim(),
              direction: _direction,
              visibility: _scope,
              audience: employee ? Audience.community : _audience,
              categoryId: _categoryId!,
            ),
          );
      refreshListings(ref);
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger?.showSnackBar(SnackBar(content: Text(l.skillPublished)));
    } on Object catch (e) {
      if (mounted) setState(() => _error = listingFailureMessage(l, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final user = ref.watch(myProfileProvider).value;
    final employee = user?.accountType == UserOutputAccountType.employee;
    final categories = ref.watch(listingCategoriesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.skillCreateTitle)),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            categories.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => Column(
                children: [
                  Text(apiFailureMessage(l, error)),
                  TextButton(
                    onPressed: () => ref.invalidate(listingCategoriesProvider),
                    child: Text(l.errorRetry),
                  ),
                ],
              ),
              data: (items) => items.isEmpty
                  ? Text(l.listingCategoriesEmpty)
                  : DropdownButtonFormField<String>(
                      key: const Key('skill-category'),
                      initialValue: items.any((item) => item.id == _categoryId)
                          ? _categoryId
                          : null,
                      decoration: InputDecoration(labelText: l.listingCategory),
                      items: [
                        for (final item in items)
                          DropdownMenuItem(
                            value: item.id,
                            child: Text(item.name),
                          ),
                      ],
                      validator: (value) =>
                          items.any((item) => item.id == value)
                          ? null
                          : l.profileChoose,
                      onChanged: (value) => setState(() => _categoryId = value),
                    ),
            ),
            DropdownButtonFormField<SkillDirection>(
              key: const Key('skill-direction'),
              initialValue: _direction,
              decoration: InputDecoration(labelText: l.skillDirection),
              items: [
                for (final direction in const [
                  SkillDirection.teach,
                  SkillDirection.learn,
                ])
                  DropdownMenuItem(
                    value: direction,
                    child: Text(skillDirectionLabel(l, direction)),
                  ),
              ],
              onChanged: (value) =>
                  setState(() => _direction = value ?? _direction),
            ),
            TextFormField(
              key: const Key('skill-title'),
              controller: _title,
              decoration: InputDecoration(labelText: l.listingTitle),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? l.signInNameRequired : null,
            ),
            TextFormField(
              key: const Key('skill-description'),
              controller: _description,
              decoration: InputDecoration(labelText: l.listingDescription),
              minLines: 3,
              maxLines: null,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? l.signInNameRequired : null,
            ),
            DropdownButtonFormField<Visibility>(
              key: const Key('skill-scope'),
              initialValue: _scope,
              decoration: InputDecoration(labelText: l.listingScope),
              items: [
                for (final scope in [
                  Visibility.city,
                  if (user?.facultyId != null) Visibility.faculty,
                  if (user?.dormitoryId != null && !employee)
                    Visibility.dormitory,
                ])
                  DropdownMenuItem(
                    value: scope,
                    child: Text(scopeName(l, scope)),
                  ),
              ],
              onChanged: (value) => setState(() => _scope = value ?? _scope),
            ),
            DropdownButtonFormField<Audience>(
              key: const Key('skill-audience'),
              initialValue: employee ? Audience.community : _audience,
              decoration: InputDecoration(labelText: l.listingAudience),
              items: [
                DropdownMenuItem(
                  value: Audience.students,
                  child: Text(l.listingStudents),
                ),
                DropdownMenuItem(
                  value: Audience.community,
                  child: Text(l.listingCommunity),
                ),
              ],
              onChanged: employee
                  ? null
                  : (value) => setState(() => _audience = value ?? _audience),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  key: const Key('skill-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('skill-publish'),
              onPressed:
                  _busy ||
                      user == null ||
                      !(categories.value?.isNotEmpty ?? false)
                  ? null
                  : _publish,
              child: Text(l.listingPublish),
            ),
          ],
        ),
      ),
    );
  }
}
