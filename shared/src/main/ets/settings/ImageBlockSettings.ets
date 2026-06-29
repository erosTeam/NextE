import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { connectImageBlockSettings } from '../state/ImageBlockSettingsState'

export class ImageBlockSettings {
  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS)
      connectImageBlockSettings().enabled = store.getSync(StorageKeys.IMAGE_BLOCK_ENABLED, false) as boolean
    } catch (error) {
      DiagnosticLogger.warn('settings', 'image_block_restore_failed', (error as Error).message)
    }
  }

  static async setEnabled(context: common.UIAbilityContext, enabled: boolean): Promise<void> {
    connectImageBlockSettings().enabled = enabled
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS)
      store.putSync(StorageKeys.IMAGE_BLOCK_ENABLED, enabled)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'image_block_enabled_save_failed', (error as Error).message)
    }
  }
}
