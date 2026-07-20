# Manual dark-mode toggle + language switch + sub-tab theme-reactivity fix

Status: implemented; dark-mode + language device-verified (PuraX). Ported from V2Next ThemeSettings /
LanguageSettings / FeedPills theme-tracking.

## 1. Manual dark mode (system / light / dark)

- `ThemeDisplayState` (shared/state/AppearanceState): `@Trace mode` + `@Trace effectiveDark`.
- `ThemeSettings` (shared/settings): `apply` calls `context.getApplicationContext().setColorMode(DARK/LIGHT/
  NOT_SET)` and refreshes `effectiveDark`; persists under `StorageKeys.THEME_MODE`; `restore` on boot;
  `onSystemColorModeChanged` refreshes `effectiveDark` in follow-system mode.
- Applied at startup in `SettingsBootstrap.loadAll` (before first paint). A new `EnvironmentCallback` in
  `EntryAbility.onCreate` forwards system colorMode flips to `ThemeSettings.onSystemColorModeChanged`.
- UI: an Appearance section in SettingsPage — a Theme row + dropdown menu (跟随系统/浅色/深色).

## 2. Manual language switch (follow-system / zh-Hans / en-US / ja-JP)

- `LanguageState` (shared/state/AppearanceState): `@Trace mode` + `@Trace effectiveLocale`.
- `LanguageSettings` (shared/settings): `apply` pins the OS preferred language
  (`i18n.System.setAppPreferredLanguage`, so every `$r` re-resolves) AND an `AppStrings` override
  ResourceManager (so shared computed labels re-resolve) — both live, no restart. Persists under
  `StorageKeys.LANGUAGE`; restored in `SettingsBootstrap`.
- `AppStrings.get` now reads the `effectiveLocale` signal (repaints computed labels) and resolves through
  the override ResourceManager.
- UI: a Language row + dropdown menu in the same Appearance section.
- Verified: switching to English flips the ENTIRE UI live, including the cached bottom tab bar; switching
  back to follow-system restores Chinese.

## 3. Sub-tab unselected-text theme-reactivity fix

`SubTabBar` (the source/period/favcat pills) is hosted in a CACHED `ComponentContent`, so on a system
dark/light flip its `$r('sys.color.font_secondary/tertiary')` tokens stayed stale (the cached subtree never
rebuilt). Fix: the bar reads `connectThemeDisplay().effectiveDark` via a `themeTracked()` color helper, so
the EnvironmentCallback's `effectiveDark` update (a `@Trace`) forces the cached subtree to repaint — the
exact V2Next FeedPills pattern. (Manual light/dark verified; the system-flip live path is code-correct but
wasn't reproducible via the emulator's control center — confirm on a real device.)

## Files

New: `shared/.../state/AppearanceState.ets`, `shared/.../settings/ThemeSettings.ets`,
`shared/.../settings/LanguageSettings.ets`.
Edited: `shared/.../i18n/AppStrings.ets`, `shared/.../components/SubTabBar.ets`,
`shared/.../settings/SettingsBootstrap.ets`, `shared/.../Index.ets`,
`entry/.../entryability/EntryAbility.ets`, `feature/settings/.../pages/SettingsPage.ets`,
`entry/.../resources/{base,en_US,zh_CN,ja_JP}/element/string.json` (8 keys).

## Known follow-up (out of scope)

The home front-page source pill label "默认" stays Chinese when the app language is English (Popular/Watched
do localize) — a hardcoded source label, separate from this feature.
