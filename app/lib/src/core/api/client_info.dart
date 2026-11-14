import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'generated/campus_api.dart';

part 'client_info.g.dart';

/// Platform and version this client reports in every request (ТЗ п. 4.6).
@immutable
class ClientInfo {
  const ClientInfo({required this.platform, required this.version});

  /// Describes the running build; [version] comes from `pubspec.yaml`.
  factory ClientInfo.current(PackageInfo package) =>
      ClientInfo(platform: currentPlatform(), version: package.version);

  final ClientPlatformValue platform;
  final String version;

  /// The client platform of the running build.
  ///
  /// The Telegram Mini App is the web build; it reports itself once its
  /// launch is detected.
  static ClientPlatformValue currentPlatform() {
    if (kIsWeb) return ClientPlatformValue.web;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => ClientPlatformValue.android,
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => ClientPlatformValue.desktop,
      // Not a target of the project (ТЗ п. 5.4).
      TargetPlatform.iOS || TargetPlatform.fuchsia => throw UnsupportedError(
        'Unsupported platform: $defaultTargetPlatform',
      ),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is ClientInfo &&
      other.platform == platform &&
      other.version == version;

  @override
  int get hashCode => Object.hash(platform, version);
}

/// Loaded by `main` before the app starts.
@Riverpod(keepAlive: true)
ClientInfo clientInfo(Ref ref) =>
    throw UnimplementedError('clientInfoProvider must be overridden');
