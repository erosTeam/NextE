import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import {
  connectGalleryDetailTransitionSettings,
  GalleryDetailTransitionSettingsState,
} from '../state/GalleryDetailTransitionSettingsState'

/** Single persistence writer for the optional card -> GalleryDetail transition. */
export class GalleryDetailTransitionSettings {
  static readonly DEFAULT_ENABLED: boolean = true

  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const state: GalleryDetailTransitionSettingsState = connectGalleryDetailTransitionSettings()
      state.enabled = store.getSync(
        StorageKeys.GALLERY_DETAIL_TRANSITION_ENABLED,
        GalleryDetailTransitionSettings.DEFAULT_ENABLED,
      ) as boolean
    } catch (error) {
      DiagnosticLogger.warn('settings', 'gallery_detail_transition_restore_failed', (error as Error).message)
    }
  }

  static async setEnabled(context: common.UIAbilityContext, enabled: boolean): Promise<void> {
    connectGalleryDetailTransitionSettings().enabled = enabled
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.GALLERY_DETAIL_TRANSITION_ENABLED, enabled)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'gallery_detail_transition_save_failed', (error as Error).message)
    }
  }
}
