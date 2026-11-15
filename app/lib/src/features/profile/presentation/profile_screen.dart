import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_client.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/api_error_view.dart';
import '../../privacy/domain/privacy.dart';
import '../../privacy/presentation/privacy_labels.dart';
import '../application/my_profile.dart';
import '../application/skills.dart';
import 'name_change_dialog.dart';
import 'profile_photo_editor.dart';

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
          IconButton(
            key: const Key('profile-chats'),
            icon: const Icon(Icons.chat_bubble_outline),
            tooltip: l10n.profileChats,
            onPressed: () => context.push(AppRoutes.chats),
          ),
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

    final nextChange = nextNameChange(user);
    final accountType = switch (user.accountType) {
      UserOutputAccountType.employee => l10n.profileAccountEmployee,
      UserOutputAccountType.formerEmployee => l10n.profileAccountFormerEmployee,
      _ => l10n.profileAccountStudent,
    };

    return ListView(
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: ProfilePhotoEditor(),
        ),
        ListTile(
          key: const Key('profile-name'),
          leading: const Icon(Icons.person_outline),
          title: Text('${user.firstName} ${user.lastName}'),
          subtitle: Text(
            nextChange == null
                ? accountType
                : '$accountType\n'
                      '${l10n.profileNameNextChange(formatDate(context, nextChange))}',
          ),
          isThreeLine: nextChange != null,
          trailing: IconButton(
            key: const Key('profile-name-change'),
            icon: const Icon(Icons.drive_file_rename_outline),
            tooltip: l10n.profileNameChange,
            onPressed: nextChange != null
                ? null
                : () => showDialog<bool>(
                    context: context,
                    builder: (context) => NameChangeDialog(user: user),
                  ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.alternate_email),
          title: Text(l10n.profileEmail),
          subtitle: Text(user.email),
        ),
        ListTile(
          key: const Key('profile-emails'),
          leading: const Icon(Icons.mail_outline),
          title: Text(l10n.profileEmails),
          onTap: () => context.push(AppRoutes.profileEmails),
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
        const Divider(),
        const _Skills(),
        const Divider(),
        ListTile(
          key: const Key('profile-reviews'),
          leading: const Icon(Icons.rate_review_outlined),
          title: Text(l10n.profileReviews),
          onTap: () => context.push(AppRoutes.userReviewsOf(user.id)),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            l10n.profilePrivacy,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        ListTile(
          key: const Key('profile-message-policy'),
          leading: const Icon(Icons.forum_outlined),
          title: Text(l10n.messagePolicyTitle),
          subtitle: Text(
            messagePolicyLabel(l10n, userMessagePolicyOf(user.messagePolicy)),
          ),
          onTap: () => context.push(AppRoutes.messagePolicy),
        ),
        ListTile(
          key: const Key('profile-blocked-users'),
          leading: const Icon(Icons.shield_outlined),
          title: Text(l10n.blockedUsersTitle),
          onTap: () => context.push(AppRoutes.blockedUsers),
        ),
      ],
    );
  }
}

/// Both skill lists of the profile, with a way to change them.
class _Skills extends ConsumerWidget {
  const _Skills();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final skills = ref.watch(mySkillsProvider).value;
    String names(List<SkillTagOutput>? tags) => tags == null
        ? '…'
        : tags.isEmpty
        ? l10n.profileSkillsNone
        : tags.map((tag) => tag.name).join(', ');
    return Column(
      children: [
        ListTile(
          title: Text(
            l10n.profileSkills,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          trailing: IconButton(
            key: const Key('profile-skills-edit'),
            icon: const Icon(Icons.edit_outlined),
            tooltip: l10n.profileSkillsEdit,
            onPressed: () => context.push(AppRoutes.profileSkills),
          ),
        ),
        ListTile(
          key: const Key('profile-skills-can'),
          leading: const Icon(Icons.handyman_outlined),
          title: Text(l10n.profileSkillsCan),
          subtitle: Text(names(skills?.can)),
        ),
        ListTile(
          key: const Key('profile-skills-wants'),
          leading: const Icon(Icons.lightbulb_outline),
          title: Text(l10n.profileSkillsWants),
          subtitle: Text(names(skills?.wants)),
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
