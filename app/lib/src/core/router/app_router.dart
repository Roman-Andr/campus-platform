import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/account_emails/presentation/account_emails_screen.dart';
import '../../features/auth/application/sign_in_flow.dart';
import '../../features/auth/presentation/sign_in_code_screen.dart';
import '../../features/auth/presentation/sign_in_email_screen.dart';
import '../../features/auth/presentation/sign_in_name_screen.dart';
import '../../features/consents/presentation/consents_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/listings/presentation/event_screen.dart';
import '../../features/listings/presentation/help_screen.dart';
import '../../features/listings/presentation/interaction_timeline_screen.dart';
import '../../features/listings/presentation/listings_screens.dart';
import '../../features/listings/presentation/meeting_screen.dart';
import '../../features/listings/presentation/my_screens.dart';
import '../../features/listings/presentation/no_meeting_screen.dart';
import '../../features/listings/presentation/place_offer_screen.dart';
import '../../features/listings/presentation/publication_screen.dart';
import '../../features/listings/presentation/skill_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/profile/application/my_profile.dart';
import '../../features/profile/presentation/profile_form_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/profile/presentation/profile_steps.dart';
import '../../features/sessions/presentation/devices_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/update/presentation/update_required_screen.dart';
import '../api/client_update.dart';
import '../auth/auth_session.dart';

part 'app_router.g.dart';

/// Route locations of the app.
abstract final class AppRoutes {
  static const home = '/';
  static const settings = '/settings';
  static const devices = '/settings/devices';
  static const consents = '/settings/consents';
  static const updateRequired = '/update-required';
  static const signIn = '/sign-in';
  static const signInCode = '/sign-in/code';
  static const signInName = '/sign-in/name';
  static const profile = '/profile';
  static const profileEdit = '/profile/edit';
  static const profileEmails = '/profile/emails';
  static const profileSkills = '/profile/skills';
  static const notifications = '/notifications';

  /// The place offer opened by a notification; the path keeps the listing id.
  static const placeOfferPath = '/offers/:listingId';

  /// Location of the place offer of [listingId].
  static String placeOfferOf(String listingId) =>
      '/offers/${Uri.encodeComponent(listingId)}';

  /// Filling in the profile after the first sign-in.
  static const profileSetup = '/welcome';

  /// Optional steps after the profile is filled in: photo, then skills.
  static const profileSetupPhoto = '/welcome/photo';
  static const profileSetupSkills = '/welcome/skills';
}

