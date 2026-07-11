import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import {
  connectSearchFilter,
  SEARCH_SCOPE_FAVORITE,
  SEARCH_SCOPE_GALLERY,
  SEARCH_SCOPE_WATCHED,
} from '../state/SearchFilterState'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'

const SEARCH_FILTER_PERSIST_DELAY_MS: number = 250

/** Serialized advanced-search filter (the persistable subset of SearchFilterState; not applySeq). */
export class SearchFilterSnapshot {
  scope: string = SEARCH_SCOPE_GALLERY // gallery / watched / favorite search target
  cats: number = 0 // selectedCats (SHOW bitmask)
  adv: boolean = false // advancedEnabled; gates advsearch=1 and f_sr/f_sp/f_sto/f_sh/f_sf*
  rating: number = 0 // minRating
  pf: number = 0 // pagesFrom
  pt: number = 0 // pagesTo
  torrent: boolean = false // requireTorrent (f_sto)
  expunged: boolean = false // showExpunged (f_sh)
  // eros_fe's three independent "disable my default <X> filter" toggles (f_sfl/f_sfu/f_sft). `nodefault`
  // is the LEGACY collapsed key — read on restore (maps to all three) so old snapshots migrate, never
  // written anymore.
  sfl: boolean = false // disableLanguageFilter
  sfu: boolean = false // disableUploaderFilter
  sft: boolean = false // disableTagFilter
  nodefault: boolean = false // legacy all-or-none (migration read only)
}

/**
 * Coalesces text-field edits before they reach Preferences. A write already in progress is never
 * interrupted, but only the newest pending snapshot is appended after it so an older async write
 * cannot become the final persisted filter state.
 */
export class SearchFilterPersistScheduler {
  private readonly delayMs: number
  private timer: number = -1
  private pendingWrite: (() => Promise<void>) | null = null
  private writeTail: Promise<void> = Promise.resolve()

  constructor(delayMs: number = SEARCH_FILTER_PERSIST_DELAY_MS) {
    this.delayMs = delayMs >= 0 ? delayMs : 0
  }

  schedule(write: () => Promise<void>): void {
    this.pendingWrite = write
    if (this.timer >= 0) {
      clearTimeout(this.timer)
    }
    this.timer = setTimeout(() => {
      this.timer = -1
      this.flush()
    }, this.delayMs)
  }

  flush(): Promise<void> {
    if (this.timer >= 0) {
      clearTimeout(this.timer)
      this.timer = -1
    }
    const write: (() => Promise<void>) | null = this.pendingWrite
    if (write === null) {
      return this.writeTail
    }
    this.pendingWrite = null
    this.writeTail = this.writeTail.then(write, write)
    return this.writeTail
  }
}

/**
 * Persists the advanced-search filters + is the single writer (besides the sheet) of SearchFilterState.
 *
 * eros_fe keeps the advanced-search profile in its persistent store; NextE's SearchFilterState was
 * in-memory only, so category / rating / page-range / toggle choices were lost on every restart. This
 * restores them at startup (SettingsBootstrap) and persists them when the sheet live-edits filters or
 * Reset clears them (both bump applySeq → GallerySearchPage.onFilterApply). Stored as one JSON object
 * under the shared settings store.
 *
 * NextE now mirrors eros_fe's important user-facing distinction: advanced values can be configured
 * but dormant until `advancedEnabled` is on. The f_sr / f_sp ON gates are DERIVED from the value
 * (minRating>=2, pages>0) rather than stored as
 *    separate booleans like eros_fe. The value IS the gate, so persisting the value persists intent.
 */
