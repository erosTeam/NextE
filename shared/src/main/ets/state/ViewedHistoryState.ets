import { AppStorageV2 } from '@kit.ArkUI'

/**
 * Lightweight invalidation signal for the RDB-backed viewed-history list. Rows stay page-owned in a
 * stable LazyForEach data source; startup and sync no longer hydrate all history into AppStorageV2.
 */
@ObservedV2
export class ViewedHistoryState {
  @Trace revision: number = 0
}

const VIEWED_HISTORY_KEY: string = 'v2_viewedHistory'

export function connectViewedHistory(): ViewedHistoryState {
  return AppStorageV2.connect(ViewedHistoryState, VIEWED_HISTORY_KEY, () => new ViewedHistoryState())!
}
