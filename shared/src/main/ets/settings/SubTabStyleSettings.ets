import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import {
  connectSubTabStyle,
  SUBTAB_STYLE_UNDERLINE,
  SUBTAB_STYLE_CAPSULE,
} from '../state/SubTabStyleState'

export interface SubTabStyleOption {
  label: ResourceStr
  style: string
}

/** Shared appearance for Home, Toplist and Favorites sub-tabs. */
export class SubTabStyleSettings {
  static isCapsule(style: string): boolean {
    return SubTabStyleSettings.normalizeStyle(style) === SUBTAB_STYLE_CAPSULE
  }

  static normalizeStyle(style: string): string {
    return (style || '').trim() === SUBTAB_STYLE_CAPSULE ? SUBTAB_STYLE_CAPSULE : SUBTAB_STYLE_UNDERLINE
  }

  static options(): SubTabStyleOption[] {
    return [
      { label: $r('app.string.subtab_style_underline'), style: SUBTAB_STYLE_UNDERLINE },
      { label: $r('app.string.subtab_style_capsule'), style: SUBTAB_STYLE_CAPSULE },
    ]
  }

  static label(style: string): ResourceStr {
    return SubTabStyleSettings.isCapsule(style)
      ? $r('app.string.subtab_style_capsule')
      : $r('app.string.subtab_style_underline')
  }

  static apply(style: string): void {
    connectSubTabStyle().style = SubTabStyleSettings.normalizeStyle(style)
  }

  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS)
      SubTabStyleSettings.apply(store.getSync(StorageKeys.SUBTAB_STYLE, SUBTAB_STYLE_UNDERLINE) as string)
    } catch (error) {
      DiagnosticLogger.warn('settings', 'subtab_style_restore_failed', (error as Error).message)
    }
  }

  static async setStyle(context: common.UIAbilityContext, style: string): Promise<void> {
    const normalized: string = SubTabStyleSettings.normalizeStyle(style)
    SubTabStyleSettings.apply(normalized)
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS)
      store.putSync(StorageKeys.SUBTAB_STYLE, normalized)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'subtab_style_save_failed', (error as Error).message)
    }
  }
}
