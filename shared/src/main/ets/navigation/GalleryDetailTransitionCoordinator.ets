import { image } from '@kit.ImageKit'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { connectGalleryDetailTransition } from '../state/GalleryDetailTransitionState'
import { connectGalleryDetailTransitionSettings } from '../state/GalleryDetailTransitionSettingsState'
import { connectLayoutSafeArea } from '../state/LayoutSafeAreaState'
import { connectNavStack } from '../state/NavStackHolder'
import { ThemeConstants } from '../theme/ThemeConstants'

/**
 * Shared launcher for every gallery-card -> GalleryDetail transition surface. Pages only provide
 * the real card node id and their existing navigation action; capture, eligibility and cleanup stay
 * identical across Home, Toplist, Favorites, Search and Viewed History.
 */
export class GalleryDetailTransitionCoordinator {
  private static scopeSeed: number = 0
  private static opening: boolean = false

  static allocateScope(owner: string): string {
    GalleryDetailTransitionCoordinator.scopeSeed += 1
    return `gallery-list-${owner}-${GalleryDetailTransitionCoordinator.scopeSeed}`
  }

  static sourceId(scope: string, mode: string, galleryId: string): string {
    return `${scope}-${mode}-${galleryId}`
  }

  static open(
    uiContext: UIContext,
    componentId: string,
    galleryId: string,
    openDetail: () => void,
  ): void {
    if (GalleryDetailTransitionCoordinator.opening) {
      return
    }
    const transition = connectGalleryDetailTransition()
    transition.reset()
    if (!connectGalleryDetailTransitionSettings().enabled || connectNavStack().isSplitMode) {
      openDetail()
      return
    }

    GalleryDetailTransitionCoordinator.opening = true
    let sourceSnapshot: image.PixelMap | undefined = undefined
    let cardSnapshot: image.PixelMap | undefined = undefined
    try {
      const rect = uiContext.getComponentUtils().getRectangleById(componentId)
      const layout = connectLayoutSafeArea()
      const targetWidth: number = uiContext.px2vp(layout.mainWindowWidthPx)
      const targetHeight: number = uiContext.px2vp(layout.mainWindowHeightPx)
      const sourceWidth: number = uiContext.px2vp(rect.size.width)
      const sourceHeight: number = uiContext.px2vp(rect.size.height)
      const sourceX: number = uiContext.px2vp(rect.windowOffset.x)
      const sourceY: number = uiContext.px2vp(rect.windowOffset.y)
      if (targetWidth <= 0 || targetHeight <= 0 || sourceWidth <= 0 || sourceHeight <= 0) {
        GalleryDetailTransitionCoordinator.opening = false
        openDetail()
        return
      }

      sourceSnapshot = uiContext.getComponentSnapshot()
        .getSync('nexte-root-navigation', { waitUntilRenderFinished: true })
      cardSnapshot = uiContext.getComponentSnapshot()
        .getSync(componentId, { waitUntilRenderFinished: true })
      transition.prepare(
        galleryId,
        Math.max(0.08, Math.min(1, sourceWidth / targetWidth)),
        Math.max(0.08, Math.min(1, sourceHeight / targetHeight)),
        sourceX + sourceWidth / 2 - targetWidth / 2,
        sourceY + sourceHeight / 2 - targetHeight / 2,
        ThemeConstants.RADIUS_CARD,
        sourceSnapshot,
        cardSnapshot,
      )
      sourceSnapshot = undefined
      cardSnapshot = undefined
      DiagnosticLogger.info(
        'gallery-detail-transition',
        'snapshots_ready',
        `gid=${galleryId} source=${componentId}`,
      )
      GalleryDetailTransitionCoordinator.opening = false
      openDetail()
      return
    } catch (error) {
      if (sourceSnapshot !== undefined) {
        sourceSnapshot.release().catch((_releaseError: Error) => {})
      }
      if (cardSnapshot !== undefined) {
        cardSnapshot.release().catch((_releaseError: Error) => {})
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
