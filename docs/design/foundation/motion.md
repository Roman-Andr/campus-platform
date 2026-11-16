# Motion contract (#382)

Use `CampusMotion` in foundations/tokens.dart. Feedback: 120 ms; local content:
180 ms; modal entry: 260 ms; modal exit: 180 ms; theme: 200 ms. Selection uses
easeOutCubic; animations 3.0.0 supplies the maintained fade-through curve.
Native route transitions retain platform duration/curve and interactive Back;
never replace every go_router page with a custom fade/scale route.

`CampusContentSwitch(stateKey, child)` changes local content, with outgoing
content excluded from taps and semantics. Use only when the semantic state
changes; keep forms with ongoing edits mounted rather than replacing them.
`CampusSelectionFeedback` animates surface/border selection without movement.
`showCampusSheet`/`showCampusDialog` retain native scrim/focus/Back/keyboard and
use the central policy. Standard button ripples remain native.

Both MediaQuery.disableAnimations (Android) and MediaQuery.reduceMotion (iOS)
render final custom content immediately, suppress modal/theme durations and
replace the busy action spinner with a static hourglass. The catalog overrides
both flags for custom previews; actual platform flags also govern framework
AnimationController behavior. No decorative repeating animation is added.

`CampusMotionVisibility` uses TickerMode plus AppLifecycleListener. Place it
around retained inactive branches and the app content; parent TickerMode is
respected by Flutter. The listener is disposed. PageTransitionSwitcher owns
and disposes its controllers; implicit feedback has no manually owned ticker.
Rapid replacement/disposal and actual lifecycle transitions are tested.

Application state is applied as soon as the controller emits it. Never await
an animation to submit a command, complete an API future, display an error or
claim success. Animation completion is not a business event. Gesture Back,
keyboard dismissal, route pop and async mounted checks retain native behavior.

Catalog: Motion / Content feedback and modals. Compare normal/reduced motion
using the same controls, including content, selection, sheet and dialog.
Tests: `flutter test test/core/design_system/motion_test.dart` and the design
system/l10n/app suites. Widget tests prove final state and lifecycle, not FPS.

## Reproducible profile

`benchmark/motion_profile.dart` runs 16 local-content changes, 16 sheet
open/close cycles and 16 dialog cycles in each mode, after a 2-second warmup.
It uses the actual shared primitives and bundles no backend/auth/durable data.
FrameTiming reports build/raster p95 and counts above a 60 Hz (16.67 ms)
reference budget. No performance pass/fail threshold is inferred on emulators.

```sh
cd app
flutter build apk --profile --target-platform android-x64 \
  -t benchmark/motion_profile.dart
adb -s emulator-5580 install -r build/app/outputs/flutter-apk/app-profile.apk
adb -s emulator-5580 shell am start -n \
  io.github.romanandr.campus/.MainActivity
adb -s emulator-5580 logcat -v raw -s flutter:I
# Save the single MOTION_PROFILE_JSON line after the finite run.
```

Use android-arm64 for real arm64 hardware if available. The user explicitly
confirmed physical Android hardware is unavailable. Emulator results, device
conditions and limitations are recorded separately in motion-profile.md;
they cannot establish production phone performance. Source guidance:
[Flutter performance profiling](https://docs.flutter.dev/perf/ui-performance),
[disableAnimations](https://api.flutter.dev/flutter/widgets/MediaQueryData/disableAnimations.html).
