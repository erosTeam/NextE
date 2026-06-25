import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { connectListMode, ListMode, ListModeState } from '../state/ListModeState'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'

/** Persists the gallery list/grid view mode + is the single writer of ListModeState. */
export class ListModeSettings {
  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const mode: string = store.getSync(StorageKeys.LIST_MODE, ListMode.LIST) as string
      // Default TRUE = eros_fe parity (its _fixedHeightOfListItems defaults to true → fixed rows out of box).
      const fixedHeight: boolean = store.getSync(
        StorageKeys.LIST_ITEM_FIXED_HEIGHT,
        true,
      ) as boolean
      const gridColW: number = store.getSync(StorageKeys.GRID_COLUMN_WIDTH, 0) as number
      const waterfallColW: number = store.getSync(StorageKeys.WATERFALL_COLUMN_WIDTH, 0) as number
      const coverWallColW: number = store.getSync(StorageKeys.COVER_WALL_COLUMN_WIDTH, 0) as number
      const state: ListModeState = connectListMode()
      state.mode = mode
      state.fixedHeight = fixedHeight
      state.gridColW = gridColW
      state.waterfallColW = waterfallColW
      state.coverWallColW = coverWallColW
    } catch (error) {
      DiagnosticLogger.warn('settings', 'listmode_restore_failed', (error as Error).message)
    }
  }

  static async setMode(context: common.UIAbilityContext, mode: string): Promise<void> {
    connectListMode().mode = mode
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.LIST_MODE, mode)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'listmode_save_failed', (error as Error).message)
    }
  }

  // Single writer of the fixed/adaptive list-row height axis (eros_fe fixedHeightOfListItems).
  static async setFixedHeight(
    context: common.UIAbilityContext,
    fixedHeight: boolean,
  ): Promise<void> {
    connectListMode().fixedHeight = fixedHeight
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.LIST_ITEM_FIXED_HEIGHT, fixedHeight)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn(
        'settings',
        'listmode_fixed_height_save_failed',
        (error as Error).message,
      )
    }
  }

  // Single writer of the per-mode column min-width override (pinch-zoom / settings slider). The live
  // in-memory updates during a pinch/drag are written directly to ListModeState; this persists the
  // final value on release. `mode` is one of ListMode.GRID/WATERFALL/COVER_WALL.
  static async setColumnWidth(
    context: common.UIAbilityContext,
    mode: string,
    width: number,
  ): Promise<void> {
    connectListMode().setWidthFor(mode, width)
    const key: string = ListModeSettings.columnWidthKey(mode)
    if (key.length === 0) {
      return
    }
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(key, width)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn(
        'settings',
        'listmode_column_width_save_failed',
        (error as Error).message,
      )
    }
  }

  private static columnWidthKey(mode: string): string {
    if (mode === ListMode.GRID) {
      return StorageKeys.GRID_COLUMN_WIDTH
    }
    if (mode === ListMode.WATERFALL) {
      return StorageKeys.WATERFALL_COLUMN_WIDTH
    }
    if (mode === ListMode.COVER_WALL) {
      return StorageKeys.COVER_WALL_COLUMN_WIDTH
    }
    return ''
  }
}
