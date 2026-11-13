import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/home/presentation/home_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';

part 'app_router.g.dart';

/// Route locations of the app.
abstract final class AppRoutes {
  static const home = '/';
  static const settings = '/settings';
}

@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  final router = GoRouter(
    initialLocation: AppRoutes.home,
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
    ],
  );
  ref.onDispose(router.dispose);
  return router;
}
