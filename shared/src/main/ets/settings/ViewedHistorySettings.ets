import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { connectViewedHistory } from '../state/ViewedHistoryState'
import { ViewedGallery } from '../model/ViewedGallery'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import {
  ViewedHistoryCursor,
  ViewedHistoryPage,
  ViewedHistoryRepository,
} from '../storage/ViewedHistoryRepository'
import { SyncScheduler } from '../sync/SyncScheduler'

// Keep the current NextE retention size while moving the source of truth from Preferences JSON to RDB.
const MAX_HISTORY: number = 200

/**
 * Persists recently-viewed galleries in RDB. The page owns only one bounded cursor window; the shared
 * state is an invalidation signal so startup and sync never hydrate the whole retained list.
 */
export class ViewedHistorySettings {
  // Reserve every durable mutation synchronously so a delayed detail-page timer, a backup restore,
  // and a sync drain cannot reorder their RDB transactions.
  private static rdbWriteTail: Promise<void> = Promise.resolve()
  // Also protects a one-time legacy migration from racing a local RDB mutation.
  private static mutationRevision: number = 0

  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      await ViewedHistorySettings.migrateLegacyPreferences(context)
      ViewedHistorySettings.publishChanged()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'history_restore_failed', (error as Error).message)
    }
  }

  /** Record a viewed gallery: the repository dedups by gid, promotes it, and trims the active window. */
  static async add(context: common.UIAbilityContext, entry: ViewedGallery): Promise<void> {
    if (entry.gid.length === 0) {
      return
    }
    const nextEntry: ViewedGallery = entry.copy()
    ViewedHistorySettings.mutationRevision = ViewedHistorySettings.mutationRevision + 1
    await ViewedHistorySettings.persist(context, nextEntry)
  }

  static async clear(context: common.UIAbilityContext): Promise<void> {
    ViewedHistorySettings.mutationRevision = ViewedHistorySettings.mutationRevision + 1
    await ViewedHistorySettings.enqueueRdbWrite(
      (): Promise<void> => ViewedHistoryRepository.replaceAll(context, []),
    )
    await ViewedHistorySettings.deleteLegacyPreference(context)
    ViewedHistorySettings.publishChanged()
    SyncScheduler.requestAfterLocalWrite(context, 'viewed_history_clear')
  }

  /** Remove one gid without rewriting the retained history snapshot. */
  static async remove(context: common.UIAbilityContext, gid: string): Promise<boolean> {
    if (gid.length === 0) {
      return false
    }
    ViewedHistorySettings.mutationRevision = ViewedHistorySettings.mutationRevision + 1
    try {
      await ViewedHistorySettings.enqueueRdbWrite(
        async (): Promise<void> => {
          await ViewedHistoryRepository.tombstone(context, gid)
        },
      )
      ViewedHistorySettings.publishChanged()
      SyncScheduler.requestAfterLocalWrite(context, 'viewed_history_delete')
      return true
    } catch (error) {
      DiagnosticLogger.warn('settings', 'history_delete_failed', (error as Error).message)
      return false
    }
  }

  static async loadPage(
    context: common.UIAbilityContext,
    limit: number,
    cursor: ViewedHistoryCursor | null,
  ): Promise<ViewedHistoryPage> {
    await ViewedHistorySettings.flushForSync(context)
    return ViewedHistoryRepository.loadPage(context, limit, cursor)
  }

  private static async persist(
    context: common.UIAbilityContext,
    entry: ViewedGallery,
  ): Promise<void> {
    try {
      await ViewedHistorySettings.enqueueRdbWrite(async (): Promise<void> => {
        entry.time = await ViewedHistoryRepository.upsertAndTrim(context, entry, MAX_HISTORY)
      })
      ViewedHistorySettings.publishChanged()
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
    ViewedHistorySettings.publishChanged()
    SyncScheduler.requestAfterLocalWrite(context, 'viewed_history_restore_backup')
  }

  static async migrateLegacyPreferences(context: common.UIAbilityContext): Promise<void> {
    const revision: number = ViewedHistorySettings.mutationRevision
    const store: preferences.Preferences = await preferences.getPreferences(
      context,
      StorageKeys.STORE_SETTINGS,
    )
    const raw: string = store.getSync(StorageKeys.VIEWED_HISTORY, '') as string
    if (raw.length === 0) {
      return
    }
    const items: ViewedGallery[] = ViewedHistorySettings.parse(raw)
    try {
      await ViewedHistorySettings.enqueueRdbWrite(async (): Promise<void> => {
        if (revision !== ViewedHistorySettings.mutationRevision) {
          return
        }
        if (await ViewedHistoryRepository.hasPersistedState(context)) {
          return
        }
        if (revision !== ViewedHistorySettings.mutationRevision) {
          return
        }
        if (items.length > 0) {
          await ViewedHistoryRepository.replaceAll(context, items)
        }
      })
    } catch (error) {
      DiagnosticLogger.warn('settings', 'history_migrate_failed', (error as Error).message)
      // Keep the only legacy copy intact. A later startup can retry after a transient RDB failure.
      return
    }
    if (revision !== ViewedHistorySettings.mutationRevision) {
      return
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

  private static publishChanged(): void {
    const state = connectViewedHistory()
    state.revision = state.revision + 1
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
