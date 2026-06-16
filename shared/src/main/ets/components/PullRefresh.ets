import { vibrator } from '@kit.SensorServiceKit'
import { ThemeConstants } from '../theme/ThemeConstants'
import { RefreshFeedback } from '../utils/RefreshFeedback'

const PULL_START_DRAG_VP: number = 4
// A pull only ARMS (and disables the inner Scroll) after a deliberate, vertical-dominant drag past this
// many vp — far enough that a tap's small finger jitter can never arm it. Arming disables the Scroll
// (onScrollEnableChange(false)), which otherwise swallows the tapped child's onClick (the "tap does
// nothing, multi-tap works" bug on the Discover node chips). The pull OFFSET still anchors at the smaller
// PULL_START_DRAG_VP so the indicator starts from where the finger first crossed.
const PULL_ARM_VP: number = 10
const PULL_RESISTANCE_FACTOR: number = 0.8
const DEFAULT_PULL_REFRESH_THRESHOLD: number = 80
const REFRESH_HOLD_OFFSET: number = 56
const HAPTIC_HD_INTENSITY: number = 80
const HAPTIC_FALLBACK_DURATION: number = 30
const DIRECTION_LOCK_VP: number = 6
const PROGRAMMATIC_PULL_ANIM_DURATION: number = 300

export class PullRefreshController {
  private topRefreshAction: () => void = () => {}

  setTopRefreshAction(action: () => void): void {
    this.topRefreshAction = action
  }

  triggerTopRefresh(): void {
    this.topRefreshAction()
  }
}

@ComponentV2
export struct PullRefresh {
  @BuilderParam content: () => void;
  @Param scroller: Scroller = new Scroller();
  @Param controller: PullRefreshController = new PullRefreshController();
  @Event onRefresh: () => Promise<void> = async () => {};
  @Event onBottomRefresh: () => Promise<void> = async () => {};
  @Param canStartBottomRefresh: () => boolean = () => false;
  @Event onScrollEnableChange: (enabled: boolean) => void = (_) => {};
  @Param indicatorTop: number = 0;
  @Param threshold: number = DEFAULT_PULL_REFRESH_THRESHOLD;
  @Param bottomIndicatorBottom: number = ThemeConstants.SPACE_XL;

  @Local pullOffset: number = 0;
  @Local bottomPullOffset: number = 0;
  @Local refreshState: number = 0;
  @Local bottomRefreshState: number = 0;
  @Local containerHeight: number = 0;
  // Indicator MOUNT is intentionally decoupled from pullOffset's instantaneous logical value and from
  // refreshState (the load lifecycle). It turns true the moment a gap opens and only turns false once the
  // rebound animation has fully settled, so the indicator's opacity/position (pure functions of the gap)
  // can fade with the collapsing gap instead of popping out the frame pullOffset logically reaches 0.
  // At rest both are false, so nothing is mounted over the content top to swallow taps.
  @Local topIndicatorMounted: boolean = false;
  @Local bottomIndicatorMounted: boolean = false;
  private hapticFired: boolean = false;
  private touchStartX: number = 0;
  private touchStartY: number = 0;
  private touchStartPullOffset: number = 0;
  private touchStartBottomPullOffset: number = 0;
  private topEdgeDragStartY: number = 0;
  private bottomEdgeDragStartY: number = 0;
  private isTracking: boolean = false;
  private isBottomTracking: boolean = false;
  private isHorizontalGesture: boolean = false;

  aboutToAppear(): void {
    this.controller.setTopRefreshAction(() => {
      this.triggerProgrammaticTopRefresh()
    })
  }

  private isListAtTop(): boolean {
    return this.scroller.currentOffset().yOffset <= 0
  }

  // Pixel-true bottom check for MANUAL pull-up (force refresh) gesture only.
  // Auto pagination uses List.onReachEnd/onScrollIndex which fire when the
  // last item enters the viewport — that signal is intentionally looser and
  // must NOT gate the manual pull-up indicator, otherwise the user sees the
  // bottom indicator flash while the list is still mid-scroll.
  private isListAtBottom(): boolean {
    try {
      return this.scroller.isAtEnd()
    } catch (_e) {
      return false
    }
  }

