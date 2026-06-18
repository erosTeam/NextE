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

/** Serialized advanced-search filter (the persistable subset of SearchFilterState; not applySeq). */
export class SearchFilterSnapshot {
  scope: string = SEARCH_SCOPE_GALLERY // gallery / watched / favorite search target
  cats: number = 0 // selectedCats (SHOW bitmask)
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
 * Persists the advanced-search filters + is the single writer (besides the sheet) of SearchFilterState.
 *
 * eros_fe keeps the advanced-search profile in its persistent store; NextE's SearchFilterState was
 * in-memory only, so category / rating / page-range / toggle choices were lost on every restart. This
 * restores them at startup (SettingsBootstrap) and persists them when the sheet live-edits filters or
 * Reset clears them (both bump applySeq → GallerySearchPage.onFilterApply). Stored as one JSON object
 * under the shared settings store.
 *
 * Two DELIBERATE divergences from eros_fe (not field parity — recorded honestly):
 *  • No persisted `enableAdvanceSearch` master toggle. eros_fe restores a "configured but dormant"
 *    profile that the user arms; NextE treats "any non-default value" as active (SearchFilterState
 *    .isActive()). A restored NextE filter is live, not dormant — but it still only drives a search on
 *    an explicit submit/live edit, never auto-runs at launch (restore writes no applySeq).
 *  • The f_sr / f_sp ON gates are DERIVED from the value (minRating>=2, pages>0) rather than stored as
 *    separate booleans like eros_fe. The value IS the gate, so persisting the value persists intent.
 */
export class SearchFilterSettings {
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

  /** Persist the current filter state (called when the sheet live-edits or resets filters). */
  static async persist(context: common.UIAbilityContext): Promise<void> {
    try {
      const f = connectSearchFilter()
      const snap: SearchFilterSnapshot = new SearchFilterSnapshot()
      snap.scope = SearchFilterSettings.sanitizeScope(f.searchScope)
      snap.cats = f.selectedCats
      snap.rating = f.minRating
      snap.pf = f.pagesFrom
      snap.pt = f.pagesTo
      snap.torrent = f.requireTorrent
      snap.expunged = f.showExpunged
      snap.sfl = f.disableLanguageFilter
      snap.sfu = f.disableUploaderFilter
      snap.sft = f.disableTagFilter
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.SEARCH_FILTER, JSON.stringify(snap))
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'searchfilter_save_failed', (error as Error).message)
    }
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
