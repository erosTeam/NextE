# Theme-color polish: drop redundant blue, show current swatch, make accent UI follow the theme

Status: implemented, device-verified (PuraX). Follow-up to the theme-color picker.

## A. Drop the redundant "blue" preset

`默认/Default` (system) already resolves to the platform brand blue, so the separate `蓝色/Blue` (#0958F7)
preset was a visual duplicate. Removed it from ThemeColorSettings (palette is now system + orange/red/
purple/pink/green). (The `theme_color_blue` i18n key is left in place, unused, to keep locale parity.)

## B. Show the current accent as a swatch on the 主题色 row

The row only showed a text label; the current color wasn't visible. The 主题色 ConciseListRow now uses
`suffixBuilderParam` to render a color dot (`Circle().fill(ThemeColorSettings.currentColor())`) + the label
+ a dropdown chevron — V2Next's SettingsThemeColorDropdownRow. `currentColor()` reads the @Trace, so the
swatch tracks the live color.

## D. Make accent UI follow the theme (12 fixes)

Audit found controls that showed the brand/accent but did NOT route through `ThemeConstants.BRAND_PRIMARY`
(so they stayed system-blue when the theme changed). Fixed:
- Read FAB capsule button (GalleryDetailPage): capsule buttons default to the SYSTEM brand; added
  `.backgroundColor(ThemeConstants.BRAND_PRIMARY)`. ← the headline; now follows the theme.
- Reader progress Slider (ReaderPage): added `.selectedColor` + `.blockColor` BRAND_PRIMARY.
- Comment vote color (GalleryCommentsCard) + reply-quote bar (GalleryCommentsPage): `$r('sys.color.
  font_emphasize')` → BRAND_PRIMARY.
- 8 `LoadingProgress()` spinners (GalleryDetailPage, GalleryTorrentsPage, GalleryEditTagsPage,
  GalleryArchiverPage ×2, ImagePageRouteErrorPage, EhLoginWebPage, GalleryWebPage): added
  `.color(ThemeConstants.BRAND_PRIMARY)` (they default to the system brand).

## Known remaining (deliberately left, pending a call)

Prominent blue LINK text — 相似/评分/下载, 查看全部, comment author/links — uses `$r('sys.color.
font_emphasize')` (the system emphasis/link color, semantically distinct from the brand accent). Left as-is;
switching these to BRAND_PRIMARY is a broader sweep to confirm with the user.

## Verified (PuraX)

主题色 row shows the live color swatch; the menu no longer lists blue; picking Red turns the toggles AND the
Read FAB red app-wide.
