import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_failure_message.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/widgets/api_error_view.dart';
import '../../auth/presentation/auth_layout.dart';
import '../application/my_profile.dart';
import '../application/profile_config.dart';

/// Choice of the dormitory field meaning "does not live in a dormitory".
const noDormitory = '';

/// Filling in the profile after the first sign-in ([onboarding]) or
/// changing it: campus city, then a dormitory (or none) and a faculty of
/// that city, and the course for students (ТЗ п. 5.1.1, модуль 2, п. 1).
class ProfileFormScreen extends ConsumerStatefulWidget {
  const ProfileFormScreen({this.onboarding = false, super.key});

  /// The profile is not filled in yet: no way back, only to sign out.
  final bool onboarding;

  @override
  ConsumerState<ProfileFormScreen> createState() => _ProfileFormScreenState();
}

class _ProfileFormScreenState extends ConsumerState<ProfileFormScreen> {
  final _form = GlobalKey<FormState>();
  String? _cityId;
  String? _dormitoryId;
  String? _facultyId;
  int? _course;
  var _busy = false;
  String? _error;

  /// Fields the server rejected, by name, with the reason code.
  var _invalid = <String, String>{};

  @override
  void initState() {
    super.initState();
    final user = ref.read(myProfileProvider).value;
    if (user != null && user.profileComplete) {
      _cityId = user.cityId;
      _dormitoryId = user.dormitoryId ?? noDormitory;
      _facultyId = user.facultyId;
      _course = user.course;
    }
  }

  void _chooseCity(String? cityId) {
    if (cityId == _cityId) return;
    setState(() {
      _cityId = cityId;
      _dormitoryId = null;
      _facultyId = null;
      _invalid = {};
    });
  }

