import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import {
  connectGalleryReadProgress,
  GalleryReadProgressState,
  ReadProgressEntry,
} from '../state/GalleryReadProgressState'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { ReadProgressRepository } from '../storage/ReadProgressRepository'
import { SyncScheduler } from '../sync/SyncScheduler'
import { ReadColumnMode } from '../state/ReadModeState'

// eros_fe debounces the persistent write 3s after the index settles (view_state.dart) so paging
// fast doesn't hammer the store; the in-memory value updates immediately on every page change.
const FLUSH_DEBOUNCE_MS: number = 3000

/**
 * Persists per-gallery reading progress + is the single writer of GalleryReadProgressState.
 *
 * Two-tier, mirroring eros_fe (view_state `ever`+`debounce` over GalleryCacheController.setIndex):
 *   • setIndex(): update the in-memory holder NOW (so the detail READ button reflects it at once),
 *     then (re)schedule a single debounced disk flush ~3s later.
 *   • flush(): persist immediately + cancel the pending timer — called when the reader closes so the
 *     last page is never lost to an unfired debounce.
 * RDB is the durable source; the settings layer keeps only the latest unflushed record for each gid.
 */
export class GalleryReadProgressSettings {
  private static flushTimer: number = -1
  // One latest durable snapshot per gid. This remains tiny during ordinary reading (one active
  // gallery) and prevents a page turn from serially rewriting every historical progress row.
  private static dirtyEntries: Map<string, ReadProgressEntry> = new Map<string, ReadProgressEntry>()
  // Keep every RDB mutation ordered. In particular, a backup restore must not be overtaken by a
  // saveEntries() batch that had already started when the restore UI was opened.
  private static rdbWriteTail: Promise<void> = Promise.resolve()

  static async restore(context: common.UIAbilityContext): Promise<void> {
    const state = connectGalleryReadProgress()
    const revision: number = state.revision
    try {
      await GalleryReadProgressSettings.migrateLegacyPreferences(context)
      const entries: ReadProgressEntry[] = await ReadProgressRepository.load(context)
      // A reader mutation while hydration was awaiting RDB is newer than this load. Do not replace
      // it with the stale snapshot; the pending persistence path will carry it to disk.
      if (state.revision === revision) {
        state.replaceAll(entries)
      }
    } catch (error) {
      DiagnosticLogger.warn('settings', 'readprogress_restore_failed', (error as Error).message)
    }
  }

  /** Record the current page for a gallery: memory now, disk on a debounce. */
  static setIndex(context: common.UIAbilityContext, gid: string, index: number): void {
    if (gid.length === 0 || index < 0) {
      return
    }
    const state = connectGalleryReadProgress()
    state.setIndex(gid, index, Date.now())
    GalleryReadProgressSettings.markDirty(state, gid)
    GalleryReadProgressSettings.schedulePersist(context)
  }

  static setColumnMode(context: common.UIAbilityContext, gid: string, columnMode: string): void {
    if (
      gid.length === 0 ||
      (columnMode !== ReadColumnMode.ODD_LEFT && columnMode !== ReadColumnMode.EVEN_LEFT)
    ) {
      return
    }
    const state = connectGalleryReadProgress()
    state.setColumnMode(gid, columnMode, Date.now())
    GalleryReadProgressSettings.markDirty(state, gid)
    GalleryReadProgressSettings.schedulePersist(context)
  }

  /** Force-persist now (reader exit) so a pending debounced write isn't lost. */
  static flush(context: common.UIAbilityContext): void {
    if (GalleryReadProgressSettings.flushTimer >= 0) {
      clearTimeout(GalleryReadProgressSettings.flushTimer)
      GalleryReadProgressSettings.flushTimer = -1
    }
    GalleryReadProgressSettings.persist(context)
  }

  /** Persist active reader state before a sync without scheduling that same provider again. */
  static async flushForSync(context: common.UIAbilityContext): Promise<void> {
    if (GalleryReadProgressSettings.flushTimer >= 0) {
      clearTimeout(GalleryReadProgressSettings.flushTimer)
      GalleryReadProgressSettings.flushTimer = -1
    }
    await GalleryReadProgressSettings.persist(context, false)
  }

