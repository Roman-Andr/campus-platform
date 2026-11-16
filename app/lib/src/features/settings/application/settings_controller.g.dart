// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Current [AppSettings]; changes are applied immediately and persisted.

@ProviderFor(SettingsController)
final settingsControllerProvider = SettingsControllerProvider._();

/// Current [AppSettings]; changes are applied immediately and persisted.
final class SettingsControllerProvider
    extends $AsyncNotifierProvider<SettingsController, AppSettings> {
  /// Current [AppSettings]; changes are applied immediately and persisted.
  SettingsControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'settingsControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$settingsControllerHash();

  @$internal
  @override
  SettingsController create() => SettingsController();
}

String _$settingsControllerHash() =>
    r'd5fc0cbdff92beb78f8b28ca3f45b3ccd9627e08';

/// Current [AppSettings]; changes are applied immediately and persisted.

abstract class _$SettingsController extends $AsyncNotifier<AppSettings> {
  FutureOr<AppSettings> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<AppSettings>, AppSettings>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<AppSettings>, AppSettings>,
              AsyncValue<AppSettings>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
