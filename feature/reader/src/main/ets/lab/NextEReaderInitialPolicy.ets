import { ReaderDisplayPolicy } from '@reader-kit/core'
import { ReadModeState, ReadMode, ReadColumnMode, ReadSpreadLayout } from 'shared'

/** Canonical host values only; the shared map owns pairing and source anchors. */
export class NextEReaderInitialPolicy {
  static resolve(state: ReadModeState, column: string,
    layoutOverride: string | null = null, directionOverride: string | null = null): ReaderDisplayPolicy {
    const policy = new ReaderDisplayPolicy()
    const horizontal = state.mode === ReadMode.LTR || state.mode === ReadMode.RTL
    policy.layout = state.mode === ReadMode.VERTICAL ? 'continuous' :
      horizontal && state.doublePageEnabled ? 'spread' : 'single'
    policy.pagingAxis = state.mode === ReadMode.TOP_TO_BOTTOM ? 'vertical' : 'horizontal'
    policy.direction = state.mode === ReadMode.RTL ? 'rtl' : 'ltr'
    policy.spreadLayout = state.spreadLayoutMode === ReadSpreadLayout.SPLIT ? 'split' : 'joined'
    policy.firstPageAlone = column === ReadColumnMode.EVEN_LEFT
    if (layoutOverride === 'continuous') {
      policy.layout = 'continuous'
      policy.pagingAxis = 'vertical'
    } else if (layoutOverride === 'single' || layoutOverride === 'spread') {
      policy.layout = layoutOverride
      policy.pagingAxis = 'horizontal'
    }
    if (directionOverride === 'ltr' || directionOverride === 'rtl') {
      policy.direction = directionOverride
    }
    return policy
  }
}
