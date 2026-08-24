import { FrameCallback } from '@kit.ArkUI'
import { image } from '@kit.ImageKit'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { EhGalleryImage } from '../model/EhGalleryImage'
import { connectGalleryDetailTransitionSettings } from '../state/GalleryDetailTransitionSettingsState'
import { GalleryDetailTransitionMode } from '../state/GalleryDetailTransitionSettingsState'
import {
  connectReaderThumbnailTransition,
  ReaderThumbnailTransitionState,
} from '../state/ReaderThumbnailTransitionState'
import { ThemeConstants } from '../theme/ThemeConstants'

class ReaderThumbnailTransitionFrameCallback extends FrameCallback {
  private action: () => void

  constructor(action: () => void) {
    super()
    this.action = action
  }

  onFrame(_frameTimeInNano: number): void {}

  onIdle(_timeLeftInNano: number): void {
    this.action()
  }
}

/** Coordinates the real thumbnail node with a root-level Reader geometry proxy. */
export class ReaderThumbnailTransitionCoordinator {
  private static scopeSeed: number = 0
  private static geometrySeed: number = 0

  static allocateScope(owner: string): string {
    ReaderThumbnailTransitionCoordinator.scopeSeed += 1
    return `reader-thumb-${owner}-${ReaderThumbnailTransitionCoordinator.scopeSeed}`
  }

  static sourceId(scope: string, index: number): string {
    return `${scope}-page-${index}`
  }

  private static componentAvailable(uiContext: UIContext, componentId: string): boolean {
    try {
      const rect = uiContext.getComponentUtils().getRectangleById(componentId)
      return rect.size.width > 0 && rect.size.height > 0
    } catch (_error) {
      return false
    }
  }

  private static captureReaderImage(
    uiContext: UIContext,
    componentId: string,
    intrinsicWidth: number,
    intrinsicHeight: number,
  ): image.PixelMap | undefined {
    if (componentId.length === 0 || intrinsicWidth <= 0 || intrinsicHeight <= 0) {
      return undefined
    }
    try {
      const componentRect = uiContext.getComponentUtils().getRectangleById(componentId)
      const componentWidth: number = Math.floor(componentRect.size.width)
      const componentHeight: number = Math.floor(componentRect.size.height)
      if (componentWidth <= 0 || componentHeight <= 0) {
        return undefined
      }
      const ratio: number = intrinsicWidth / intrinsicHeight
      const displayWidth: number = componentWidth / componentHeight > ratio
        ? componentHeight * ratio
        : componentWidth
      const displayHeight: number = displayWidth / ratio
      const left: number = Math.max(0, Math.floor((componentWidth - displayWidth) / 2))
      const top: number = Math.max(0, Math.floor((componentHeight - displayHeight) / 2))
      const right: number = Math.min(componentWidth, Math.ceil(left + displayWidth))
      const bottom: number = Math.min(componentHeight, Math.ceil(top + displayHeight))
      if (right <= left || bottom <= top) {
        return undefined
      }
      return uiContext.getComponentSnapshot().getSync(componentId, {
        waitUntilRenderFinished: true,
        region: { left: left, right: right, top: top, bottom: bottom },
      })
    } catch (error) {
      DiagnosticLogger.info(
        'reader-transition',
        'reader_snapshot_failed',
        `component=${componentId} error=${error}`,
      )
      return undefined
    }
  }

  static open(
    uiContext: UIContext,
    sourceScope: string,
    galleryId: string,
    index: number,
    image: EhGalleryImage,
    openReader: (animated: boolean) => void,
  ): void {
    const transition: ReaderThumbnailTransitionState = connectReaderThumbnailTransition()
    transition.reset()
    const sourceComponentId: string = ReaderThumbnailTransitionCoordinator.sourceId(sourceScope, index)
    if (
      connectGalleryDetailTransitionSettings().mode !== GalleryDetailTransitionMode.COVER_EXPAND ||
      !ReaderThumbnailTransitionCoordinator.componentAvailable(uiContext, sourceComponentId)
    ) {
      openReader(true)
      return
    }
    try {
      const rootRect = uiContext.getComponentUtils().getRectangleById('nexte-root-navigation')
      const rootWidth: number = uiContext.px2vp(rootRect.size.width)
      const rootHeight: number = uiContext.px2vp(rootRect.size.height)
      if (rootWidth <= 0 || rootHeight <= 0) {
        openReader(true)
        return
      }
      ReaderThumbnailTransitionCoordinator.geometrySeed += 1
      transition.arm(
        sourceScope,
        sourceComponentId,
        `reader-thumbnail-geometry-${ReaderThumbnailTransitionCoordinator.geometrySeed}`,
        galleryId,
        index,
        image,
        rootWidth,
        rootHeight,
      )
      DiagnosticLogger.info(
        'reader-transition',
        'armed',
        `gid=${galleryId} index=${index} source=${sourceComponentId}`,
      )
      openReader(false)
    } catch (error) {
      transition.reset()
      DiagnosticLogger.info('reader-transition', 'open_fallback', `${error}`)
      openReader(true)
    }
  }

