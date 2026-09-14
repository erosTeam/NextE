import { ReaderDisplayPolicy } from '@reader-kit/core'
import { ReadModeState, ReadMode, ReadColumnMode, ReadSpreadLayout } from 'shared'
import { NextEReaderHostRequest } from './NextEReaderHostRequest'

/** Canonical host values only; the shared map owns pairing and source anchors. */
export class NextEReaderInitialPolicy {
  static resolve(state: ReadModeState, column: string, request: NextEReaderHostRequest): ReaderDisplayPolicy {
    const policy = new ReaderDisplayPolicy()
    const horizontal = state.mode === ReadMode.LTR || state.mode === ReadMode.RTL
    policy.layout = state.mode === ReadMode.VERTICAL ? 'continuous' :
      horizontal && state.doublePageEnabled ? 'spread' : 'single'
    policy.pagingAxis = state.mode === ReadMode.TOP_TO_BOTTOM ? 'vertical' : 'horizontal'
    policy.direction = state.mode === ReadMode.RTL ? 'rtl' : 'ltr'
    policy.spreadLayout = state.spreadLayoutMode === ReadSpreadLayout.SPLIT ? 'split' : 'joined'
    policy.firstPageAlone = column === ReadColumnMode.EVEN_LEFT
    if (request.entryLayoutOverride === 'continuous') {
      policy.layout = 'continuous'
      policy.pagingAxis = 'vertical'
    } else if (request.entryLayoutOverride === 'single' || request.entryLayoutOverride === 'spread') {
      policy.layout = request.entryLayoutOverride
      policy.pagingAxis = 'horizontal'
    }
    if (request.entryDirectionOverride === 'ltr' || request.entryDirectionOverride === 'rtl') {
      policy.direction = request.entryDirectionOverride
    }
    return policy
  }
}
