# Tokens and appearance (#379)

Import `core/design_system/foundations/tokens.dart` for spacing, geometry and
motion names. Use Material TextTheme/ColorScheme semantic roles. Status
surfaces use `CampusColors.of(context)` with their paired foregrounds; never
use palette accents to mean success/error/warning. Each palette has deliberate
brand, surface and container roles over generated complementary tonal roles.
Contrast tests cover eight schemes, status pairs, outline and focused input.

Theme entry point: `CampusTheme.build(PaletteId, Brightness)`. Existing
`AppTheme` delegates to it. ThemeExtension supports copyWith/lerp. Standard
Material states/targets remain native. Manrope 400/500/600/700 is packaged
with Latin/Cyrillic and its OFL; Material Icons stay bundled by Flutter.

Storage: `settings.palette_id` stores stable enum names in existing Drift
Preferences; no schema migration. Missing/unknown ID → lavender. Language,
ThemeMode and unrelated keys survive saves. ThemeMode.system follows device
brightness independently of palette. Settings exposes RU/EN palette choices.

Checks (from app): `flutter analyze --no-pub`,
`flutter test test/core/design_system/theme_test.dart test/features/settings test/app_test.dart test/l10n`.
These tests do not claim manual TalkBack, physical-device profiling or final
visual approval of #376. Controls/catalog/goldens follow in #380.
