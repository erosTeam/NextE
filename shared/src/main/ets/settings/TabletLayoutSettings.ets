import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import {
  connectTabletLayout,
  TABLET_LAYOUT_AUTO,
  TABLET_LAYOUT_LANDSCAPE_ONLY,
  TABLET_LAYOUT_OFF,
} from '../state/TabletLayoutState'

export interface TabletLayoutOption {
  label: ResourceStr
  mode: string
}

/** Persists the layout policy only; main-window orientation remains a separate setting. */
export class TabletLayoutSettings {
  static readonly MODE_AUTO: string = TABLET_LAYOUT_AUTO
  static readonly MODE_OFF: string = TABLET_LAYOUT_OFF
  static readonly MODE_LANDSCAPE_ONLY: string = TABLET_LAYOUT_LANDSCAPE_ONLY

  static normalizeMode(mode: string): string {
    if (mode === TABLET_LAYOUT_OFF || mode === TABLET_LAYOUT_LANDSCAPE_ONLY) {
      return mode
    }
    return TABLET_LAYOUT_AUTO
  }

  static options(): TabletLayoutOption[] {
    return [
      {
        label: $r('app.string.common_auto'),
        mode: TABLET_LAYOUT_AUTO,
      },
      {
        label: $r('app.string.common_off'),
        mode: TABLET_LAYOUT_OFF,
      },
      {
        label: $r('app.string.tablet_layout_landscape_only'),
        mode: TABLET_LAYOUT_LANDSCAPE_ONLY,
      },
    ]
  }

  static label(mode: string): ResourceStr {
    const normalized: string = TabletLayoutSettings.normalizeMode(mode)
    if (normalized === TABLET_LAYOUT_OFF) {
      return $r('app.string.common_off')
    }
    if (normalized === TABLET_LAYOUT_LANDSCAPE_ONLY) {
      return $r('app.string.tablet_layout_landscape_only')
    }
    return $r('app.string.common_auto')
  }

  /**
   * Returns whether a wide layout may be used. Auto keeps existing HDS width behaviour; landscape-only
   * deliberately uses actual main-window geometry rather than requesting a device orientation.
   */
  static allowsSplit(mode: string, widthPx: number, heightPx: number): boolean {
    const normalized: string = TabletLayoutSettings.normalizeMode(mode)
    if (normalized === TABLET_LAYOUT_OFF) {
      return false
    }
    if (normalized === TABLET_LAYOUT_LANDSCAPE_ONLY) {
      return widthPx > 0 && heightPx > 0 && widthPx > heightPx
    }
    return true
  }

  static apply(mode: string): void {
    connectTabletLayout().mode = TabletLayoutSettings.normalizeMode(mode)
  }

  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const mode: string = store.getSync(StorageKeys.TABLET_LAYOUT_MODE, TABLET_LAYOUT_AUTO) as string
      TabletLayoutSettings.apply(mode)
    } catch (error) {
      DiagnosticLogger.warn('settings', 'tablet_layout_restore_failed', (error as Error).message)
    }
  }

  static async setMode(context: common.UIAbilityContext, mode: string): Promise<void> {
    const normalized: string = TabletLayoutSettings.normalizeMode(mode)
    TabletLayoutSettings.apply(normalized)
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.TABLET_LAYOUT_MODE, normalized)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'tablet_layout_save_failed', (error as Error).message)
    }
  }
}
