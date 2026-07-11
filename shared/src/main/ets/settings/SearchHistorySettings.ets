import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { connectSearchHistory } from '../state/SearchHistoryState'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { SearchHistoryRepository } from '../storage/SearchHistoryRepository'
import { SyncScheduler } from '../sync/SyncScheduler'

const MAX_HISTORY: number = 100

/** Persists recent search queries + is the single writer of SearchHistoryState. */
export class SearchHistorySettings {
  // Search submissions are intentionally fire-and-forget from the page. Keep their durable order so
  // a rapid submit/delete/clear sequence cannot let an older RDB write finish last.
  private static rdbWriteTail: Promise<void> = Promise.resolve()
  private static mutationRevision: number = 0

  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      await SearchHistorySettings.migrateLegacyPreferences(context)
      await SearchHistorySettings.refreshFromStorage(context)
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      connectSearchHistory().translateEnabled = store.getSync(
        StorageKeys.SEARCH_HISTORY_TRANSLATE,
        true,
      ) as boolean
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
    SearchHistorySettings.mutationRevision = SearchHistorySettings.mutationRevision + 1
    await SearchHistorySettings.persistAdd(context, q)
  }

  static async clear(context: common.UIAbilityContext): Promise<void> {
    connectSearchHistory().items = []
    SearchHistorySettings.mutationRevision = SearchHistorySettings.mutationRevision + 1
    await SearchHistorySettings.enqueueRdbWrite(
      (): Promise<void> => SearchHistoryRepository.replaceAll(context, []),
    )
    await SearchHistorySettings.deleteLegacyPreference(context)
    SyncScheduler.requestAfterLocalWrite(context, 'search_history_clear')
  }

  static async setTranslateEnabled(context: common.UIAbilityContext, enabled: boolean): Promise<void> {
    connectSearchHistory().translateEnabled = enabled
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.SEARCH_HISTORY_TRANSLATE, enabled)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'searchhistory_translate_save_failed', (error as Error).message)
    }
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
    SearchHistorySettings.mutationRevision = SearchHistorySettings.mutationRevision + 1
    await SearchHistorySettings.persistRemoval(context, q)
  }

  private static async persistAdd(context: common.UIAbilityContext, query: string): Promise<void> {
    try {
      await SearchHistorySettings.enqueueRdbWrite(
        async (): Promise<void> => {
          await SearchHistoryRepository.upsertAndTrim(context, query, MAX_HISTORY)
        },
      )
      SyncScheduler.requestAfterLocalWrite(context, 'search_history')
    } catch (error) {
      DiagnosticLogger.warn('settings', 'searchhistory_save_failed', (error as Error).message)
    }
  }

  static async exportForBackup(context: common.UIAbilityContext): Promise<string[]> {
    await SearchHistorySettings.migrateLegacyPreferences(context)
    await SearchHistorySettings.flushForSync(context)
    return SearchHistoryRepository.load(context, MAX_HISTORY)
  }

  static async restoreBackup(context: common.UIAbilityContext, items: string[]): Promise<void> {
    SearchHistorySettings.mutationRevision = SearchHistorySettings.mutationRevision + 1
    await SearchHistorySettings.enqueueRdbWrite(
      (): Promise<void> => SearchHistoryRepository.replaceAll(
        context,
        SearchHistorySettings.normalize(items),
      ),
    )
    await SearchHistorySettings.deleteLegacyPreference(context)
    await SearchHistorySettings.refreshFromStorage(context)
    SyncScheduler.requestAfterLocalWrite(context, 'search_history_restore_backup')
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
      await SearchHistorySettings.enqueueRdbWrite(
        (): Promise<void> => SearchHistoryRepository.replaceAll(context, items),
      )
    }
    store.deleteSync(StorageKeys.SEARCH_HISTORY)
    store.flushSync()
  }

  /** Drain queued writes before backup and sync providers read search_history. */
  static async flushForSync(_context: common.UIAbilityContext): Promise<void> {
    await SearchHistorySettings.rdbWriteTail
  }

  private static async persistRemoval(context: common.UIAbilityContext, query: string): Promise<void> {
    try {
      await SearchHistorySettings.enqueueRdbWrite(
        async (): Promise<void> => {
          await SearchHistoryRepository.tombstone(context, query)
        },
      )
      SyncScheduler.requestAfterLocalWrite(context, 'search_history')
    } catch (error) {
      DiagnosticLogger.warn('settings', 'searchhistory_remove_failed', (error as Error).message)
    }
  }

  /** A rejected write must not poison the serialized tail. */
  private static enqueueRdbWrite(work: () => Promise<void>): Promise<void> {
    const next: Promise<void> = SearchHistorySettings.rdbWriteTail.then(
      (): Promise<void> => work(),
      (): Promise<void> => work(),
    )
    SearchHistorySettings.rdbWriteTail = next
    return next
  }

  /** Avoid replacing a newer in-memory submit/delete with a stale RDB snapshot. */
  private static async refreshFromStorage(context: common.UIAbilityContext): Promise<void> {
    for (let attempt: number = 0; attempt < 2; attempt++) {
      await SearchHistorySettings.rdbWriteTail
      const revision: number = SearchHistorySettings.mutationRevision
      const items: string[] = await SearchHistoryRepository.load(context, MAX_HISTORY)
      if (revision === SearchHistorySettings.mutationRevision) {
        connectSearchHistory().items = items
        return
      }
    }
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
