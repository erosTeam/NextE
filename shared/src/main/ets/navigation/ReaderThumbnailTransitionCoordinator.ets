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
const READER_TARGET_LAYOUT_STABLE_FRAMES: number = 2
const READER_TARGET_LAYOUT_MAX_FRAMES: number = 60

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

  static sourceSnapshotId(sourceComponentId: string): string {
    return sourceComponentId.length > 0 ? `${sourceComponentId}-content` : ''
  }

  static closeProxyHostId(): string {
    return 'reader_key_surface'
  }

  static currentTargetLayoutKey(uiContext: UIContext): string {
    const transition: ReaderThumbnailTransitionState = connectReaderThumbnailTransition()
    if (transition.sourceScope.length === 0) {
      return ''
    }
    const targetId: string = ReaderThumbnailTransitionCoordinator.sourceId(
      transition.sourceScope,
      transition.currentIndex,
    )
    try {
      const targetRect = uiContext.getComponentUtils().getRectangleById(targetId)
      const proxyHostRect = uiContext.getComponentUtils().getRectangleById(
        ReaderThumbnailTransitionCoordinator.closeProxyHostId(),
      )
      if (
        targetRect.size.width <= 0 || targetRect.size.height <= 0 ||
        proxyHostRect.size.width <= 0 || proxyHostRect.size.height <= 0
      ) {
        return ''
      }
      return `${Math.round(targetRect.windowOffset.x)},${Math.round(targetRect.windowOffset.y)},` +
        `${Math.round(targetRect.size.width)},${Math.round(targetRect.size.height)};` +
        `${Math.round(proxyHostRect.windowOffset.x)},${Math.round(proxyHostRect.windowOffset.y)},` +
        `${Math.round(proxyHostRect.size.width)},${Math.round(proxyHostRect.size.height)}`
    } catch (_error) {
      return ''
    }
  }

  private static waitForTargetLayoutFrame(
    uiContext: UIContext,
    stableLayoutKey: string,
    stableFrames: number,
    remainingFrames: number,
    resolve: (ready: boolean) => void,
  ): void {
    uiContext.postFrameCallback(new ReaderThumbnailTransitionFrameCallback((): void => {
      const currentLayoutKey: string = ReaderThumbnailTransitionCoordinator.currentTargetLayoutKey(uiContext)
      const currentStableFrames: number = currentLayoutKey.length > 0
        ? (currentLayoutKey === stableLayoutKey ? stableFrames + 1 : 1)
        : 0
      if (currentStableFrames >= READER_TARGET_LAYOUT_STABLE_FRAMES) {
        DiagnosticLogger.info(
          'reader-transition',
          'close_target_layout_ready',
          `target=${currentLayoutKey}`,
        )
        resolve(true)
        return
      }
      if (remainingFrames <= 1) {
        DiagnosticLogger.info(
          'reader-transition',
          'close_target_layout_unsettled',
          `current=${currentLayoutKey}`,
        )
        resolve(false)
        return
      }
      ReaderThumbnailTransitionCoordinator.waitForTargetLayoutFrame(
        uiContext,
        currentLayoutKey,
        currentStableFrames,
        remainingFrames - 1,
        resolve,
      )
    }))
  }

  static waitForTargetLayoutCommit(
    uiContext: UIContext,
  ): Promise<boolean> {
    return new Promise<boolean>((resolve: (ready: boolean) => void): void => {
      ReaderThumbnailTransitionCoordinator.waitForTargetLayoutFrame(
        uiContext,
        '',
        0,
        READER_TARGET_LAYOUT_MAX_FRAMES,
        resolve,
      )
    })
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
    // Keep the decoded image above an opaque thumbnail placeholder while it fades in. This makes
    // Image.onComplete's early callback harmless: an unpainted Image node is transparent, so it
    // cannot expose the black Reader canvas before its first bitmap reaches the display.
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
      const sourceSnapshotComponentId: string =
        ReaderThumbnailTransitionCoordinator.sourceSnapshotId(sourceComponentId)
      const snapshotComponentId: string = ReaderThumbnailTransitionCoordinator.componentAvailable(
        uiContext,
        sourceSnapshotComponentId,
      )
        ? sourceSnapshotComponentId
        : sourceComponentId
      const sourceSnapshot: image.PixelMap | undefined =
        ReaderThumbnailTransitionCoordinator.captureSourceImage(
          uiContext,
          snapshotComponentId,
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
    if (transition.waitingReader() && transition.galleryId !== galleryId) {
      DiagnosticLogger.info(
        'reader-transition',
        'open_gallery_mismatch',
        `expected=${transition.galleryId} actual=${galleryId}`,
      )
      transition.reset()
    }
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
    galleryId: string,
    readerSnapshotComponentId: string,
    readerIntrinsicWidth: number,
    readerIntrinsicHeight: number,
    closeReader: (animated: boolean) => void,
  ): boolean {
    const transition: ReaderThumbnailTransitionState = connectReaderThumbnailTransition()
    if (!transition.openingCanReverse() || transition.galleryId !== galleryId) {
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

  static notifyReaderImageReady(uiContext: UIContext, galleryId: string, page: number): void {
    const transition: ReaderThumbnailTransitionState = connectReaderThumbnailTransition()
    if (transition.galleryId !== galleryId) {
      return
    }
    if (transition.markReaderImageReady(page)) {
      DiagnosticLogger.info('reader-transition', 'open_handoff_started', `index=${transition.currentIndex}`)
      ReaderThumbnailTransitionCoordinator.startOpeningHandoff(uiContext, transition)
    }
  }

  static close(
    uiContext: UIContext,
    galleryId: string,
    currentIndex: number,
    currentImage: EhGalleryImage,
    readerImageReady: boolean,
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
    if (transition.galleryId !== galleryId) {
      DiagnosticLogger.info(
        'reader-transition',
        'close_gallery_mismatch',
        `expected=${transition.galleryId} actual=${galleryId}`,
      )
      transition.reset()
      return false
    }
    if (!transition.normalCloseReadyFor(galleryId)) {
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
    let proxyHostWidth: number = 0
    let proxyHostHeight: number = 0
    try {
      const targetRect = uiContext.getComponentUtils().getRectangleById(targetId)
      const proxyHostRect = uiContext.getComponentUtils().getRectangleById(
        ReaderThumbnailTransitionCoordinator.closeProxyHostId(),
      )
      targetX = uiContext.px2vp(targetRect.windowOffset.x - proxyHostRect.windowOffset.x)
      targetY = uiContext.px2vp(targetRect.windowOffset.y - proxyHostRect.windowOffset.y)
      targetWidth = uiContext.px2vp(targetRect.size.width)
      targetHeight = uiContext.px2vp(targetRect.size.height)
      proxyHostWidth = uiContext.px2vp(proxyHostRect.size.width)
      proxyHostHeight = uiContext.px2vp(proxyHostRect.size.height)
      if (
        targetWidth <= 0 || targetHeight <= 0 ||
        proxyHostWidth <= 0 || proxyHostHeight <= 0
      ) {
        transition.reset()
        return false
      }
      DiagnosticLogger.info(
        'reader-transition',
        'close_target_measured',
        `targetWindow=${Math.round(targetRect.windowOffset.x)},${Math.round(targetRect.windowOffset.y)} ` +
          `proxyHostWindow=${Math.round(proxyHostRect.windowOffset.x)},` +
          `${Math.round(proxyHostRect.windowOffset.y)} ` +
          `local=${targetX},${targetY} size=${targetWidth},${targetHeight}`,
      )
    } catch (error) {
      DiagnosticLogger.info(
        'reader-transition',
        'close_target_measure_failed',
        `index=${currentIndex} target=${targetId} error=${error}`,
      )
      transition.reset()
      return false
    }
    const readerSnapshot: image.PixelMap | undefined = readerImageReady
      ? ReaderThumbnailTransitionCoordinator.captureReaderImage(
        uiContext,
        readerSnapshotComponentId,
        readerIntrinsicWidth,
        readerIntrinsicHeight,
      )
      : undefined
    const closeTargetSnapshotComponentId: string =
      ReaderThumbnailTransitionCoordinator.sourceSnapshotId(targetId)
    const closeTargetSnapshotId: string = ReaderThumbnailTransitionCoordinator.componentAvailable(
      uiContext,
      closeTargetSnapshotComponentId,
    )
      ? closeTargetSnapshotComponentId
      : targetId
    const closeTargetSnapshot: image.PixelMap | undefined =
      ReaderThumbnailTransitionCoordinator.captureSourceImage(uiContext, closeTargetSnapshotId)
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
        `index=${currentIndex} component=${readerSnapshotComponentId} ready=${readerImageReady} ` +
          `targetSnapshot=${closeTargetSnapshot !== undefined}`,
      )
    }
    transition.prepareClose(
      targetId,
      currentIndex,
      currentImage,
      proxyHostWidth,
      proxyHostHeight,
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
