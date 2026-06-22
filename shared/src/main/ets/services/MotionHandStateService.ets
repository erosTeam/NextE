import { motion } from '@kit.MultimodalAwarenessKit'
import { BusinessError } from '@ohos.base'
import { ActionAlignmentSettings, ActionAlignmentMode } from '../settings/ActionAlignmentSettings'
import { connectActionHandEdge } from '../state/ActionHandEdgeState'
import { connectActionAlignment } from '../state/ActionAlignmentState'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'

export type MotionHandEdge = 'left' | 'right'

type StableMotionHandEdge = 'left' | 'right'

/**
 * Resolves the floating Read-button alignment mode into a concrete left/right edge, ported from V2Next
 * MotionHandStateService ("智感握姿"). Subscribes to the HarmonyOS @kit.MultimodalAwarenessKit grip
 * detector ('holdingHandChanged') for smartGrip; tracks tap X for followOperation; pins for fixed modes.
 * Single writer of ActionHandEdgeState. Grip detection is best-effort: if the device lacks it, the
 * subscription throws, holdingHandSupported flips false, and smartGrip degrades to followOperation.
 */
export class MotionHandStateService {
  private static startAttempted: boolean = false
  private static holdingSubscribed: boolean = false
  private static pendingHoldingEdge: StableMotionHandEdge | null = null
  private static debounceTimerId: number = 0
  private static lastFollowUpdateAt: number = 0
  private static readonly EDGE_DEBOUNCE_MS: number = 450
  static readonly FOLLOW_OPERATION_SAFE_ZONE_RATIO: number = 0.28
  private static readonly FOLLOW_OPERATION_THROTTLE_MS: number = 260

  private static readonly holdingChanged = (status: motion.HoldingHandStatus): void => {
    MotionHandStateService.handleHoldingStatus(status)
  }

  static start(): void {
    MotionHandStateService.ensureDefaultEdge()
    if (MotionHandStateService.startAttempted) {
      MotionHandStateService.applyAlignmentMode()
      return
    }
    MotionHandStateService.startAttempted = true

    try {
      motion.on('holdingHandChanged', MotionHandStateService.holdingChanged)
      MotionHandStateService.holdingSubscribed = true
      MotionHandStateService.setHoldingHandSupported(true)
    } catch (error) {
      MotionHandStateService.setHoldingHandSupported(false)
      MotionHandStateService.logError('subscribe holding hand', error as Error)
    }
    MotionHandStateService.applyAlignmentMode()
  }

  static stop(): void {
    if (MotionHandStateService.holdingSubscribed) {
      try {
        motion.off('holdingHandChanged', MotionHandStateService.holdingChanged)
      } catch (error) {
        MotionHandStateService.logError('unsubscribe holding hand', error as Error)
      }
      MotionHandStateService.holdingSubscribed = false
    }
    MotionHandStateService.cancelPendingEdge()
    MotionHandStateService.startAttempted = false
  }

  // Resolve the active mode into an edge. fixed modes pin immediately; smartGrip waits for a grip event;
  // followOperation waits for a tap report. A runtime-only default is written when the mode is unset.
  static applyAlignmentMode(mode?: string): void {
    const alignment = connectActionAlignment()
    if (mode !== undefined) {
      alignment.alignmentMode = ActionAlignmentSettings.normalizeMode(mode)
    }
    MotionHandStateService.ensureDefaultEdge()
    const rawMode: string = alignment.alignmentMode
    if (ActionAlignmentSettings.normalizeMode(rawMode) === ActionAlignmentSettings.MODE_UNSET) {
      alignment.alignmentMode = ActionAlignmentSettings.defaultMode(
        MotionHandStateService.isHoldingHandSupported(),
      )
    }
    const effectiveMode: ActionAlignmentMode = MotionHandStateService.effectiveAlignmentMode()
    if (effectiveMode === ActionAlignmentSettings.MODE_FIXED_LEFT) {
      MotionHandStateService.cancelPendingEdge()
      MotionHandStateService.setEdge('left')
      return
    }
    if (effectiveMode === ActionAlignmentSettings.MODE_FIXED_RIGHT) {
      MotionHandStateService.cancelPendingEdge()
      MotionHandStateService.setEdge('right')
      return
    }
    if (effectiveMode !== ActionAlignmentSettings.MODE_SMART_GRIP) {
      MotionHandStateService.cancelPendingEdge()
    }
  }

