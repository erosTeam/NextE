import { ReaderDisplayPolicy } from '@reader-kit/core'
import { ReadModeState, ReadMode, ReadColumnMode, ReadSpreadLayout, isContinuousReadMode,
  isHorizontalContinuousReadMode } from 'shared'

/** Canonical host values only; the shared map owns pairing and source anchors. */
export class NextEReaderInitialPolicy {
  static resolve(state: ReadModeState, column: string,
    layoutOverride: string | null = null, directionOverride: string | null = null): ReaderDisplayPolicy {
    const policy = new ReaderDisplayPolicy()
    NextEReaderInitialPolicy.applyMode(policy, state.mode, state.doublePageEnabled)
    policy.spreadLayout = state.spreadLayoutMode === ReadSpreadLayout.SPLIT ? 'split' : 'joined'
    policy.firstPageAlone = column === ReadColumnMode.EVEN_LEFT
    if (layoutOverride === 'continuous') {
      policy.layout = 'continuous'
      policy.pagingAxis = 'vertical'
      policy.continuousAxis = 'vertical'
    } else if (layoutOverride === 'single' || layoutOverride === 'spread') {
      policy.layout = layoutOverride
      policy.pagingAxis = 'horizontal'
    }
    if (directionOverride === 'ltr' || directionOverride === 'rtl') {
      policy.direction = directionOverride
    }
    return policy
  }

  static applyMode(policy: ReaderDisplayPolicy, mode: string, doublePageEnabled: boolean): void {
    const pagedHorizontal = mode === ReadMode.LTR || mode === ReadMode.RTL
    policy.layout = isContinuousReadMode(mode) ? 'continuous' :
      pagedHorizontal && doublePageEnabled ? 'spread' : 'single'
    policy.pagingAxis = mode === ReadMode.TOP_TO_BOTTOM ? 'vertical' : 'horizontal'
    policy.continuousAxis = isHorizontalContinuousReadMode(mode) ? 'horizontal' : 'vertical'
    policy.direction = mode === ReadMode.RTL || mode === ReadMode.HORIZONTAL_CONTINUOUS_RTL ? 'rtl' : 'ltr'
  }

  static modeForPolicy(policy: ReaderDisplayPolicy): ReadMode {
    if (policy.layout === 'continuous') {
      if (policy.continuousAxis === 'vertical') return ReadMode.VERTICAL
      return policy.direction === 'rtl' ? ReadMode.HORIZONTAL_CONTINUOUS_RTL : ReadMode.HORIZONTAL_CONTINUOUS_LTR
    }
    if (policy.pagingAxis === 'vertical') return ReadMode.TOP_TO_BOTTOM
    return policy.direction === 'rtl' ? ReadMode.RTL : ReadMode.LTR
  }
}
