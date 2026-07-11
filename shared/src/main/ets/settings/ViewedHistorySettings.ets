import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { connectViewedHistory } from '../state/ViewedHistoryState'
import { ViewedGallery } from '../model/ViewedGallery'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { ViewedHistoryRepository } from '../storage/ViewedHistoryRepository'
import { SyncScheduler } from '../sync/SyncScheduler'

// Keep the current NextE retention size while moving the source of truth from Preferences JSON to RDB.
const MAX_HISTORY: number = 200

/**
 * Persists recently-viewed galleries + is the single writer of ViewedHistoryState (eros_fe
 * HistoryController.addHistory). add() dedups by gid (move-to-front with a fresh timestamp), caps the
 * list, and persists. The 5s open-debounce lives at the call site (the detail page), matching eros_fe
 * which delays addHistory 5s after the gallery loads so a quick bounce doesn't get recorded.
 */
export class ViewedHistorySettings {
  // Reserve every durable mutation synchronously so a delayed detail-page timer, a backup restore,
  // and a sync drain cannot reorder their RDB transactions.
  private static rdbWriteTail: Promise<void> = Promise.resolve()
  // A storage refresh only replaces the live list when no local history mutation raced its load.
  private static mutationRevision: number = 0

  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      await ViewedHistorySettings.migrateLegacyPreferences(context)
      await ViewedHistorySettings.refreshFromStorage(context)
    } catch (error) {
      DiagnosticLogger.warn('settings', 'history_restore_failed', (error as Error).message)
    }
  }

  /** Record a viewed gallery: dedup by gid (move to front), set its time, cap, persist. */
  static async add(context: common.UIAbilityContext, entry: ViewedGallery): Promise<void> {
    if (entry.gid.length === 0) {
      return
    }
    const state = connectViewedHistory()
    const nextEntry: ViewedGallery = entry.copy()
    nextEntry.time = ViewedHistorySettings.nextViewedAt(state.items, nextEntry.time)
    const next: ViewedGallery[] = [nextEntry]
    state.items.forEach((it: ViewedGallery) => {
      if (it.gid !== nextEntry.gid && next.length < MAX_HISTORY) {
        next.push(it)
      }
    })
    state.items = next
    ViewedHistorySettings.mutationRevision = ViewedHistorySettings.mutationRevision + 1
    await ViewedHistorySettings.persist(context, nextEntry)
  }

  static async clear(context: common.UIAbilityContext): Promise<void> {
    connectViewedHistory().items = []
    ViewedHistorySettings.mutationRevision = ViewedHistorySettings.mutationRevision + 1
    await ViewedHistorySettings.enqueueRdbWrite(
      (): Promise<void> => ViewedHistoryRepository.replaceAll(context, []),
    )
    await ViewedHistorySettings.deleteLegacyPreference(context)
    SyncScheduler.requestAfterLocalWrite(context, 'viewed_history_clear')
  }

  private static async persist(
    context: common.UIAbilityContext,
    entry: ViewedGallery,
  ): Promise<void> {
    try {
      await ViewedHistorySettings.enqueueRdbWrite(async (): Promise<void> => {
        entry.time = await ViewedHistoryRepository.upsertAndTrim(context, entry, MAX_HISTORY)
      })
      SyncScheduler.requestAfterLocalWrite(context, 'viewed_history')
    } catch (error) {
      DiagnosticLogger.warn('settings', 'history_save_failed', (error as Error).message)
    }
  }

  /** Drain queued detail writes before a provider reads the history table. */
  static async flushForSync(_context: common.UIAbilityContext): Promise<void> {
    await ViewedHistorySettings.rdbWriteTail
  }

  static async exportForBackup(context: common.UIAbilityContext): Promise<ViewedGallery[]> {
    await ViewedHistorySettings.migrateLegacyPreferences(context)
    await ViewedHistorySettings.flushForSync(context)
    return ViewedHistoryRepository.load(context, MAX_HISTORY)
  }

  static async restoreBackup(context: common.UIAbilityContext, items: ViewedGallery[]): Promise<void> {
    ViewedHistorySettings.mutationRevision = ViewedHistorySettings.mutationRevision + 1
    await ViewedHistorySettings.enqueueRdbWrite(
      (): Promise<void> => ViewedHistoryRepository.replaceAll(context, items),
    )
    await ViewedHistorySettings.deleteLegacyPreference(context)
    await ViewedHistorySettings.refreshFromStorage(context)
    SyncScheduler.requestAfterLocalWrite(context, 'viewed_history_restore_backup')
  }

  static async migrateLegacyPreferences(context: common.UIAbilityContext): Promise<void> {
    const store: preferences.Preferences = await preferences.getPreferences(
      context,
      StorageKeys.STORE_SETTINGS,
    )
    const raw: string = store.getSync(StorageKeys.VIEWED_HISTORY, '') as string
    if (raw.length === 0) {
      return
    }
    const items: ViewedGallery[] = ViewedHistorySettings.parse(raw)
    if (items.length > 0) {
      await ViewedHistorySettings.enqueueRdbWrite(
        (): Promise<void> => ViewedHistoryRepository.replaceAll(context, items),
      )
    }
    store.deleteSync(StorageKeys.VIEWED_HISTORY)
    store.flushSync()
  }

  /** A rejected write does not poison the tail: the next mutation still gets a turn. */
  private static enqueueRdbWrite(work: () => Promise<void>): Promise<void> {
    const next: Promise<void> = ViewedHistorySettings.rdbWriteTail.then(
      (): Promise<void> => work(),
      (): Promise<void> => work(),
    )
    ViewedHistorySettings.rdbWriteTail = next
    return next
  }

  /** Keep the in-memory order deterministic while the repository advances past persisted tombstones. */
  private static nextViewedAt(items: ViewedGallery[], requestedTime: number): number {
    let newest: number = 0
    items.forEach((item: ViewedGallery) => {
      newest = Math.max(newest, Math.floor(item.time))
    })
    return Math.max(Date.now(), Math.max(0, Math.floor(requestedTime)), newest + 1)
  }

  /**
   * Rehydrate only when the snapshot stayed current during its await. Retrying once lets an add that
   * landed during the first load reach RDB without replacing that newer live list with stale rows.
   */
  private static async refreshFromStorage(context: common.UIAbilityContext): Promise<void> {
    for (let attempt: number = 0; attempt < 2; attempt++) {
      await ViewedHistorySettings.rdbWriteTail
      const revision: number = ViewedHistorySettings.mutationRevision
      const items: ViewedGallery[] = await ViewedHistoryRepository.load(context, MAX_HISTORY)
      if (revision === ViewedHistorySettings.mutationRevision) {
        connectViewedHistory().items = items
        return
      }
    }
  }

  private static async deleteLegacyPreference(context: common.UIAbilityContext): Promise<void> {
    const store: preferences.Preferences = await preferences.getPreferences(
      context,
      StorageKeys.STORE_SETTINGS,
    )
    store.deleteSync(StorageKeys.VIEWED_HISTORY)
    store.flushSync()
  }

  /** Defensive parse: bad JSON / shape → []; drop records without a gid; keep newest-first order. */
  private static parse(raw: string): ViewedGallery[] {
    const out: ViewedGallery[] = []
    try {
      const arr: Object = JSON.parse(raw) as Object
      if (Array.isArray(arr)) {
        ;(arr as Object[]).forEach((v: Object) => {
          const rec = v as ViewedGallery
          if (rec !== null && typeof rec.gid === 'string' && rec.gid.length > 0) {
            const e: ViewedGallery = new ViewedGallery()
            e.gid = rec.gid
            e.token = typeof rec.token === 'string' ? rec.token : ''
            e.title = typeof rec.title === 'string' ? rec.title : ''
            e.titleJp = typeof rec.titleJp === 'string' ? rec.titleJp : ''
            e.thumbUrl = typeof rec.thumbUrl === 'string' ? rec.thumbUrl : ''
            e.category = typeof rec.category === 'string' ? rec.category : ''
            e.uploader = typeof rec.uploader === 'string' ? rec.uploader : ''
            e.rating = typeof rec.rating === 'number' ? rec.rating : 0
            e.fileCount = typeof rec.fileCount === 'string' ? rec.fileCount : ''
            e.time = typeof rec.time === 'number' ? rec.time : 0
            out.push(e)
          }
        })
      }
    } catch (error) {
      DiagnosticLogger.warn('settings', 'history_parse_failed', (error as Error).message)
    }
    return out
  }
}
