import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { connectBackGuard } from '../state/BackGuardState'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'

/**
 * Persists the home back-guard; SINGLE WRITER of BackGuardState.
 * Mirrors ThumbnailModeSettings: restore() seeds the AppStorageV2 mirror at startup
 * (SettingsBootstrap), setEnabled() writes the mirror first then flushes to the preferences store.
 */
export class BackGuardSettings {
  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      connectBackGuard().enabled = store.getSync(
        StorageKeys.BACK_GUARD_ENABLED,
        true,
      ) as boolean
    } catch (error) {
      DiagnosticLogger.warn('settings', 'backguard_restore_failed', (error as Error).message)
    }
  }

  static async setEnabled(context: common.UIAbilityContext, value: boolean): Promise<void> {
    connectBackGuard().enabled = value
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.BACK_GUARD_ENABLED, value)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'backguard_save_failed', (error as Error).message)
    }
  }
}
