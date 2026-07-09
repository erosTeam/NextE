export class ReaderImageTransformCoordinator {
  static readonly MIN_DYNAMIC_MAX_SCALE: number = 4
  static readonly MAX_DYNAMIC_MAX_SCALE: number = 12
  static readonly MAX_EFFECTIVE_MAX_SCALE: number = 48
  static readonly NATIVE_SCALE_HEADROOM: number = 2
  static readonly DOUBLE_TAP_PRIMARY_SCALE: number = 2
  static readonly DOUBLE_TAP_FALLBACK_SCALE: number = 2
  static readonly DOUBLE_TAP_SCALE_EPSILON: number = 0.02
  static readonly PINCH_ELASTIC_MIN_SCALE: number = 0.8
  static readonly PINCH_UNDER_SCALE_RESISTANCE: number = 0.35

  static clampScale(value: number, maxScale: number = ReaderImageTransformCoordinator.MIN_DYNAMIC_MAX_SCALE): number {
    if (!Number.isFinite(value)) {
      return 1
    }
    if (value < 1) {
      return 1
    }
    const boundedMax: number = ReaderImageTransformCoordinator.saneEffectiveMaxScale(maxScale)
    if (value > boundedMax) {
      return boundedMax
    }
    return value
  }

  static clampPinchScale(
    value: number,
    maxScale: number = ReaderImageTransformCoordinator.MIN_DYNAMIC_MAX_SCALE,
  ): number {
    if (!Number.isFinite(value)) {
      return 1
    }
    if (value >= 1) {
      return ReaderImageTransformCoordinator.clampScale(value, maxScale)
    }
    const resisted: number = 1 -
      (1 - value) * ReaderImageTransformCoordinator.PINCH_UNDER_SCALE_RESISTANCE
    return Math.max(ReaderImageTransformCoordinator.PINCH_ELASTIC_MIN_SCALE, resisted)
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

  static saneEffectiveMaxScale(value: number): number {
    if (!Number.isFinite(value) || value < ReaderImageTransformCoordinator.MIN_DYNAMIC_MAX_SCALE) {
      return ReaderImageTransformCoordinator.MIN_DYNAMIC_MAX_SCALE
    }
    if (value > ReaderImageTransformCoordinator.MAX_EFFECTIVE_MAX_SCALE) {
      return ReaderImageTransformCoordinator.MAX_EFFECTIVE_MAX_SCALE
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

  static scaleForReferenceDisplay(
    targetReferenceScale: number,
    displayW: number,
    displayH: number,
    referenceDisplayW: number,
    referenceDisplayH: number,
  ): number {
    if (
      !Number.isFinite(targetReferenceScale) || targetReferenceScale <= 0 ||
      displayW <= 0 || displayH <= 0 || referenceDisplayW <= 0 || referenceDisplayH <= 0
    ) {
      return targetReferenceScale
    }
    const scaleW: number = (referenceDisplayW * targetReferenceScale) / displayW
    const scaleH: number = (referenceDisplayH * targetReferenceScale) / displayH
    const scale: number = Math.min(scaleW, scaleH)
    return scale > 0 && Number.isFinite(scale) ? scale : targetReferenceScale
  }

  static dynamicMaxScaleForDisplay(
    intrinsicW: number,
    intrinsicH: number,
    displayW: number,
    displayH: number,
    referenceDisplayW: number,
    referenceDisplayH: number,
  ): number {
    const referenceMax: number = ReaderImageTransformCoordinator.dynamicMaxScale(
      intrinsicW,
      intrinsicH,
      referenceDisplayW,
      referenceDisplayH,
    )
    return ReaderImageTransformCoordinator.saneEffectiveMaxScale(
      ReaderImageTransformCoordinator.scaleForReferenceDisplay(
        referenceMax,
        displayW,
        displayH,
        referenceDisplayW,
        referenceDisplayH,
      ),
    )
  }

  static nearScale(first: number, second: number): boolean {
    return Math.abs(first - second) <= ReaderImageTransformCoordinator.DOUBLE_TAP_SCALE_EPSILON
  }

  static nextDoubleTapScale(
    currentScale: number,
    maxScale: number,
    primaryScale: number,
    nativeScale: number,
    pinchAdjusted: boolean,
  ): number {
    if (pinchAdjusted && currentScale > 1.01) {
      return 1
    }
    const primary: number = ReaderImageTransformCoordinator.clampScale(primaryScale, maxScale)
    const native: number = ReaderImageTransformCoordinator.clampScale(nativeScale, maxScale)
    if (currentScale <= 1.01) {
      return primary
    }
    if (
      ReaderImageTransformCoordinator.nearScale(currentScale, primary) &&
      native > 1 + ReaderImageTransformCoordinator.DOUBLE_TAP_SCALE_EPSILON
    ) {
      return native
    }
    return 1
  }

  static doubleTapTarget(
    currentScale: number,
    maxScale: number,
    nativeScale: number,
    pinchAdjusted: boolean = false,
  ): number {
    return ReaderImageTransformCoordinator.nextDoubleTapScale(
      currentScale,
      maxScale,
      ReaderImageTransformCoordinator.DOUBLE_TAP_PRIMARY_SCALE,
      nativeScale,
      pinchAdjusted,
    )
  }

  static doubleTapTargetForDisplay(
    currentScale: number,
    maxScale: number,
    referenceNativeScale: number,
    displayW: number,
    displayH: number,
    referenceDisplayW: number,
    referenceDisplayH: number,
    pinchAdjusted: boolean = false,
  ): number {
    const primary: number = ReaderImageTransformCoordinator.scaleForReferenceDisplay(
      ReaderImageTransformCoordinator.DOUBLE_TAP_PRIMARY_SCALE,
      displayW,
      displayH,
      referenceDisplayW,
      referenceDisplayH,
    )
    const native: number = ReaderImageTransformCoordinator.scaleForReferenceDisplay(
      referenceNativeScale,
      displayW,
      displayH,
      referenceDisplayW,
      referenceDisplayH,
    )
    return ReaderImageTransformCoordinator.nextDoubleTapScale(
      currentScale,
      maxScale,
      primary,
      native,
      pinchAdjusted,
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