  /**
   * Reload progress after a provider writes RDB rows, preserving only mutations that happened while
   * the refresh was awaiting storage. This keeps remote updates for untouched galleries intact.
   */
  static async refreshAfterSync(context: common.UIAbilityContext): Promise<void> {
    const state = connectGalleryReadProgress()
    const before: ReadProgressEntry[] = state.snapshot()
    try {
      await GalleryReadProgressSettings.flushForSync(context)
      const stored: ReadProgressEntry[] = await ReadProgressRepository.load(context)
      const changedWhileRefreshing: ReadProgressEntry[] =
        GalleryReadProgressSettings.entriesChangedSince(before, state.snapshot())
      state.replaceAll(stored)
      state.mergeNewest(changedWhileRefreshing)
    } catch (error) {
      DiagnosticLogger.warn('settings', 'readprogress_sync_refresh_failed', (error as Error).message)
    }
  }

  private static async persist(
    context: common.UIAbilityContext,
    scheduleSync: boolean = true,
  ): Promise<void> {
    const state = connectGalleryReadProgress()
    const entries: ReadProgressEntry[] = GalleryReadProgressSettings.dirtySnapshot()
    if (entries.length === 0) {
      return
    }
    try {
      await GalleryReadProgressSettings.enqueueRdbWrite(async (): Promise<void> => {
        const persisted: ReadProgressEntry[] = await ReadProgressRepository.saveEntries(context, entries)
        // Do this in the queued work, after a successful SQL write. A newer page turn may have
        // replaced this gid in dirtyEntries while the batch was awaiting RDB; leave that newer
        // entry alone so its already-scheduled flush receives its own logical timestamp.
        GalleryReadProgressSettings.reconcilePersisted(state, entries, persisted)
      })
      if (scheduleSync) {
        SyncScheduler.requestAfterLocalWrite(context, 'read_progress')
      }
    } catch (error) {
      DiagnosticLogger.warn('settings', 'readprogress_save_failed', (error as Error).message)
    }
  }

  private static markDirty(state: GalleryReadProgressState, gid: string): void {
    const entry: ReadProgressEntry | null = state.getEntry(gid)
    if (entry !== null) {
      GalleryReadProgressSettings.dirtyEntries.set(gid, entry)
    }
  }

  private static schedulePersist(context: common.UIAbilityContext): void {
    if (GalleryReadProgressSettings.flushTimer >= 0) {
      clearTimeout(GalleryReadProgressSettings.flushTimer)
    }
    GalleryReadProgressSettings.flushTimer = setTimeout(() => {
      GalleryReadProgressSettings.flushTimer = -1
      GalleryReadProgressSettings.persist(context)
    }, FLUSH_DEBOUNCE_MS)
  }

  private static dirtySnapshot(): ReadProgressEntry[] {
    const out: ReadProgressEntry[] = []
    GalleryReadProgressSettings.dirtyEntries.forEach((entry: ReadProgressEntry) => {
      out.push(new ReadProgressEntry(entry.g, entry.i, entry.t, entry.c))
    })
    return out
  }

  /**
   * Keep the in-memory clock aligned with the timestamp RDB actually accepted. A dirty record is
   * removed only when it is the same mutation that was written; a newer page turn remains dirty
   * and its existing debounce will write it after this batch.
   */
  private static reconcilePersisted(
    state: GalleryReadProgressState,
    requested: ReadProgressEntry[],
    persisted: ReadProgressEntry[],
  ): void {
    const requestedTimes: Map<string, number> = new Map<string, number>()
    requested.forEach((entry: ReadProgressEntry) => requestedTimes.set(entry.g, entry.t))
    persisted.forEach((entry: ReadProgressEntry) => {
      const requestedTime: number | undefined = requestedTimes.get(entry.g)
      if (requestedTime === undefined) {
        return
      }
      const current: ReadProgressEntry | undefined =
        GalleryReadProgressSettings.dirtyEntries.get(entry.g)
      if (current !== undefined && current.t === requestedTime) {
        const adopted: ReadProgressEntry | null = state.adoptPersistedTimestamp(entry.g, entry.t)
        if (adopted !== null) {
          // The page/pairing stays unchanged; only its durable logical clock was rebased.
          GalleryReadProgressSettings.dirtyEntries.delete(entry.g)
        }
      }
    })
  }

