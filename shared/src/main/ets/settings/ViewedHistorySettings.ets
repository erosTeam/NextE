import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { connectViewedHistory } from '../state/ViewedHistoryState'
import { ViewedGallery } from '../model/ViewedGallery'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'

// eros_fe's history is DB-backed and effectively unbounded; NextE stores a JSON list in preferences,
// so cap it to keep the blob small. 200 recent galleries is plenty for a phone history surface.
const MAX_HISTORY: number = 200

/**
 * Persists recently-viewed galleries + is the single writer of ViewedHistoryState (eros_fe
 * HistoryController.addHistory). add() dedups by gid (move-to-front with a fresh timestamp), caps the
 * list, and persists. The 5s open-debounce lives at the call site (the detail page), matching eros_fe
 * which delays addHistory 5s after the gallery loads so a quick bounce doesn't get recorded.
 */
export class ViewedHistorySettings {
  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const raw: string = store.getSync(StorageKeys.VIEWED_HISTORY, '[]') as string
      connectViewedHistory().items = ViewedHistorySettings.parse(raw)
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
    const next: ViewedGallery[] = [entry]
    state.items.forEach((it: ViewedGallery) => {
      if (it.gid !== entry.gid && next.length < MAX_HISTORY) {
        next.push(it)
      }
    })
    state.items = next
    await ViewedHistorySettings.persist(context, next)
  }

  static async clear(context: common.UIAbilityContext): Promise<void> {
    connectViewedHistory().items = []
    await ViewedHistorySettings.persist(context, [])
  }

  private static async persist(
    context: common.UIAbilityContext,
    items: ViewedGallery[],
  ): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.VIEWED_HISTORY, JSON.stringify(items))
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'history_save_failed', (error as Error).message)
    }
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
