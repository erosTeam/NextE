import { AppStorageV2 } from '@kit.ArkUI'

/**
 * Saved search queries (eros_fe QuickSearch), newest first. Restored from preferences at startup;
 * QuickSearchSettings is the single writer.
 */
@ObservedV2
export class QuickSearchState {
  @Trace items: string[] = []
}

const QUICK_SEARCH_KEY: string = 'v2:quickSearch'

export function connectQuickSearch(): QuickSearchState {
  return AppStorageV2.connect(
    QuickSearchState,
    QUICK_SEARCH_KEY,
    () => new QuickSearchState(),
  )!
}