  // followOperation: a tap near the left/right edge slides the button toward that side (center safe-zone
  // is ignored so normal mid-screen taps don't fight the button). Throttled to avoid thrash.
  static reportFollowOperationX(x: number, width: number): void {
    if (
      MotionHandStateService.effectiveAlignmentMode() !==
      ActionAlignmentSettings.MODE_FOLLOW_OPERATION
    ) {
      return
    }
    const nextEdge: MotionHandEdge | null = MotionHandStateService.edgeForFollowOperationX(x, width)
    if (nextEdge === null) {
      return
    }
    const now: number = Date.now()
    if (
      MotionHandStateService.lastFollowUpdateAt > 0 &&
      now - MotionHandStateService.lastFollowUpdateAt <
        MotionHandStateService.FOLLOW_OPERATION_THROTTLE_MS &&
      connectActionHandEdge().edge !== nextEdge
    ) {
      return
    }
    MotionHandStateService.lastFollowUpdateAt = now
    if (connectActionHandEdge().edge !== nextEdge) {
      MotionHandStateService.setEdge(nextEdge)
    }
  }

  static edgeForFollowOperationX(x: number, width: number): MotionHandEdge | null {
    if (!Number.isFinite(x) || !Number.isFinite(width) || width <= 0) {
      return null
    }
    const safeHalf: number = MotionHandStateService.FOLLOW_OPERATION_SAFE_ZONE_RATIO / 2
    const leftBoundary: number = width * (0.5 - safeHalf)
    const rightBoundary: number = width * (0.5 + safeHalf)
    if (x < leftBoundary) {
      return 'left'
    }
    if (x > rightBoundary) {
      return 'right'
    }
    return null
  }

  private static effectiveAlignmentMode(): ActionAlignmentMode {
    const rawMode: string = connectActionAlignment().alignmentMode
    return ActionAlignmentSettings.effectiveMode(
      rawMode,
      MotionHandStateService.isHoldingHandSupported(),
    )
  }

  private static isHoldingHandSupported(): boolean {
    return connectActionAlignment().holdingHandSupported
  }

  private static setHoldingHandSupported(supported: boolean): void {
    connectActionAlignment().holdingHandSupported = supported
  }

  private static ensureDefaultEdge(): void {
    const current: string = connectActionHandEdge().edge
    if (current !== 'left' && current !== 'right') {
      MotionHandStateService.setEdge('right')
    }
  }

  private static handleHoldingStatus(status: motion.HoldingHandStatus): void {
    if (
      MotionHandStateService.effectiveAlignmentMode() !== ActionAlignmentSettings.MODE_SMART_GRIP
    ) {
      return
    }
    if (status === motion.HoldingHandStatus.LEFT_HAND_HELD) {
      MotionHandStateService.scheduleHoldingEdge('left')
      return
    }
    if (status === motion.HoldingHandStatus.RIGHT_HAND_HELD) {
      MotionHandStateService.scheduleHoldingEdge('right')
    }
  }

  private static scheduleHoldingEdge(edge: StableMotionHandEdge): void {
    MotionHandStateService.pendingHoldingEdge = edge
    MotionHandStateService.ensureDebounceTimer()
  }

  private static ensureDebounceTimer(): void {
    if (MotionHandStateService.debounceTimerId > 0) {
      return
    }
    MotionHandStateService.debounceTimerId = setTimeout(() => {
      MotionHandStateService.flushPendingEdge()
    }, MotionHandStateService.EDGE_DEBOUNCE_MS)
  }

  private static flushPendingEdge(): void {
    const nextEdge: StableMotionHandEdge | null = MotionHandStateService.pendingHoldingEdge
    MotionHandStateService.debounceTimerId = 0
    MotionHandStateService.pendingHoldingEdge = null
    if (
      nextEdge !== null &&
      MotionHandStateService.effectiveAlignmentMode() === ActionAlignmentSettings.MODE_SMART_GRIP &&
      connectActionHandEdge().edge !== nextEdge
    ) {
      MotionHandStateService.setEdge(nextEdge)
    }
  }

  private static cancelPendingEdge(): void {
    if (MotionHandStateService.debounceTimerId > 0) {
      clearTimeout(MotionHandStateService.debounceTimerId)
      MotionHandStateService.debounceTimerId = 0
    }
    MotionHandStateService.pendingHoldingEdge = null
  }

  private static setEdge(edge: MotionHandEdge): void {
    connectActionHandEdge().edge = edge
  }

  private static logError(action: string, error: Error): void {
    const businessError = error as BusinessError
    DiagnosticLogger.info(
      'motion',
      'hand_state_degraded',
      `${action}: ${businessError.code || 0} ${businessError.message || ''}`,
    )
  }
}
