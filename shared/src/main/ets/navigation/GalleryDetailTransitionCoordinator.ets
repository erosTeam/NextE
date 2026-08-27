import { image } from '@kit.ImageKit'
import { FrameCallback } from '@kit.ArkUI'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { connectGalleryDetailTransition } from '../state/GalleryDetailTransitionState'
import {
  connectGalleryDetailTransitionSettings,
  GalleryDetailTransitionMode,
} from '../state/GalleryDetailTransitionSettingsState'
import { connectNavStack } from '../state/NavStackHolder'
import { ThemeConstants } from '../theme/ThemeConstants'

class GalleryDetailCaptureFrameCallback extends FrameCallback {
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

/**
 * Shared launcher for every gallery-card -> GalleryDetail transition surface. Pages only provide
 * the real card node id and their existing navigation action; capture, eligibility and cleanup stay
 * identical across Home, Toplist, Favorites, Search and Viewed History.
 */
export class GalleryDetailTransitionCoordinator {
  private static scopeSeed: number = 0
  private static opening: boolean = false

  static syncDetailCoverTarget(uiContext: UIContext): boolean {
    const transition = connectGalleryDetailTransition()
    if (!transition.isCoverExpand() || transition.targetCoverComponentId.length === 0) {
      return false
    }
    transition.clearCoverTarget()
    try {
      const rootRect = uiContext.getComponentUtils().getRectangleById('nexte-root-navigation')
      const coverRect = uiContext.getComponentUtils()
        .getRectangleById(transition.targetCoverComponentId)
      const rootWidth: number = uiContext.px2vp(rootRect.size.width)
      const rootHeight: number = uiContext.px2vp(rootRect.size.height)
      const width: number = uiContext.px2vp(coverRect.size.width)
      const height: number = uiContext.px2vp(coverRect.size.height)
      if (width <= 0 || height <= 0) {
        return false
      }
      const x: number = uiContext.px2vp(coverRect.windowOffset.x - rootRect.windowOffset.x)
      const y: number = uiContext.px2vp(coverRect.windowOffset.y - rootRect.windowOffset.y)
      if (x + width <= 0 || y + height <= 0 || x >= rootWidth || y >= rootHeight) {
        return false
      }
      transition.setCoverTarget(
        x,
        y,
        width,
        height,
        ThemeConstants.DETAIL_COVER_RADIUS,
      )
      return true
    } catch (_error) {
      return false
    }
  }

  static allocateScope(owner: string): string {
    GalleryDetailTransitionCoordinator.scopeSeed += 1
    return `gallery-list-${owner}-${GalleryDetailTransitionCoordinator.scopeSeed}`
  }

  static sourceId(scope: string, mode: string, galleryId: string): string {
    return `${scope}-${mode}-${galleryId}`
  }

  static sourceCoverId(scope: string, mode: string, galleryId: string): string {
    return `${GalleryDetailTransitionCoordinator.sourceId(scope, mode, galleryId)}-cover`
  }

