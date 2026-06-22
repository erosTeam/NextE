import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { connectThemeColor } from '../state/AppearanceState'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'

// Preset palette ported verbatim from V2Next (shared/.../settings/ThemeColorSettings.ets): same values,
// same hex, same label keys, same default. galaxyBlue is the default accent.
const THEME_COLOR_GALAXY_BLUE: string = 'galaxyBlue'
const THEME_COLOR_ORANGE_YELLOW: string = 'orangeYellow'
const THEME_COLOR_CAT_BLUE: string = 'catBlue'
const THEME_COLOR_HUAWEI_RED: string = 'huaweiRed'
const THEME_COLOR_ELEGANT_PURPLE: string = 'elegantPurple'
const THEME_COLOR_BILIBILI_PINK: string = 'bilibiliPink'
const THEME_COLOR_GRASS_GREEN: string = 'grassGreen'

export interface ThemeColorOption {
  label: ResourceStr
  value: string
  color: ResourceColor
}

/**
 * User-selectable ACCENT color, persisted under StorageKeys.THEME_COLOR and the single writer of
 * ThemeColorState. The seven named presets and their hex are V2Next's, verbatim (galaxyBlue is the default).
 * NextE adds ONE thing V2Next does not have: a custom accent, which is any valid #RRGGBB hex.
 * ThemeConstants.BRAND_PRIMARY is a getter reading currentColor() → connectThemeColor().color (@Trace), so
 * picking a color recolors every brand-tinted control with no call-site changes.
 */
export class ThemeColorSettings {
  static readonly COLOR_GALAXY_BLUE: string = THEME_COLOR_GALAXY_BLUE
  static readonly COLOR_ORANGE_YELLOW: string = THEME_COLOR_ORANGE_YELLOW
  static readonly COLOR_CAT_BLUE: string = THEME_COLOR_CAT_BLUE
  static readonly COLOR_HUAWEI_RED: string = THEME_COLOR_HUAWEI_RED
  static readonly COLOR_ELEGANT_PURPLE: string = THEME_COLOR_ELEGANT_PURPLE
  static readonly COLOR_BILIBILI_PINK: string = THEME_COLOR_BILIBILI_PINK
  static readonly COLOR_GRASS_GREEN: string = THEME_COLOR_GRASS_GREEN
  static readonly DEFAULT_COLOR: string = THEME_COLOR_GALAXY_BLUE

  static options(): ThemeColorOption[] {
    return [
      {
        label: $r('app.string.theme_color_galaxy_blue'),
        value: THEME_COLOR_GALAXY_BLUE,
        color: '#0958F7',
      },
      {
        label: $r('app.string.theme_color_orange_yellow'),
        value: THEME_COLOR_ORANGE_YELLOW,
        color: '#FE9925',
      },
      {
        label: $r('app.string.theme_color_cat_blue'),
        value: THEME_COLOR_CAT_BLUE,
        color: '#345483',
      },
      {
        label: $r('app.string.theme_color_huawei_red'),
        value: THEME_COLOR_HUAWEI_RED,
        color: '#D9323B',
      },
      {
        label: $r('app.string.theme_color_elegant_purple'),
        value: THEME_COLOR_ELEGANT_PURPLE,
        color: '#8143D6',
      },
      {
        label: $r('app.string.theme_color_bilibili_pink'),
        value: THEME_COLOR_BILIBILI_PINK,
        color: '#FB80A5',
      },
      {
        label: $r('app.string.theme_color_grass_green'),
        value: THEME_COLOR_GRASS_GREEN,
        color: '#8ED931',
      },
    ]
  }

  static isPreset(value: string): boolean {
    return (
      value === THEME_COLOR_GALAXY_BLUE ||
      value === THEME_COLOR_ORANGE_YELLOW ||
      value === THEME_COLOR_CAT_BLUE ||
      value === THEME_COLOR_HUAWEI_RED ||
      value === THEME_COLOR_ELEGANT_PURPLE ||
      value === THEME_COLOR_BILIBILI_PINK ||
      value === THEME_COLOR_GRASS_GREEN
    )
  }

  // NextE extension: a custom accent is any valid #RRGGBB hex.
  static isCustom(color: string): boolean {
    return /^#[0-9a-fA-F]{6}$/.test(color.trim())
  }

  // Seed the custom picker from the current selection: a preset → its hex, a custom hex → itself.
  static customSeed(color: string): string {
    return ThemeColorSettings.colorValue(ThemeColorSettings.normalize(color)) as string
  }

  static normalize(color: string): string {
    const value: string = (color || '').trim()
    if (ThemeColorSettings.isPreset(value)) {
      return value
    }
    if (ThemeColorSettings.isCustom(value)) {
      return value.toUpperCase()
    }
    return THEME_COLOR_GALAXY_BLUE
  }

  static label(color: string): ResourceStr {
    const v: string = ThemeColorSettings.normalize(color)
    if (ThemeColorSettings.isCustom(v)) {
      return $r('app.string.theme_color_custom')
    }
    if (v === THEME_COLOR_ORANGE_YELLOW) {
      return $r('app.string.theme_color_orange_yellow')
    }
    if (v === THEME_COLOR_CAT_BLUE) {
      return $r('app.string.theme_color_cat_blue')
    }
    if (v === THEME_COLOR_HUAWEI_RED) {
      return $r('app.string.theme_color_huawei_red')
    }
    if (v === THEME_COLOR_ELEGANT_PURPLE) {
      return $r('app.string.theme_color_elegant_purple')
    }
    if (v === THEME_COLOR_BILIBILI_PINK) {
      return $r('app.string.theme_color_bilibili_pink')
    }
    if (v === THEME_COLOR_GRASS_GREEN) {
      return $r('app.string.theme_color_grass_green')
    }
    return $r('app.string.theme_color_galaxy_blue')
  }

  static colorValue(color: string): ResourceColor {
    const v: string = ThemeColorSettings.normalize(color)
    if (ThemeColorSettings.isCustom(v)) {
      return v
    }
    if (v === THEME_COLOR_ORANGE_YELLOW) {
      return '#FE9925'
    }
    if (v === THEME_COLOR_CAT_BLUE) {
      return '#345483'
    }
    if (v === THEME_COLOR_HUAWEI_RED) {
      return '#D9323B'
    }
    if (v === THEME_COLOR_ELEGANT_PURPLE) {
      return '#8143D6'
    }
    if (v === THEME_COLOR_BILIBILI_PINK) {
      return '#FB80A5'
    }
    if (v === THEME_COLOR_GRASS_GREEN) {
      return '#8ED931'
    }
    return '#0958F7'
  }

  static currentColor(): ResourceColor {
    return ThemeColorSettings.colorValue(connectThemeColor().color)
  }

  static apply(color: string): void {
    connectThemeColor().color = ThemeColorSettings.normalize(color)
  }

  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const color: string = store.getSync(
        StorageKeys.THEME_COLOR,
        ThemeColorSettings.DEFAULT_COLOR,
      ) as string
      ThemeColorSettings.apply(color)
    } catch (error) {
      DiagnosticLogger.warn('settings', 'theme_color_restore_failed', (error as Error).message)
    }
  }

  static async setColor(context: common.UIAbilityContext, color: string): Promise<void> {
    const normalized: string = ThemeColorSettings.normalize(color)
    ThemeColorSettings.apply(normalized)
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.THEME_COLOR, normalized)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'theme_color_save_failed', (error as Error).message)
    }
  }
}
