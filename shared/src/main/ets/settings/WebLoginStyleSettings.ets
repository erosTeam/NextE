import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { connectWebLoginStyle } from '../state/WebLoginStyleState'

/** Persists whether the WebView login page should be CSS-beautified by default. */
export class WebLoginStyleSettings {
  static readonly DEFAULT_BEAUTIFY: boolean = true

  static apply(value: boolean): void {
    connectWebLoginStyle().beautifyEnabled = value
  }

  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS)
      WebLoginStyleSettings.apply(
        store.getSync(StorageKeys.WEB_LOGIN_BEAUTIFY_ENABLED, WebLoginStyleSettings.DEFAULT_BEAUTIFY) as boolean,
      )
    } catch (error) {
      DiagnosticLogger.warn('settings', 'web_login_style_restore_failed', (error as Error).message)
      WebLoginStyleSettings.apply(WebLoginStyleSettings.DEFAULT_BEAUTIFY)
    }
  }

  static async save(context: common.UIAbilityContext, value: boolean): Promise<void> {
    WebLoginStyleSettings.apply(value)
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS)
      store.putSync(StorageKeys.WEB_LOGIN_BEAUTIFY_ENABLED, value)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'web_login_style_save_failed', (error as Error).message)
    }
  }
}
