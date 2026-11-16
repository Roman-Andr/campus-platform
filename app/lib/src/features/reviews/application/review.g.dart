// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'review.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(reviewConfig)
final reviewConfigProvider = ReviewConfigProvider._();

final class ReviewConfigProvider
    extends $FunctionalProvider<ReviewConfig, ReviewConfig, ReviewConfig>
    with $Provider<ReviewConfig> {
  ReviewConfigProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'reviewConfigProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$reviewConfigHash();

  @$internal
  @override
  $ProviderElement<ReviewConfig> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ReviewConfig create(Ref ref) {
    return reviewConfig(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ReviewConfig value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ReviewConfig>(value),
    );
  }
}

String _$reviewConfigHash() => r'569dd5735537b5d7b845aca651ab0b69f977e4b6';

/// The review state of one interaction.
///
/// The state always comes from the server: the screen reloads it after every
/// attempt, including a refused one, so a review written on another device,
/// a reveal that already happened and a closed window are never hidden behind
/// a stale response. A realtime publication only wakes [sync] up, which loads
/// the whole state again; the payload never carries a rating or a text.

@ProviderFor(InteractionReview)
final interactionReviewProvider = InteractionReviewFamily._();

/// The review state of one interaction.
///
/// The state always comes from the server: the screen reloads it after every
/// attempt, including a refused one, so a review written on another device,
/// a reveal that already happened and a closed window are never hidden behind
/// a stale response. A realtime publication only wakes [sync] up, which loads
/// the whole state again; the payload never carries a rating or a text.
final class InteractionReviewProvider
    extends $AsyncNotifierProvider<InteractionReview, ReviewStateOutput> {
  /// The review state of one interaction.
  ///
  /// The state always comes from the server: the screen reloads it after every
  /// attempt, including a refused one, so a review written on another device,
  /// a reveal that already happened and a closed window are never hidden behind
  /// a stale response. A realtime publication only wakes [sync] up, which loads
  /// the whole state again; the payload never carries a rating or a text.
  InteractionReviewProvider._({
    required InteractionReviewFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: listingRetry,
         name: r'interactionReviewProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$interactionReviewHash();

  @override
  String toString() {
    return r'interactionReviewProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  InteractionReview create() => InteractionReview();

  @override
  bool operator ==(Object other) {
    return other is InteractionReviewProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$interactionReviewHash() => r'1ddc8a13551472a668527705ffdc182cd8142e2f';

/// The review state of one interaction.
///
/// The state always comes from the server: the screen reloads it after every
/// attempt, including a refused one, so a review written on another device,
/// a reveal that already happened and a closed window are never hidden behind
/// a stale response. A realtime publication only wakes [sync] up, which loads
/// the whole state again; the payload never carries a rating or a text.

final class InteractionReviewFamily extends $Family
    with
        $ClassFamilyOverride<
          InteractionReview,
          AsyncValue<ReviewStateOutput>,
          ReviewStateOutput,
          FutureOr<ReviewStateOutput>,
          (String, String)
        > {
  InteractionReviewFamily._()
    : super(
        retry: listingRetry,
        name: r'interactionReviewProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The review state of one interaction.
  ///
  /// The state always comes from the server: the screen reloads it after every
  /// attempt, including a refused one, so a review written on another device,
  /// a reveal that already happened and a closed window are never hidden behind
  /// a stale response. A realtime publication only wakes [sync] up, which loads
  /// the whole state again; the payload never carries a rating or a text.

  InteractionReviewProvider call((String, String) ids) =>
      InteractionReviewProvider._(argument: ids, from: this);

  @override
  String toString() => r'interactionReviewProvider';
}

/// The review state of one interaction.
///
/// The state always comes from the server: the screen reloads it after every
/// attempt, including a refused one, so a review written on another device,
/// a reveal that already happened and a closed window are never hidden behind
/// a stale response. A realtime publication only wakes [sync] up, which loads
/// the whole state again; the payload never carries a rating or a text.

abstract class _$InteractionReview extends $AsyncNotifier<ReviewStateOutput> {
  late final _$args = ref.$arg as (String, String);
  (String, String) get ids => _$args;

  FutureOr<ReviewStateOutput> build((String, String) ids);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<ReviewStateOutput>, ReviewStateOutput>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<ReviewStateOutput>, ReviewStateOutput>,
              AsyncValue<ReviewStateOutput>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// The public reviews about a user: revealed and not hidden ones only.
///
/// The list is paginated by the server cursor. A realtime publication about a
/// review or its answer reloads the first page, so a reply written on another
/// device and a reveal that has just happened show up without a restart; the
/// loaded extra pages are dropped, because a new review shifts them.

@ProviderFor(UserReviews)
final userReviewsProvider = UserReviewsFamily._();

/// The public reviews about a user: revealed and not hidden ones only.
///
/// The list is paginated by the server cursor. A realtime publication about a
/// review or its answer reloads the first page, so a reply written on another
/// device and a reveal that has just happened show up without a restart; the
/// loaded extra pages are dropped, because a new review shifts them.
final class UserReviewsProvider
    extends $AsyncNotifierProvider<UserReviews, ReviewPage> {
  /// The public reviews about a user: revealed and not hidden ones only.
  ///
  /// The list is paginated by the server cursor. A realtime publication about a
  /// review or its answer reloads the first page, so a reply written on another
  /// device and a reveal that has just happened show up without a restart; the
  /// loaded extra pages are dropped, because a new review shifts them.
  UserReviewsProvider._({
    required UserReviewsFamily super.from,
    required String super.argument,
  }) : super(
         retry: listingRetry,
         name: r'userReviewsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$userReviewsHash();

  @override
  String toString() {
    return r'userReviewsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  UserReviews create() => UserReviews();

  @override
  bool operator ==(Object other) {
    return other is UserReviewsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$userReviewsHash() => r'31461d8f32850680a0f3535edf3b3c5e4cdc9391';

/// The public reviews about a user: revealed and not hidden ones only.
///
/// The list is paginated by the server cursor. A realtime publication about a
/// review or its answer reloads the first page, so a reply written on another
/// device and a reveal that has just happened show up without a restart; the
/// loaded extra pages are dropped, because a new review shifts them.

final class UserReviewsFamily extends $Family
    with
        $ClassFamilyOverride<
          UserReviews,
          AsyncValue<ReviewPage>,
          ReviewPage,
          FutureOr<ReviewPage>,
          String
        > {
  UserReviewsFamily._()
    : super(
        retry: listingRetry,
        name: r'userReviewsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The public reviews about a user: revealed and not hidden ones only.
  ///
  /// The list is paginated by the server cursor. A realtime publication about a
  /// review or its answer reloads the first page, so a reply written on another
  /// device and a reveal that has just happened show up without a restart; the
  /// loaded extra pages are dropped, because a new review shifts them.

  UserReviewsProvider call(String userId) =>
      UserReviewsProvider._(argument: userId, from: this);

  @override
  String toString() => r'userReviewsProvider';
}

/// The public reviews about a user: revealed and not hidden ones only.
///
/// The list is paginated by the server cursor. A realtime publication about a
/// review or its answer reloads the first page, so a reply written on another
/// device and a reveal that has just happened show up without a restart; the
/// loaded extra pages are dropped, because a new review shifts them.

abstract class _$UserReviews extends $AsyncNotifier<ReviewPage> {
  late final _$args = ref.$arg as String;
  String get userId => _$args;

  FutureOr<ReviewPage> build(String userId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<ReviewPage>, ReviewPage>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<ReviewPage>, ReviewPage>,
              AsyncValue<ReviewPage>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
