import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { connectThumbnailMode, ThumbnailModeState } from '../state/ThumbnailModeState'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'

/**
 * Persists the two detail-preview toggles and is the SINGLE WRITER of ThumbnailModeState.
 * Mirrors ListModeSettings / ReadModeSettings: restore() seeds the AppStorageV2 mirror at startup
 * (SettingsBootstrap), setX() writes the mirror first then flushes to the preferences store.
 */
export class ThumbnailModeSettings {
  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const state: ThumbnailModeState = connectThumbnailMode()
      state.hideGalleryThumbnails = store.getSync(
        StorageKeys.HIDE_GALLERY_THUMBNAILS,
        false,
      ) as boolean
      state.horizontalThumbnails = store.getSync(
        StorageKeys.HORIZONTAL_THUMBNAILS,
        false,
      ) as boolean
    } catch (error) {
      DiagnosticLogger.warn('settings', 'thumbnailmode_restore_failed', (error as Error).message)
    }
  }

  static async setHideGalleryThumbnails(
    context: common.UIAbilityContext,
    value: boolean,
  ): Promise<void> {
    connectThumbnailMode().hideGalleryThumbnails = value
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.HIDE_GALLERY_THUMBNAILS, value)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'thumbnailmode_save_failed', (error as Error).message)
    }
  }

  static async setHorizontalThumbnails(
    context: common.UIAbilityContext,
    value: boolean,
  ): Promise<void> {
    connectThumbnailMode().horizontalThumbnails = value
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.HORIZONTAL_THUMBNAILS, value)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'thumbnailmode_save_failed', (error as Error).message)
    }
  }
}
