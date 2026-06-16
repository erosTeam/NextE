import { AppStorageV2 } from '@kit.ArkUI'

/**
 * V2 bus for the table-site search (ported from V2Next), stored under `'v2:searchAction'`. The
 * title-bar search field (hosted in the HDS title bar — a separate ComponentContent tree) and the
 * `@ComponentV2` GallerySearchPage both connect to this one singleton, which is how they stay in
 * sync across the two trees.
 *
 * - `keyword`: the live query text. The title-bar field is the primary writer (one write per
 *   keystroke); the page reads it on submit. `@Trace` so both trees react.
 * - `submitSeq`: a monotonically increasing submit signal. The field bumps it on Enter / search
 *   button; the page reacts via `@Monitor('actionState.submitSeq')` to run the remote search. The
 *   value is meaningless — it only guarantees a change so the bus refires for a repeated submit
 *   (replaces the old `Date.now()`-prefixed string hack).
 * - `seedSeq`: one-shot "pull keyword into the displayed field" signal. The field must NOT read
 *   `keyword` in build() (typing writes keyword every keystroke, which would rebuild the title-bar
 *   ComponentContent subtree and re-mount the Search, flapping the IME). Instead, when the page
 *   seeds a query (future: history chip / pending request / reset) it bumps seedSeq and the field
 *   reacts via `@Monitor` to pull the new keyword once.
 * - `pendingQuery`: a cross-page "search for X" request (e.g. tapping a tag on the detail page);
 *   reserved for when that wiring lands. `<token>:<query>` form so a repeated request still fires.
 */
@ObservedV2
export class SearchActionState {
  @Trace keyword: string = ''
  @Trace submitSeq: number = 0
  @Trace seedSeq: number = 0
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

const SEARCH_ACTION_V2_KEY: string = 'v2:searchAction'

/** Returns the app-wide SearchActionState singleton from AppStorageV2. */
export function connectSearchAction(): SearchActionState {
  return AppStorageV2.connect(SearchActionState, SEARCH_ACTION_V2_KEY, () => new SearchActionState())!
}