  /**
   * Serialize RDB writes while allowing a rejected write to be followed by recovery work. Calling
   * this synchronously reserves the operation's position, so restoreBackup() cannot race an
   * already-snapshotted dirty batch.
   */
  private static enqueueRdbWrite(work: () => Promise<void>): Promise<void> {
    const next: Promise<void> = GalleryReadProgressSettings.rdbWriteTail.then(
      (): Promise<void> => work(),
      (): Promise<void> => work(),
    )
    GalleryReadProgressSettings.rdbWriteTail = next
    return next
  }

  private static entriesChangedSince(
    before: ReadProgressEntry[],
    current: ReadProgressEntry[],
  ): ReadProgressEntry[] {
    const previousTimes: Map<string, number> = new Map<string, number>()
    before.forEach((entry: ReadProgressEntry) => previousTimes.set(entry.g, entry.t))
    const changed: ReadProgressEntry[] = []
    current.forEach((entry: ReadProgressEntry) => {
      const previous: number | undefined = previousTimes.get(entry.g)
      if (previous === undefined || entry.t > previous) {
        changed.push(entry)
      }
    })
    return changed
  }

  static async exportForBackup(context: common.UIAbilityContext): Promise<ReadProgressEntry[]> {
    await GalleryReadProgressSettings.migrateLegacyPreferences(context)
    await GalleryReadProgressSettings.flushForSync(context)
    return ReadProgressRepository.load(context)
  }

  static async restoreBackup(context: common.UIAbilityContext, entries: ReadProgressEntry[]): Promise<void> {
    const state = connectGalleryReadProgress()
    const before: ReadProgressEntry[] = state.snapshot()
    const pendingBeforeRestore: ReadProgressEntry[] = GalleryReadProgressSettings.dirtySnapshot()
    GalleryReadProgressSettings.clearPending()
    let restoredAt: number = 0
    try {
      await GalleryReadProgressSettings.enqueueRdbWrite(async (): Promise<void> => {
        restoredAt = await ReadProgressRepository.replaceAll(context, entries)
      })
    } catch (error) {
      // replaceAll is transactional, but a failed restore must not strand the entries that were
      // waiting for its debounce. Prefer any page turn that happened after the restore started.
      GalleryReadProgressSettings.mergeDirtyEntries(pendingBeforeRestore)
      if (GalleryReadProgressSettings.dirtyEntries.size > 0) {
        GalleryReadProgressSettings.schedulePersist(context)
      }
      throw error as Error
    }
    await GalleryReadProgressSettings.deleteLegacyPreference(context)
    const stored: ReadProgressEntry[] = await ReadProgressRepository.load(context)
    const changedWhileRestoring: ReadProgressEntry[] =
      GalleryReadProgressSettings.entriesChangedSince(before, state.snapshot())
    const rebasedChanges: ReadProgressEntry[] =
      GalleryReadProgressSettings.rebaseAfterRestore(stored, changedWhileRestoring, restoredAt)
    // A successful restore intentionally discards progress that existed before it started, but
    // retains actual reader input that arrived while the restore was awaiting RDB. Those changes
    // must receive a newer timestamp than this restore's tombstone and backup rows.
    GalleryReadProgressSettings.dirtyEntries.clear()
    state.replaceAll(stored)
    state.mergeNewest(rebasedChanges)
    rebasedChanges.forEach((entry: ReadProgressEntry) => {
      GalleryReadProgressSettings.markDirty(state, entry.g)
    })
    await GalleryReadProgressSettings.persist(context, false)
    if (GalleryReadProgressSettings.dirtyEntries.size > 0) {
      GalleryReadProgressSettings.schedulePersist(context)
    }
    SyncScheduler.requestAfterLocalWrite(context, 'read_progress_restore_backup')
  }

  private static clearPending(): void {
    if (GalleryReadProgressSettings.flushTimer >= 0) {
      clearTimeout(GalleryReadProgressSettings.flushTimer)
      GalleryReadProgressSettings.flushTimer = -1
    }
    GalleryReadProgressSettings.dirtyEntries.clear()
  }

