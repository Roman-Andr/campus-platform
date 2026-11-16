# Components and isolated catalog (#380)

From `app/`:

```sh
flutter pub get
flutter run -d chrome -t catalog/main.dart
# Or: flutter build web -t catalog/main.dart
flutter test test/core/design_system test/features/settings test/l10n
flutter analyze --no-pub
```

Widgetbook is a pinned **dev dependency**. Its shell uses legacy Material;
`CatalogPreview` supplies a material_ui MaterialApp, production ThemeData,
localizations and configurable MediaQuery. No app bootstrap, providers,
backend, authentication, production data or cloud account is involved.
Preview width is capped to the actual available container. Tool labels are
English; fixture content follows RU/EN. For broad previews enlarge the browser
window (the sidebar consumes some space).

Select palette, light/dark/system, RU/EN, 320/390/720/1100 width, 1/1.5/2/3
text scale and reduced motion. Actions show normal/busy/disabled/long text;
use real Tab, Enter and pointer to inspect focus/pressed/hover. Fields show
focus/validation/disabled, functional search/segmented/chip states. Sheets
and dialogs retain native keyboard, scrim, focus and Back behavior. Feedback
shows all semantic tones, retained content/retry and initial empty/error/load.

Use native FilledButton/OutlinedButton/TextButton/TextField/SearchBar/
SegmentedButton/FilterChip/IconButton and native dialogs; the theme handles
geometry, focus and semantic roles. Only repeated composition/behavior is
wrapped: `BusyAction`, `InlineNotice`, `StatePanel`, `SectionHeading`,
`CampusAvatar`, `BottomActions`, `showCampusSheet`. Import the barrel at
`core/design_system/components/components.dart`. Labels and image providers
are supplied by the caller, callbacks never load data inside shared UI.
BusyAction blocks repeated activation; callers display actual request state.

To add a fixture: add a WidgetbookUseCase in `catalog/stories.dart`, use
StoryPage and synthetic data. Add fixtures for relevant failure/redaction/
long-text/offline/unknown states, not only the happy path. Feature patterns
will have feature-owned view data in #381. Shipping strings stay in ARB RU/EN.

Goldens: bundled Manrope, Linux, Flutter 3.50.0, 390×780, lavender light/dark,
no network or active indeterminate progress. Baselines are local PNGs under
`test/core/design_system/goldens`; review them visually before accepting.
`flutter test --update-goldens test/core/design_system/controls_golden_test.dart`
is only for deliberate changes. Behavior tests cover duplicate submission,
narrow/large text, accessible targets/labels, keyboard, native Back and offline
catalog startup. Numerical scheme coverage remains in #379. These checks do
not claim physical-device TalkBack or final visual design approval.
