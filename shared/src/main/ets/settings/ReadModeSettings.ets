import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import {
  connectReadMode,
  ReadColumnMode,
  ReadMode,
  ReaderBackgroundMode,
  ReadSpreadLayout,
} from '../state/ReadModeState'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import {
  ReaderTapZoneInvert,
  ReaderTapZoneLayout,
  ReaderTapZoneResolver,
} from '../utils/ReaderTapZoneResolver'

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

  private static normalizeBackgroundMode(mode: string): string {
    if (mode === ReaderBackgroundMode.BLACK ||
      mode === ReaderBackgroundMode.GRAY ||
      mode === ReaderBackgroundMode.WHITE ||
      mode === ReaderBackgroundMode.AUTO) {
      return mode
    }
    return ReaderBackgroundMode.BLACK
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
      const tapZoneLayout: string = ReaderTapZoneResolver.normalizeLayout(
        store.getSync(StorageKeys.READING_TAP_ZONE_LAYOUT, ReaderTapZoneLayout.RIGHT_LEFT) as string
      )
      const tapZoneInvert: string = ReaderTapZoneResolver.normalizeInvert(
        store.getSync(StorageKeys.READING_TAP_ZONE_INVERT, ReaderTapZoneInvert.NONE) as string
      )
      const backgroundMode: string = ReadModeSettings.normalizeBackgroundMode(
        store.getSync(StorageKeys.READING_BACKGROUND_MODE, ReaderBackgroundMode.BLACK) as string
      )
      const showPageNumber: boolean = store.getSync(
        StorageKeys.READING_SHOW_PAGE_NUMBER,
        true,
      ) as boolean
      const fullscreen: boolean = store.getSync(StorageKeys.READING_FULLSCREEN, true) as boolean
      const keepScreenOn: boolean = store.getSync(StorageKeys.READING_KEEP_SCREEN_ON, true) as boolean
      const pageTurnAnimation: boolean = store.getSync(
        StorageKeys.READING_PAGE_TURN_ANIMATION,
        true,
      ) as boolean
      connectReadMode().mode = mode
      connectReadMode().doublePageEnabled = ReadModeSettings.restoreDoublePageEnabled(rawDoublePage)
      connectReadMode().columnMode = ReadColumnMode.ODD_LEFT
      connectReadMode().spreadLayoutMode = spreadLayoutMode
      connectReadMode().autoPageSeconds = ReadModeSettings.normalizeAutoPageSeconds(autoPageSeconds)
      connectReadMode().preloadPages = ReadModeSettings.normalizePreloadPages(preloadPages)
      connectReadMode().volumeKeyTurn = volumeKeyTurn
      connectReadMode().tapZoneLayout = tapZoneLayout
      connectReadMode().tapZoneInvert = tapZoneInvert
      connectReadMode().backgroundMode = backgroundMode
      connectReadMode().showPageNumber = showPageNumber
      connectReadMode().fullscreen = fullscreen
      connectReadMode().keepScreenOn = keepScreenOn
      connectReadMode().pageTurnAnimation = pageTurnAnimation
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

  static async setTapZoneLayout(context: common.UIAbilityContext, layout: string): Promise<void> {
    const normalized: string = ReaderTapZoneResolver.normalizeLayout(layout)
    connectReadMode().tapZoneLayout = normalized
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.READING_TAP_ZONE_LAYOUT, normalized)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'read_tap_zone_layout_save_failed', (error as Error).message)
    }
  }

  static async setTapZoneInvert(context: common.UIAbilityContext, invert: string): Promise<void> {
    const normalized: string = ReaderTapZoneResolver.normalizeInvert(invert)
    connectReadMode().tapZoneInvert = normalized
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.READING_TAP_ZONE_INVERT, normalized)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'read_tap_zone_invert_save_failed', (error as Error).message)
    }
  }

  static async setBackgroundMode(context: common.UIAbilityContext, mode: string): Promise<void> {
    const normalized: string = ReadModeSettings.normalizeBackgroundMode(mode)
    connectReadMode().backgroundMode = normalized
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.READING_BACKGROUND_MODE, normalized)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'read_background_mode_save_failed', (error as Error).message)
    }
  }

  static async setShowPageNumber(context: common.UIAbilityContext, enabled: boolean): Promise<void> {
    connectReadMode().showPageNumber = enabled
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.READING_SHOW_PAGE_NUMBER, enabled)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'read_show_page_number_save_failed', (error as Error).message)
    }
  }

  static async setFullscreen(context: common.UIAbilityContext, enabled: boolean): Promise<void> {
    connectReadMode().fullscreen = enabled
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.READING_FULLSCREEN, enabled)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'read_fullscreen_save_failed', (error as Error).message)
    }
  }

  static async setKeepScreenOn(context: common.UIAbilityContext, enabled: boolean): Promise<void> {
    connectReadMode().keepScreenOn = enabled
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.READING_KEEP_SCREEN_ON, enabled)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'read_keep_screen_on_save_failed', (error as Error).message)
    }
  }

  static async setPageTurnAnimation(context: common.UIAbilityContext, enabled: boolean): Promise<void> {
    connectReadMode().pageTurnAnimation = enabled
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.READING_PAGE_TURN_ANIMATION, enabled)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'read_page_turn_animation_save_failed', (error as Error).message)
    }
  }
}
