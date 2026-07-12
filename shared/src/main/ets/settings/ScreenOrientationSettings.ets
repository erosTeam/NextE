import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import {
  connectScreenOrientation,
  SCREEN_ORIENTATION_AUTO_ROTATION_UNSPECIFIED,
  SCREEN_ORIENTATION_UNSPECIFIED,
} from '../state/ScreenOrientationState'

export interface ScreenOrientationOption {
  label: ResourceStr
  mode: string
}

type WindowOrientationApplier = (mode: string) => void

let windowOrientationApplier: WindowOrientationApplier | null = null

/**
 * Persists the two system-managed orientation policies. The EntryAbility owns the actual Window
 * API call through the narrow applier bridge, matching the existing window-privacy setting.
 */
export class ScreenOrientationSettings {
  static readonly MODE_UNSPECIFIED: string = SCREEN_ORIENTATION_UNSPECIFIED
  static readonly MODE_AUTO_ROTATION_UNSPECIFIED: string =
    SCREEN_ORIENTATION_AUTO_ROTATION_UNSPECIFIED

  static bindWindowOrientationApplier(applier: WindowOrientationApplier): void {
    windowOrientationApplier = applier
    ScreenOrientationSettings.applyWindowOrientation()
  }

  static normalizeMode(mode: string): string {
    return mode === SCREEN_ORIENTATION_AUTO_ROTATION_UNSPECIFIED
      ? SCREEN_ORIENTATION_AUTO_ROTATION_UNSPECIFIED
      : SCREEN_ORIENTATION_UNSPECIFIED
  }

  static options(): ScreenOrientationOption[] {
    return [
      {
        label: $r('app.string.screen_orientation_unspecified'),
        mode: SCREEN_ORIENTATION_UNSPECIFIED,
      },
      {
        label: $r('app.string.screen_orientation_auto_rotation_unspecified'),
        mode: SCREEN_ORIENTATION_AUTO_ROTATION_UNSPECIFIED,
      },
    ]
  }

  static label(mode: string): ResourceStr {
    return ScreenOrientationSettings.normalizeMode(mode) ===
      SCREEN_ORIENTATION_AUTO_ROTATION_UNSPECIFIED
      ? $r('app.string.screen_orientation_auto_rotation_unspecified')
      : $r('app.string.screen_orientation_unspecified')
  }

  static apply(mode: string): void {
    connectScreenOrientation().mode = ScreenOrientationSettings.normalizeMode(mode)
    ScreenOrientationSettings.applyWindowOrientation()
  }

  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const mode: string = store.getSync(
        StorageKeys.SCREEN_ORIENTATION,
        SCREEN_ORIENTATION_UNSPECIFIED,
      ) as string
      ScreenOrientationSettings.apply(mode)
    } catch (error) {
      DiagnosticLogger.warn('settings', 'screen_orientation_restore_failed', (error as Error).message)
    }
  }

  static async setMode(context: common.UIAbilityContext, mode: string): Promise<void> {
    const normalized: string = ScreenOrientationSettings.normalizeMode(mode)
    ScreenOrientationSettings.apply(normalized)
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.SCREEN_ORIENTATION, normalized)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'screen_orientation_save_failed', (error as Error).message)
    }
  }

  private static applyWindowOrientation(): void {
    if (windowOrientationApplier === null) {
      return
    }
    windowOrientationApplier(connectScreenOrientation().mode)
  }
}
