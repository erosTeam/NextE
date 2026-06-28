import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { SAFE_MODE_BUILD_ENABLED } from '../safe/SafeModeBuildFlag'
import { connectSafeMode, SafeModeState } from '../state/SafeModeState'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'

export class SafeModeSettings {
  static apply(unlocked: boolean): void {
    const state: SafeModeState = connectSafeMode()
    state.buildEnabled = SAFE_MODE_BUILD_ENABLED
    state.unlocked = SAFE_MODE_BUILD_ENABLED && unlocked
  }

  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const unlocked: boolean = store.getSync(StorageKeys.SAFE_MODE_UNLOCKED, false) as boolean
      SafeModeSettings.apply(unlocked)
    } catch (error) {
      DiagnosticLogger.warn('settings', 'safe_mode_restore_failed', (error as Error).message)
      SafeModeSettings.apply(false)
    }
  }

  static async unlock(context: common.UIAbilityContext): Promise<void> {
    if (!SAFE_MODE_BUILD_ENABLED) {
      return
    }
    SafeModeSettings.apply(true)
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.SAFE_MODE_UNLOCKED, true)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'safe_mode_save_failed', (error as Error).message)
    }
  }
}
