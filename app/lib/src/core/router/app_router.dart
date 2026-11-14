import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/auth/application/sign_in_flow.dart';
import '../../features/auth/presentation/sign_in_code_screen.dart';
import '../../features/auth/presentation/sign_in_email_screen.dart';
import '../../features/auth/presentation/sign_in_name_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/update/presentation/update_required_screen.dart';
import '../api/client_update.dart';
import '../auth/auth_session.dart';

part 'app_router.g.dart';

/// Route locations of the app.
abstract final class AppRoutes {
  static const home = '/';
  static const settings = '/settings';
  static const updateRequired = '/update-required';
  static const signIn = '/sign-in';
  static const signInCode = '/sign-in/code';
  static const signInName = '/sign-in/name';
}

@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  final router = GoRouter(
    initialLocation: AppRoutes.home,
    redirect: (context, state) => _redirect(ref, state.matchedLocation),
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomeScreen(),
        routes: [
          GoRoute(
            path: AppRoutes.settings.substring(1),
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
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
    case AuthenticationStatus.initial || null:
  }
  return null;
}