  private bounceBack(target: number = 0): void {
    this.onScrollEnableChange(true)
    this.getUIContext().animateTo(
      { duration: ThemeConstants.ANIM_DURATION, curve: Curve.EaseOut },
      () => {
        this.pullOffset = target
      },
    )
    if (target === 0) {
      // Unmount AFTER the rebound finishes (ANIM_STATE_RESET_MS > ANIM_DURATION) so the indicator stays in
      // the tree for the whole collapse and fades out with the gap. Guard on pullOffset so a fresh pull that
      // started during the timeout window isn't torn down out from under the user.
      setTimeout(() => {
        if (this.pullOffset <= 0) {
          this.refreshState = 0
          this.hapticFired = false
          this.topIndicatorMounted = false
        }
      }, ThemeConstants.ANIM_STATE_RESET_MS)
    }
  }

  private bounceBottomBack(target: number = 0): void {
    this.onScrollEnableChange(true)
    this.getUIContext().animateTo(
      { duration: ThemeConstants.ANIM_DURATION, curve: Curve.EaseOut },
      () => {
        this.bottomPullOffset = target
      },
    )
    if (target === 0) {
      setTimeout(() => {
        if (this.bottomPullOffset <= 0) {
          this.bottomRefreshState = 0
          this.hapticFired = false
          this.bottomIndicatorMounted = false
        }
      }, ThemeConstants.ANIM_STATE_RESET_MS)
    }
  }

  private onPullEnd(): void {
    if (this.pullOffset >= this.threshold && this.refreshState !== 2) {
      this.onScrollEnableChange(true)
      this.getUIContext().animateTo(
        { duration: ThemeConstants.ANIM_DURATION, curve: Curve.EaseOut },
        () => {
          this.pullOffset = REFRESH_HOLD_OFFSET
        },
      )
      this.refreshState = 2
      this.doRefresh()
    } else if (this.pullOffset > 0) {
      this.bounceBack(0)
    }
  }

  private triggerProgrammaticTopRefresh(): void {
    if (this.refreshState >= 2 || this.topIndicatorMounted || this.pullOffset > 0 || this.bottomPullOffset > 0) {
      return
    }
    try {
      if (!this.isListAtTop()) {
        this.scroller.scrollTo({
          xOffset: 0,
          yOffset: 0,
        })
      }
    } catch (_error) {}
    this.onScrollEnableChange(false)
    this.topIndicatorMounted = true
    this.getUIContext().animateTo(
      { duration: PROGRAMMATIC_PULL_ANIM_DURATION, curve: Curve.EaseOut },
      () => {
        this.pullOffset = this.threshold
      },
    )
    setTimeout(() => {
      this.refreshState = 1
      this.triggerHaptic()
      this.onPullEnd()
    }, PROGRAMMATIC_PULL_ANIM_DURATION)
  }

  private onBottomPullEnd(): void {
    if (this.bottomPullOffset >= this.threshold && this.bottomRefreshState !== 2) {
      this.onScrollEnableChange(true)
      this.getUIContext().animateTo(
        { duration: ThemeConstants.ANIM_DURATION, curve: Curve.EaseOut },
        () => {
          this.bottomPullOffset = REFRESH_HOLD_OFFSET
        },
      )
      this.bottomRefreshState = 2
      this.doBottomRefresh()
    } else if (this.bottomPullOffset > 0) {
      this.bounceBottomBack(0)
    }
  }

  private async doRefresh(): Promise<void> {
    // Centralized pull-to-refresh failure feedback: a rejecting onRefresh means an interactive refresh
    // failed, so surface one toast — and still finish the indicator animation either way.
    try {
      await this.onRefresh()
    } catch (_error) {
      RefreshFeedback.notifyRefreshFailed()
    }
    this.refreshState = 3
    setTimeout(() => this.bounceBack(0), ThemeConstants.ANIM_DONE_DELAY_MS)
  }

  private async doBottomRefresh(): Promise<void> {
    await this.onBottomRefresh()
    this.bottomRefreshState = 3
    setTimeout(() => this.bounceBottomBack(0), ThemeConstants.ANIM_DONE_DELAY_MS)
  }

