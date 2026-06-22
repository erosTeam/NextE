import { common, ConfigurationConstant } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { connectThemeDisplay, ThemeDisplayState } from '../state/AppearanceState'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'

/**
 * Manual dark-mode override (system / light / dark), persisted under StorageKeys.THEME_MODE and the single
 * writer of ThemeDisplayState. Applies the override app-wide via ApplicationContext.setColorMode and keeps
 * `effectiveDark` fresh so cached sub-tab pills recolor on a system flip (V2Next ThemeSettings pattern).
 */
export class ThemeSettings {
  static readonly MODE_SYSTEM: string = 'system'
  static readonly MODE_LIGHT: string = 'light'
  static readonly MODE_DARK: string = 'dark'

  static normalize(mode: string): string {
    if (mode === ThemeSettings.MODE_LIGHT || mode === ThemeSettings.MODE_DARK) {
      return mode
    }
    return ThemeSettings.MODE_SYSTEM
  }

  private static computeDark(context: common.UIAbilityContext, mode: string): boolean {
    if (mode === ThemeSettings.MODE_DARK) {
      return true
    }
    if (mode === ThemeSettings.MODE_LIGHT) {
      return false
    }
    return context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
  }

  // Push the override into the framework + refresh the reactive signal. light/dark force the app colorMode;
  // system clears it (NOT_SET → follow device).
  static apply(context: common.UIAbilityContext, mode: string): void {
    const normalized: string = ThemeSettings.normalize(mode)
    let target: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET
    if (normalized === ThemeSettings.MODE_DARK) {
      target = ConfigurationConstant.ColorMode.COLOR_MODE_DARK
    } else if (normalized === ThemeSettings.MODE_LIGHT) {
      target = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
    }
    try {
      context.getApplicationContext().setColorMode(target)
    } catch (error) {
      DiagnosticLogger.warn('theme', 'set_color_mode_failed', (error as Error).message)
    }
    const state: ThemeDisplayState = connectThemeDisplay()
    state.mode = normalized
    state.effectiveDark = ThemeSettings.computeDark(context, normalized)
  }

  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const mode: string = store.getSync(
        StorageKeys.THEME_MODE,
        ThemeSettings.MODE_SYSTEM,
      ) as string
      ThemeSettings.apply(context, mode)
    } catch (error) {
      DiagnosticLogger.warn('settings', 'theme_restore_failed', (error as Error).message)
      ThemeSettings.apply(context, ThemeSettings.MODE_SYSTEM)
    }
  }

  static async setMode(context: common.UIAbilityContext, mode: string): Promise<void> {
    const normalized: string = ThemeSettings.normalize(mode)
    ThemeSettings.apply(context, normalized)
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.THEME_MODE, normalized)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'theme_save_failed', (error as Error).message)
    }
  }

  // EnvironmentCallback hook: when the DEVICE flips dark/light and we're in follow-system mode, refresh the
  // signal so cached sub-tab pills (which never rebuild on their own) recolor immediately. No-op when forced.
  static onSystemColorModeChanged(colorMode: ConfigurationConstant.ColorMode): void {
    const state: ThemeDisplayState = connectThemeDisplay()
    if (state.mode !== ThemeSettings.MODE_SYSTEM) {
      return
    }
    state.effectiveDark = colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
  }
}
