import { AppStorageV2 } from '@kit.ArkUI'

/**
 * The RESOLVED side ('left' | 'right') the floating Read button should sit on, computed by
 * MotionHandStateService from the active alignment mode (grip detection / follow-operation /
 * fixed). Ported from V2Next MotionHandEdgeState. Default 'right' matches the prior fixed
 * bottom-right Read FAB. Single-writer (MotionHandStateService); pages observe it via @Monitor
 * and slide the button with .translate()+.animation().
 */
@ObservedV2
export class ActionHandEdgeState {
  @Trace edge: string = 'right'
}

const ACTION_HAND_EDGE_V2_KEY: string = 'v2:actionHandEdge'

export function connectActionHandEdge(): ActionHandEdgeState {
  return AppStorageV2.connect(
    ActionHandEdgeState,
    ACTION_HAND_EDGE_V2_KEY,
    () => new ActionHandEdgeState(),
  )!
}
