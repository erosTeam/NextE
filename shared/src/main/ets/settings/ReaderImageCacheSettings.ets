import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'

const DEFAULT_LIMIT_MB: number = 1024
const MIN_LIMIT_MB: number = 256
const MAX_LIMIT_MB: number = 2048

export class ReaderImageCacheSettings {
  private static currentLimitMb: number = DEFAULT_LIMIT_MB

  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const value: number = store.getSync(
        StorageKeys.READER_IMAGE_CACHE_LIMIT_MB,
        DEFAULT_LIMIT_MB,
      ) as number
      ReaderImageCacheSettings.currentLimitMb = ReaderImageCacheSettings.normalize(value)
    } catch (error) {
      DiagnosticLogger.warn('settings', 'reader_image_cache_restore_failed', (error as Error).message)
    }
  }

  static limitMb(): number {
    return ReaderImageCacheSettings.currentLimitMb
  }

  static limitBytes(): number {
    return ReaderImageCacheSettings.currentLimitMb * 1024 * 1024
  }

  static async setLimitMb(context: common.UIAbilityContext, value: number): Promise<void> {
    const normalized: number = ReaderImageCacheSettings.normalize(value)
    ReaderImageCacheSettings.currentLimitMb = normalized
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.READER_IMAGE_CACHE_LIMIT_MB, normalized)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'reader_image_cache_save_failed', (error as Error).message)
    }
  }

  private static normalize(value: number): number {
    if (!Number.isFinite(value)) {
      return DEFAULT_LIMIT_MB
    }
    const rounded: number = Math.round(value)
    if (rounded <= MIN_LIMIT_MB) {
      return MIN_LIMIT_MB
    }
    if (rounded <= 512) {
      return 512
    }
    if (rounded <= DEFAULT_LIMIT_MB) {
      return DEFAULT_LIMIT_MB
    }
    return MAX_LIMIT_MB
  }
}
