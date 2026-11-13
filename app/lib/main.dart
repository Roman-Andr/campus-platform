import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'src/app.dart';
import 'src/features/settings/application/settings_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer();
  // Load language and theme before the first frame to avoid a flash of
  // default settings; a failure falls back to defaults inside the app.
  await container
      .read(settingsControllerProvider.future)
      .then<void>((_) {}, onError: (Object _) {});
  runApp(
    UncontrolledProviderScope(container: container, child: const CampusApp()),
  );
}
