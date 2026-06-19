import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { connectReadMode, ReadColumnMode, ReadMode } from '../state/ReadModeState'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'

/** Persists reader direction + double-page mode and is the single writer of ReadModeState. */
export class ReadModeSettings {
  private static normalizeAutoPageSeconds(value: number): number {
    if (!Number.isFinite(value)) {
      return 3
    }
    if (value < 1) {
      return 1
    }
    if (value > 60) {
      return 60
    }
    return Math.round(value)
  }

  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const mode: string = store.getSync(StorageKeys.READING_DIRECTION, ReadMode.LTR) as string
      const columnMode: string = store.getSync(
        StorageKeys.READING_DOUBLE_PAGE,
        ReadColumnMode.SINGLE,
      ) as string
      const autoPageSeconds: number = store.getSync(
        StorageKeys.READING_AUTO_PAGE_SEC,
        3,
      ) as number
      connectReadMode().mode = mode
      connectReadMode().columnMode = columnMode
      connectReadMode().autoPageSeconds = ReadModeSettings.normalizeAutoPageSeconds(autoPageSeconds)
    } catch (error) {
      DiagnosticLogger.warn('settings', 'readmode_restore_failed', (error as Error).message)
    }
  }

  static async setMode(context: common.UIAbilityContext, mode: string): Promise<void> {
    connectReadMode().mode = mode
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.READING_DIRECTION, mode)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'readmode_save_failed', (error as Error).message)
    }
  }

  static async setColumnMode(context: common.UIAbilityContext, columnMode: string): Promise<void> {
    connectReadMode().columnMode = columnMode
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.READING_DOUBLE_PAGE, columnMode)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'read_column_save_failed', (error as Error).message)
    }
  }

  static async setAutoPageSeconds(context: common.UIAbilityContext, seconds: number): Promise<void> {
    const normalized: number = ReadModeSettings.normalizeAutoPageSeconds(seconds)
    connectReadMode().autoPageSeconds = normalized
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.READING_AUTO_PAGE_SEC, normalized)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'read_auto_page_save_failed', (error as Error).message)
    }
  }
}
