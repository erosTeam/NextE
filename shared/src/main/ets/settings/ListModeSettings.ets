import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { connectListMode, ListMode } from '../state/ListModeState'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'

/** Persists the gallery list/grid view mode + is the single writer of ListModeState. */
export class ListModeSettings {
  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS)
      const mode: string = store.getSync(StorageKeys.LIST_MODE, ListMode.LIST) as string
      connectListMode().mode = mode
    } catch (error) {
      DiagnosticLogger.warn('settings', 'listmode_restore_failed', (error as Error).message)
    }
  }

  static async setMode(context: common.UIAbilityContext, mode: string): Promise<void> {
    connectListMode().mode = mode
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS)
      store.putSync(StorageKeys.LIST_MODE, mode)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'listmode_save_failed', (error as Error).message)
    }
  }
}
