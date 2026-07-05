import { AppStorageV2 } from '@kit.ArkUI'

/**
 * Recent search queries (most-recent-first), shown as tappable chips on the search empty state.
 * Restored from preferences (SearchHistorySettings) at startup; SearchHistorySettings is the
 * single writer.
 */
@ObservedV2
export class SearchHistoryState {
  @Trace items: string[] = []
  @Trace translateEnabled: boolean = true
}

const SEARCH_HISTORY_KEY: string = 'v2:searchHistory'

export function connectSearchHistory(): SearchHistoryState {
  return AppStorageV2.connect(
    SearchHistoryState,
    SEARCH_HISTORY_KEY,
    () => new SearchHistoryState(),
  )!
}
