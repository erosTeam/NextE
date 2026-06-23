import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import {
  connectReadButtonStyle,
  READ_BUTTON_STYLE_FILLED,
  READ_BUTTON_STYLE_HDS,
} from '../state/ReadButtonStyleState'

export interface ReadButtonStyleOption {
  label: ResourceStr
  style: string
}

/** Persists the gallery-detail floating Read button visual style. */
export class ReadButtonStyleSettings {
  static readonly STYLE_FILLED: string = READ_BUTTON_STYLE_FILLED
  static readonly STYLE_HDS: string = READ_BUTTON_STYLE_HDS

  static normalizeStyle(style: string): string {
    const value: string = (style || '').trim()
    if (value === READ_BUTTON_STYLE_HDS) {
      return READ_BUTTON_STYLE_HDS
    }
    return READ_BUTTON_STYLE_FILLED
  }

  static options(): ReadButtonStyleOption[] {
    return [
      { label: $r('app.string.read_button_style_filled'), style: READ_BUTTON_STYLE_FILLED },
      { label: $r('app.string.read_button_style_hds'), style: READ_BUTTON_STYLE_HDS },
    ]
  }

  static label(style: string): ResourceStr {
    return ReadButtonStyleSettings.normalizeStyle(style) === READ_BUTTON_STYLE_HDS
      ? $r('app.string.read_button_style_hds')
      : $r('app.string.read_button_style_filled')
  }

  static apply(style: string): void {
    connectReadButtonStyle().style = ReadButtonStyleSettings.normalizeStyle(style)
  }

  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const style: string = store.getSync(
        StorageKeys.READ_BUTTON_STYLE,
        READ_BUTTON_STYLE_FILLED,
      ) as string
      ReadButtonStyleSettings.apply(style)
    } catch (error) {
      DiagnosticLogger.warn('settings', 'read_button_style_restore_failed', (error as Error).message)
    }
  }

  static async setStyle(context: common.UIAbilityContext, style: string): Promise<void> {
    const normalized: string = ReadButtonStyleSettings.normalizeStyle(style)
    ReadButtonStyleSettings.apply(normalized)
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.READ_BUTTON_STYLE, normalized)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'read_button_style_save_failed', (error as Error).message)
    }
  }
}
