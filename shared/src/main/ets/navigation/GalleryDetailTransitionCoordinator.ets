import { image } from '@kit.ImageKit'
import { FrameCallback } from '@kit.ArkUI'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import {
  connectGalleryDetailTransition,
  GalleryDetailTransitionPhase,
} from '../state/GalleryDetailTransitionState'
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
    try {
      const rootRect = uiContext.getComponentUtils().getRectangleById('nexte-root-navigation')
      const coverRect = uiContext.getComponentUtils()
        .getRectangleById(transition.targetCoverComponentId)
      const rootWidth: number = uiContext.px2vp(rootRect.size.width)
      const rootHeight: number = uiContext.px2vp(rootRect.size.height)
      const width: number = uiContext.px2vp(coverRect.size.width)
      const height: number = uiContext.px2vp(coverRect.size.height)
      if (width <= 0 || height <= 0) {
        return transition.coverTargetReadyForRoot(rootWidth, rootHeight)
      }
      const x: number = uiContext.px2vp(coverRect.windowOffset.x - rootRect.windowOffset.x)
      const y: number = uiContext.px2vp(coverRect.windowOffset.y - rootRect.windowOffset.y)
      if (x + width <= 0 || y + height <= 0 || x >= rootWidth || y >= rootHeight) {
        transition.clearCoverTarget()
        return false
      }
      transition.setCoverTarget(
        x,
        y,
        width,
        height,
        ThemeConstants.DETAIL_COVER_RADIUS,
        rootWidth,
        rootHeight,
      )
      return true
    } catch (_error) {
      return false
    }
  }

  static sourceGeometryNeedsRefresh(uiContext: UIContext): boolean {
    const transition = connectGalleryDetailTransition()
    if (
      !transition.eligible ||
      transition.phase !== GalleryDetailTransitionPhase.OPEN ||
      transition.sourceComponentId.length === 0
    ) {
      return false
    }
    try {
      const rootRect = uiContext.getComponentUtils().getRectangleById('nexte-root-navigation')
      const rootWidth: number = uiContext.px2vp(rootRect.size.width)
      const rootHeight: number = uiContext.px2vp(rootRect.size.height)
      return Math.abs(rootWidth - transition.rootWidth) > 0.5 ||
        Math.abs(rootHeight - transition.rootHeight) > 0.5
    } catch (_error) {
      return false
    }
  }

  static prepareIndependentPopSurface(uiContext: UIContext): boolean {
    const transition = connectGalleryDetailTransition()
    let snapshot: image.PixelMap | undefined = undefined
    try {
      const rootRect = uiContext.getComponentUtils().getRectangleById('nexte-root-navigation')
      const rootWidth: number = uiContext.px2vp(rootRect.size.width)
      const rootHeight: number = uiContext.px2vp(rootRect.size.height)
      if (rootWidth <= 0 || rootHeight <= 0) {
        return false
      }
      snapshot = uiContext.getComponentSnapshot()
        .getSync('nexte-root-navigation', { waitUntilRenderFinished: true })
      if (!transition.prepareIndependentPopSurface(snapshot, rootWidth, rootHeight)) {
        snapshot.release().catch((_error: Error) => {})
        return false
      }
      snapshot = undefined
      return true
    } catch (error) {
      if (snapshot !== undefined) {
        snapshot.release().catch((_releaseError: Error) => {})
      }
      DiagnosticLogger.info(
        'gallery-detail-transition',
        'detail_surface_snapshot_failed',
        `gid=${transition.galleryId} error=${error}`,
      )
      return false
    }
  }

  static refreshSourceGeometryForPop(
    uiContext: UIContext,
    onComplete: (success: boolean) => void,
  ): void {
    const transition = connectGalleryDetailTransition()
    const componentId: string = transition.beginSourceRecapture()
    if (componentId.length === 0) {
      onComplete(false)
      return
    }

    let rootWidth: number = 0
    let rootHeight: number = 0
    let sourceX: number = 0
    let sourceY: number = 0
    let sourceWidth: number = 0
    let sourceHeight: number = 0
    let coverX: number = 0
    let coverY: number = 0
    let coverWidth: number = 0
    let coverHeight: number = 0
    let coverSnapshot: image.PixelMap | undefined = undefined
    let sourceSurfaceX: number = 0
    let sourceSurfaceY: number = 0
    let sourceSurfaceWidth: number = 0
    let sourceSurfaceHeight: number = 0
    let currentSourceSnapshot: image.PixelMap | undefined = undefined
    let cardSnapshot: image.PixelMap | undefined = undefined

    const finishAfterHiddenFrame: (success: boolean) => void = (success: boolean): void => {
      uiContext.postFrameCallback(new GalleryDetailCaptureFrameCallback((): void => {
        onComplete(success)
      }))
    }
    const fail: (reason: string) => void = (reason: string): void => {
      if (coverSnapshot !== undefined) {
        coverSnapshot.release().catch((_releaseError: Error) => {})
        coverSnapshot = undefined
      }
      if (currentSourceSnapshot !== undefined) {
        currentSourceSnapshot.release().catch((_releaseError: Error) => {})
        currentSourceSnapshot = undefined
      }
      if (cardSnapshot !== undefined) {
        cardSnapshot.release().catch((_releaseError: Error) => {})
        cardSnapshot = undefined
      }
      transition.cancelSourceRecapture(componentId)
      DiagnosticLogger.info(
        'gallery-detail-transition',
        'source_recapture_failed',
        `gid=${transition.galleryId} source=${componentId} reason=${reason}`,
      )
      finishAfterHiddenFrame(false)
    }
    const captureSourceSurface: () => void = (): void => {
      if (
        transition.independentPopSurfaceActive ||
        transition.sourceSurfaceComponentId.length === 0 ||
        currentSourceSnapshot !== undefined
      ) {
        return
      }
      try {
        const rootRect = uiContext.getComponentUtils().getRectangleById('nexte-root-navigation')
        const sourceSurfaceRect = uiContext.getComponentUtils()
          .getRectangleById(transition.sourceSurfaceComponentId)
        sourceSurfaceWidth = uiContext.px2vp(sourceSurfaceRect.size.width)
        sourceSurfaceHeight = uiContext.px2vp(sourceSurfaceRect.size.height)
        sourceSurfaceX = uiContext.px2vp(
          sourceSurfaceRect.windowOffset.x - rootRect.windowOffset.x,
        )
        sourceSurfaceY = uiContext.px2vp(
          sourceSurfaceRect.windowOffset.y - rootRect.windowOffset.y,
        )
        if (sourceSurfaceWidth > 0 && sourceSurfaceHeight > 0) {
          currentSourceSnapshot = uiContext.getComponentSnapshot()
            .getSync(transition.sourceSurfaceComponentId, { waitUntilRenderFinished: true })
        }
      } catch (surfaceError) {
        DiagnosticLogger.info(
          'gallery-detail-transition',
          'source_surface_snapshot_failed',
          `gid=${transition.galleryId} source=${transition.sourceSurfaceComponentId} ` +
            `error=${surfaceError}`,
        )
      }
    }
    const completeAfterSourceHidden: () => void = (): void => {
      try {
        captureSourceSurface()
        if (
          cardSnapshot === undefined ||
          (!transition.independentPopSurfaceActive &&
            (currentSourceSnapshot === undefined ||
              sourceSurfaceWidth <= 0 ||
              sourceSurfaceHeight <= 0))
        ) {
          fail('missing_current_source_surface')
          return
        }
        const completed: boolean = transition.completeSourceRecapture(
          componentId,
          rootWidth,
          rootHeight,
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
          currentSourceSnapshot,
          sourceSurfaceX,
          sourceSurfaceY,
          sourceSurfaceWidth,
          sourceSurfaceHeight,
        )
        if (!completed) {
          cardSnapshot.release().catch((_releaseError: Error) => {})
          if (coverSnapshot !== undefined) {
            coverSnapshot.release().catch((_releaseError: Error) => {})
          }
          if (currentSourceSnapshot !== undefined) {
            currentSourceSnapshot.release().catch((_releaseError: Error) => {})
          }
          cardSnapshot = undefined
          coverSnapshot = undefined
          currentSourceSnapshot = undefined
          finishAfterHiddenFrame(false)
          return
        }
        cardSnapshot = undefined
        coverSnapshot = undefined
        currentSourceSnapshot = undefined
        DiagnosticLogger.info(
          'gallery-detail-transition',
          'source_recaptured',
          `gid=${transition.galleryId} source=${componentId} root=${rootWidth}x${rootHeight} ` +
            `card=${sourceX},${sourceY},${sourceWidth}x${sourceHeight}`,
        )
        finishAfterHiddenFrame(true)
      } catch (error) {
        fail(`${error}`)
      }
    }
    const captureCard: () => void = (): void => {
      try {
        cardSnapshot = uiContext.getComponentSnapshot()
          .getSync(componentId, { waitUntilRenderFinished: true })
        if (!transition.hideSourceForSurfaceCapture(componentId)) {
          fail('source_hide_before_surface_capture_failed')
          return
        }
        // The destination list is now active, but its virtualized item still needs rendered-frame
        // barriers after the source card becomes Hidden. Independent POP renders that live list
        // directly; only the legacy in-route path needs a captured source surface afterward.
        uiContext.postFrameCallback(new GalleryDetailCaptureFrameCallback((): void => {
          uiContext.postFrameCallback(new GalleryDetailCaptureFrameCallback(
            completeAfterSourceHidden,
          ))
        }))
      } catch (error) {
        fail(`${error}`)
      }
    }

    // Rendering the retained source behind the still-opaque detail page gives ComponentUtils and
    // ComponentSnapshot the actual post-rotation card. No coordinate rotation or cached portrait
    // aspect is inferred here.
    uiContext.postFrameCallback(new GalleryDetailCaptureFrameCallback((): void => {
      try {
        const rootRect = uiContext.getComponentUtils().getRectangleById('nexte-root-navigation')
        const sourceRect = uiContext.getComponentUtils().getRectangleById(componentId)
        rootWidth = uiContext.px2vp(rootRect.size.width)
        rootHeight = uiContext.px2vp(rootRect.size.height)
        sourceWidth = uiContext.px2vp(sourceRect.size.width)
        sourceHeight = uiContext.px2vp(sourceRect.size.height)
        sourceX = uiContext.px2vp(sourceRect.windowOffset.x - rootRect.windowOffset.x)
        sourceY = uiContext.px2vp(sourceRect.windowOffset.y - rootRect.windowOffset.y)
        if (rootWidth <= 0 || rootHeight <= 0 || sourceWidth <= 0 || sourceHeight <= 0) {
          fail('invalid_current_geometry')
          return
        }

        if (transition.isCoverExpand()) {
          if (transition.sourceCoverComponentId.length === 0) {
            fail('missing_source_cover_id')
            return
          }
          const coverRect = uiContext.getComponentUtils()
            .getRectangleById(transition.sourceCoverComponentId)
          coverWidth = uiContext.px2vp(coverRect.size.width)
          coverHeight = uiContext.px2vp(coverRect.size.height)
          coverX = uiContext.px2vp(coverRect.windowOffset.x - rootRect.windowOffset.x)
          coverY = uiContext.px2vp(coverRect.windowOffset.y - rootRect.windowOffset.y)
          if (coverWidth <= 0 || coverHeight <= 0) {
            fail('invalid_current_cover_geometry')
            return
          }
          coverSnapshot = uiContext.getComponentSnapshot()
            .getSync(transition.sourceCoverComponentId, { waitUntilRenderFinished: true })
        }

        if (transition.isCoverExpand() && transition.preserveSourceCoverBackground) {
          uiContext.postFrameCallback(new GalleryDetailCaptureFrameCallback((): void => {
            uiContext.postFrameCallback(new GalleryDetailCaptureFrameCallback((): void => {
              transition.hideSourceCoverForRecapture()
              uiContext.postFrameCallback(new GalleryDetailCaptureFrameCallback(captureCard))
            }))
          }))
          return
        }
        // A retained list item can expose cached image/tag render groups one frame before ordinary
        // Text and Symbol children. Capture both the card and its current list surface only after two
        // further rendered-frame boundaries; this is a paint barrier, not a millisecond delay.
        uiContext.postFrameCallback(new GalleryDetailCaptureFrameCallback((): void => {
          uiContext.postFrameCallback(new GalleryDetailCaptureFrameCallback(captureCard))
        }))
      } catch (error) {
        fail(`${error}`)
      }
    }))
  }

  static finishPostPopHandoff(
    uiContext: UIContext,
    onComplete: () => void,
  ): boolean {
    const transition = connectGalleryDetailTransition()
    if (!transition.beginPostPopHandoff()) {
      return false
    }
    uiContext.postFrameCallback(new GalleryDetailCaptureFrameCallback((): void => {
      if (!transition.postPopHandoffActive()) {
        return
      }
      uiContext.postFrameCallback(new GalleryDetailCaptureFrameCallback((): void => {
        if (transition.postPopHandoffActive()) {
          onComplete()
        }
      }))
    }))
    return true
  }

  static finishNavigationBeforeIndependentPop(
    uiContext: UIContext,
    finishNavigation: () => void,
    onSourceReady: () => void,
  ): void {
    const transition = connectGalleryDetailTransition()
    // First render the opaque detail snapshot above Navigation. Only then finish POP so the real source
    // route and its HDS chrome can become active underneath without exposing an intermediate frame.
    uiContext.postFrameCallback(new GalleryDetailCaptureFrameCallback((): void => {
      if (!transition.independentPopSurfaceVisible()) {
        return
      }
      finishNavigation()
      // HDS applies the destination route and its title/tab chrome on rendered-frame boundaries. Wait
      // for two such boundaries before shrinking the snapshot; no visual millisecond delay is inferred.
      uiContext.postFrameCallback(new GalleryDetailCaptureFrameCallback((): void => {
        uiContext.postFrameCallback(new GalleryDetailCaptureFrameCallback((): void => {
          if (transition.independentPopSurfaceVisible()) {
            onSourceReady()
          }
        }))
      }))
    }))
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

  static sourceSurfaceId(scope: string, mode: string): string {
    return `${scope}-${mode}-surface`
  }

  static open(
    uiContext: UIContext,
    componentId: string,
    galleryId: string,
    openDetail: () => void,
    sourceCoverComponentId: string = '',
    coverUrl: string = '',
    sourceSurfaceComponentId: string = '',
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
        sourceSurfaceComponentId,
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
