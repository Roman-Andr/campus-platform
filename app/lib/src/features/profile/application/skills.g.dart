// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'skills.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Skills of the signed-in user's profile: "can" and "wants to learn",
/// tags of the common reference (ТЗ п. 5.1.1, модуль 2, п. 1).

@ProviderFor(MySkills)
final mySkillsProvider = MySkillsProvider._();

/// Skills of the signed-in user's profile: "can" and "wants to learn",
/// tags of the common reference (ТЗ п. 5.1.1, модуль 2, п. 1).
final class MySkillsProvider
    extends $AsyncNotifierProvider<MySkills, SkillsOutput?> {
  /// Skills of the signed-in user's profile: "can" and "wants to learn",
  /// tags of the common reference (ТЗ п. 5.1.1, модуль 2, п. 1).
  MySkillsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mySkillsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mySkillsHash();

  @$internal
  @override
  MySkills create() => MySkills();
}

String _$mySkillsHash() => r'82dbdce0db1f22f0f8c53eda9fa003357db47283';

/// Skills of the signed-in user's profile: "can" and "wants to learn",
/// tags of the common reference (ТЗ п. 5.1.1, модуль 2, п. 1).

abstract class _$MySkills extends $AsyncNotifier<SkillsOutput?> {
  FutureOr<SkillsOutput?> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<SkillsOutput?>, SkillsOutput?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<SkillsOutput?>, SkillsOutput?>,
              AsyncValue<SkillsOutput?>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Skill tags whose name in the interface language starts with [query].

@ProviderFor(skillTagSearch)
final skillTagSearchProvider = SkillTagSearchFamily._();

/// Skill tags whose name in the interface language starts with [query].

final class SkillTagSearchProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<SkillTagOutput>>,
          List<SkillTagOutput>,
          FutureOr<List<SkillTagOutput>>
        >
    with
        $FutureModifier<List<SkillTagOutput>>,
        $FutureProvider<List<SkillTagOutput>> {
  /// Skill tags whose name in the interface language starts with [query].
  SkillTagSearchProvider._({
    required SkillTagSearchFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'skillTagSearchProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$skillTagSearchHash();

  @override
  String toString() {
    return r'skillTagSearchProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<SkillTagOutput>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<SkillTagOutput>> create(Ref ref) {
    final argument = this.argument as String;
    return skillTagSearch(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is SkillTagSearchProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$skillTagSearchHash() => r'd1bc3c4c44b385ddf116c1b7a7895762e46b6ad8';

/// Skill tags whose name in the interface language starts with [query].

final class SkillTagSearchFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<SkillTagOutput>>, String> {
  SkillTagSearchFamily._()
    : super(
        retry: null,
        name: r'skillTagSearchProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Skill tags whose name in the interface language starts with [query].

  SkillTagSearchProvider call(String query) =>
      SkillTagSearchProvider._(argument: query, from: this);

  @override
  String toString() => r'skillTagSearchProvider';
}
