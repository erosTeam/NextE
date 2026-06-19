import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { connectGalleryTitle, GalleryTitleState } from '../state/GalleryTitleState'

/** Persists the gallery-detail primary-title preference. */
export class GalleryTitleSettings {
  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const state: GalleryTitleState = connectGalleryTitle()
      state.japaneseTitleInGalleryPage = store.getSync(
        StorageKeys.JAPANESE_TITLE_IN_GALLERY_PAGE,
        false,
      ) as boolean
    } catch (error) {
      DiagnosticLogger.warn('settings', 'gallery_title_restore_failed', (error as Error).message)
    }
  }

  static async setJapaneseTitleInGalleryPage(
    context: common.UIAbilityContext,
    enabled: boolean,
  ): Promise<void> {
    connectGalleryTitle().japaneseTitleInGalleryPage = enabled
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.JAPANESE_TITLE_IN_GALLERY_PAGE, enabled)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'gallery_title_save_failed', (error as Error).message)
    }
  }
}
