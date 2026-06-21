import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { connectAppColorFavorites } from '../state/AppColorFavoritesState'

const MAX_APP_COLOR_FAVORITES: number = 36

export class AppColorFavoritesSettings {
  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const raw: string = store.getSync(StorageKeys.APP_COLOR_FAVORITES, '') as string
      if (raw.length === 0) {
        return
      }
      const colors: string[] | null = AppColorFavoritesSettings.parse(raw)
      if (colors !== null) {
        connectAppColorFavorites().colors = colors
      }
    } catch (error) {
      DiagnosticLogger.warn('settings', 'colorfavorites_restore_failed', (error as Error).message)
    }
  }

  static async persist(context: common.UIAbilityContext, colors: string[]): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.APP_COLOR_FAVORITES, JSON.stringify(AppColorFavoritesSettings.clean(colors)))
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'colorfavorites_save_failed', (error as Error).message)
    }
  }

  private static parse(raw: string): string[] | null {
    try {
      const parsed: Object = JSON.parse(raw) as Object
      if (!Array.isArray(parsed)) {
        return null
      }
      return AppColorFavoritesSettings.clean(parsed as string[])
    } catch (error) {
      DiagnosticLogger.warn('settings', 'colorfavorites_parse_failed', (error as Error).message)
      return null
    }
  }

  private static clean(colors: string[]): string[] {
    const next: string[] = []
    colors.forEach((color: string) => {
      const normalized: string = AppColorFavoritesSettings.normalizedHex(color)
      if (normalized.length > 0 && next.indexOf(normalized) < 0 && next.length < MAX_APP_COLOR_FAVORITES) {
        next.push(normalized)
      }
    })
    return next
  }

  private static normalizedHex(color: string): string {
    let c: string = color.trim()
    if (c.startsWith('#')) {
      c = c.substring(1)
    }
    if (c.length !== 6) {
      return ''
    }
    for (let i: number = 0; i < c.length; i++) {
      const code: number = c.charCodeAt(i)
      const digit: boolean = code >= 48 && code <= 57
      const upper: boolean = code >= 65 && code <= 70
      const lower: boolean = code >= 97 && code <= 102
      if (!digit && !upper && !lower) {
        return ''
      }
    }
    return `#${c.toUpperCase()}`
  }
}
