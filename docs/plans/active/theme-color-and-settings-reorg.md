# Theme-color (accent) picker + settings reorg into one "界面" page

Status: implemented, device-verified (PuraX). Ported the accent picker from V2Next; reorganized the
appearance settings per the user's "don't over-split, one 界面 page" direction.

## 1. Theme color (user-selectable accent)

- `ThemeColorState` (shared/state/AppearanceState): `@Trace color` (preset id). `ThemeColorSettings`
  (shared/settings): palette `system`(=$r('sys.color.brand'), default) + blue/orange/red/purple/pink/green
  (hex from V2Next), `colorValue`/`label`/`normalize`/`currentColor`, persist under `StorageKeys.THEME_COLOR`,
  restore in SettingsBootstrap.
- THE MECHANISM: `ThemeConstants.BRAND_PRIMARY` changed from a `static readonly` to a
  `static get BRAND_PRIMARY()` returning `ThemeColorSettings.currentColor()` → `connectThemeColor().color`
  (@Trace). So every component already reading `ThemeConstants.BRAND_PRIMARY` recolors when the user picks a
  color — ZERO call-site changes across the 11 files that use it (V2Next pattern). Default `system` returns
  the platform brand token, so existing installs look unchanged.
- Verified: picking Red recolors every brand-tinted control (switches, etc.) app-wide instantly; Default
  returns to blue.

## 2. Settings reorg — one "界面" (Interface) page

Per the user, no separate Appearance page (would overlap Layout). Instead:
- Renamed the "布局/Layout" row + page → "界面/Interface" (via the `settings_layout` i18n value; key kept).
- Moved 深色模式 + 主题色 + 语言 to the TOP of that page (LayoutSettingsPage), above the existing layout
  controls (view mode, cover background, japanese title, thumbnails, auto-hide, smart-grip, tag translation).
- Removed the loose appearance rows + their menus/handlers from the settings root (SettingsPage).
- Renamed "主题/Theme" → "深色模式/Dark mode" to free the name for "主题色/Theme color".

## 3. Theme-color picker UI

The 主题色 row opens a `bindMenu` popup built as a Column of tappable Rows (a custom MenuItem builder
swallows the click), each a color dot (`Circle().fill(option.color)`) + name + a checkmark on the active one.

## Files

New: `shared/.../settings/ThemeColorSettings.ets`.
Edited: `shared/.../state/AppearanceState.ets`, `shared/.../theme/ThemeConstants.ets`,
`shared/.../constants/StorageKeys.ets`, `shared/.../settings/SettingsBootstrap.ets`, `shared/.../Index.ets`,
`feature/settings/.../pages/LayoutSettingsPage.ets`, `feature/settings/.../pages/SettingsPage.ets`,
`entry/.../resources/{base,en_US,zh_CN,ja_JP}/element/string.json` (8 new keys: settings_theme_color +
theme_color_system/blue/orange/red/purple/pink/green; renamed settings_layout→界面, settings_theme→深色模式).
