import { HdsNavDestination } from '@kit.UIDesignKit'
import {
  DiagnosticLogger,
  LayoutSafeAreaState,
  ThemeConstants,
  connectLayoutSafeArea,
  immersiveTitleBar,
} from 'shared'

const PROBE_IMAGE_RATIO_W: number = 1440
const PROBE_IMAGE_RATIO_H: number = 2560
const PROBE_DOUBLE_TAP_SCALE: number = 2.5
const PROBE_MIN_SCALE: number = 1
const PROBE_MAX_SCALE: number = 6
const PROBE_ZOOM_ANIM_MS: number = 240

interface ProbeImageLoadEvent {
  loadingStatus: number
  width?: number
  height?: number
  componentWidth?: number
  componentHeight?: number
}

@ComponentV2
export struct ReaderGestureProbePage {
  @Local layout: LayoutSafeAreaState = connectLayoutSafeArea();
  @Local viewportW: number = 0;
  @Local viewportH: number = 0;
  @Local intrinsicW: number = PROBE_IMAGE_RATIO_W;
  @Local intrinsicH: number = PROBE_IMAGE_RATIO_H;
  @Local zoomScale: number = 1;
  @Local offsetX: number = 0;
  @Local offsetY: number = 0;
  @Local anchorX: number = 0.5;
  @Local anchorY: number = 0.5;
  @Local preScale: number = 1;
  @Local zoomAnimating: boolean = false;
  @Local lastEvent: string = 'ready';
  private panStartOffX: number = 0;
  private panStartOffY: number = 0;
  private animationTimer: number = -1;

