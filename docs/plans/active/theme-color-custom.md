# Custom theme color via the shared AppColorPicker

Status: implemented, device-verified (PuraX). Follow-up to the theme-color picker.

## What

A "自定义/Custom" entry lets the user pick ANY accent color (not just the presets), reusing NextE's existing
`AppColorPicker` (HSV grid + sliders + favorites + hex). The custom color is a `#RRGGBB` stored as the theme
color and persisted like a preset.

## How

- `ThemeColorSettings`: a custom color is just a valid `#RRGGBB` hex. `isHex`/`isCustom` detect it;
  `normalize`/`colorValue`/`label` pass a hex through (label → "自定义"); `customSeed` seeds the picker from
  the current selection (preset → its hex, system → a default blue).
- `LayoutSettingsPage`: a `自定义` row (its own GroupedListSection card, below the dark-mode/theme-color/
  language card) opens the AppColorPicker in a `bindSheet`/`AppModalScaffold`. The picker's `colorChange`
  previews live (`ThemeColorSettings.apply`, no persist); the sheet's ✓ persists (`setColor`), its ✗ reverts
  to the pre-open color. The row's trailing shows the live custom swatch when a custom color is active.
- New i18n key `theme_color_custom` (自定义/Custom/カスタム), 4 locales.

## Files

`shared/.../settings/ThemeColorSettings.ets`, `feature/settings/.../pages/LayoutSettingsPage.ets`,
`entry/.../resources/{base,en_US,zh_CN,ja_JP}/element/string.json`.

## Verified (PuraX)

The 自定义 row opens the AppColorPicker sheet (seeded from the current accent); picking a grid color previews
the accent live (hex updates, e.g. #00FF15); ✓ persists it and 主题色 then shows "自定义" + the custom swatch.

## Note

The earlier "row won't render" dead-end was a deploy artifact: the install step matched a STALE
`*signed*.hap` (the glob also matches `un*signed*`) and `install -r` didn't redeploy — an uninstall + fresh
install of the freshly-built hap fixed it. The code was correct throughout.
