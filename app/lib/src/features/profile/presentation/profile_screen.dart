import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_client.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/api_error_view.dart';
import '../application/my_profile.dart';

/// The signed-in user's own profile, with a way to change it.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final profile = ref.watch(myProfileProvider);
    final user = profile.value;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.profileTitle),
        actions: [
          if (user != null)
            IconButton(
              key: const Key('profile-edit'),
              icon: const Icon(Icons.edit_outlined),
              tooltip: l10n.profileEditTitle,
              onPressed: () => context.push(AppRoutes.profileEdit),
            ),
        ],
      ),
      body: switch (profile) {
        AsyncValue(value: final user?) => _ProfileDetails(user),
        AsyncValue(:final error?) => ApiErrorView(
          error: error,
          onRetry: () => ref.invalidate(myProfileProvider),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _ProfileDetails extends ConsumerWidget {
  const _ProfileDetails(this.user);

  final UserOutput user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final cityId = user.cityId;
    String? nameOf(Iterable<(String, String)>? places, String? id) {
      for (final (placeId, name) in places ?? const <(String, String)>[]) {
        if (placeId == id) return name;
      }
      return null;
    }

    Iterable<(String, String)>? placesOf(
      AsyncValue<List<CityPlaceOut>> places,
    ) => places.value?.map((place) => (place.id, place.name));

    final cities = ref
        .watch(citiesProvider)
        .value
        ?.map((city) => (city.id, city.name));
    final dormitories = cityId == null
        ? null
        : placesOf(ref.watch(dormitoriesProvider(cityId)));
    final faculties = cityId == null
        ? null
        : placesOf(ref.watch(facultiesProvider(cityId)));
    final dormitory = user.dormitoryId == null
        ? l10n.profileNoDormitory
        : nameOf(dormitories, user.dormitoryId);
    final course = user.course;

    return ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.person_outline),
          title: Text('${user.firstName} ${user.lastName}'),
          subtitle: Text(switch (user.accountType) {
            UserOutputAccountType.employee => l10n.profileAccountEmployee,
            UserOutputAccountType.formerEmployee =>
              l10n.profileAccountFormerEmployee,
            _ => l10n.profileAccountStudent,
          }),
        ),
        ListTile(
          leading: const Icon(Icons.alternate_email),
          title: Text(l10n.profileEmail),
          subtitle: Text(user.email),
        ),
        const Divider(),
        _Detail(
          icon: Icons.location_city_outlined,
          label: l10n.profileCity,
          value: nameOf(cities, cityId),
        ),
        _Detail(
          icon: Icons.apartment_outlined,
          label: l10n.profileDormitory,
          value: dormitory,
        ),
        _Detail(
          icon: Icons.school_outlined,
          label: l10n.profileFaculty,
          value: nameOf(faculties, user.facultyId),
        ),
        if (hasCourse(user.accountType))
          _Detail(
            icon: Icons.timeline_outlined,
            label: l10n.profileCourse,
            value: course == null ? null : l10n.profileCourseValue(course),
          ),
      ],
    );
  }
}

/// One item of the profile; `null` [value] while it loads.
class _Detail extends StatelessWidget {
  const _Detail({required this.icon, required this.label, this.value});

  final IconData icon;
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(label),
    subtitle: Text(value ?? '…'),
  );
}
