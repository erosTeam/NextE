import { AppStorageV2 } from '@kit.ArkUI'
import { ViewedGallery } from '../model/ViewedGallery'

/**
 * Recently-viewed galleries (eros_fe HistoryController), newest first. The detail page adds an entry
 * 5s after open (the debounce that keeps transient bounces out of history); ViewedHistorySettings is
 * the single writer + persistence. A `@Trace` array so a future history surface re-renders on change.
 */
@ObservedV2
export class ViewedHistoryState {
  @Trace items: ViewedGallery[] = []
}

const VIEWED_HISTORY_KEY: string = 'v2:viewedHistory'

export function connectViewedHistory(): ViewedHistoryState {
  return AppStorageV2.connect(ViewedHistoryState, VIEWED_HISTORY_KEY, () => new ViewedHistoryState())!
}
