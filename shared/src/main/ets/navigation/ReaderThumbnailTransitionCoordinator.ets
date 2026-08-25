import { FrameCallback } from '@kit.ArkUI'
import { image } from '@kit.ImageKit'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { EhGalleryImage } from '../model/EhGalleryImage'
import { connectGalleryDetailTransitionSettings } from '../state/GalleryDetailTransitionSettingsState'
import {
  connectReaderThumbnailTransition,
  ReaderThumbnailTransitionState,
} from '../state/ReaderThumbnailTransitionState'
import { ThemeConstants } from '../theme/ThemeConstants'

const READER_OPEN_CONTENT_HANDOFF_FRACTION: number = 0.22
const READER_CLOSE_TARGET_HANDOFF_START: number = 0.55
const READER_CLOSE_TARGET_HANDOFF_END: number = 0.90

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

/** Coordinates the real thumbnail node with one root-level Reader flight proxy. */
export class ReaderThumbnailTransitionCoordinator {
  private static scopeSeed: number = 0

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

  private static captureSourceImage(
    uiContext: UIContext,
    componentId: string,
  ): image.PixelMap | undefined {
    try {
      return uiContext.getComponentSnapshot().getSync(componentId, {
        waitUntilRenderFinished: true,
      })
    } catch (error) {
      DiagnosticLogger.info(
        'reader-transition',
        'source_snapshot_failed',
        `component=${componentId} error=${error}`,
      )
      return undefined
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

  private static startOpeningHandoff(
    uiContext: UIContext,
    transition: ReaderThumbnailTransitionState,
  ): void {
    if (!transition.openingHandoff()) {
      return
    }
    uiContext.animateTo({
      duration: ThemeConstants.ANIM_DURATION * READER_OPEN_CONTENT_HANDOFF_FRACTION,
      curve: Curve.EaseOut,
      onFinish: () => {
        if (transition.finishOpeningHandoff()) {
          DiagnosticLogger.info('reader-transition', 'open_finished', `index=${transition.currentIndex}`)
        }
      },
    }, () => {
      transition.startOpeningHandoff()
    })
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
      !connectGalleryDetailTransitionSettings().readerThumbnailEnabled ||
      !ReaderThumbnailTransitionCoordinator.componentAvailable(uiContext, sourceComponentId)
    ) {
      openReader(true)
      return
    }
    try {
      const rootRect = uiContext.getComponentUtils().getRectangleById('nexte-root-navigation')
      const sourceRect = uiContext.getComponentUtils().getRectangleById(sourceComponentId)
      const rootWidth: number = uiContext.px2vp(rootRect.size.width)
      const rootHeight: number = uiContext.px2vp(rootRect.size.height)
      const sourceX: number = uiContext.px2vp(sourceRect.windowOffset.x - rootRect.windowOffset.x)
      const sourceY: number = uiContext.px2vp(sourceRect.windowOffset.y - rootRect.windowOffset.y)
      const sourceWidth: number = uiContext.px2vp(sourceRect.size.width)
      const sourceHeight: number = uiContext.px2vp(sourceRect.size.height)
      if (
        rootWidth <= 0 || rootHeight <= 0 ||
        sourceWidth <= 0 || sourceHeight <= 0
      ) {
        openReader(true)
        return
      }
      const sourceSnapshot: image.PixelMap | undefined =
        ReaderThumbnailTransitionCoordinator.captureSourceImage(
          uiContext,
          sourceComponentId,
        )
      if (sourceSnapshot === undefined) {
        transition.reset()
        openReader(true)
        return
      }
      transition.arm(
        sourceScope,
        sourceComponentId,
        galleryId,
        index,
        image,
        rootWidth,
        rootHeight,
        sourceX,
        sourceY,
        sourceWidth,
        sourceHeight,
        ThemeConstants.THUMB_RADIUS,
        sourceSnapshot,
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

  static startOpening(uiContext: UIContext, galleryId: string): void {
    const transition: ReaderThumbnailTransitionState = connectReaderThumbnailTransition()
    if (!transition.waitingReader()) {
      // With the default navigation transition there is no flight state. onShown already means the
      // Reader route owns the window; wait one rendered frame before publishing the initial page.
      uiContext.postFrameCallback(new ReaderThumbnailTransitionFrameCallback((): void => {
        transition.markPresentationSettled(galleryId)
      }))
      return
    }
    transition.prepareOpening()
    // First render the proxy at the source rectangle with the real thumbnail already hidden. Start
    // the flight only on the next frame so no implicit source snapshot or opacity interpolation can
    // create a second copy.
    uiContext.postFrameCallback(new ReaderThumbnailTransitionFrameCallback((): void => {
      if (!transition.opening()) {
        return
      }
      uiContext.animateTo({
        duration: ThemeConstants.ANIM_DURATION,
        curve: Curve.Friction,
        onFinish: () => {
          if (!transition.opening()) {
            return
          }
          if (!transition.finishOpeningFlight()) {
            return
          }
          DiagnosticLogger.info(
            'reader-transition',
            'open_proxy_handoff_started',
            `index=${transition.currentIndex}`,
          )
          // The Reader-owned placeholder and its loading/chrome layers render underneath the still
          // opaque root proxy. On the next frame, remove only the root proxy; Reader is already
          // interactive even if the full image takes seconds to decode.
          uiContext.postFrameCallback(new ReaderThumbnailTransitionFrameCallback((): void => {
            if (!transition.openingProxyHandoff()) {
              return
            }
            const decodedHandoff: boolean = transition.finishOpeningProxyHandoff()
            transition.markPresentationSettled(galleryId)
            DiagnosticLogger.info(
              'reader-transition',
              decodedHandoff ? 'open_content_handoff_started' : 'open_flight_finished_waiting',
              `index=${transition.currentIndex}`,
            )
            if (decodedHandoff) {
              ReaderThumbnailTransitionCoordinator.startOpeningHandoff(uiContext, transition)
            }
          }))
        },
      }, () => {
        transition.startOpeningFlight()
      })
    }))
  }

  static reverseOpening(
    uiContext: UIContext,
    readerSnapshotComponentId: string,
    readerIntrinsicWidth: number,
    readerIntrinsicHeight: number,
    closeReader: (animated: boolean) => void,
  ): boolean {
    const transition: ReaderThumbnailTransitionState = connectReaderThumbnailTransition()
    if (!transition.openingCanReverse()) {
      return false
    }
    const reverseSnapshot: image.PixelMap | undefined = transition.openingHandoff()
      ? ReaderThumbnailTransitionCoordinator.captureReaderImage(
        uiContext,
        readerSnapshotComponentId,
        readerIntrinsicWidth,
        readerIntrinsicHeight,
      )
      : undefined
    if (!transition.prepareOpeningReverse(reverseSnapshot)) {
      if (reverseSnapshot !== undefined) {
        reverseSnapshot.release().catch((_error: Error) => {})
      }
      return false
    }
    DiagnosticLogger.info(
      'reader-transition',
      'open_reverse_requested',
      `index=${transition.currentIndex} readerSnapshot=${reverseSnapshot !== undefined}`,
    )
    // Let the ownership change paint first. The next animateTo retargets the same geometry and
    // opacity properties, so ArkUI continues from their current presentation values.
    uiContext.postFrameCallback(new ReaderThumbnailTransitionFrameCallback((): void => {
      if (!transition.openingReverse()) {
        return
      }
      uiContext.animateTo({
        duration: ThemeConstants.ANIM_DURATION,
        curve: Curve.Friction,
        onFinish: () => {
          if (!transition.openingReverse()) {
            return
          }
          DiagnosticLogger.info(
            'reader-transition',
            'open_reverse_finished',
            `index=${transition.currentIndex}`,
          )
          closeReader(false)
        },
      }, () => {
        transition.startOpeningReverse()
      })
    }))
    return true
  }

  static notifyReaderImageReady(uiContext: UIContext, page: number): void {
    const transition: ReaderThumbnailTransitionState = connectReaderThumbnailTransition()
    if (transition.markReaderImageReady(page)) {
      DiagnosticLogger.info('reader-transition', 'open_handoff_started', `index=${transition.currentIndex}`)
      ReaderThumbnailTransitionCoordinator.startOpeningHandoff(uiContext, transition)
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
    const closeTargetSnapshot: image.PixelMap | undefined =
      ReaderThumbnailTransitionCoordinator.captureSourceImage(uiContext, targetId)
    if (readerSnapshot === undefined && closeTargetSnapshot === undefined) {
      DiagnosticLogger.info(
        'reader-transition',
        'close_snapshots_unavailable',
        `index=${currentIndex} component=${readerSnapshotComponentId} target=${targetId}`,
      )
      transition.reset()
      return false
    }
    if (readerSnapshot === undefined) {
      DiagnosticLogger.info(
        'reader-transition',
        'close_snapshot_fallback',
        `index=${currentIndex} component=${readerSnapshotComponentId} ` +
          `targetSnapshot=${closeTargetSnapshot !== undefined}`,
      )
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
      readerSnapshot !== undefined && readerIntrinsicHeight > 0
        ? readerIntrinsicWidth / readerIntrinsicHeight
        : 0,
      closeTargetSnapshot,
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
            if (!transition.finishClosingFlight()) {
              return
            }
            // The state change above unhides the real thumbnail while the endpoint proxy still
            // covers it. Remove Reader only after that underlying frame has actually rendered.
            uiContext.postFrameCallback(new ReaderThumbnailTransitionFrameCallback((): void => {
              if (!transition.closeHandoff()) {
                return
              }
              DiagnosticLogger.info('reader-transition', 'close_handoff_ready', `index=${currentIndex}`)
              closeReader(false)
            }))
          },
        }, () => {
          transition.startClosing()
        })
        if (closeTargetSnapshot !== undefined) {
          uiContext.animateTo({
            delay: ThemeConstants.ANIM_DURATION * READER_CLOSE_TARGET_HANDOFF_START,
            duration: ThemeConstants.ANIM_DURATION * (
              READER_CLOSE_TARGET_HANDOFF_END - READER_CLOSE_TARGET_HANDOFF_START
            ),
            curve: Curve.EaseInOut,
          }, () => {
            transition.showCloseTargetSnapshot()
          })
        }
      }))
    }))
    return true
  }
}