@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  final router = GoRouter(
    initialLocation: AppRoutes.home,
    redirect: (context, state) => _redirect(ref, state.matchedLocation),
    routes: [
      GoRoute(
        path: '/giveaway/new',
        builder: (context, state) => const CreateListingScreen(),
      ),
      GoRoute(
        path: '/exchange/new',
        builder: (context, state) =>
            const CreateListingScreen(kind: 'exchange'),
      ),
      GoRoute(
        path: '/publication/new',
        builder: (context, state) => const CreatePublicationScreen(),
      ),
      GoRoute(
        path: '/event/new',
        builder: (context, state) => const CreateEventScreen(),
      ),
      GoRoute(
        path: '/event/:id/edit',
        builder: (context, state) =>
            EventEditScreen(id: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/skills/new',
        builder: (context, state) => const CreateSkillScreen(),
      ),
      GoRoute(
        path: '/help/new',
        builder: (context, state) => const CreateHelpScreen(),
      ),
      GoRoute(
        path: '/my-listings',
        builder: (context, state) => const MyListingsScreen(),
      ),
      GoRoute(
        path: '/favorites',
        builder: (context, state) => const FavoritesScreen(),
      ),
      GoRoute(
        path: AppRoutes.placeOfferPath,
        builder: (context, state) =>
            PlaceOfferScreen(listingId: state.pathParameters['listingId']!),
      ),
      GoRoute(
        path: '/listings/:id',
        builder: (context, state) =>
            ListingScreen(id: state.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'interactions/:interactionId',
            builder: (context, state) => InteractionTimelineScreen(
              listingId: state.pathParameters['id']!,
              interactionId: state.pathParameters['interactionId']!,
              participantName: state.extra is String
                  ? state.extra! as String
                  : null,
            ),
            routes: [
              GoRoute(
                path: 'meeting',
                builder: (context, state) => MeetingScreen(
                  listingId: state.pathParameters['id']!,
                  interactionId: state.pathParameters['interactionId']!,
                ),
              ),
              GoRoute(
                path: 'no-meeting',
                builder: (context, state) => NoMeetingScreen(
                  listingId: state.pathParameters['id']!,
                  interactionId: state.pathParameters['interactionId']!,
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomeScreen(),
        routes: [
          GoRoute(
            path: AppRoutes.settings.substring(1),
            builder: (context, state) => const SettingsScreen(),
            routes: [
              GoRoute(
                path: 'devices',
                builder: (context, state) => const DevicesScreen(),
              ),
              GoRoute(
                path: 'consents',
                builder: (context, state) => const ConsentsScreen(),
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.profile.substring(1),
            builder: (context, state) => const ProfileScreen(),
            routes: [
              GoRoute(
                path: AppRoutes.profileEdit.split('/').last,
                builder: (context, state) => const ProfileFormScreen(),
              ),
              GoRoute(
                path: AppRoutes.profileSkills.split('/').last,
                builder: (context, state) => const SkillsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.profileSetup,
        builder: (context, state) => const ProfileFormScreen(onboarding: true),
      ),
      // Not nested under the form: there is no way back to it.
      GoRoute(
        path: AppRoutes.profileSetupPhoto,
        builder: (context, state) => const ProfilePhotoStepScreen(),
      ),
      GoRoute(
        path: AppRoutes.profileSetupSkills,
        builder: (context, state) => const ProfileSkillsStepScreen(),
      ),
      GoRoute(
        path: AppRoutes.profileEmails,
        builder: (context, state) => const AccountEmailsScreen(),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: AppRoutes.signIn,
        builder: (context, state) => const SignInEmailScreen(),
        routes: [
          GoRoute(
            path: AppRoutes.signInCode.split('/').last,
            builder: (context, state) => const SignInCodeScreen(),
          ),
          GoRoute(
            path: AppRoutes.signInName.split('/').last,
            builder: (context, state) => const SignInNameScreen(),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.updateRequired,
        builder: (context, state) => const UpdateRequiredScreen(),
      ),
    ],
  );
  ref
    ..listen(clientUpdateRequiredProvider, (_, _) => router.refresh())
    ..listen(authStatusProvider, (_, _) => router.refresh())
    // Only whether the profile is filled in matters to the routes; a
    // refresh on every change would undo a pop after saving an edit.
    ..listen(
      myProfileProvider.select((profile) => profile.value?.profileComplete),
      (_, _) => router.refresh(),
    )
    ..onDispose(router.dispose);
  return router;
}

String? _redirect(Ref ref, String location) {
  // Once the server rejects this version, nothing but the update screen
  // is reachable.
  if (ref.read(clientUpdateRequiredProvider) != null) {
    return location == AppRoutes.updateRequired
        ? null
        : AppRoutes.updateRequired;
  }
  final signingIn =
      location == AppRoutes.signIn ||
      location.startsWith('${AppRoutes.signIn}/');
  switch (ref.read(authStatusProvider).value) {
    case AuthenticationStatus.unauthenticated:
      // Signed out, including a session revoked on the server: only the
      // sign-in steps, each after the previous one.
      if (!signingIn) return AppRoutes.signIn;
      final draft = ref.read(signInFlowProvider);
      if (location == AppRoutes.signInCode && draft.email == null ||
          location == AppRoutes.signInName && draft.code == null) {
        return AppRoutes.signIn;
      }
    case AuthenticationStatus.authenticated:
      if (signingIn) return AppRoutes.home;
      // Until the profile is filled in, only the screen that fills it in;
      // once it is, the optional photo and skills steps follow. While the
      // profile loads (or fails to) the user stays where they are.
      final user = ref.read(myProfileProvider).value;
      if (user != null && !user.profileComplete) {
        if (location != AppRoutes.profileSetup) return AppRoutes.profileSetup;
      } else if (location == AppRoutes.profileSetup) {
        return AppRoutes.profileSetupPhoto;
      }
    case AuthenticationStatus.initial || null:
  }
  return null;
}