  Future<void> _submit(bool withCourse) async {
    setState(() => _invalid = {});
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(myProfileProvider.notifier)
          .save(
            ProfileInput(
              cityId: _cityId!,
              dormitoryId: _dormitoryId == noDormitory ? null : _dormitoryId,
              facultyId: _facultyId!,
              course: withCourse ? _course : null,
            ),
          );
      // After onboarding the router leaves this screen by itself.
      if (mounted && !widget.onboarding) context.pop();
    } on Object catch (error) {
      if (!mounted) return;
      final fields = switch (ApiFailure.from(error)) {
        ProblemFailure(:final fieldErrors) => {
          for (final field in fieldErrors)
            if (field.pointer case final pointer?)
              pointer.split('/').last: field.code,
        },
        _ => <String, String>{},
      };
      if (fields.isNotEmpty) {
        // The reference data changed meanwhile: offer the current lists.
        ref
          ..invalidate(citiesProvider)
          ..invalidate(dormitoriesProvider)
          ..invalidate(facultiesProvider);
      }
      setState(() {
        _invalid = fields;
        _error = fields.isEmpty ? apiFailureMessage(context.l10n, error) : null;
      });
      _form.currentState!.validate();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _validate(String field, Object? value) {
    final l10n = context.l10n;
    if (value == null) return l10n.profileChoose;
    return switch (_invalid[field]) {
      null => null,
      'not_found' || 'not_of_city' => l10n.profilePlaceUnavailable,
      _ => l10n.profileChoose,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final user = ref.watch(myProfileProvider).value;
    final withCourse = user == null || hasCourse(user.accountType);
    final cities = ref.watch(citiesProvider);
    final title = widget.onboarding
        ? l10n.profileSetupTitle
        : l10n.profileEditTitle;
    if (!cities.hasValue) {
      return Scaffold(
        appBar: AppBar(title: Text(title), actions: _actions(l10n)),
        body: cities.hasError
            ? ApiErrorView(
                error: cities.error!,
                onRetry: () => ref.invalidate(citiesProvider),
              )
            : const Center(child: CircularProgressIndicator()),
      );
    }
    final cityId = _cityId;
    final dormitories = cityId == null
        ? null
        : ref.watch(dormitoriesProvider(cityId));
    final faculties = cityId == null
        ? null
        : ref.watch(facultiesProvider(cityId));
    final maxCourse = ref.watch(profileConfigProvider).maxCourse;
    return AuthLayout(
      title: title,
      actions: _actions(l10n),
      children: [
        if (widget.onboarding) ...[Text(l10n.profileSetupIntro), authGap],
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                key: const Key('profile-city'),
                initialValue: _cityId,
                isExpanded: true,
                decoration: InputDecoration(labelText: l10n.profileCity),
                items: [
                  for (final city in cities.requireValue)
                    DropdownMenuItem(value: city.id, child: Text(city.name)),
                ],
                onChanged: _busy ? null : _chooseCity,
                validator: (value) => _validate('city_id', value),
              ),
              authGap,
              _PlaceField(
                key: Key('profile-dormitory-$cityId'),
                label: l10n.profileDormitory,
                places: dormitories,
                initialValue: _dormitoryId,
                extra: DropdownMenuItem(
                  value: noDormitory,
                  child: Text(l10n.profileNoDormitory),
                ),
                enabled: !_busy,
                onChanged: (value) => setState(() => _dormitoryId = value),
                validator: (value) => _validate('dormitory_id', value),
              ),
              authGap,
              _PlaceField(
                key: Key('profile-faculty-$cityId'),
                label: l10n.profileFaculty,
                places: faculties,
                initialValue: _facultyId,
                enabled: !_busy,
                onChanged: (value) => setState(() => _facultyId = value),
                validator: (value) => _validate('faculty_id', value),
              ),
              if (withCourse) ...[
                authGap,
                DropdownButtonFormField<int>(
                  key: const Key('profile-course'),
                  initialValue: _course != null && _course! <= maxCourse
                      ? _course
                      : null,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: l10n.profileCourse),
                  items: [
                    for (var course = 1; course <= maxCourse; course++)
                      DropdownMenuItem(
                        value: course,
                        child: Text(l10n.profileCourseValue(course)),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _course = value),
                  validator: (value) => _validate('course', value),
                ),
              ],
            ],
          ),
        ),
        AuthError(_error),
        authGap,
        FilledButton(
          key: const Key('profile-save'),
          onPressed: _busy ? null : () => unawaited(_submit(withCourse)),
          child: Text(
            widget.onboarding ? l10n.profileContinue : l10n.profileSave,
          ),
        ),
      ],
    );
  }

  List<Widget> _actions(AppLocalizations l10n) => [
    if (widget.onboarding)
      IconButton(
        key: const Key('profile-sign-out'),
        icon: const Icon(Icons.logout),
        tooltip: l10n.signOut,
        onPressed: () => unawaited(ref.read(authServiceProvider).signOut()),
      ),
  ];
}

/// A dormitory or faculty of the chosen city; disabled until a city is
/// chosen and while its list loads.
class _PlaceField extends StatelessWidget {
  const _PlaceField({
    required this.label,
    required this.places,
    required this.initialValue,
    required this.enabled,
    required this.onChanged,
    required this.validator,
    this.extra,
    super.key,
  });

  final String label;
  final AsyncValue<List<CityPlaceOut>>? places;
  final String? initialValue;
  final bool enabled;
  final ValueChanged<String?> onChanged;
  final FormFieldValidator<String> validator;

  /// An option before the places, e.g. "does not live in a dormitory".
  final DropdownMenuItem<String>? extra;

  @override
  Widget build(BuildContext context) {
    final list = places?.value;
    final items = [
      ?extra,
      for (final place in list ?? const <CityPlaceOut>[])
        DropdownMenuItem(value: place.id, child: Text(place.name)),
    ];
    final known = items.any((item) => item.value == initialValue);
    return DropdownButtonFormField<String>(
      // initialValue is read once: start anew when the list arrives.
      key: ValueKey(list != null),
      initialValue: list != null && known ? initialValue : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        errorText: places?.hasError ?? false
            ? apiFailureMessage(context.l10n, places!.error!)
            : null,
      ),
      items: list == null ? const [] : items,
      onChanged: enabled && list != null ? onChanged : null,
      validator: validator,
    );
  }
}
