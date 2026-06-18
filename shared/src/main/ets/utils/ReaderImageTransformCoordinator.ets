export class ReaderImageTransformCoordinator {
  static readonly DOUBLE_TAP_SCALE: number = 2.5
  static readonly MAX_SCALE: number = 4

  static clampScale(value: number): number {
    if (!Number.isFinite(value)) {
      return 1
    }
    if (value < 1) {
      return 1
    }
    if (value > ReaderImageTransformCoordinator.MAX_SCALE) {
      return ReaderImageTransformCoordinator.MAX_SCALE
    }
    return value
  }

  static fitScale(viewportW: number, viewportH: number, intrinsicW: number, intrinsicH: number): number {
    if (viewportW <= 0 || viewportH <= 0 || intrinsicW <= 0 || intrinsicH <= 0) {
      return 1
    }
    const scale: number = Math.min(viewportW / intrinsicW, viewportH / intrinsicH)
    return scale > 0 ? scale : 1
  }

  static displaySize(viewport: number, crossViewport: number, intrinsic: number, crossIntrinsic: number): number {
    return intrinsic * ReaderImageTransformCoordinator.fitScale(
      viewport,
      crossViewport,
      intrinsic,
      crossIntrinsic,
    )
  }

  static maxOffset(viewport: number, displaySize: number, scale: number): number {
    const scaled: number = displaySize * scale
    const overflow: number = scaled - viewport
    return overflow > 0 ? overflow / 2 : 0
  }

  static clampOffset(value: number, viewport: number, displaySize: number, scale: number): number {
    const max: number = ReaderImageTransformCoordinator.maxOffset(viewport, displaySize, scale)
    if (value > max) {
      return max
    }
    if (value < -max) {
      return -max
    }
    return value
  }

  static doubleTapOffset(tap: number, viewport: number, targetScale: number): number {
    return (1 - targetScale) * (tap - viewport / 2)
  }

  static pinchOffset(
    startCenter: number,
    currentCenter: number,
    viewport: number,
    startOffset: number,
    scaleRatio: number,
  ): number {
    return (startCenter - viewport / 2) * (1 - scaleRatio) +
      scaleRatio * startOffset +
      currentCenter - startCenter
  }
}
