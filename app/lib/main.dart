import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'src/app.dart';
import 'src/core/api/client_info.dart';
import 'src/core/auth/auth_session.dart';
import 'src/features/settings/application/settings_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final package = await PackageInfo.fromPlatform();
  final container = ProviderContainer(
    overrides: [
      clientInfoProvider.overrideWithValue(ClientInfo.current(package)),
    ],
  );
  // Load language and theme before the first frame to avoid a flash of
  // default settings; a failure falls back to defaults inside the app.
  await container
      .read(settingsControllerProvider.future)
      .then<void>((_) {}, onError: (Object _) {});
  // Restore the session before the first frame, so the app opens on the
  // right screen: home when signed in, otherwise sign-in.
  await container.read(authStatusProvider.future);
  runApp(
    UncontrolledProviderScope(container: container, child: const CampusApp()),
  );
}