  /** Restore previously pending records after a failed backup transaction without replacing newer turns. */
  private static mergeDirtyEntries(entries: ReadProgressEntry[]): void {
    entries.forEach((entry: ReadProgressEntry) => {
      const current: ReadProgressEntry | undefined = GalleryReadProgressSettings.dirtyEntries.get(entry.g)
      if (current === undefined || current.t <= entry.t) {
        GalleryReadProgressSettings.dirtyEntries.set(
          entry.g,
          new ReadProgressEntry(entry.g, entry.i, entry.t, entry.c),
        )
      }
    })
  }

  /**
   * A local page turn during backup restore happened later in wall-clock order, but its original
   * timestamp can still be older than a restored backup row or the replacement tombstone. Rebase
   * it above both so SQL newest-wins and the live state agree after the next dirty flush.
   */
  private static rebaseAfterRestore(
    stored: ReadProgressEntry[],
    changed: ReadProgressEntry[],
    restoredAt: number,
  ): ReadProgressEntry[] {
    let nextTime: number = Math.max(Date.now(), restoredAt)
    stored.forEach((entry: ReadProgressEntry) => {
      nextTime = Math.max(nextTime, entry.t)
    })
    changed.forEach((entry: ReadProgressEntry) => {
      nextTime = Math.max(nextTime, entry.t)
    })
    nextTime = nextTime + 1
    const rebased: ReadProgressEntry[] = []
    changed.forEach((entry: ReadProgressEntry) => {
      rebased.push(new ReadProgressEntry(entry.g, entry.i, nextTime, entry.c))
      nextTime = nextTime + 1
    })
    return rebased
  }

  static async migrateLegacyPreferences(context: common.UIAbilityContext): Promise<void> {
    const state = connectGalleryReadProgress()
    const revision: number = state.revision
    const store: preferences.Preferences = await preferences.getPreferences(
      context,
      StorageKeys.STORE_SETTINGS,
    )
    const raw: string = store.getSync(StorageKeys.READING_PROGRESS, '') as string
    if (raw.length === 0) {
      return
    }
    const entries: ReadProgressEntry[] = GalleryReadProgressSettings.parse(raw)
    try {
      await GalleryReadProgressSettings.enqueueRdbWrite(async (): Promise<void> => {
        if (state.revision !== revision) {
          return
        }
        if (await ReadProgressRepository.hasPersistedState(context)) {
          return
        }
        if (state.revision !== revision) {
          return
        }
        if (entries.length > 0) {
          await ReadProgressRepository.saveAll(context, entries)
        }
      })
    } catch (error) {
      DiagnosticLogger.warn('settings', 'readprogress_migrate_failed', (error as Error).message)
      // Preserve the only legacy copy so a later startup can retry after a transient RDB failure.
      return
    }
    if (state.revision !== revision) {
      return
    }
    await GalleryReadProgressSettings.deleteLegacyPreference(context)
  }

  private static async deleteLegacyPreference(context: common.UIAbilityContext): Promise<void> {
    const store: preferences.Preferences = await preferences.getPreferences(
      context,
      StorageKeys.STORE_SETTINGS,
    )
    store.deleteSync(StorageKeys.READING_PROGRESS)
    store.flushSync()
  }

  private static parse(raw: string): ReadProgressEntry[] {
    const out: ReadProgressEntry[] = []
    try {
      const arr: Object = JSON.parse(raw) as Object
      if (Array.isArray(arr)) {
        ;(arr as Object[]).forEach((v: Object) => {
          const rec = v as ReadProgressEntry
          if (
            rec !== null &&
            typeof rec.g === 'string' &&
            rec.g.length > 0 &&
            typeof rec.i === 'number' &&
            rec.i >= 0
          ) {
            const columnMode: string = typeof rec.c === 'string' ? rec.c : ''
            out.push(new ReadProgressEntry(rec.g, rec.i, typeof rec.t === 'number' ? rec.t : 0, columnMode))
          }
        })
      }
    } catch (error) {
      DiagnosticLogger.warn('settings', 'readprogress_parse_failed', (error as Error).message)
    }
    return out
  }
}
