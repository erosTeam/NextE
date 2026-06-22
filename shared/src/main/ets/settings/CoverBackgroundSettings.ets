import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { connectCoverBackground, CoverBackgroundState } from '../state/CoverBackgroundState'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'

/**
 * Persists blurringOfCoverBackground and is the SINGLE WRITER of CoverBackgroundState. Mirrors
 * ThumbnailModeSettings: restore() seeds the AppStorageV2 mirror at startup (SettingsBootstrap),
 * set() writes the mirror first then flushes to the preferences store.
 */
export class CoverBackgroundSettings {
  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const state: CoverBackgroundState = connectCoverBackground()
      state.blurringOfCoverBackground = store.getSync(
        StorageKeys.BLURRING_OF_COVER_BACKGROUND,
        false,
      ) as boolean
    } catch (error) {
      DiagnosticLogger.warn('settings', 'coverbackground_restore_failed', (error as Error).message)
    }
  }

  static async setBlurringOfCoverBackground(
    context: common.UIAbilityContext,
    value: boolean,
  ): Promise<void> {
    connectCoverBackground().blurringOfCoverBackground = value
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.BLURRING_OF_COVER_BACKGROUND, value)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'coverbackground_save_failed', (error as Error).message)
    }
  }
}
