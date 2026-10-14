import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { connectQuickSearch } from '../state/QuickSearchState'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'

const MAX_QUICK_SEARCH: number = 50

/** Persists saved QuickSearch queries + is the single writer of QuickSearchState. */
export class QuickSearchSettings {
  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const raw: string = store.getSync(StorageKeys.QUICK_SEARCH, '[]') as string
      connectQuickSearch().items = QuickSearchSettings.parse(raw)
    } catch (error) {
      DiagnosticLogger.warn('settings', 'quicksearch_restore_failed', (error as Error).message)
    }
  }

  /** Save a query: dedup (move-to-front), cap to MAX_QUICK_SEARCH, persist. No-op for blank input. */
  static async add(context: common.UIAbilityContext, query: string): Promise<void> {
    const q: string = query.trim()
    if (q.length === 0) {
      return
    }
    const state = connectQuickSearch()
    const next: string[] = [q]
    state.items.forEach((item: string) => {
      if (item !== q && next.length < MAX_QUICK_SEARCH) {
        next.push(item)
      }
    })
    state.items = next
    await QuickSearchSettings.persist(context, next)
  }

  static async clear(context: common.UIAbilityContext): Promise<void> {
    connectQuickSearch().items = []
    await QuickSearchSettings.persist(context, [])
  }

  private static async persist(context: common.UIAbilityContext, items: string[]): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.QUICK_SEARCH, JSON.stringify(items))
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'quicksearch_save_failed', (error as Error).message)
    }
  }

  private static parse(raw: string): string[] {
    try {
      const arr: Object = JSON.parse(raw) as Object
      if (Array.isArray(arr)) {
        const out: string[] = []
        ;(arr as Object[]).forEach((v: Object) => {
          if (typeof v === 'string') {
            const q: string = (v as string).trim()
            if (q.length > 0 && out.length < MAX_QUICK_SEARCH) {
              out.push(q)
            }
          }
        })
        return out
      }
    } catch (error) {
      DiagnosticLogger.warn('settings', 'quicksearch_parse_failed', (error as Error).message)
    }
    return []
  }
}