  static open(
    uiContext: UIContext,
    componentId: string,
    galleryId: string,
    openDetail: () => void,
    sourceCoverComponentId: string = '',
    coverUrl: string = '',
  ): void {
    if (GalleryDetailTransitionCoordinator.opening) {
      return
    }
    const transition = connectGalleryDetailTransition()
    transition.reset()
    const selectedMode: string = connectGalleryDetailTransitionSettings().mode
    if (selectedMode === GalleryDetailTransitionMode.SYSTEM || connectNavStack().isSplitMode) {
      openDetail()
      return
    }

    GalleryDetailTransitionCoordinator.opening = true
    let transitionMode: string = selectedMode
    let cardSnapshot: image.PixelMap | undefined = undefined
    let coverSnapshot: image.PixelMap | undefined = undefined
    try {
      const rect = uiContext.getComponentUtils().getRectangleById(componentId)
      const rootRect = uiContext.getComponentUtils().getRectangleById('nexte-root-navigation')
      const targetWidth: number = uiContext.px2vp(rootRect.size.width)
      const targetHeight: number = uiContext.px2vp(rootRect.size.height)
      const sourceWidth: number = uiContext.px2vp(rect.size.width)
      const sourceHeight: number = uiContext.px2vp(rect.size.height)
      const sourceX: number = uiContext.px2vp(rect.windowOffset.x - rootRect.windowOffset.x)
      const sourceY: number = uiContext.px2vp(rect.windowOffset.y - rootRect.windowOffset.y)
      let coverX: number = sourceX
      let coverY: number = sourceY
      let coverWidth: number = sourceWidth
      let coverHeight: number = sourceHeight
      let preserveSourceCoverBackground: boolean = false
      if (targetWidth <= 0 || targetHeight <= 0 || sourceWidth <= 0 || sourceHeight <= 0) {
        GalleryDetailTransitionCoordinator.opening = false
        openDetail()
        return
      }

      if (
        transitionMode === GalleryDetailTransitionMode.COVER_EXPAND &&
        sourceCoverComponentId.length > 0
      ) {
        try {
          const coverRect = uiContext.getComponentUtils().getRectangleById(sourceCoverComponentId)
          coverWidth = uiContext.px2vp(coverRect.size.width)
          coverHeight = uiContext.px2vp(coverRect.size.height)
          coverX = uiContext.px2vp(coverRect.windowOffset.x - rootRect.windowOffset.x)
          coverY = uiContext.px2vp(coverRect.windowOffset.y - rootRect.windowOffset.y)
          if (coverWidth <= 0 || coverHeight <= 0) {
            transitionMode = GalleryDetailTransitionMode.SEAMLESS
          } else {
            coverSnapshot = uiContext.getComponentSnapshot()
              .getSync(sourceCoverComponentId, { waitUntilRenderFinished: true })
            try {
              const coverBackgroundComponentId: string = `${sourceCoverComponentId}-background`
              const coverBackgroundRect = uiContext.getComponentUtils()
                .getRectangleById(coverBackgroundComponentId)
              preserveSourceCoverBackground = coverBackgroundRect.size.width > 0 &&
                coverBackgroundRect.size.height > 0
            } catch (_backgroundError) {
              preserveSourceCoverBackground = false
            }
          }
        } catch (error) {
          DiagnosticLogger.info(
            'gallery-detail-transition',
            'cover_snapshot_fallback',
            `gid=${galleryId} source=${sourceCoverComponentId} error=${error}`,
          )
          transitionMode = GalleryDetailTransitionMode.SEAMLESS
        }
      } else if (transitionMode === GalleryDetailTransitionMode.COVER_EXPAND) {
        transitionMode = GalleryDetailTransitionMode.SEAMLESS
      }

      cardSnapshot = uiContext.getComponentSnapshot()
        .getSync(componentId, { waitUntilRenderFinished: true })
      transition.beginSourceHandoff(
        transitionMode,
        componentId,
        sourceCoverComponentId,
        preserveSourceCoverBackground,
        `${componentId}-detail-cover`,
        sourceX,
        sourceY,
        sourceWidth,
        sourceHeight,
        cardSnapshot,
        coverX,
        coverY,
        coverWidth,
        coverHeight,
        ThemeConstants.THUMB_RADIUS,
        coverSnapshot,
        coverUrl,
      )
      cardSnapshot = undefined
      coverSnapshot = undefined
      const captureRootAndOpen: () => void = (): void => {
        let sourceSnapshot: image.PixelMap | undefined = undefined
        try {
          sourceSnapshot = uiContext.getComponentSnapshot()
            .getSync('nexte-root-navigation', { waitUntilRenderFinished: true })
          transition.prepare(
            galleryId,
            Math.max(0.08, Math.min(1, sourceWidth / targetWidth)),
            Math.max(0.08, Math.min(1, sourceHeight / targetHeight)),
            sourceX + sourceWidth / 2 - targetWidth / 2,
            sourceY + sourceHeight / 2 - targetHeight / 2,
            ThemeConstants.RADIUS_CARD,
            targetWidth,
            targetHeight,
            sourceSnapshot,
          )
          sourceSnapshot = undefined
          DiagnosticLogger.info(
            'gallery-detail-transition',
            'snapshots_ready',
            `gid=${galleryId} source=${componentId}`,
          )
        } catch (error) {
          if (sourceSnapshot !== undefined) {
            sourceSnapshot.release().catch((_releaseError: Error) => {})
          }
          DiagnosticLogger.info(
            'gallery-detail-transition',
            'source_snapshot_failed',
            `gid=${galleryId} source=${componentId} error=${error}`,
          )
          transition.reset()
        }
        GalleryDetailTransitionCoordinator.opening = false
        openDetail()
      }
      if (preserveSourceCoverBackground) {
        uiContext.postFrameCallback(new GalleryDetailCaptureFrameCallback((): void => {
          let backgroundCardSnapshot: image.PixelMap | undefined = undefined
          try {
            backgroundCardSnapshot = uiContext.getComponentSnapshot()
              .getSync(componentId, { waitUntilRenderFinished: true })
            transition.completePreservedSourceCardSnapshot(componentId, backgroundCardSnapshot)
            backgroundCardSnapshot = undefined
          } catch (error) {
            if (backgroundCardSnapshot !== undefined) {
              backgroundCardSnapshot.release().catch((_releaseError: Error) => {})
            }
            DiagnosticLogger.info(
              'gallery-detail-transition',
              'background_card_snapshot_fallback',
              `gid=${galleryId} source=${componentId} error=${error}`,
            )
            transition.completePreservedSourceCardSnapshot(componentId, undefined)
          }
          uiContext.postFrameCallback(new GalleryDetailCaptureFrameCallback(captureRootAndOpen))
        }))
      } else {
        uiContext.postFrameCallback(new GalleryDetailCaptureFrameCallback(captureRootAndOpen))
      }
      return
    } catch (error) {
      if (cardSnapshot !== undefined) {
        cardSnapshot.release().catch((_releaseError: Error) => {})
      }
      if (coverSnapshot !== undefined) {
        coverSnapshot.release().catch((_releaseError: Error) => {})
      }
      DiagnosticLogger.info(
        'gallery-detail-transition',
        'snapshot_failed',
        `gid=${galleryId} source=${componentId} error=${error}`,
      )
      GalleryDetailTransitionCoordinator.opening = false
      transition.reset()
    }
    openDetail()
  }
}
