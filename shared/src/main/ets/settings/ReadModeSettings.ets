import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { connectReadMode, ReadColumnMode, ReadMode, ReadSpreadLayout } from '../state/ReadModeState'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'

/** Persists reader direction + double-page mode and is the single writer of ReadModeState. */
export class ReadModeSettings {
  private static normalizeMode(mode: string): string {
    if (mode === ReadMode.LTR ||
      mode === ReadMode.RTL ||
      mode === ReadMode.TOP_TO_BOTTOM ||
      mode === ReadMode.VERTICAL) {
      return mode
    }
    return ReadMode.LTR
  }

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

  private static normalizePreloadPages(value: number): number {
    if (!Number.isFinite(value)) {
      return 2
    }
    if (value < 0) {
      return 0
    }
    if (value > 5) {
      return 5
    }
    return Math.round(value)
  }

  private static normalizeSpreadLayout(mode: string): string {
    if (mode === ReadSpreadLayout.SPLIT || mode === ReadSpreadLayout.JOINED) {
      return mode
    }
    return ReadSpreadLayout.JOINED
  }

  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const mode: string = ReadModeSettings.normalizeMode(
        store.getSync(StorageKeys.READING_DIRECTION, ReadMode.LTR) as string
      )
      const rawDoublePage: Object = store.getSync(
        StorageKeys.READING_DOUBLE_PAGE,
        false,
      ) as Object
      const autoPageSeconds: number = store.getSync(
        StorageKeys.READING_AUTO_PAGE_SEC,
        3,
      ) as number
      const volumeKeyTurn: boolean = store.getSync(
        StorageKeys.READING_VOLUME_KEY,
        false,
      ) as boolean
      const preloadPages: number = store.getSync(
        StorageKeys.READING_PRELOAD_PAGES,
        2,
      ) as number
      const spreadLayoutMode: string = ReadModeSettings.normalizeSpreadLayout(
        store.getSync(StorageKeys.READING_SPREAD_LAYOUT, ReadSpreadLayout.JOINED) as string
      )
      connectReadMode().mode = mode
      connectReadMode().doublePageEnabled = ReadModeSettings.restoreDoublePageEnabled(rawDoublePage)
      connectReadMode().columnMode = ReadColumnMode.ODD_LEFT
      connectReadMode().spreadLayoutMode = spreadLayoutMode
      connectReadMode().autoPageSeconds = ReadModeSettings.normalizeAutoPageSeconds(autoPageSeconds)
      connectReadMode().preloadPages = ReadModeSettings.normalizePreloadPages(preloadPages)
      connectReadMode().volumeKeyTurn = volumeKeyTurn
    } catch (error) {
      DiagnosticLogger.warn('settings', 'readmode_restore_failed', (error as Error).message)
    }
  }

  private static restoreDoublePageEnabled(value: Object): boolean {
    if (typeof value === 'boolean') {
      return value
    }
    if (typeof value === 'string') {
      return value === 'true' ||
        value === '1' ||
        value === ReadColumnMode.ODD_LEFT ||
        value === ReadColumnMode.EVEN_LEFT
    }
    return false
  }

  static async setMode(context: common.UIAbilityContext, mode: string): Promise<void> {
    const normalized: string = ReadModeSettings.normalizeMode(mode)
    connectReadMode().mode = normalized
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.READING_DIRECTION, normalized)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'readmode_save_failed', (error as Error).message)
    }
  }

  static async setDoublePageEnabled(context: common.UIAbilityContext, enabled: boolean): Promise<void> {
    connectReadMode().doublePageEnabled = enabled
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.READING_DOUBLE_PAGE, enabled)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'read_column_save_failed', (error as Error).message)
    }
  }

  static async setSpreadLayoutMode(context: common.UIAbilityContext, mode: string): Promise<void> {
    const normalized: string = ReadModeSettings.normalizeSpreadLayout(mode)
    connectReadMode().spreadLayoutMode = normalized
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.READING_SPREAD_LAYOUT, normalized)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'read_spread_layout_save_failed', (error as Error).message)
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

  static async setVolumeKeyTurn(context: common.UIAbilityContext, enabled: boolean): Promise<void> {
    connectReadMode().volumeKeyTurn = enabled
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.READING_VOLUME_KEY, enabled)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'read_volume_key_save_failed', (error as Error).message)
    }
  }

  static async setPreloadPages(context: common.UIAbilityContext, pages: number): Promise<void> {
    const normalized: number = ReadModeSettings.normalizePreloadPages(pages)
    connectReadMode().preloadPages = normalized
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.READING_PRELOAD_PAGES, normalized)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'read_preload_pages_save_failed', (error as Error).message)
    }
  }
}
