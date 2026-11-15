// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'attendance.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The current rotating code of the event: the organiser's self-mark code or
/// the personal code of a participant, depending on [request].
///
/// A new code is requested before the current one expires, so the screen
/// never shows a code that the server would reject as expired. The screen
/// watches this provider only inside the attendance window and only in the
/// matching mode; the server refuses a code of the other mode.

@ProviderFor(attendanceCode)
final attendanceCodeProvider = AttendanceCodeFamily._();

/// The current rotating code of the event: the organiser's self-mark code or
/// the personal code of a participant, depending on [request].
///
/// A new code is requested before the current one expires, so the screen
/// never shows a code that the server would reject as expired. The screen
/// watches this provider only inside the attendance window and only in the
/// matching mode; the server refuses a code of the other mode.

final class AttendanceCodeProvider
    extends
        $FunctionalProvider<
          AsyncValue<AttendanceCodeState>,
          AttendanceCodeState,
          FutureOr<AttendanceCodeState>
        >
    with
        $FutureModifier<AttendanceCodeState>,
        $FutureProvider<AttendanceCodeState> {
  /// The current rotating code of the event: the organiser's self-mark code or
  /// the personal code of a participant, depending on [request].
  ///
  /// A new code is requested before the current one expires, so the screen
  /// never shows a code that the server would reject as expired. The screen
  /// watches this provider only inside the attendance window and only in the
  /// matching mode; the server refuses a code of the other mode.
  AttendanceCodeProvider._({
    required AttendanceCodeFamily super.from,
    required (String, bool) super.argument,
  }) : super(
         retry: attendanceRetry,
         name: r'attendanceCodeProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$attendanceCodeHash();

  @override
  String toString() {
    return r'attendanceCodeProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<AttendanceCodeState> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AttendanceCodeState> create(Ref ref) {
    final argument = this.argument as (String, bool);
    return attendanceCode(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AttendanceCodeProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$attendanceCodeHash() => r'e54e34deecfb70adc6fba677ff600de947ce6bb6';

/// The current rotating code of the event: the organiser's self-mark code or
/// the personal code of a participant, depending on [request].
///
/// A new code is requested before the current one expires, so the screen
/// never shows a code that the server would reject as expired. The screen
/// watches this provider only inside the attendance window and only in the
/// matching mode; the server refuses a code of the other mode.

final class AttendanceCodeFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<AttendanceCodeState>,
          (String, bool)
        > {
  AttendanceCodeFamily._()
    : super(
        retry: attendanceRetry,
        name: r'attendanceCodeProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The current rotating code of the event: the organiser's self-mark code or
  /// the personal code of a participant, depending on [request].
  ///
  /// A new code is requested before the current one expires, so the screen
  /// never shows a code that the server would reject as expired. The screen
  /// watches this provider only inside the attendance window and only in the
  /// matching mode; the server refuses a code of the other mode.

  AttendanceCodeProvider call((String, bool) request) =>
      AttendanceCodeProvider._(argument: request, from: this);

  @override
  String toString() => r'attendanceCodeProvider';
}

/// The organiser's view of the marks: the chosen mode, every mark of the
/// event and the live updates of the list.
///
/// The list endpoint is the authoritative state: a realtime publication and
/// the reload of a reconnected channel only wake [sync] up, which loads the
/// whole list again, so a missed publication never loses or duplicates a
/// mark.

@ProviderFor(OrganizerAttendance)
final organizerAttendanceProvider = OrganizerAttendanceFamily._();

/// The organiser's view of the marks: the chosen mode, every mark of the
/// event and the live updates of the list.
///
/// The list endpoint is the authoritative state: a realtime publication and
/// the reload of a reconnected channel only wake [sync] up, which loads the
/// whole list again, so a missed publication never loses or duplicates a
/// mark.
final class OrganizerAttendanceProvider
    extends $AsyncNotifierProvider<OrganizerAttendance, AttendanceListOutput> {
  /// The organiser's view of the marks: the chosen mode, every mark of the
  /// event and the live updates of the list.
  ///
  /// The list endpoint is the authoritative state: a realtime publication and
  /// the reload of a reconnected channel only wake [sync] up, which loads the
  /// whole list again, so a missed publication never loses or duplicates a
  /// mark.
  OrganizerAttendanceProvider._({
    required OrganizerAttendanceFamily super.from,
    required String super.argument,
  }) : super(
         retry: attendanceRetry,
         name: r'organizerAttendanceProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$organizerAttendanceHash();

  @override
  String toString() {
    return r'organizerAttendanceProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  OrganizerAttendance create() => OrganizerAttendance();

  @override
  bool operator ==(Object other) {
    return other is OrganizerAttendanceProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$organizerAttendanceHash() =>
    r'c84eb3265f0ba22afac094688c71a6a7ccf2efe7';

/// The organiser's view of the marks: the chosen mode, every mark of the
/// event and the live updates of the list.
///
/// The list endpoint is the authoritative state: a realtime publication and
/// the reload of a reconnected channel only wake [sync] up, which loads the
/// whole list again, so a missed publication never loses or duplicates a
/// mark.

final class OrganizerAttendanceFamily extends $Family
    with
        $ClassFamilyOverride<
          OrganizerAttendance,
          AsyncValue<AttendanceListOutput>,
          AttendanceListOutput,
          FutureOr<AttendanceListOutput>,
          String
        > {
  OrganizerAttendanceFamily._()
    : super(
        retry: attendanceRetry,
        name: r'organizerAttendanceProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The organiser's view of the marks: the chosen mode, every mark of the
  /// event and the live updates of the list.
  ///
  /// The list endpoint is the authoritative state: a realtime publication and
  /// the reload of a reconnected channel only wake [sync] up, which loads the
  /// whole list again, so a missed publication never loses or duplicates a
  /// mark.

  OrganizerAttendanceProvider call(String listingId) =>
      OrganizerAttendanceProvider._(argument: listingId, from: this);

  @override
  String toString() => r'organizerAttendanceProvider';
}

/// The organiser's view of the marks: the chosen mode, every mark of the
/// event and the live updates of the list.
///
/// The list endpoint is the authoritative state: a realtime publication and
/// the reload of a reconnected channel only wake [sync] up, which loads the
/// whole list again, so a missed publication never loses or duplicates a
/// mark.

abstract class _$OrganizerAttendance
    extends $AsyncNotifier<AttendanceListOutput> {
  late final _$args = ref.$arg as String;
  String get listingId => _$args;

  FutureOr<AttendanceListOutput> build(String listingId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<AttendanceListOutput>, AttendanceListOutput>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<AttendanceListOutput>,
                AttendanceListOutput
              >,
              AsyncValue<AttendanceListOutput>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
