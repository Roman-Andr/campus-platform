import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_router.dart';
import '../../auth/presentation/auth_layout.dart';
import 'profile_photo_editor.dart';
import 'skills_form.dart';

/// Optional step of filling in the profile after the first sign-in: the
/// photo; it may be skipped.
class ProfilePhotoStepScreen extends StatelessWidget {
  const ProfilePhotoStepScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AuthLayout(
      title: l10n.profilePhoto,
      children: [
        Text(l10n.profileSetupPhotoIntro),
        authGap,
        const ProfilePhotoEditor(),
        authGap,
        FilledButton(
          key: const Key('profile-step-next'),
          onPressed: () => context.go(AppRoutes.profileSetupSkills),
          child: Text(l10n.profileContinue),
        ),
        TextButton(
          key: const Key('profile-step-skip'),
          onPressed: () => context.go(AppRoutes.profileSetupSkills),
          child: Text(l10n.profileSkip),
        ),
      ],
    );
  }
}

/// Optional step of filling in the profile after the first sign-in: the
/// skills; it may be skipped.
class ProfileSkillsStepScreen extends StatelessWidget {
  const ProfileSkillsStepScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AuthLayout(
      title: l10n.profileSkills,
      children: [
        Text(l10n.profileSetupSkillsIntro),
        authGap,
        SkillsForm(
          submitLabel: l10n.profileDone,
          onSaved: () => context.go(AppRoutes.home),
          secondary: TextButton(
            key: const Key('profile-step-skip'),
            onPressed: () => context.go(AppRoutes.home),
            child: Text(l10n.profileSkip),
          ),
        ),
      ],
    );
  }
}

/// Changing the skills of the own profile.
class SkillsScreen extends StatelessWidget {
  const SkillsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileSkillsEdit)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SkillsForm(
          submitLabel: l10n.profileSave,
          onSaved: () => context.pop(),
        ),
      ),
    );
  }
}
