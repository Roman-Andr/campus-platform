import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' hide Visibility;
import 'package:timezone/timezone.dart' as tz;

import '../../../core/api/api_client.dart';
import '../../../core/api/api_failure_message.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/time/city_time.dart';
import '../../../core/widgets/city_date_time_picker.dart';
import '../../profile/application/my_profile.dart';
import '../application/help_config.dart';
import '../application/listings.dart';
import '../domain/help.dart';
import 'listings_screens.dart';

/// The form of a help request: what is needed and until when it is relevant
/// (ТЗ п. 5.1.1, модуль 4, п. 11).
class CreateHelpScreen extends ConsumerStatefulWidget {
  const CreateHelpScreen({super.key});

  @override
  ConsumerState<CreateHelpScreen> createState() => _CreateHelpScreenState();
}

class _CreateHelpScreenState extends ConsumerState<CreateHelpScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  Visibility _scope = Visibility.city;
  Audience _audience = Audience.students;
  String? _categoryId;
  late DateTime _deadline = clock.now().add(const Duration(days: 1));
  String? _deadlineError;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    final l = context.l10n;
    final config = ref.read(helpConfigProvider);
    final issue = helpDeadlineIssue(
      _deadline,
      lifetime: config.listingLifetime,
    );
    if (issue != null) {
      setState(
        () => _deadlineError = helpDeadlineError(
          l,
          issue,
          lifetimeDays: config.listingLifetimeDays,
        ),
      );
      return;
    }
    setState(() => _deadlineError = null);
    if (!(_form.currentState?.validate() ?? false)) return;
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
          .publishHelpRequest(
            body: HelpRequestInput(
              title: _title.text.trim(),
              description: _description.text.trim(),
              visibility: _scope,
              audience: employee ? Audience.community : _audience,
              categoryId: _categoryId!,
              actualUntil: _deadline,
            ),
          );
      refreshListings(ref);
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger?.showSnackBar(SnackBar(content: Text(l.helpPublished)));
    } on Object catch (e) {
      if (mounted) setState(() => _error = helpFailureMessage(l, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final config = ref.watch(helpConfigProvider);
    final user = ref.watch(myProfileProvider).value;
    final employee = user?.accountType == UserOutputAccountType.employee;
    final categories = ref.watch(listingCategoriesProvider);
    final timezone = user?.cityTimezone ?? 'UTC';
    final today = tz.TZDateTime.from(clock.now(), cityLocation(timezone));
    final firstDate = DateTime(today.year, today.month, today.day);
    final lastDate = firstDate.add(config.listingLifetime);
    final pickerValue = _deadline.isBefore(firstDate) ? firstDate : _deadline;
    return Scaffold(
      appBar: AppBar(title: Text(l.helpCreateTitle)),
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
                      key: const Key('help-category'),
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
            TextFormField(
              key: const Key('help-title'),
              controller: _title,
              decoration: InputDecoration(labelText: l.listingTitle),
              validator: (value) => value == null || value.trim().isEmpty
                  ? l.signInNameRequired
                  : null,
            ),
            TextFormField(
              key: const Key('help-description'),
              controller: _description,
              decoration: InputDecoration(labelText: l.listingDescription),
              minLines: 3,
              maxLines: null,
              validator: (value) => value == null || value.trim().isEmpty
                  ? l.signInNameRequired
                  : null,
            ),
            DropdownButtonFormField<Visibility>(
              key: const Key('help-scope'),
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
              key: const Key('help-audience'),
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
            const SizedBox(height: 16),
            Text(l.helpDeadline, style: Theme.of(context).textTheme.titleSmall),
            Text(l.helpDeadlineHint(config.listingLifetimeDays)),
            CityDateTimePicker(
              key: const Key('help-deadline'),
              value: pickerValue,
              timezone: timezone,
              city: user?.cityTimezone ?? timezone,
              firstDate: firstDate,
              lastDate: lastDate,
              onChanged: (value) => setState(() {
                _deadline = value;
                _deadlineError = null;
              }),
            ),
            if (_deadlineError != null)
              Text(
                _deadlineError!,
                key: const Key('help-deadline-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  key: const Key('help-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 8),
            ListingAction(
              label: l.listingPublish,
              buttonKey: const Key('help-publish'),
              enabled:
                  !_busy &&
                  user != null &&
                  (categories.value?.isNotEmpty ?? false),
              run: _publish,
              failureMessage: helpFailureMessage,
            ),
          ],
        ),
      ),
    );
  }
}
