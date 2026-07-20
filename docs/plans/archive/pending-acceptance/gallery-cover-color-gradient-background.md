# Gallery cover color-gradient / blur background (off-aspect covers)

Status: implemented, pending device acceptance. Parallel lane to the reader work (no file overlap).

## Problem

Gallery list/grid/waterfall covers whose source ratio does not match the card cover slot were letterboxed
(Contain) into a **transparent** gap (the card surface showed through), reading as empty padding. eros_fe
fills that gap; NextE did not.

## Decision (user-driven)

- **Fit threshold** (eros_fe `gallery_item.dart` `_fit`): covers whose ratio is *close* to the slot fill it
  (`Cover`, light crop); *far* ratios letterbox (`Contain`) so the whole cover shows and the gap is filled.
- **Gap fill**, two tiers, controlled by a new setting `blurringOfCoverBackground` (default **off**):
  - **off (default)** → vertical gradient from the cover's **extracted dominant color**, fading to
    transparent (blends into the card). Cheap: one-time cacheable color extraction + a GPU gradient fill.
  - **on** → a blurred `Cover` copy of the same cover image (heavier real-time `.blur()`, opt-in).
- Color source is **image extraction only** (no category-color fallback).
- Scope: **list card + grid + waterfall** only. Detail header / preview grids are untouched (opt-in param).

## Why gradient as default

`.blur()` is a real-time per-frame interface; in a recycling list every new cover re-decodes + re-blurs a
second full image and holds an extra texture. A `linearGradient` is a GPU background fill (~free per frame).
The cost moves to a **one-time** dominant-color extraction, cached by URL for the process lifetime.

## Implementation

New:
- `shared/.../state/CoverBackgroundState.ets` — `@ObservedV2 @Trace blurringOfCoverBackground` + `connectCoverBackground()`.
- `shared/.../settings/CoverBackgroundSettings.ets` — restore/set (mirrors `ThumbnailModeSettings`).
- `shared/.../services/CoverColorService.ets` — `@Concurrent extractCoverColor(url)` on TaskPool
  (http GET thumb bytes → `image.createImageSource(buf)` → `createPixelMap({desiredSize:32x32})` →
  `effectKit.createColorPicker` → `getMainColorSync` → packed `0xAARRGGBB` via `>>>0`; releases
  PixelMap/ImageSource). `CoverColorService` singleton: in-memory cache + in-flight dedup; `resolve()`
  returns 0 on failure (no gradient).

Edited:
- `StorageKeys` (`BLURRING_OF_COVER_BACKGROUND`), `SettingsBootstrap` (restore), `shared/Index` (exports),
  `ThemeConstants` (`COVER_BG_BLUR_RADIUS = 16`).
- `EhThumbnail` — `@Param letterboxBackground` (opt-in), `@Local coverBgColor`/`coverBgState`, color
  resolution on `aboutToAppear`/`@Monitor('url')`/`@Monitor('coverBgState.blurringOfCoverBackground')`,
  `coverBackgroundLayer()` @Builder (blur vs gradient) inserted as the bottom child of the list-contain and
  grid-contain Stacks (gated so it only paints on the Contain path).
- `GalleryCard` — `coverFillsSlot()` ratio band; `containFit: !this.coverFillsSlot()` + `letterboxBackground: true`.
- `GalleryWaterfallCard`, `GalleryGridCard` — `letterboxBackground: true`.
- `LayoutSettingsPage` — toggle row; i18n `settings_blurring_of_cover_background[_hint]` (base/zh_CN/en_US/ja_JP).

## Contract impact

- `test_cover_presentation_contract.mjs` — unchanged, still green (the Contain transparent-slot + real-aspect
  structure is preserved; the gap fill is an added bottom layer).
- `test_list_responsive_cover_contract.mjs` — line 87 rewritten: `containFit: true` → assert `coverFillsSlot()`
  + `containFit: !this.coverFillsSlot()` + `letterboxBackground: true`. The Contain regression guard remains
  (the far case still letterboxes).

## Gates (all green)

`test_v1_decorator_inventory_contract.mjs` (0 files), `test_version_consistency_contract.mjs`,
`check_i18n_duplicates.py`, both cover contracts. Formatted with oxk.

## Follow-ups / known gaps

- Color cache is **in-memory only** (re-extracts on cold start). Persisting the hex by gid is a trivial
  optimization for true once-ever extraction.
- Gradient bottom fades to *transparent*: on the grid Stack (which keeps `COVER_PLACEHOLDER` grey as the
  loading base) the bottom of a Contain gap shows grey rather than the card surface; the list slot is
  transparent so it blends perfectly. Acceptable; revisit if the grid looks off on device.
- Extraction does a **second** small thumb fetch (the ArkUI `Image` fetch is not reusable as a PixelMap). A
  PixelMap-based thumbnail load would unify decode but is a larger refactor of the hot cover path.
- Device acceptance pending: verify on real off-aspect covers (very wide / very tall) in fixed + adaptive
  list modes, grid, and waterfall, light + dark, gradient + blur.