  private triggerHaptic(): void {
    if (this.hapticFired) return
    this.hapticFired = true
    try {
      if (vibrator.isHdHapticSupported()) {
        vibrator.startVibration(
          {
            type: 'preset',
            effectId: 'haptic.effect.soft',
            count: 1,
            intensity: HAPTIC_HD_INTENSITY,
          },
          { usage: 'physicalFeedback' },
        )
      } else {
        vibrator.startVibration(
          {
            type: 'time',
            duration: HAPTIC_FALLBACK_DURATION,
          },
          { usage: 'physicalFeedback' },
        )
      }
    } catch (e) {}
  }

  private resetTouchState(): void {
    this.isTracking = false
    this.isBottomTracking = false
    this.isHorizontalGesture = false
    this.topEdgeDragStartY = 0
    this.bottomEdgeDragStartY = 0
  }

  private areaLength(value: Length | undefined): number {
    if (typeof value === 'number') {
      return value
    }
    if (typeof value === 'string') {
      const parsed = Number.parseFloat(value)
      return Number.isNaN(parsed) ? 0 : parsed
    }
    return 0
  }

  // Opacity is a pure function of the GAP so the indicator fades in/out with the blank, never with the load
  // lifecycle. It stays 0 until the gap exceeds the spinner's own diameter (so a half-shown spinner can never
  // overlap the adjacent content row) and ramps to 1 at the refresh hold offset.
  private indicatorOpacity(gap: number, indicatorSize: number): number {
    const range = REFRESH_HOLD_OFFSET - indicatorSize
    if (range <= 0) {
      return gap >= indicatorSize ? 1 : 0
    }
    return Math.min(Math.max((gap - indicatorSize) / range, 0), 1)
  }

