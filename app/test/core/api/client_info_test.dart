import 'package:campus/src/core/api/client_info.dart';
import 'package:campus/src/core/api/generated/campus_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('reports the platform of the build', () {
    final expected = {
      TargetPlatform.android: ClientPlatformValue.android,
      TargetPlatform.linux: ClientPlatformValue.desktop,
      TargetPlatform.macOS: ClientPlatformValue.desktop,
      TargetPlatform.windows: ClientPlatformValue.desktop,
    };
    for (final MapEntry(key: target, value: platform) in expected.entries) {
      debugDefaultTargetPlatformOverride = target;
      expect(ClientInfo.currentPlatform(), platform, reason: '$target');
    }
  });

  test('reports the version of the package', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final package = PackageInfo(
      appName: 'Campus',
      packageName: 'io.github.romanandr.campus',
      version: '1.4.0',
      buildNumber: '7',
    );

    expect(
      ClientInfo.current(package),
      const ClientInfo(platform: ClientPlatformValue.android, version: '1.4.0'),
    );
  });

  test('fails on platforms the project does not target', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    expect(ClientInfo.currentPlatform, throwsUnsupportedError);
  });
}
