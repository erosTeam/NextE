import { common } from '@kit.AbilityKit'
import { i18n } from '@kit.LocalizationKit'
import { preferences } from '@kit.ArkData'
import { connectLanguageState } from '../state/AppearanceState'
import { AppStrings } from '../i18n/AppStrings'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'

/**
 * Manual in-app LANGUAGE override (follow-system / zh-Hans / en-US / ja-JP), persisted under
 * StorageKeys.LANGUAGE and the single writer of LanguageState. Pins the OS preferred language (so $r
 * resources re-resolve) AND an AppStrings override ResourceManager (so shared computed labels re-resolve),
 * both live without a restart (V2Next LanguageSettings pattern).
 */
export class LanguageSettings {
  static readonly MODE_SYSTEM: string = 'system'
  static readonly MODE_ZH_CN: string = 'zh-Hans'
  static readonly MODE_EN: string = 'en-US'
  static readonly MODE_JA: string = 'ja-JP'

  static normalize(mode: string): string {
    if (
      mode === LanguageSettings.MODE_ZH_CN ||
      mode === LanguageSettings.MODE_EN ||
      mode === LanguageSettings.MODE_JA
    ) {
      return mode
    }
    return LanguageSettings.MODE_SYSTEM
  }

  // setAppPreferredLanguage cannot clear a previous pin with 'default', so follow-system resolves the live
  // system language explicitly.
  private static resolveLocale(mode: string): string {
    if (mode !== LanguageSettings.MODE_SYSTEM) {
      return mode
    }
    try {
      return i18n.System.getSystemLanguage()
    } catch (_e) {
      return ''
    }
  }

  static apply(mode: string): void {
    const normalized: string = LanguageSettings.normalize(mode)
    const locale: string = LanguageSettings.resolveLocale(normalized)
    if (locale.length > 0) {
      try {
        i18n.System.setAppPreferredLanguage(locale)
      } catch (error) {
        DiagnosticLogger.warn('lang', 'set_preferred_language_failed', (error as Error).message)
      }
    }
    // Follow-system uses the default ResourceManager (no override); an explicit mode pins the override.
    const overrideLocale: string = normalized === LanguageSettings.MODE_SYSTEM ? '' : normalized
    AppStrings.setOverrideLocale(overrideLocale)
    const state = connectLanguageState()
    state.mode = normalized
    state.effectiveLocale = overrideLocale.length > 0 ? overrideLocale : locale
  }

  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const mode: string = store.getSync(
        StorageKeys.LANGUAGE,
        LanguageSettings.MODE_SYSTEM,
      ) as string
      LanguageSettings.apply(mode)
    } catch (error) {
      DiagnosticLogger.warn('settings', 'language_restore_failed', (error as Error).message)
      LanguageSettings.apply(LanguageSettings.MODE_SYSTEM)
    }
  }

  static async setMode(context: common.UIAbilityContext, mode: string): Promise<void> {
    const normalized: string = LanguageSettings.normalize(mode)
    LanguageSettings.apply(normalized)
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.LANGUAGE, normalized)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'language_save_failed', (error as Error).message)
    }
  }
}
