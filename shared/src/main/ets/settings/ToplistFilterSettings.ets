import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { connectToplistFilter } from '../state/ToplistFilterState'

/** Persists whether Toplist hides galleries carrying the user's hidden My Tags. */
export class ToplistFilterSettings {
  static readonly DEFAULT_APPLY_HIDDEN: boolean = true

  static apply(value: boolean): void {
    connectToplistFilter().applyHiddenUserTags = value
  }

  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS)
      ToplistFilterSettings.apply(
        store.getSync(StorageKeys.TOPLIST_APPLY_HIDDEN_USER_TAGS, ToplistFilterSettings.DEFAULT_APPLY_HIDDEN) as boolean,
      )
    } catch (error) {
      DiagnosticLogger.warn('settings', 'toplist_filter_restore_failed', (error as Error).message)
      ToplistFilterSettings.apply(ToplistFilterSettings.DEFAULT_APPLY_HIDDEN)
    }
  }

  static async save(context: common.UIAbilityContext, value: boolean): Promise<void> {
    ToplistFilterSettings.apply(value)
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS)
      store.putSync(StorageKeys.TOPLIST_APPLY_HIDDEN_USER_TAGS, value)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'toplist_filter_save_failed', (error as Error).message)
    }
  }
}
