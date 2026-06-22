import { AppStorageV2 } from '@kit.ArkUI'

/**
 * Reactive carrier for the floating action-button alignment mode (ported from V2Next
 * MotionReplyAlignmentState — "智感握姿"). `alignmentMode` is the user's chosen mode
 * (smartGrip / followOperation / fixedLeft / fixedRight, '' = unset → resolved default);
 * `holdingHandSupported` is whether this device's @kit.MultimodalAwarenessKit motion grip
 * detection subscription succeeded (drives whether the smartGrip option is offered).
 *
 * Seeded by ActionAlignmentSettings at startup; MotionHandStateService resolves it into a
 * concrete left/right edge (ActionHandEdgeState). The settings page is the only writer of mode.
 */
@ObservedV2
export class ActionAlignmentState {
  @Trace alignmentMode: string = ''
  @Trace holdingHandSupported: boolean = false
}

const ACTION_ALIGNMENT_V2_KEY: string = 'v2:actionAlignment'

export function connectActionAlignment(): ActionAlignmentState {
  return AppStorageV2.connect(
    ActionAlignmentState,
    ACTION_ALIGNMENT_V2_KEY,
    () => new ActionAlignmentState(),
  )!
}
