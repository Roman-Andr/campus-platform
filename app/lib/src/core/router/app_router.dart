import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/home/presentation/home_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/update/presentation/update_required_screen.dart';
import '../api/client_update.dart';

part 'app_router.g.dart';

/// Route locations of the app.
abstract final class AppRoutes {
  static const home = '/';
  static const settings = '/settings';
  static const updateRequired = '/update-required';
}

@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  final router = GoRouter(
    initialLocation: AppRoutes.home,
    // Once the server rejects this version, nothing but the update screen
    // is reachable.
    redirect: (context, state) =>
        ref.read(clientUpdateRequiredProvider) != null &&
            state.matchedLocation != AppRoutes.updateRequired
        ? AppRoutes.updateRequired
        : null,
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
        path: AppRoutes.updateRequired,
        builder: (context, state) => const UpdateRequiredScreen(),
      ),
    ],
  );
  ref
    ..listen(clientUpdateRequiredProvider, (_, _) => router.refresh())
    ..onDispose(router.dispose);
  return router;
}
