import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import {
  GalleryDetailTransitionMode,
  connectGalleryDetailTransitionSettings,
  GalleryDetailTransitionSettingsState,
} from '../state/GalleryDetailTransitionSettingsState'

/** Single persistence writer for the selected card -> GalleryDetail transition. */
export class GalleryDetailTransitionSettings {
  static readonly DEFAULT_MODE: string = GalleryDetailTransitionMode.SEAMLESS

  static normalize(mode: string): string {
    if (
      mode === GalleryDetailTransitionMode.SYSTEM ||
      mode === GalleryDetailTransitionMode.SEAMLESS ||
      mode === GalleryDetailTransitionMode.COVER_EXPAND
    ) {
      return mode
    }
    return GalleryDetailTransitionSettings.DEFAULT_MODE
  }

  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const state: GalleryDetailTransitionSettingsState = connectGalleryDetailTransitionSettings()
      const storedMode: string = store.getSync(
        StorageKeys.GALLERY_DETAIL_TRANSITION_MODE,
        '',
      ) as string
      if (storedMode.length > 0) {
        state.mode = GalleryDetailTransitionSettings.normalize(storedMode)
        return
      }
      const legacyEnabled: boolean = store.getSync(
        StorageKeys.GALLERY_DETAIL_TRANSITION_ENABLED,
        true,
      ) as boolean
      state.mode = legacyEnabled
        ? GalleryDetailTransitionMode.SEAMLESS
        : GalleryDetailTransitionMode.SYSTEM
    } catch (error) {
      DiagnosticLogger.warn('settings', 'gallery_detail_transition_restore_failed', (error as Error).message)
    }
  }

  static async setMode(context: common.UIAbilityContext, mode: string): Promise<void> {
    const normalized: string = GalleryDetailTransitionSettings.normalize(mode)
    connectGalleryDetailTransitionSettings().mode = normalized
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.GALLERY_DETAIL_TRANSITION_MODE, normalized)
      store.putSync(
        StorageKeys.GALLERY_DETAIL_TRANSITION_ENABLED,
        normalized !== GalleryDetailTransitionMode.SYSTEM,
      )
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'gallery_detail_transition_save_failed', (error as Error).message)
    }
  }
}
