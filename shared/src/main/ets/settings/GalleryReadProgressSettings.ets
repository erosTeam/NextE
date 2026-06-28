import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import {
  connectGalleryReadProgress,
  ReadProgressEntry,
} from '../state/GalleryReadProgressState'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { ReadProgressRepository } from '../storage/ReadProgressRepository'
import { HuaweiCloudSyncScheduler } from '../sync/HuaweiCloudSyncScheduler'

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
 * The map is stored as a JSON array of {g,i,t} records (ArkTS has no clean object index signature).
 */
export class GalleryReadProgressSettings {
  private static flushTimer: number = -1

  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      await GalleryReadProgressSettings.migrateLegacyPreferences(context)
      connectGalleryReadProgress().replaceAll(await ReadProgressRepository.load(context))
    } catch (error) {
      DiagnosticLogger.warn('settings', 'readprogress_restore_failed', (error as Error).message)
    }
  }

  /** Record the current page for a gallery: memory now, disk on a debounce. */
  static setIndex(context: common.UIAbilityContext, gid: string, index: number): void {
    if (gid.length === 0 || index < 0) {
      return
    }
    connectGalleryReadProgress().setIndex(gid, index, Date.now())
    if (GalleryReadProgressSettings.flushTimer >= 0) {
      clearTimeout(GalleryReadProgressSettings.flushTimer)
    }
    GalleryReadProgressSettings.flushTimer = setTimeout(() => {
      GalleryReadProgressSettings.flushTimer = -1
      GalleryReadProgressSettings.persist(context)
    }, FLUSH_DEBOUNCE_MS)
  }

  /** Force-persist now (reader exit) so a pending debounced write isn't lost. */
  static flush(context: common.UIAbilityContext): void {
    if (GalleryReadProgressSettings.flushTimer >= 0) {
      clearTimeout(GalleryReadProgressSettings.flushTimer)
      GalleryReadProgressSettings.flushTimer = -1
    }
    GalleryReadProgressSettings.persist(context)
  }

  private static async persist(context: common.UIAbilityContext): Promise<void> {
    try {
      const entries: ReadProgressEntry[] = connectGalleryReadProgress().snapshot()
      await ReadProgressRepository.saveAll(context, entries)
      HuaweiCloudSyncScheduler.requestAfterLocalWrite(context, 'read_progress')
    } catch (error) {
      DiagnosticLogger.warn('settings', 'readprogress_save_failed', (error as Error).message)
    }
  }

  static async exportForBackup(context: common.UIAbilityContext): Promise<ReadProgressEntry[]> {
    await GalleryReadProgressSettings.migrateLegacyPreferences(context)
    return ReadProgressRepository.load(context)
  }

  static async restoreBackup(context: common.UIAbilityContext, entries: ReadProgressEntry[]): Promise<void> {
    await ReadProgressRepository.replaceAll(context, entries)
    await GalleryReadProgressSettings.deleteLegacyPreference(context)
    connectGalleryReadProgress().replaceAll(await ReadProgressRepository.load(context))
    HuaweiCloudSyncScheduler.requestAfterLocalWrite(context, 'read_progress_restore_backup')
  }

  static async migrateLegacyPreferences(context: common.UIAbilityContext): Promise<void> {
    const store: preferences.Preferences = await preferences.getPreferences(
      context,
      StorageKeys.STORE_SETTINGS,
    )
    const raw: string = store.getSync(StorageKeys.READING_PROGRESS, '') as string
    if (raw.length === 0) {
      return
    }
    const entries: ReadProgressEntry[] = GalleryReadProgressSettings.parse(raw)
    if (entries.length > 0) {
      await ReadProgressRepository.saveAll(context, entries)
    }
    store.deleteSync(StorageKeys.READING_PROGRESS)
    store.flushSync()
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
            out.push(new ReadProgressEntry(rec.g, rec.i, typeof rec.t === 'number' ? rec.t : 0))
          }
        })
      }
    } catch (error) {
      DiagnosticLogger.warn('settings', 'readprogress_parse_failed', (error as Error).message)
    }
    return out
  }
}