  build() {
    HdsNavDestination() {
      Column({ space: ThemeConstants.SPACE_MD }) {
        Stack({ alignContent: Alignment.Center }) {
          Image($r('app.media.reader_gesture_probe_vertical'))
            .objectFit(ImageFit.Contain)
            .interpolation(ImageInterpolation.High)
            .width('100%')
            .height('100%')
            .draggable(false)
            .scale({ x: this.zoomScale, y: this.zoomScale })
            .translate({ x: this.offsetX, y: this.offsetY })
            .animation({ duration: this.zoomAnimating ? PROBE_ZOOM_ANIM_MS : 0, curve: Curve.FastOutSlowIn })
            .onComplete((event?: ProbeImageLoadEvent) => {
              if (event && event.width && event.height) {
                this.intrinsicW = this.getUIContext().px2vp(event.width)
                this.intrinsicH = this.getUIContext().px2vp(event.height)
              }
            })
        }
        .width('100%')
        .layoutWeight(1)
        .clip(true)
        .backgroundColor(ThemeConstants.COVER_PLACEHOLDER)
        .borderRadius(ThemeConstants.RADIUS_CARD)
        .onAreaChange((_o: Area, n: Area) => {
          this.viewportW = n.width as number
          this.viewportH = n.height as number
          this.clampOffset()
        })
        .gesture(
          GestureGroup(
            GestureMode.Parallel,
            PinchGesture({ fingers: 2 })
              .onActionStart((event?: GestureEvent) => {
                if (!event) {
                  return
                }
                this.zoomAnimating = false
                this.captureAnchor(event.pinchCenterX as number, event.pinchCenterY as number)
                this.preScale = this.zoomScale
                this.lastEvent = `pinch start anchor=${this.fmt(this.anchorX)},${this.fmt(this.anchorY)}`
                DiagnosticLogger.info('reader-gesture-probe', 'pinch_start', this.metricsText())
              })
              .onActionUpdate((event?: GestureEvent) => {
                if (!event) {
                  return
                }
                const nextScale: number = this.clampScale(this.preScale * (event.scale as number))
                this.applyAnchoredZoom(nextScale, event.pinchCenterX as number, event.pinchCenterY as number)
                this.lastEvent = `pinch update scale=${this.fmt(this.zoomScale)}`
              })
              .onActionEnd(() => {
                this.clampOffset()
                this.lastEvent = `pinch end scale=${this.fmt(this.zoomScale)}`
                DiagnosticLogger.info('reader-gesture-probe', 'pinch_end', this.metricsText())
              })
              .onActionCancel(() => {
                this.clampOffset()
                this.lastEvent = 'pinch cancel'
              }),
            TapGesture({ count: 2, distanceThreshold: 8 })
              .onAction((event?: GestureEvent) => {
                const loc = event ? event.tapLocation : undefined
                const tapX: number = loc ? (loc.x as number) : this.viewportW / 2
                const tapY: number = loc ? (loc.y as number) : this.viewportH / 2
                this.onDoubleTap(tapX, tapY)
              }),
            PanGesture({ fingers: 1, direction: PanDirection.All, distance: 2 })
              .onActionStart(() => {
                this.panStartOffX = this.offsetX
                this.panStartOffY = this.offsetY
              })
              .onActionUpdate((event?: GestureEvent) => {
                if (!event || this.zoomScale <= 1.01) {
                  return
                }
                this.zoomAnimating = false
                this.offsetX = this.clampOffsetX(this.panStartOffX + (event.offsetX as number), this.zoomScale)
                this.offsetY = this.clampOffsetY(this.panStartOffY + (event.offsetY as number), this.zoomScale)
                this.lastEvent = `pan ${this.fmt(this.offsetX)},${this.fmt(this.offsetY)}`
              }),
          ),
        )

        Row() {
          Column({ space: ThemeConstants.SPACE_XS }) {
            Text(this.metricsText())
              .fontSize(ThemeConstants.FONT_SIZE_META)
              .fontColor(ThemeConstants.TEXT_SECONDARY)
              .maxLines(2)
            Text(this.lastEvent)
              .fontSize(ThemeConstants.FONT_SIZE_META)
              .fontColor(ThemeConstants.TEXT_SECONDARY)
              .maxLines(1)
          }
          .layoutWeight(1)

          Button('Reset')
            .height(ThemeConstants.ACTION_HEIGHT)
            .onClick(() => {
              this.resetZoom(true)
            })
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .padding({
        top: this.layout.topAvoidHeight + ThemeConstants.TITLE_BAR_HEIGHT + ThemeConstants.SPACE_MD,
        left: ThemeConstants.SPACE_LG,
        right: ThemeConstants.SPACE_LG,
        bottom: this.layout.bottomAvoidHeight + ThemeConstants.SPACE_LG,
      })
    }
    .titleBar(immersiveTitleBar('Reader gesture probe'))
    .backgroundColor(ThemeConstants.BG_PRIMARY)
  }

  private onDoubleTap(tapX: number, tapY: number): void {
    this.startZoomAnimation()
    if (this.zoomScale > 1.01) {
      this.resetZoom(false)
      this.lastEvent = 'double tap reset'
    } else {
      this.captureAnchor(tapX, tapY)
      this.applyAnchoredZoom(PROBE_DOUBLE_TAP_SCALE, tapX, tapY)
      this.lastEvent = `double tap zoom ${this.fmt(tapX)},${this.fmt(tapY)}`
    }
    DiagnosticLogger.info('reader-gesture-probe', 'double_tap', this.metricsText())
  }

  private resetZoom(withAnimation: boolean): void {
    if (withAnimation) {
      this.startZoomAnimation()
    }
    this.zoomScale = 1
    this.offsetX = 0
    this.offsetY = 0
    this.anchorX = 0.5
    this.anchorY = 0.5
    this.preScale = 1
    this.lastEvent = 'reset'
    DiagnosticLogger.info('reader-gesture-probe', 'reset', this.metricsText())
  }

  private startZoomAnimation(): void {
    this.zoomAnimating = true
    if (this.animationTimer >= 0) {
      clearTimeout(this.animationTimer)
    }
    this.animationTimer = setTimeout(() => {
      this.zoomAnimating = false
      this.animationTimer = -1
    }, PROBE_ZOOM_ANIM_MS + 40)
  }

  private captureAnchor(centerX: number, centerY: number): void {
    const displayW: number = this.contentW() * this.zoomScale
    const displayH: number = this.contentH() * this.zoomScale
    if (displayW <= 0 || displayH <= 0) {
      this.anchorX = 0.5
      this.anchorY = 0.5
      return
    }
    const left: number = (this.viewportW - displayW) / 2 + this.offsetX
    const top: number = (this.viewportH - displayH) / 2 + this.offsetY
    this.anchorX = (centerX - left) / displayW
    this.anchorY = (centerY - top) / displayH
  }

  private applyAnchoredZoom(nextScale: number, centerX: number, centerY: number): void {
    this.zoomScale = nextScale
    const targetW: number = this.contentW() * nextScale
    const targetH: number = this.contentH() * nextScale
    const pointX: number = (this.viewportW - targetW) / 2 + targetW * this.anchorX
    const pointY: number = (this.viewportH - targetH) / 2 + targetH * this.anchorY
    this.offsetX = this.clampOffsetX(centerX - pointX, nextScale)
    this.offsetY = this.clampOffsetY(centerY - pointY, nextScale)
  }

  private clampOffset(): void {
    this.offsetX = this.clampOffsetX(this.offsetX, this.zoomScale)
    this.offsetY = this.clampOffsetY(this.offsetY, this.zoomScale)
  }

  private clampOffsetX(value: number, scale: number): number {
    const max: number = Math.max(0, (this.contentW() * scale - this.viewportW) / 2)
    return Math.min(max, Math.max(-max, value))
  }

  private clampOffsetY(value: number, scale: number): number {
    const max: number = Math.max(0, (this.contentH() * scale - this.viewportH) / 2)
    return Math.min(max, Math.max(-max, value))
  }

  private clampScale(value: number): number {
    return Math.min(PROBE_MAX_SCALE, Math.max(PROBE_MIN_SCALE, value))
  }

  private contentW(): number {
    const scale: number = this.fitScale()
    return this.intrinsicW * scale
  }

  private contentH(): number {
    const scale: number = this.fitScale()
    return this.intrinsicH * scale
  }

  private fitScale(): number {
    if (this.viewportW <= 0 || this.viewportH <= 0 || this.intrinsicW <= 0 || this.intrinsicH <= 0) {
      return 1
    }
    return Math.min(this.viewportW / this.intrinsicW, this.viewportH / this.intrinsicH)
  }

  private metricsText(): string {
    return `scale=${this.fmt(this.zoomScale)} offset=${this.fmt(this.offsetX)},${this.fmt(this.offsetY)} anchor=${this.fmt(this.anchorX)},${this.fmt(this.anchorY)} viewport=${this.fmt(this.viewportW)}x${this.fmt(this.viewportH)}`
  }

  private fmt(value: number): string {
    return value.toFixed(2)
  }
}