  private bottomIndicatorY(): number {
    // Mirror the top refresh indicator: keep the node mounted and derive its
    // absolute position from the current pull offset so drag and rebound share
    // one coordinate formula.
    return Math.max(
      0,
      this.containerHeight -
        this.bottomIndicatorBottom -
        this.bottomPullOffset / 2 -
        REFRESH_HOLD_OFFSET / 2 +
        ThemeConstants.SPACE_SM,
    )
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Column() {
        this.content()
      }
      .offset({ y: this.pullOffset - this.bottomPullOffset })
      .onTouch((event: TouchEvent) => {
        if (this.refreshState >= 2 || this.bottomRefreshState >= 2) return

        if (event.type === TouchType.Down) {
          this.touchStartX = event.touches[0].x
          this.touchStartY = event.touches[0].y
          this.touchStartPullOffset = this.pullOffset
          this.touchStartBottomPullOffset = this.bottomPullOffset
          this.resetTouchState()
          return
        }

        if (event.type === TouchType.Move) {
          let deltaX = event.touches[0].x - this.touchStartX
          let deltaY = event.touches[0].y - this.touchStartY
          if (this.isHorizontalGesture) {
            return
          }
          if (!this.isTracking && !this.isBottomTracking) {
            if (Math.abs(deltaX) > DIRECTION_LOCK_VP && Math.abs(deltaX) > Math.abs(deltaY)) {
              this.isHorizontalGesture = true
              return
            }
            // Only arm a pull on a deliberate, vertical-dominant drag past PULL_ARM_VP. A tap's small
            // (often slightly diagonal) finger jitter must not arm it, because arming disables the inner
            // Scroll (onScrollEnableChange(false)) and that swallows the tapped child's onClick.
            const verticalDominant = Math.abs(deltaY) > Math.abs(deltaX) * 1.5
            if (verticalDominant && deltaY > PULL_ARM_VP && this.isListAtTop()) {
              this.isTracking = true
              this.topEdgeDragStartY = event.touches[0].y - PULL_START_DRAG_VP
              this.touchStartPullOffset = 0
              this.onScrollEnableChange(false)
            } else if (
              verticalDominant &&
              deltaY < -PULL_ARM_VP &&
              this.isListAtBottom() &&
              this.canStartBottomRefresh()
            ) {
              this.isBottomTracking = true
              this.bottomEdgeDragStartY = event.touches[0].y + PULL_START_DRAG_VP
              this.touchStartBottomPullOffset = 0
              this.onScrollEnableChange(false)
            } else {
              return
            }
          }
          if (this.isTracking) {
            const topPullDelta = event.touches[0].y - this.topEdgeDragStartY
            this.pullOffset = Math.max(
              0,
              this.touchStartPullOffset + topPullDelta * PULL_RESISTANCE_FACTOR,
            )
            if (this.pullOffset > 0) {
              this.topIndicatorMounted = true
            }
            if (this.pullOffset >= this.threshold) {
              this.refreshState = 1
              this.triggerHaptic()
            } else {
              this.refreshState = 0
            }
          } else if (this.isBottomTracking) {
            const bottomPullDelta = this.bottomEdgeDragStartY - event.touches[0].y
            this.bottomPullOffset = Math.max(
              0,
              this.touchStartBottomPullOffset + bottomPullDelta * PULL_RESISTANCE_FACTOR,
            )
            if (this.bottomPullOffset > 0) {
              this.bottomIndicatorMounted = true
            }
            if (this.bottomPullOffset >= this.threshold) {
              this.bottomRefreshState = 1
              this.triggerHaptic()
            } else {
              this.bottomRefreshState = 0
            }
          }
        }

        if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          if (this.isTracking && this.pullOffset > 0) {
            this.onPullEnd()
          } else if (this.isBottomTracking && this.bottomPullOffset > 0) {
            this.onBottomPullEnd()
          } else {
            // Pulled the indicator out then pushed it back to a zero gap (or never opened one): there is no
            // rebound to ride, so unmount now — otherwise an opacity-0 indicator stays mounted at the content
            // top and swallows taps on the first row (the Discover node-chip dead-top-half bug).
            this.topIndicatorMounted = false
            this.bottomIndicatorMounted = false
          }
          // Always re-enable the inner Scroll on touch end so a momentarily-disabled scroll can never
          // stick into the next tap and swallow its onClick. onPullEnd/onBottomPullEnd already re-enable
          // it when they start a refresh; this is the catch-all for every other release path.
          this.onScrollEnableChange(true)
          this.resetTouchState()
        }
      })
      // Mount/position/opacity are all derived from the GAP (pullOffset), never from refreshState (the load
      // lifecycle), so the indicator dissolves with the shrinking blank on every release — whether or not a
      // refresh fired. The spinner (diameter INDICATOR_SIZE) is centered on the gap, so its bottom edge only
      // clears the content top once pullOffset >= INDICATOR_SIZE; below that it would overlap the first row,
      // so opacity is pinned to 0 there (see indicatorOpacity). It reaches 1 at the refresh hold offset.
      // topIndicatorMounted keeps the node alive through the rebound and is cleared only
      // after it settles (see bounceBack); at rest it is false so nothing overlays the content top.
      if (this.topIndicatorMounted) {
        Column() {
          Row() {
            LoadingProgress()
              .width(ThemeConstants.INDICATOR_SIZE)
              .height(ThemeConstants.INDICATOR_SIZE)
          }
          .width('100%')
          .height(REFRESH_HOLD_OFFSET)
          .justifyContent(FlexAlign.Center)
          .opacity(this.indicatorOpacity(this.pullOffset, ThemeConstants.INDICATOR_SIZE))
        }
        .position({ y: this.indicatorTop + this.pullOffset / 2 })
        .hitTestBehavior(HitTestMode.None)
      }
      // Bottom pull-up indicator mirrors the top one: opacity is a pure function of its gap, pinned to 0 until
      // the gap clears the spinner's own diameter (LOADING_SIZE_SMALL) so it never overlaps the last row, and
      // the mount flag rides the rebound — so it fades with the collapsing gap instead of staying pinned by
      // bottomRefreshState until the list snaps home.
      if (this.bottomIndicatorMounted) {
        Row({ space: ThemeConstants.SPACE_SM }) {
          LoadingProgress()
            .width(ThemeConstants.LOADING_SIZE_SMALL)
            .height(ThemeConstants.LOADING_SIZE_SMALL)
            .color($r('sys.color.font_secondary'))
        }
        .width('100%')
        .height(REFRESH_HOLD_OFFSET)
        .justifyContent(FlexAlign.Center)
        .opacity(this.indicatorOpacity(this.bottomPullOffset, ThemeConstants.LOADING_SIZE_SMALL))
        .position({ y: this.bottomIndicatorY() })
        .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height('100%')
    .clip(false)
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.containerHeight = this.areaLength(newValue.height)
    })
  }
}
