import { AppStorageV2 } from '@kit.ArkUI'

/**
 * V2 bus for the table-site search (ported from V2Next), stored under `'v2_searchAction'`. The
 * title-bar search field (hosted in the HDS title bar — a separate ComponentContent tree) and the
 * `@ComponentV2` GallerySearchPage both connect to this one singleton, which is how they stay in
 * sync across the two trees.
 *
 * - `pendingQuery`: a cross-page "search for X" request (e.g. tapping a tag on the detail page);
 *   `<token>:<query>` form so a repeated request still fires. Index is the only consumer; it converts
 *   this into SearchPageParams.initialQuery. Per-page keyword/submit/filter state lives in
 *   SearchPageFieldState, not this singleton, so stacked Search pages cannot steal each other's query.
 */
@ObservedV2
export class SearchActionState {
  @Trace pendingQuery: string = ''

  /**
   * Publish a cross-page "search for X" request (Similar title, uploader, a tag). A unique numeric
   * token is prefixed so the bus refires even for a repeat of the same query; consumers strip it at
   * the FIRST ':' (the token has no colon, so any colons inside the query — e.g. `uploader:foo` or
   * `title:"a:b"` — survive intact). Single writer of pendingQuery.
   */
  publishQuery(query: string): void {
    this.pendingQuery = `${Date.now()}:${query}`
  }

  /**
   * Clear a consumed cross-page request so it does not resurrect on the next fresh search-page open
   * (mirrors V2Next's SearchQueryBus.clearPending). Without this, the search page consumes a stale
   * pendingQuery on a later plain open and auto-runs an unrelated query instead of showing history.
   */
  clearPending(): void {
    this.pendingQuery = ''
  }
}

const SEARCH_ACTION_V2_KEY: string = 'v2_searchAction'

/** Returns the app-wide SearchActionState singleton from AppStorageV2. */
export function connectSearchAction(): SearchActionState {
  return AppStorageV2.connect(SearchActionState, SEARCH_ACTION_V2_KEY, () => new SearchActionState())!
}
