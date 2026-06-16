import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { connectSearchHistory } from '../state/SearchHistoryState'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'

const MAX_HISTORY: number = 20

/** Persists recent search queries + is the single writer of SearchHistoryState. */
export class SearchHistorySettings {
  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const raw: string = store.getSync(StorageKeys.SEARCH_HISTORY, '[]') as string
      connectSearchHistory().items = SearchHistorySettings.parse(raw)
    } catch (error) {
      DiagnosticLogger.warn('settings', 'searchhistory_restore_failed', (error as Error).message)
    }
  }

  /** Record a query: dedup (move-to-front), cap to MAX_HISTORY, persist. No-op for blank input. */
  static async add(context: common.UIAbilityContext, query: string): Promise<void> {
    const q: string = query.trim()
    if (q.length === 0) {
      return
    }
    const state = connectSearchHistory()
    const next: string[] = [q]
    state.items.forEach((item: string) => {
      if (item !== q && next.length < MAX_HISTORY) {
        next.push(item)
      }
    })
    state.items = next
    await SearchHistorySettings.persist(context, next)
  }

  static async clear(context: common.UIAbilityContext): Promise<void> {
    connectSearchHistory().items = []
    await SearchHistorySettings.persist(context, [])
  }

  private static async persist(context: common.UIAbilityContext, items: string[]): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.SEARCH_HISTORY, JSON.stringify(items))
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'searchhistory_save_failed', (error as Error).message)
    }
  }

  private static parse(raw: string): string[] {
    try {
      const arr: Object = JSON.parse(raw) as Object
      if (Array.isArray(arr)) {
        const out: string[] = []
        ;(arr as Object[]).forEach((v: Object) => {
          if (typeof v === 'string' && (v as string).length > 0) {
            out.push(v as string)
          }
        })
        return out
      }
    } catch (error) {
      DiagnosticLogger.warn('settings', 'searchhistory_parse_failed', (error as Error).message)
    }
    return []
  }
}