export class SearchFilterSettings {
  private static readonly persistScheduler: SearchFilterPersistScheduler = new SearchFilterPersistScheduler()

  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const raw: string = store.getSync(StorageKeys.SEARCH_FILTER, '') as string
      if (raw.length === 0) {
        return
      }
      const snap: SearchFilterSnapshot | null = SearchFilterSettings.parse(raw)
      if (snap === null) {
        return
      }
      const f = connectSearchFilter()
      f.searchScope = snap.scope
      f.selectedCats = snap.cats
      f.advancedEnabled = snap.adv
      f.minRating = snap.rating
      f.pagesFrom = snap.pf
      f.pagesTo = snap.pt
      f.requireTorrent = snap.torrent
      f.showExpunged = snap.expunged
      // Migrate the legacy single `nodefault` (all-or-none) onto all three when no per-filter key is set.
      f.disableLanguageFilter = snap.sfl || snap.nodefault
      f.disableUploaderFilter = snap.sfu || snap.nodefault
      f.disableTagFilter = snap.sft || snap.nodefault
    } catch (error) {
      DiagnosticLogger.warn('settings', 'searchfilter_restore_failed', (error as Error).message)
    }
  }

  /** Queue the newest filter snapshot; live text edits share one durable write instead of flushing each key. */
  static persist(context: common.UIAbilityContext): void {
    const serialized: string = SearchFilterSettings.serializedCurrent()
    SearchFilterSettings.persistScheduler.schedule(
      (): Promise<void> => SearchFilterSettings.writeSerialized(context, serialized),
    )
  }

  /** Force the latest known snapshot durable before leaving the filter/search surface. */
  static async flush(context: common.UIAbilityContext): Promise<void> {
    SearchFilterSettings.persist(context)
    await SearchFilterSettings.persistScheduler.flush()
  }

  private static serializedCurrent(): string {
    const f = connectSearchFilter()
    const snap: SearchFilterSnapshot = new SearchFilterSnapshot()
    snap.scope = SearchFilterSettings.sanitizeScope(f.searchScope)
    snap.cats = f.selectedCats
    snap.adv = f.advancedEnabled
    snap.rating = f.minRating
    snap.pf = f.pagesFrom
    snap.pt = f.pagesTo
    snap.torrent = f.requireTorrent
    snap.expunged = f.showExpunged
    snap.sfl = f.disableLanguageFilter
    snap.sfu = f.disableUploaderFilter
    snap.sft = f.disableTagFilter
    return JSON.stringify(snap)
  }

  private static async writeSerialized(context: common.UIAbilityContext, serialized: string): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const existing: string = store.getSync(StorageKeys.SEARCH_FILTER, '') as string
      if (existing === serialized) {
        return
      }
      store.putSync(StorageKeys.SEARCH_FILTER, serialized)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'searchfilter_save_failed', (error as Error).message)
    }
  }

  /** Reset persisted search filters to the clean default profile and notify any open Search page. */
  static async reset(context: common.UIAbilityContext): Promise<void> {
    const f = connectSearchFilter()
    f.searchScope = SEARCH_SCOPE_GALLERY
    f.selectedCats = 0
    f.advancedEnabled = false
    f.minRating = 0
    f.pagesFrom = 0
    f.pagesTo = 0
    f.requireTorrent = false
    f.showExpunged = false
    f.disableLanguageFilter = false
    f.disableUploaderFilter = false
    f.disableTagFilter = false
    f.applySeq = f.applySeq + 1
    await SearchFilterSettings.flush(context)
  }

  /** Defensive parse: bad JSON / shape → null; bad fields → safe defaults (0 / false). */
  private static parse(raw: string): SearchFilterSnapshot | null {
    try {
      const parsed: Object = JSON.parse(raw) as Object
      // Reject a non-object blob (null / primitive / array) outright rather than silently coercing it
      // to an all-defaults snapshot that would overwrite live state.
      if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
        return null
      }
      const o = parsed as SearchFilterSnapshot
      const s: SearchFilterSnapshot = new SearchFilterSnapshot()
      s.scope = SearchFilterSettings.sanitizeScope(o.scope)
      s.cats = typeof o.cats === 'number' && o.cats >= 0 ? o.cats : 0
      s.adv = o.adv === true
      s.rating = typeof o.rating === 'number' && o.rating >= 0 ? o.rating : 0
      s.pf = typeof o.pf === 'number' && o.pf >= 0 ? o.pf : 0
      s.pt = typeof o.pt === 'number' && o.pt >= 0 ? o.pt : 0
      s.torrent = o.torrent === true
      s.expunged = o.expunged === true
      s.sfl = o.sfl === true
      s.sfu = o.sfu === true
      s.sft = o.sft === true
      s.nodefault = o.nodefault === true
      return s
    } catch (error) {
      DiagnosticLogger.warn('settings', 'searchfilter_parse_failed', (error as Error).message)
      return null
    }
  }

  private static sanitizeScope(scope: string): string {
    if (scope === SEARCH_SCOPE_WATCHED || scope === SEARCH_SCOPE_FAVORITE) {
      return scope
    }
    return SEARCH_SCOPE_GALLERY
  }
}
