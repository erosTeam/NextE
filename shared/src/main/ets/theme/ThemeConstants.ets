/**
 * NextE design tokens — the SINGLE source of spacing / font-size / radius / color.
 *
 * Hard rule (mirrors V2Next): components NEVER hardcode pixel sizes, colors, or font
 * sizes. Prefer HarmonyOS system color tokens ($r('sys.color.*')) so light/dark follow
 * the platform automatically; brand-specific values are defined here. EH-domain palettes
 * (category colors, tag-namespace colors, favcat slot colors) live in EhSemanticColors.
 */
export class ThemeConstants {
  // Brand
  static readonly BRAND_PRIMARY: ResourceColor = $r('sys.color.brand')
  static readonly BRAND_ACCENT: ResourceColor = $r('sys.color.font_secondary')
  // Readable text on a saturated/brand-colored surface (selected chips, badges). White both themes.
  static readonly TEXT_ON_BRAND: ResourceColor = $r('app.color.text_on_brand')
  // Fallback heart color when a favorited gallery's favcat slot is unresolved (eros_fe default red).
  static readonly FAV_HEART_DEFAULT: ResourceColor = $r('app.color.fav_heart_default')

  // Text (semantic aliases over system tokens)
  static readonly TEXT_PRIMARY: ResourceColor = $r('sys.color.font_primary')
  static readonly TEXT_SECONDARY: ResourceColor = $r('sys.color.font_secondary')
  static readonly TEXT_TERTIARY: ResourceColor = $r('sys.color.font_tertiary')
  static readonly TEXT_LINK: ResourceColor = $r('sys.color.font_emphasize')
  static readonly BG_PRIMARY: ResourceColor = $r('sys.color.background_primary')
  static readonly BG_SUB: ResourceColor = $r('sys.color.ohos_id_color_sub_background')
  static readonly DIVIDER: ResourceColor = $r('sys.color.ohos_id_color_list_separator')
  // Translucent black scrim for chrome drawn OVER full-bleed images (reader page counter,
  // future over-image controls). No system token fits an over-image scrim — V2Next hardcodes
  // it per page; this is the shared, reusable version of that literal.
  static readonly OVERLAY_SCRIM: ResourceColor = '#99000000'

  // Spacing
  static readonly SPACE_XS: number = 4
  static readonly SPACE_SM: number = 8
  static readonly SPACE_MD: number = 12
  static readonly SPACE_LG: number = 16
  static readonly SPACE_XL: number = 24
  static readonly SPACE_XXL: number = 32

  // Font sizes
  static readonly FONT_SIZE_TINY: number = 10
  static readonly FONT_SIZE_TAG: number = 11
  static readonly FONT_SIZE_CAPTION: number = 12
  static readonly FONT_SIZE_META: number = 13
  static readonly FONT_SIZE_BODY: number = 14
  static readonly FONT_SIZE_LIST_ITEM: number = 13
  static readonly FONT_SIZE_TITLE: number = 16
  static readonly FONT_SIZE_HEADING: number = 18
  static readonly FONT_SIZE_H2: number = 22
  static readonly FONT_SIZE_H1: number = 24

  // Border radius
  static readonly RADIUS_SM: number = 4
  static readonly RADIUS_MD: number = 12
  static readonly RADIUS_CARD: number = 16
  static readonly RADIUS_ROUND: number = 999

  // Grouped list (SecondaryListScaffold / GroupedListSection / ConciseListRow — V2Next pattern)
  static readonly LIST_SECTION_INSET: number = 4
  static readonly LIST_ROW_RADIUS: number = 19
  static readonly LIST_ROW_TEXT_INDENT: number = 8

  // Dimensions
  static readonly TITLE_BAR_HEIGHT: number = 56
  static readonly FLOAT_BAR_HEIGHT: number = 56
  static readonly FOOTER_HEIGHT: number = 48
  static readonly BUTTON_HEIGHT: number = 46 // primary action buttons (reader/detail Read, etc.)
  static readonly LOADING_SIZE: number = 32
  static readonly LOADING_SIZE_SMALL: number = 24
  static readonly LOADING_SIZE_LARGE: number = 40
  static readonly INDICATOR_SIZE: number = 28
  static readonly THUMB_ASPECT: number = 1.414 // EH cover/thumbnail default H:W ≈ √2 (A-series)
  // Min comfortable preview-thumbnail column width (vp). The detail inline grid + the all-thumbnails
  // page derive their column count from the pane width and this min (eros_fe max-cross-axis-extent),
  // so a phone lands ~3 columns and wider screens scale up — never a hardcoded column count.
  static readonly PREVIEW_THUMB_MIN_W: number = 105

  // Line heights
  static readonly LINE_HEIGHT_TITLE: number = 22
  static readonly LINE_HEIGHT_BODY: number = 20

  // Animations
  static readonly ANIM_DURATION: number = 400
  static readonly ANIM_STATE_RESET_MS: number = 420
  static readonly ANIM_DONE_DELAY_MS: number = 200
}
