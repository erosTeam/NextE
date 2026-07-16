import { AppStorageV2 } from '@kit.ArkUI'

/** All 10 EH category bits OR'd together (Misc..Western = 1+2+…+512). */
const ALL_CATS: number = 1023
export const SEARCH_SCOPE_GALLERY: string = 'gallery'
export const SEARCH_SCOPE_WATCHED: string = 'watched'
export const SEARCH_SCOPE_FAVORITE: string = 'favorite'

/**
 * Persisted advanced filters, shared between the filter sheet (writer) and SearchViewModel (reader).
 * Search scope is intentionally page-session state, because stacked Search routes must not overwrite
 * each other's endpoint. `selectedCats` is the bitmask of categories to SHOW (0 or all = no category filter);
 * EH's `f_cats` is the EXCLUDE mask, so fCats() inverts. `advancedEnabled` is the explicit master
 * switch for EH's advsearch block; when false, advanced fields are remembered but not sent. `applySeq`
 * bumps on live filter changes and Reset, so the search page persists and re-runs when appropriate.
 */
@ObservedV2
export class SearchFilterState {
  @Trace selectedCats: number = 0
  @Trace advancedEnabled: boolean = false
  @Trace minRating: number = 0
  @Trace pagesFrom: number = 0
  @Trace pagesTo: number = 0
  // EH advanced toggles: f_sto (only galleries with torrents), f_sh (only expunged galleries), and eros_fe's
  // three INDEPENDENT "ignore my default <X> filter" toggles (f_sfl language / f_sfu uploader / f_sft tag).
  @Trace requireTorrent: boolean = false
  @Trace showExpunged: boolean = false
  @Trace disableLanguageFilter: boolean = false
  @Trace disableUploaderFilter: boolean = false
  @Trace disableTagFilter: boolean = false
  @Trace applySeq: number = 0

  /** EH f_cats = sum of EXCLUDED categories; 0 when nothing or everything is selected. */
  fCats(): number {
    if (this.selectedCats === 0 || this.selectedCats === ALL_CATS) {
      return 0
    }
    return ALL_CATS - this.selectedCats
  }

  isActive(): boolean {
    return (
      this.fCats() > 0 ||
      (this.advancedEnabled && this.advancedFieldsActive())
    )
  }

  advancedFieldsActive(): boolean {
    return (
      this.minRating >= 2 ||
      this.pagesFrom > 0 ||
      this.pagesTo > 0 ||
      this.requireTorrent ||
      this.showExpunged ||
      this.disableLanguageFilter ||
      this.disableUploaderFilter ||
      this.disableTagFilter
    )
  }
}

const SEARCH_FILTER_KEY: string = 'v2_searchFilter'

export function connectSearchFilter(): SearchFilterState {
  return AppStorageV2.connect(SearchFilterState, SEARCH_FILTER_KEY, () => new SearchFilterState())!
}
