import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { StorageKeys } from '../constants/StorageKeys'
import { connectEhAppProfile } from '../state/EhAppProfileState'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'

/** Optional, default-on application profile. The server profile ID remains in the account cookie jar. */
export class EhAppProfileSettings {
  static revision: number = 0

  static async restore(context: common.UIAbilityContext): Promise<void> {
    const revision: number = ++EhAppProfileSettings.revision
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS)
      if (revision === EhAppProfileSettings.revision) {
        connectEhAppProfile().enabled = store.getSync(StorageKeys.EH_APP_PROFILE_ENABLED, true) as boolean
      }
    } catch (error) {
      DiagnosticLogger.warn('settings', 'eh_app_profile_restore_failed', (error as Error).message)
    }
  }

  static async setEnabled(context: common.UIAbilityContext, enabled: boolean): Promise<void> {
    const previous: boolean = connectEhAppProfile().enabled
    const revision: number = ++EhAppProfileSettings.revision
    connectEhAppProfile().enabled = enabled
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS)
      if (revision !== EhAppProfileSettings.revision) {
        return
      }
      store.putSync(StorageKeys.EH_APP_PROFILE_ENABLED, enabled)
      store.flushSync()
    } catch (error) {
      if (revision === EhAppProfileSettings.revision) {
        connectEhAppProfile().enabled = previous
      }
      throw error as Error
    }
  }
}
