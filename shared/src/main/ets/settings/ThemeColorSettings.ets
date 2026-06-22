import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { connectThemeColor } from '../state/AppearanceState'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'

export interface ThemeColorOption {
  label: ResourceStr
  value: string
  color: ResourceColor
}

/**
 * User-selectable ACCENT color, persisted under StorageKeys.THEME_COLOR and the single writer of
 * ThemeColorState. `system` (default) returns the platform brand token so existing installs look unchanged;
 * the rest are fixed hex presets (palette from V2Next). ThemeConstants.BRAND_PRIMARY is a getter reading
 * currentColor() → connectThemeColor().color (@Trace), so picking a color recolors every brand-tinted
 * control with no call-site changes.
 */
export class ThemeColorSettings {
  static readonly COLOR_SYSTEM: string = 'system'
  static readonly COLOR_ORANGE: string = 'orange'
  static readonly COLOR_RED: string = 'red'
  static readonly COLOR_PURPLE: string = 'purple'
  static readonly COLOR_PINK: string = 'pink'
  static readonly COLOR_GREEN: string = 'green'
  static readonly DEFAULT_COLOR: string = 'system'

  static options(): ThemeColorOption[] {
    return [
      {
        label: $r('app.string.theme_color_system'),
        value: ThemeColorSettings.COLOR_SYSTEM,
        color: $r('sys.color.brand'),
      },
      {
        label: $r('app.string.theme_color_orange'),
        value: ThemeColorSettings.COLOR_ORANGE,
        color: '#FE9925',
      },
      {
        label: $r('app.string.theme_color_red'),
        value: ThemeColorSettings.COLOR_RED,
        color: '#D9323B',
      },
      {
        label: $r('app.string.theme_color_purple'),
        value: ThemeColorSettings.COLOR_PURPLE,
        color: '#8143D6',
      },
      {
        label: $r('app.string.theme_color_pink'),
        value: ThemeColorSettings.COLOR_PINK,
        color: '#FB80A5',
      },
      {
        label: $r('app.string.theme_color_green'),
        value: ThemeColorSettings.COLOR_GREEN,
        color: '#8ED931',
      },
    ]
  }

  static normalize(color: string): string {
    const v: string = color.trim()
    if (
      v === ThemeColorSettings.COLOR_ORANGE ||
      v === ThemeColorSettings.COLOR_RED ||
      v === ThemeColorSettings.COLOR_PURPLE ||
      v === ThemeColorSettings.COLOR_PINK ||
      v === ThemeColorSettings.COLOR_GREEN
    ) {
      return v
    }
    return ThemeColorSettings.COLOR_SYSTEM
  }

  static colorValue(color: string): ResourceColor {
    const v: string = ThemeColorSettings.normalize(color)
    if (v === ThemeColorSettings.COLOR_ORANGE) {
      return '#FE9925'
    }
    if (v === ThemeColorSettings.COLOR_RED) {
      return '#D9323B'
    }
    if (v === ThemeColorSettings.COLOR_PURPLE) {
      return '#8143D6'
    }
    if (v === ThemeColorSettings.COLOR_PINK) {
      return '#FB80A5'
    }
    if (v === ThemeColorSettings.COLOR_GREEN) {
      return '#8ED931'
    }
    return $r('sys.color.brand')
  }

  static label(color: string): ResourceStr {
    const v: string = ThemeColorSettings.normalize(color)
    if (v === ThemeColorSettings.COLOR_ORANGE) {
      return $r('app.string.theme_color_orange')
    }
    if (v === ThemeColorSettings.COLOR_RED) {
      return $r('app.string.theme_color_red')
    }
    if (v === ThemeColorSettings.COLOR_PURPLE) {
      return $r('app.string.theme_color_purple')
    }
    if (v === ThemeColorSettings.COLOR_PINK) {
      return $r('app.string.theme_color_pink')
    }
    if (v === ThemeColorSettings.COLOR_GREEN) {
      return $r('app.string.theme_color_green')
    }
    return $r('app.string.theme_color_system')
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
        ThemeColorSettings.COLOR_SYSTEM,
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
