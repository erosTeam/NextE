import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { connectSearchHistory } from '../state/SearchHistoryState'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { SearchHistoryRepository } from '../storage/SearchHistoryRepository'
import { HuaweiCloudSyncScheduler } from '../sync/HuaweiCloudSyncScheduler'

const MAX_HISTORY: number = 100

/** Persists recent search queries + is the single writer of SearchHistoryState. */
export class SearchHistorySettings {
  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      await SearchHistorySettings.migrateLegacyPreferences(context)
      connectSearchHistory().items = await SearchHistoryRepository.load(context, MAX_HISTORY)
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
    await SearchHistoryRepository.replaceAll(context, [])
    await SearchHistorySettings.deleteLegacyPreference(context)
    HuaweiCloudSyncScheduler.requestAfterLocalWrite(context, 'search_history_clear')
  }

  /** Remove one query from history, preserving the rest in order. */
  static async remove(context: common.UIAbilityContext, query: string): Promise<void> {
    const q: string = query.trim()
    if (q.length === 0) {
      return
    }
    const next: string[] = []
    connectSearchHistory().items.forEach((item: string) => {
      if (item !== q && next.length < MAX_HISTORY) {
        next.push(item)
      }
    })
    connectSearchHistory().items = next
    await SearchHistorySettings.persist(context, next)
  }

  private static async persist(context: common.UIAbilityContext, items: string[]): Promise<void> {
    try {
      await SearchHistoryRepository.replaceAll(context, items)
      HuaweiCloudSyncScheduler.requestAfterLocalWrite(context, 'search_history')
    } catch (error) {
      DiagnosticLogger.warn('settings', 'searchhistory_save_failed', (error as Error).message)
    }
  }

  static async exportForBackup(context: common.UIAbilityContext): Promise<string[]> {
    await SearchHistorySettings.migrateLegacyPreferences(context)
    return SearchHistoryRepository.load(context, MAX_HISTORY)
  }

  static async restoreBackup(context: common.UIAbilityContext, items: string[]): Promise<void> {
    await SearchHistoryRepository.replaceAll(context, SearchHistorySettings.normalize(items))
    await SearchHistorySettings.deleteLegacyPreference(context)
    connectSearchHistory().items = await SearchHistoryRepository.load(context, MAX_HISTORY)
    HuaweiCloudSyncScheduler.requestAfterLocalWrite(context, 'search_history_restore_backup')
  }

  static async migrateLegacyPreferences(context: common.UIAbilityContext): Promise<void> {
    const store: preferences.Preferences = await preferences.getPreferences(
      context,
      StorageKeys.STORE_SETTINGS,
    )
    const raw: string = store.getSync(StorageKeys.SEARCH_HISTORY, '') as string
    if (raw.length === 0) {
      return
    }
    const items: string[] = SearchHistorySettings.parse(raw)
    if (items.length > 0) {
      await SearchHistoryRepository.replaceAll(context, items)
    }
    store.deleteSync(StorageKeys.SEARCH_HISTORY)
    store.flushSync()
  }

  private static parse(raw: string): string[] {
    try {
      const arr: Object = JSON.parse(raw) as Object
      if (Array.isArray(arr)) {
        const out: string[] = []
        ;(arr as Object[]).forEach((v: Object) => {
          if (typeof v === 'string' && (v as string).length > 0 && out.length < MAX_HISTORY) {
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

  private static normalize(items: string[]): string[] {
    const out: string[] = []
    items.forEach((item: string) => {
      const query: string = item.trim()
      if (query.length > 0 && out.indexOf(query) < 0 && out.length < MAX_HISTORY) {
        out.push(query)
      }
    })
    return out
  }

  private static async deleteLegacyPreference(context: common.UIAbilityContext): Promise<void> {
    const store: preferences.Preferences = await preferences.getPreferences(
      context,
      StorageKeys.STORE_SETTINGS,
    )
    store.deleteSync(StorageKeys.SEARCH_HISTORY)
    store.flushSync()
  }
}