  static startOpening(uiContext: UIContext): void {
    const transition: ReaderThumbnailTransitionState = connectReaderThumbnailTransition()
    if (!transition.waitingReader()) {
      return
    }
    uiContext.animateTo({
      duration: ThemeConstants.ANIM_DURATION,
      curve: Curve.Friction,
      onFinish: () => {
        const handedOff: boolean = transition.finishOpeningGeometry()
        DiagnosticLogger.info(
          'reader-transition',
          handedOff ? 'open_finished' : 'open_geometry_finished_waiting',
          `index=${transition.currentIndex}`,
        )
      },
    }, () => {
      transition.startOpening()
    })
  }

  static notifyReaderImageReady(page: number): void {
    const transition: ReaderThumbnailTransitionState = connectReaderThumbnailTransition()
    if (transition.markReaderImageReady(page)) {
      DiagnosticLogger.info('reader-transition', 'open_finished', `index=${transition.currentIndex}`)
    }
  }

  static close(
    uiContext: UIContext,
    currentIndex: number,
    currentImage: EhGalleryImage,
    readerSnapshotComponentId: string,
    readerIntrinsicWidth: number,
    readerIntrinsicHeight: number,
    closeReader: (animated: boolean) => void,
  ): boolean {
    const transition: ReaderThumbnailTransitionState = connectReaderThumbnailTransition()
    DiagnosticLogger.info(
      'reader-transition',
      'close_requested',
      `index=${currentIndex} phase=${transition.phase} scope=${transition.sourceScope}`,
    )
    if (!transition.active() || transition.sourceScope.length === 0) {
      return false
    }
    const targetId: string = ReaderThumbnailTransitionCoordinator.sourceId(
      transition.sourceScope,
      currentIndex,
    )
    if (!ReaderThumbnailTransitionCoordinator.componentAvailable(uiContext, targetId)) {
      DiagnosticLogger.info(
        'reader-transition',
        'close_target_unavailable',
        `index=${currentIndex} target=${targetId}`,
      )
      transition.reset()
      return false
    }
    let targetX: number = 0
    let targetY: number = 0
    let targetWidth: number = 0
    let targetHeight: number = 0
    try {
      const targetRect = uiContext.getComponentUtils().getRectangleById(targetId)
      const rootRect = uiContext.getComponentUtils().getRectangleById('nexte-root-navigation')
      targetX = uiContext.px2vp(targetRect.windowOffset.x - rootRect.windowOffset.x)
      targetY = uiContext.px2vp(targetRect.windowOffset.y - rootRect.windowOffset.y)
      targetWidth = uiContext.px2vp(targetRect.size.width)
      targetHeight = uiContext.px2vp(targetRect.size.height)
      if (targetWidth <= 0 || targetHeight <= 0) {
        transition.reset()
        return false
      }
    } catch (error) {
      DiagnosticLogger.info(
        'reader-transition',
        'close_target_measure_failed',
        `index=${currentIndex} target=${targetId} error=${error}`,
      )
      transition.reset()
      return false
    }
    const readerSnapshot: image.PixelMap | undefined = ReaderThumbnailTransitionCoordinator.captureReaderImage(
      uiContext,
      readerSnapshotComponentId,
      readerIntrinsicWidth,
      readerIntrinsicHeight,
    )
    if (readerSnapshot === undefined) {
      DiagnosticLogger.info(
        'reader-transition',
        'close_snapshot_unavailable',
        `index=${currentIndex} component=${readerSnapshotComponentId}`,
      )
      transition.reset()
      return false
    }
    transition.prepareClose(
      targetId,
      currentIndex,
      currentImage,
      targetX,
      targetY,
      targetWidth,
      targetHeight,
      ThemeConstants.THUMB_RADIUS,
      readerSnapshot,
      readerIntrinsicWidth / readerIntrinsicHeight,
    )
    uiContext.postFrameCallback(new ReaderThumbnailTransitionFrameCallback((): void => {
      // Index owns the root proxy while Reader owns this callback. Give the root subscriber a full
      // render pass, then start on the following frame so the prepared target really exists.
      uiContext.postFrameCallback(new ReaderThumbnailTransitionFrameCallback((): void => {
        if (!transition.active() || transition.sourceComponentId !== targetId) {
          return
        }
        DiagnosticLogger.info('reader-transition', 'close_proxy_prepared', `index=${currentIndex}`)
        uiContext.animateTo({
          duration: ThemeConstants.ANIM_DURATION,
          curve: Curve.Friction,
          onFinish: () => {
            DiagnosticLogger.info('reader-transition', 'close_finished', `index=${currentIndex}`)
            closeReader(false)
          },
        }, () => {
          transition.startClosing()
        })
      }))
    }))
    return true
  }
}
