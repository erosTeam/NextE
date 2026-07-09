export class ReaderImageTransformCoordinator {
  static readonly MIN_DYNAMIC_MAX_SCALE: number = 4
  static readonly MAX_DYNAMIC_MAX_SCALE: number = 12
  static readonly NATIVE_SCALE_HEADROOM: number = 2
  static readonly DOUBLE_TAP_MIN_SCALE: number = 1.5
  static readonly DOUBLE_TAP_MAX_SCALE: number = 3
  static readonly DOUBLE_TAP_FALLBACK_SCALE: number = 2

  static clampScale(value: number, maxScale: number = ReaderImageTransformCoordinator.MIN_DYNAMIC_MAX_SCALE): number {
    if (!Number.isFinite(value)) {
      return 1
    }
    if (value < 1) {
      return 1
    }
    const boundedMax: number = ReaderImageTransformCoordinator.saneMaxScale(maxScale)
    if (value > boundedMax) {
      return boundedMax
    }
    return value
  }

  static saneMaxScale(value: number): number {
    if (!Number.isFinite(value) || value < ReaderImageTransformCoordinator.MIN_DYNAMIC_MAX_SCALE) {
      return ReaderImageTransformCoordinator.MIN_DYNAMIC_MAX_SCALE
    }
    if (value > ReaderImageTransformCoordinator.MAX_DYNAMIC_MAX_SCALE) {
      return ReaderImageTransformCoordinator.MAX_DYNAMIC_MAX_SCALE
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

  static nativeScale(intrinsicW: number, intrinsicH: number, displayW: number, displayH: number): number {
    if (intrinsicW <= 0 || intrinsicH <= 0 || displayW <= 0 || displayH <= 0) {
      return ReaderImageTransformCoordinator.DOUBLE_TAP_FALLBACK_SCALE
    }
    const scaleW: number = intrinsicW / displayW
    const scaleH: number = intrinsicH / displayH
    const scale: number = Math.min(scaleW, scaleH)
    return scale > 0 && Number.isFinite(scale) ? scale : ReaderImageTransformCoordinator.DOUBLE_TAP_FALLBACK_SCALE
  }

  static dynamicMaxScale(intrinsicW: number, intrinsicH: number, displayW: number, displayH: number): number {
    const native: number = ReaderImageTransformCoordinator.nativeScale(intrinsicW, intrinsicH, displayW, displayH)
    return ReaderImageTransformCoordinator.saneMaxScale(
      native * ReaderImageTransformCoordinator.NATIVE_SCALE_HEADROOM,
    )
  }

  static doubleTapTarget(currentScale: number, maxScale: number, nativeScale: number): number {
    if (currentScale > 1.01) {
      return 1
    }
    let target: number = nativeScale
    if (!Number.isFinite(target) || target <= 0) {
      target = ReaderImageTransformCoordinator.DOUBLE_TAP_FALLBACK_SCALE
    }
    if (target < ReaderImageTransformCoordinator.DOUBLE_TAP_MIN_SCALE) {
      target = ReaderImageTransformCoordinator.DOUBLE_TAP_MIN_SCALE
    }
    if (target > ReaderImageTransformCoordinator.DOUBLE_TAP_MAX_SCALE) {
      target = ReaderImageTransformCoordinator.DOUBLE_TAP_MAX_SCALE
    }
    return ReaderImageTransformCoordinator.clampScale(target, maxScale)
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

  static pinchAnchor(
    center: number,
    viewport: number,
    displaySize: number,
    scale: number,
    offset: number,
  ): number {
    const displayed: number = displaySize * scale
    if (displayed <= 0) {
      return 0.5
    }
    const displayStart: number = (viewport - displayed) / 2 + offset
    return (center - displayStart) / displayed
  }

  static anchoredOffset(
    center: number,
    viewport: number,
    displaySize: number,
    scale: number,
    anchor: number,
  ): number {
    const displayed: number = displaySize * scale
    const point: number = (viewport - displayed) / 2 + displayed * anchor
    return center - point
  }
}
