import { AppStorageV2 } from '@kit.ArkUI'
import { image } from '@kit.ImageKit'
import { GalleryDetailTransitionMode } from './GalleryDetailTransitionSettingsState'

/** Runtime-only state for the optional gallery card -> GalleryDetail transition. */
export enum GalleryDetailTransitionPhase {
  IDLE = 'idle',
  PREPARING = 'preparing',
  OPENING = 'opening',
  OPEN = 'open',
  CLOSING = 'closing',
  POST_POP_HANDOFF = 'post_pop_handoff',
}

/**
 * Stable OPEN-state payload retained while a deeper list -> detail transition owns the render proxy.
 * PixelMaps move into this context instead of being copied or released; the parent route receives the
 * same resources again after the child detail returns to its source list.
 */
class SuspendedGalleryDetailTransitionContext {
  mode: string = GalleryDetailTransitionMode.SEAMLESS
  galleryId: string = ''
  routeDestinationId: string = ''
  sourceComponentId: string = ''
  sourceCoverComponentId: string = ''
  sourceSurfaceComponentId: string = ''
  preserveSourceCoverBackground: boolean = false
  targetCoverComponentId: string = ''
  handoffX: number = 0
  handoffY: number = 0
  handoffWidth: number = 0
  handoffHeight: number = 0
  rootWidth: number = 0
  rootHeight: number = 0
  collapsedScaleX: number = 1
  collapsedScaleY: number = 1
  collapsedTranslateX: number = 0
  collapsedTranslateY: number = 0
  collapsedRadius: number = 0
  sourceCoverX: number = 0
  sourceCoverY: number = 0
  sourceCoverWidth: number = 0
  sourceCoverHeight: number = 0
  sourceCoverRadius: number = 0
  targetCoverX: number = 0
  targetCoverY: number = 0
  targetCoverWidth: number = 0
  targetCoverHeight: number = 0
  targetCoverRadius: number = 0
  targetCoverRootWidth: number = 0
  targetCoverRootHeight: number = 0
  targetCoverReady: boolean = false
  coverUrl: string = ''
  sourceSnapshotX: number = 0
  sourceSnapshotY: number = 0
  sourceSnapshotWidth: number = 0
  sourceSnapshotHeight: number = 0
  sourceSnapshotFreshForCurrentRoot: boolean = false
  sourceSnapshot: image.PixelMap | undefined = undefined
  cardSnapshot: image.PixelMap | undefined = undefined
  coverSnapshot: image.PixelMap | undefined = undefined
}

@ObservedV2
export class GalleryDetailTransitionState {
  @Trace eligible: boolean = false
  @Trace phase: GalleryDetailTransitionPhase = GalleryDetailTransitionPhase.IDLE
  @Trace mode: string = GalleryDetailTransitionMode.SEAMLESS
  @Trace galleryId: string = ''
  @Trace routeDestinationId: string = ''
  @Trace sourceComponentId: string = ''
  @Trace sourceCoverComponentId: string = ''
  sourceSurfaceComponentId: string = ''
  @Trace preserveSourceCoverBackground: boolean = false
  @Trace sourceCoverRecaptureHidden: boolean = false
  @Trace targetCoverComponentId: string = ''
  @Trace handoffX: number = 0
  @Trace handoffY: number = 0
  @Trace handoffWidth: number = 0
  @Trace handoffHeight: number = 0
  @Trace scaleX: number = 1
  @Trace scaleY: number = 1
  @Trace translateX: number = 0
  @Trace translateY: number = 0
  @Trace radius: number = 0
  @Trace cardOpacity: number = 0
  @Trace contentOpacity: number = 1
  @Trace chromeVisible: boolean = true
  @Trace clipX: number = 0
  @Trace clipY: number = 0
  @Trace clipWidth: number = 0
  @Trace clipHeight: number = 0
  @Trace flightCoverX: number = 0
  @Trace flightCoverY: number = 0
  @Trace flightCoverWidth: number = 0
  @Trace flightCoverHeight: number = 0
  @Trace flightCoverRadius: number = 0
  @Trace targetCoverReady: boolean = false
  @Trace coverPopPrepared: boolean = false
  @Trace coverFadePopFallback: boolean = false
  @Trace fallbackCoverOpacity: number = 0
  @Trace coverResourceReady: boolean = false
  @Trace coverUrl: string = ''
  @Trace independentPopSurfaceActive: boolean = false
  sourceSnapshot: image.PixelMap | undefined = undefined
  detailSnapshot: image.PixelMap | undefined = undefined
  cardSnapshot: image.PixelMap | undefined = undefined
  coverSnapshot: image.PixelMap | undefined = undefined
  @Trace sourceSnapshotX: number = 0
  @Trace sourceSnapshotY: number = 0
  @Trace sourceSnapshotWidth: number = 0
  @Trace sourceSnapshotHeight: number = 0
  private sourceSnapshotFreshForCurrentRoot: boolean = false

  @Trace rootWidth: number = 0
  @Trace rootHeight: number = 0
  private collapsedScaleX: number = 1
  private collapsedScaleY: number = 1
  private collapsedTranslateX: number = 0
  private collapsedTranslateY: number = 0
  private collapsedRadius: number = 0
  @Trace sourceCoverX: number = 0
  @Trace sourceCoverY: number = 0
  @Trace sourceCoverWidth: number = 0
  @Trace sourceCoverHeight: number = 0
  @Trace sourceCoverRadius: number = 0
  @Trace targetCoverX: number = 0
  @Trace targetCoverY: number = 0
  @Trace targetCoverWidth: number = 0
  @Trace targetCoverHeight: number = 0
  @Trace targetCoverRadius: number = 0
  private targetCoverRootWidth: number = 0
  private targetCoverRootHeight: number = 0
  private suspendedContexts: SuspendedGalleryDetailTransitionContext[] = []

  /**
   * Opens a new route-owned transition slot. An already-open parent is moved to the suspended stack
   * without releasing its snapshots; transient animation phases are deliberately not nestable.
   */
  beginRouteContext(): boolean {
    if (this.eligible) {
      if (
        this.phase !== GalleryDetailTransitionPhase.OPEN ||
        this.independentPopSurfaceActive ||
        this.detailSnapshot !== undefined
      ) {
        return false
      }
      const context: SuspendedGalleryDetailTransitionContext =
        new SuspendedGalleryDetailTransitionContext()
      context.mode = this.mode
      context.galleryId = this.galleryId
      context.routeDestinationId = this.routeDestinationId
      context.sourceComponentId = this.sourceComponentId
      context.sourceCoverComponentId = this.sourceCoverComponentId
      context.sourceSurfaceComponentId = this.sourceSurfaceComponentId
      context.preserveSourceCoverBackground = this.preserveSourceCoverBackground
      context.targetCoverComponentId = this.targetCoverComponentId
      context.handoffX = this.handoffX
      context.handoffY = this.handoffY
      context.handoffWidth = this.handoffWidth
      context.handoffHeight = this.handoffHeight
      context.rootWidth = this.rootWidth
      context.rootHeight = this.rootHeight
      context.collapsedScaleX = this.collapsedScaleX
      context.collapsedScaleY = this.collapsedScaleY
      context.collapsedTranslateX = this.collapsedTranslateX
      context.collapsedTranslateY = this.collapsedTranslateY
      context.collapsedRadius = this.collapsedRadius
      context.sourceCoverX = this.sourceCoverX
      context.sourceCoverY = this.sourceCoverY
      context.sourceCoverWidth = this.sourceCoverWidth
      context.sourceCoverHeight = this.sourceCoverHeight
      context.sourceCoverRadius = this.sourceCoverRadius
      context.targetCoverX = this.targetCoverX
      context.targetCoverY = this.targetCoverY
      context.targetCoverWidth = this.targetCoverWidth
      context.targetCoverHeight = this.targetCoverHeight
      context.targetCoverRadius = this.targetCoverRadius
      context.targetCoverRootWidth = this.targetCoverRootWidth
      context.targetCoverRootHeight = this.targetCoverRootHeight
      context.targetCoverReady = this.targetCoverReady
      context.coverUrl = this.coverUrl
      context.sourceSnapshotX = this.sourceSnapshotX
      context.sourceSnapshotY = this.sourceSnapshotY
      context.sourceSnapshotWidth = this.sourceSnapshotWidth
      context.sourceSnapshotHeight = this.sourceSnapshotHeight
      context.sourceSnapshotFreshForCurrentRoot = this.sourceSnapshotFreshForCurrentRoot
      context.sourceSnapshot = this.sourceSnapshot
      context.cardSnapshot = this.cardSnapshot
      context.coverSnapshot = this.coverSnapshot
      this.sourceSnapshot = undefined
      this.cardSnapshot = undefined
      this.coverSnapshot = undefined
      this.suspendedContexts.push(context)
    } else {
      this.releaseCurrentSnapshots()
    }
    this.clearCurrentFields()
    return true
  }

  bindRouteDestination(navDestinationId: string): void {
    if (!this.eligible || navDestinationId.length === 0) {
      return
    }
    this.routeDestinationId = navDestinationId
  }

  ownsRoute(galleryId: string, navDestinationId: string): boolean {
    if (!this.eligible || galleryId.length === 0 || galleryId !== this.galleryId) {
      return false
    }
    return this.routeDestinationId.length === 0 ||
      (navDestinationId.length > 0 && navDestinationId === this.routeDestinationId)
  }

  suspendedDepth(): number {
    return this.suspendedContexts.length
  }

  /** Releases the current child context and restores the nearest retained parent, if one exists. */
  finishRouteContext(): void {
    this.releaseCurrentSnapshots()
    this.clearCurrentFields()
    const context: SuspendedGalleryDetailTransitionContext | undefined = this.suspendedContexts.pop()
    if (context === undefined) {
      return
    }
    this.mode = context.mode
    this.galleryId = context.galleryId
    this.routeDestinationId = context.routeDestinationId
    this.sourceComponentId = context.sourceComponentId
    this.sourceCoverComponentId = context.sourceCoverComponentId
    this.sourceSurfaceComponentId = context.sourceSurfaceComponentId
    this.preserveSourceCoverBackground = context.preserveSourceCoverBackground
    this.targetCoverComponentId = context.targetCoverComponentId
    this.handoffX = context.handoffX
    this.handoffY = context.handoffY
    this.handoffWidth = context.handoffWidth
    this.handoffHeight = context.handoffHeight
    this.rootWidth = context.rootWidth
    this.rootHeight = context.rootHeight
    this.collapsedScaleX = context.collapsedScaleX
    this.collapsedScaleY = context.collapsedScaleY
    this.collapsedTranslateX = context.collapsedTranslateX
    this.collapsedTranslateY = context.collapsedTranslateY
    this.collapsedRadius = context.collapsedRadius
    this.sourceCoverX = context.sourceCoverX
    this.sourceCoverY = context.sourceCoverY
    this.sourceCoverWidth = context.sourceCoverWidth
    this.sourceCoverHeight = context.sourceCoverHeight
    this.sourceCoverRadius = context.sourceCoverRadius
    this.targetCoverX = context.targetCoverX
    this.targetCoverY = context.targetCoverY
    this.targetCoverWidth = context.targetCoverWidth
    this.targetCoverHeight = context.targetCoverHeight
    this.targetCoverRadius = context.targetCoverRadius
    this.targetCoverRootWidth = context.targetCoverRootWidth
    this.targetCoverRootHeight = context.targetCoverRootHeight
    this.targetCoverReady = context.targetCoverReady
    this.coverUrl = context.coverUrl
    this.sourceSnapshotX = context.sourceSnapshotX
    this.sourceSnapshotY = context.sourceSnapshotY
    this.sourceSnapshotWidth = context.sourceSnapshotWidth
    this.sourceSnapshotHeight = context.sourceSnapshotHeight
    this.sourceSnapshotFreshForCurrentRoot = context.sourceSnapshotFreshForCurrentRoot
    this.sourceSnapshot = context.sourceSnapshot
    this.cardSnapshot = context.cardSnapshot
    this.coverSnapshot = context.coverSnapshot
    this.scaleX = 1
    this.scaleY = 1
    this.translateX = 0
    this.translateY = 0
    this.radius = 0
    this.cardOpacity = 0
    this.contentOpacity = 1
    this.chromeVisible = true
    this.clipX = 0
    this.clipY = 0
    this.clipWidth = this.rootWidth
    this.clipHeight = this.rootHeight
    if (this.targetCoverReady) {
      this.flightCoverX = this.targetCoverX
      this.flightCoverY = this.targetCoverY
      this.flightCoverWidth = this.targetCoverWidth
      this.flightCoverHeight = this.targetCoverHeight
      this.flightCoverRadius = this.targetCoverRadius
    } else {
      this.flightCoverX = this.sourceCoverX
      this.flightCoverY = this.sourceCoverY
      this.flightCoverWidth = this.sourceCoverWidth
      this.flightCoverHeight = this.sourceCoverHeight
      this.flightCoverRadius = this.sourceCoverRadius
    }
    this.phase = GalleryDetailTransitionPhase.OPEN
    this.eligible = true
  }

  beginSourceHandoff(
    mode: string,
    componentId: string,
    sourceCoverComponentId: string,
    sourceSurfaceComponentId: string,
    preserveSourceCoverBackground: boolean,
    targetCoverComponentId: string,
    x: number,
    y: number,
    width: number,
    height: number,
    cardSnapshot: image.PixelMap,
    coverX: number,
    coverY: number,
    coverWidth: number,
    coverHeight: number,
    coverRadius: number,
    coverSnapshot: image.PixelMap | undefined,
    coverUrl: string,
  ): void {
    this.mode = mode
    this.sourceComponentId = preserveSourceCoverBackground ? '' : componentId
    this.sourceCoverComponentId = sourceCoverComponentId
    this.sourceSurfaceComponentId = sourceSurfaceComponentId
    this.preserveSourceCoverBackground = preserveSourceCoverBackground
    this.targetCoverComponentId = targetCoverComponentId
    this.handoffX = x
    this.handoffY = y
    this.handoffWidth = width
    this.handoffHeight = height
    this.cardSnapshot = cardSnapshot
    this.sourceCoverX = coverX
    this.sourceCoverY = coverY
    this.sourceCoverWidth = coverWidth
    this.sourceCoverHeight = coverHeight
    this.sourceCoverRadius = coverRadius
    this.flightCoverX = coverX
    this.flightCoverY = coverY
    this.flightCoverWidth = coverWidth
    this.flightCoverHeight = coverHeight
    this.flightCoverRadius = coverRadius
    this.coverSnapshot = coverSnapshot
    this.coverUrl = coverUrl
    this.coverFadePopFallback = false
    this.fallbackCoverOpacity = 0
    this.coverResourceReady = false
    this.sourceSnapshotFreshForCurrentRoot = false
    if (preserveSourceCoverBackground) {
      // Keep the click-time flight visible while one frame is used to recapture the live card with only
      // its foreground image transparent. The clip starts at the source card, matching the later surface.
      this.clipX = x
      this.clipY = y
      this.clipWidth = width
      this.clipHeight = height
      this.radius = coverRadius
      this.cardOpacity = 1
    }
    this.phase = GalleryDetailTransitionPhase.PREPARING
  }

  completePreservedSourceCardSnapshot(
    componentId: string,
    replacement: image.PixelMap | undefined,
  ): void {
    if (!this.preserveSourceCoverBackground || this.phase !== GalleryDetailTransitionPhase.PREPARING) {
      if (replacement !== undefined) {
        replacement.release().catch((_error: Error) => {})
      }
      return
    }
    if (replacement !== undefined) {
      const previous: image.PixelMap | undefined = this.cardSnapshot
      this.cardSnapshot = replacement
      if (previous !== undefined) {
        previous.release().catch((_error: Error) => {})
      }
    } else {
      this.preserveSourceCoverBackground = false
    }
    this.sourceComponentId = componentId
  }

  beginSourceRecapture(): string {
    if (
      !this.eligible ||
      this.phase !== GalleryDetailTransitionPhase.OPEN ||
      this.sourceComponentId.length === 0
    ) {
      return ''
    }
    const componentId: string = this.sourceComponentId
    // The retained list item is normally Visibility.Hidden. Clear only its runtime hide key so the
    // current post-rotation card can render behind the opaque detail page for one capture frame.
    this.sourceComponentId = ''
    this.sourceCoverRecaptureHidden = false
    return componentId
  }

  prepareIndependentPopSurface(
    snapshot: image.PixelMap,
    rootWidth: number,
    rootHeight: number,
  ): boolean {
    if (
      !this.eligible ||
      !this.isCoverExpand() ||
      this.phase !== GalleryDetailTransitionPhase.OPEN ||
      rootWidth <= 0 ||
      rootHeight <= 0
    ) {
      return false
    }
    const previous: image.PixelMap | undefined = this.detailSnapshot
    // Publish the captured surface and the geometry that produced it as one renderable state. After
    // rotation the previous transition geometry belongs to the old orientation; exposing the new
    // PixelMap before these values would stretch it for one or more frames.
    this.detailSnapshot = snapshot
    this.rootWidth = rootWidth
    this.rootHeight = rootHeight
    this.clipX = 0
    this.clipY = 0
    this.clipWidth = rootWidth
    this.clipHeight = rootHeight
    this.radius = 0
    this.independentPopSurfaceActive = true
    if (previous !== undefined) {
      previous.release().catch((_error: Error) => {})
    }
    return true
  }

  independentPopSurfaceVisible(): boolean {
    return this.independentPopSurfaceActive &&
      this.detailSnapshot !== undefined &&
      (this.phase === GalleryDetailTransitionPhase.OPEN ||
        this.phase === GalleryDetailTransitionPhase.CLOSING ||
        this.phase === GalleryDetailTransitionPhase.POST_POP_HANDOFF)
  }

  hideSourceForSurfaceCapture(componentId: string): boolean {
    if (
      !this.eligible ||
      this.phase !== GalleryDetailTransitionPhase.OPEN ||
      componentId.length === 0 ||
      this.sourceComponentId.length > 0
    ) {
      return false
    }
    // Geometry/card pixels have been captured from the now-active destination route. Hide the real
    // source card again before capturing the destination surface used below the closing animation.
    this.sourceCoverRecaptureHidden = false
    this.sourceComponentId = componentId
    return true
  }

  hideSourceCoverForRecapture(): void {
    if (this.preserveSourceCoverBackground && this.phase === GalleryDetailTransitionPhase.OPEN) {
      // Wide covers own a real blur/gradient layer below the foreground image. Preserve that accepted
      // two-layer contract by hiding only the foreground before recapturing the card remainder.
      this.sourceCoverRecaptureHidden = true
    }
  }

  cancelSourceRecapture(componentId: string): void {
    this.sourceCoverRecaptureHidden = false
    if (
      this.eligible &&
      this.phase === GalleryDetailTransitionPhase.OPEN &&
      this.sourceComponentId.length === 0
    ) {
      this.sourceComponentId = componentId
    }
  }

  completeSourceRecapture(
    componentId: string,
    rootWidth: number,
    rootHeight: number,
    x: number,
    y: number,
    width: number,
    height: number,
    cardSnapshot: image.PixelMap,
    coverX: number,
    coverY: number,
    coverWidth: number,
    coverHeight: number,
    coverRadius: number,
    coverSnapshot: image.PixelMap | undefined,
    currentSourceSnapshot: image.PixelMap | undefined,
    sourceSnapshotX: number,
    sourceSnapshotY: number,
    sourceSnapshotWidth: number,
    sourceSnapshotHeight: number,
  ): boolean {
    if (
      !this.eligible ||
      this.phase !== GalleryDetailTransitionPhase.OPEN ||
      componentId.length === 0 ||
      rootWidth <= 0 ||
      rootHeight <= 0 ||
      width <= 0 ||
      height <= 0
    ) {
      this.cancelSourceRecapture(componentId)
      return false
    }

    const previousCardSnapshot: image.PixelMap | undefined = this.cardSnapshot
    this.cardSnapshot = cardSnapshot
    if (previousCardSnapshot !== undefined) {
      previousCardSnapshot.release().catch((_error: Error) => {})
    }
    if (coverSnapshot !== undefined) {
      const previousCoverSnapshot: image.PixelMap | undefined = this.coverSnapshot
      this.coverSnapshot = coverSnapshot
      if (previousCoverSnapshot !== undefined) {
        previousCoverSnapshot.release().catch((_error: Error) => {})
      }
    }
    if (
      currentSourceSnapshot !== undefined &&
      sourceSnapshotWidth > 0 &&
      sourceSnapshotHeight > 0
    ) {
      const previousSourceSnapshot: image.PixelMap | undefined = this.sourceSnapshot
      this.sourceSnapshot = currentSourceSnapshot
      this.sourceSnapshotX = sourceSnapshotX
      this.sourceSnapshotY = sourceSnapshotY
      this.sourceSnapshotWidth = sourceSnapshotWidth
      this.sourceSnapshotHeight = sourceSnapshotHeight
      this.sourceSnapshotFreshForCurrentRoot = true
      if (previousSourceSnapshot !== undefined) {
        previousSourceSnapshot.release().catch((_error: Error) => {})
      }
    }

    this.rootWidth = rootWidth
    this.rootHeight = rootHeight
    this.handoffX = x
    this.handoffY = y
    this.handoffWidth = width
    this.handoffHeight = height
    this.collapsedScaleX = Math.max(0.08, Math.min(1, width / rootWidth))
    this.collapsedScaleY = Math.max(0.08, Math.min(1, height / rootHeight))
    this.collapsedTranslateX = x + width / 2 - rootWidth / 2
    this.collapsedTranslateY = y + height / 2 - rootHeight / 2
    this.clipX = 0
    this.clipY = 0
    this.clipWidth = rootWidth
    this.clipHeight = rootHeight
    if (coverWidth > 0 && coverHeight > 0) {
      this.sourceCoverX = coverX
      this.sourceCoverY = coverY
      this.sourceCoverWidth = coverWidth
      this.sourceCoverHeight = coverHeight
      this.sourceCoverRadius = coverRadius
    }
    this.sourceCoverRecaptureHidden = false
    this.sourceComponentId = componentId
    return true
  }

  prepare(
    galleryId: string,
    scaleX: number,
    scaleY: number,
    translateX: number,
    translateY: number,
    radius: number,
    rootWidth: number,
    rootHeight: number,
    sourceSnapshot: image.PixelMap,
  ): void {
    this.galleryId = galleryId
    this.rootWidth = rootWidth
    this.rootHeight = rootHeight
    this.collapsedScaleX = scaleX
    this.collapsedScaleY = scaleY
    this.collapsedTranslateX = translateX
    this.collapsedTranslateY = translateY
    this.collapsedRadius = radius
    if (this.isCoverExpand()) {
      this.scaleX = 1
      this.scaleY = 1
      this.translateX = 0
      this.translateY = 0
      this.radius = this.collapsedRadius
      this.cardOpacity = 1
      // The captured source-card remainder owns title/metadata/tags at the start. Fade the settled
      // detail content in only as that remainder leaves so the expanding clip never reveals both text
      // systems at full opacity.
      this.contentOpacity = 0
      this.chromeVisible = true
      // The rounded surface grows from the whole source card. The cover moves independently inside that
      // surface, so starting the clip at the cover alone would make the requested card expansion invisible.
      this.clipX = this.handoffX
      this.clipY = this.handoffY
      this.clipWidth = this.handoffWidth
      this.clipHeight = this.handoffHeight
    } else {
      this.scaleX = scaleX
      this.scaleY = scaleY
      this.translateX = translateX
      this.translateY = translateY
      this.radius = radius
      this.cardOpacity = 1
      this.contentOpacity = 0
      this.chromeVisible = false
      this.clipX = 0
      this.clipY = 0
      this.clipWidth = rootWidth
      this.clipHeight = rootHeight
    }
    this.sourceSnapshot = sourceSnapshot
    this.sourceSnapshotX = 0
    this.sourceSnapshotY = 0
    this.sourceSnapshotWidth = rootWidth
    this.sourceSnapshotHeight = rootHeight
    this.sourceSnapshotFreshForCurrentRoot = false
    this.eligible = true
    this.phase = GalleryDetailTransitionPhase.OPENING
  }

  isCoverExpand(): boolean {
    return this.mode === GalleryDetailTransitionMode.COVER_EXPAND
  }

  coverFlightVisible(): boolean {
    return this.isCoverExpand() &&
      !this.coverFadePopFallback &&
      this.coverSnapshot !== undefined &&
      ((this.phase === GalleryDetailTransitionPhase.PREPARING &&
        this.preserveSourceCoverBackground) ||
        this.coverPopPrepared ||
        this.phase === GalleryDetailTransitionPhase.OPENING ||
        this.phase === GalleryDetailTransitionPhase.CLOSING ||
        this.phase === GalleryDetailTransitionPhase.POST_POP_HANDOFF)
  }

  coverMaskVisible(): boolean {
    return this.isCoverExpand() && (this.coverPopPrepared || this.coverFlightVisible())
  }

  fallbackCoverVisible(): boolean {
    return this.isCoverExpand() &&
      this.coverFadePopFallback &&
      this.coverSnapshot !== undefined &&
      (this.phase === GalleryDetailTransitionPhase.CLOSING ||
        this.phase === GalleryDetailTransitionPhase.POST_POP_HANDOFF)
  }

  prepareCoverPop(targetVisible: boolean): void {
    if (this.isCoverExpand() && this.phase === GalleryDetailTransitionPhase.OPEN) {
      this.coverPopPrepared = targetVisible && this.targetCoverReady
      if (this.coverPopPrepared) {
        // The network-backed flight cover was unmounted after opening. Require its newly mounted
        // instance to report ready again, keeping the click-time snapshot underneath until then.
        this.coverResourceReady = false
        this.flightCoverX = this.targetCoverX
        this.flightCoverY = this.targetCoverY
        this.flightCoverWidth = this.targetCoverWidth
        this.flightCoverHeight = this.targetCoverHeight
        this.flightCoverRadius = this.targetCoverRadius
      }
    }
  }

  setCoverTarget(
    x: number,
    y: number,
    width: number,
    height: number,
    radius: number,
    rootWidth: number,
    rootHeight: number,
  ): void {
    if (
      !this.isCoverExpand() ||
      width <= 0 ||
      height <= 0 ||
      rootWidth <= 0 ||
      rootHeight <= 0
    ) {
      return
    }
    this.targetCoverX = x
    this.targetCoverY = y
    this.targetCoverWidth = width
    this.targetCoverHeight = height
    this.targetCoverRadius = radius
    this.targetCoverRootWidth = rootWidth
    this.targetCoverRootHeight = rootHeight
    this.targetCoverReady = true
  }

  coverTargetReadyForRoot(rootWidth: number, rootHeight: number): boolean {
    return this.targetCoverReady &&
      Math.abs(this.targetCoverRootWidth - rootWidth) <= 0.5 &&
      Math.abs(this.targetCoverRootHeight - rootHeight) <= 0.5
  }

  clearCoverTarget(): void {
    this.targetCoverReady = false
    this.targetCoverX = 0
    this.targetCoverY = 0
    this.targetCoverWidth = 0
    this.targetCoverHeight = 0
    this.targetCoverRadius = 0
    this.targetCoverRootWidth = 0
    this.targetCoverRootHeight = 0
  }

  markCoverResourceReady(): void {
    this.coverResourceReady = true
  }

  useSeamlessFallback(): void {
    this.mode = GalleryDetailTransitionMode.SEAMLESS
    this.targetCoverReady = false
    this.scaleX = this.collapsedScaleX
    this.scaleY = this.collapsedScaleY
    this.translateX = this.collapsedTranslateX
    this.translateY = this.collapsedTranslateY
    this.radius = this.collapsedRadius
    this.cardOpacity = 1
    this.contentOpacity = 0
    this.chromeVisible = false
    this.clipX = 0
    this.clipY = 0
    this.clipWidth = this.rootWidth
    this.clipHeight = this.rootHeight
  }

  useCoverFadePopFallback(): void {
    if (!this.isCoverExpand()) {
      return
    }
    this.clearCoverTarget()
    this.coverFadePopFallback = true
    this.fallbackCoverOpacity = 0
    this.radius = 0
    this.cardOpacity = 0
    this.contentOpacity = 1
    this.chromeVisible = true
    this.clipX = 0
    this.clipY = 0
    this.clipWidth = this.rootWidth
    this.clipHeight = this.rootHeight
  }

  expandWindow(): void {
    if (this.isCoverExpand()) {
      this.clipX = 0
      this.clipY = 0
      this.clipWidth = this.rootWidth
      this.clipHeight = this.rootHeight
      // Keep the surface visibly rounded throughout the expansion. At full coverage the corners lie
      // on the viewport edge; markPushSettled removes the radius after the animation completes.
      this.radius = this.collapsedRadius
      if (this.targetCoverReady) {
        this.flightCoverX = this.targetCoverX
        this.flightCoverY = this.targetCoverY
        this.flightCoverWidth = this.targetCoverWidth
        this.flightCoverHeight = this.targetCoverHeight
        this.flightCoverRadius = this.targetCoverRadius
      }
      return
    }
    this.scaleX = 1
    this.scaleY = 1
    this.translateX = 0
    this.translateY = 0
    this.radius = 0
  }

  crossfadeToDetail(): void {
    if (this.isCoverExpand()) {
      return
    }
    this.cardOpacity = 0
    this.contentOpacity = 1
    this.chromeVisible = true
  }

  crossfadeToCard(): void {
    if (this.isCoverExpand()) {
      return
    }
    this.cardOpacity = 1
    this.contentOpacity = 0
    this.chromeVisible = false
  }

  revealSourceCard(): void {
    if (!this.isCoverExpand()) {
      return
    }
    this.cardOpacity = 1
    this.contentOpacity = 0
    if (this.coverFadePopFallback) {
      this.fallbackCoverOpacity = 1
    }
  }

  hideSourceCard(): void {
    if (!this.isCoverExpand()) {
      return
    }
    this.cardOpacity = 0
    this.contentOpacity = 1
    this.fallbackCoverOpacity = 0
  }

  collapseWindow(radius: number): void {
    if (this.isCoverExpand()) {
      this.clipX = this.handoffX
      this.clipY = this.handoffY
      this.clipWidth = this.handoffWidth
      this.clipHeight = this.handoffHeight
      this.radius = this.collapsedRadius
      this.flightCoverX = this.sourceCoverX
      this.flightCoverY = this.sourceCoverY
      this.flightCoverWidth = this.sourceCoverWidth
      this.flightCoverHeight = this.sourceCoverHeight
      this.flightCoverRadius = this.sourceCoverRadius
      return
    }
    this.scaleX = this.collapsedScaleX
    this.scaleY = this.collapsedScaleY
    this.translateX = this.collapsedTranslateX
    this.translateY = this.collapsedTranslateY
    this.radius = radius
  }

  markPushSettled(success: boolean): void {
    if (this.phase !== GalleryDetailTransitionPhase.OPENING) {
      return
    }
    if (!success) {
      this.finishRouteContext()
      return
    }
    this.phase = GalleryDetailTransitionPhase.OPEN
    if (this.isCoverExpand()) {
      this.radius = 0
      this.cardOpacity = 0
      this.contentOpacity = 1
    }
    this.crossfadeToDetail()
  }

  beginPop(): void {
    if (this.isCoverExpand()) {
      this.clipX = 0
      this.clipY = 0
      this.clipWidth = this.rootWidth
      this.clipHeight = this.rootHeight
      this.radius = 0
      if (this.targetCoverReady) {
        this.flightCoverX = this.targetCoverX
        this.flightCoverY = this.targetCoverY
        this.flightCoverWidth = this.targetCoverWidth
        this.flightCoverHeight = this.targetCoverHeight
        this.flightCoverRadius = this.targetCoverRadius
      }
      this.cardOpacity = 0
    }
    this.coverPopPrepared = false
    this.phase = GalleryDetailTransitionPhase.CLOSING
  }

  beginPostPopHandoff(): boolean {
    if (
      !this.isCoverExpand() ||
      this.phase !== GalleryDetailTransitionPhase.CLOSING ||
      (!this.independentPopSurfaceActive &&
        (!this.sourceSnapshotFreshForCurrentRoot || this.sourceSnapshot === undefined))
    ) {
      return false
    }
    // Geometry recapture now runs only after POP has activated and rendered the destination list.
    // Keep that live list visible, keep only its source card hidden, and hold the landed card overlay
    // for two rendered frames before reset swaps it for the real card. Hiding the whole list here
    // leaves a blank handoff frame because the navigation surface sits above the list snapshot.
    this.phase = GalleryDetailTransitionPhase.POST_POP_HANDOFF
    return true
  }

  postPopHandoffActive(): boolean {
    return this.phase === GalleryDetailTransitionPhase.POST_POP_HANDOFF
  }

  markPopSettled(success: boolean): void {
    if (this.phase !== GalleryDetailTransitionPhase.CLOSING) {
      return
    }
    if (success) {
      this.finishRouteContext()
      return
    }
    this.phase = GalleryDetailTransitionPhase.OPEN
    this.coverFadePopFallback = false
    this.fallbackCoverOpacity = 0
    this.expandWindow()
    if (this.isCoverExpand()) {
      // A cancelled pop must return to the exact settled detail presentation. The close handoff may
      // already have hidden detail content and revealed the source-card remainder, so geometry alone
      // is not enough to recover the page.
      this.radius = 0
      this.cardOpacity = 0
      this.contentOpacity = 1
      this.chromeVisible = true
    }
    this.crossfadeToDetail()
  }

  private clearCurrentFields(): void {
    this.eligible = false
    this.phase = GalleryDetailTransitionPhase.IDLE
    this.mode = GalleryDetailTransitionMode.SEAMLESS
    this.galleryId = ''
    this.routeDestinationId = ''
    this.sourceComponentId = ''
    this.sourceCoverComponentId = ''
    this.sourceSurfaceComponentId = ''
    this.preserveSourceCoverBackground = false
    this.sourceCoverRecaptureHidden = false
    this.targetCoverComponentId = ''
    this.handoffX = 0
    this.handoffY = 0
    this.handoffWidth = 0
    this.handoffHeight = 0
    this.scaleX = 1
    this.scaleY = 1
    this.translateX = 0
    this.translateY = 0
    this.radius = 0
    this.cardOpacity = 0
    this.contentOpacity = 1
    this.chromeVisible = true
    this.clipX = 0
    this.clipY = 0
    this.clipWidth = 0
    this.clipHeight = 0
    this.flightCoverX = 0
    this.flightCoverY = 0
    this.flightCoverWidth = 0
    this.flightCoverHeight = 0
    this.flightCoverRadius = 0
    this.targetCoverReady = false
    this.coverPopPrepared = false
    this.coverFadePopFallback = false
    this.fallbackCoverOpacity = 0
    this.coverResourceReady = false
    this.coverUrl = ''
    this.independentPopSurfaceActive = false
    this.rootWidth = 0
    this.rootHeight = 0
    this.collapsedScaleX = 1
    this.collapsedScaleY = 1
    this.collapsedTranslateX = 0
    this.collapsedTranslateY = 0
    this.collapsedRadius = 0
    this.sourceCoverX = 0
    this.sourceCoverY = 0
    this.sourceCoverWidth = 0
    this.sourceCoverHeight = 0
    this.sourceCoverRadius = 0
    this.targetCoverX = 0
    this.targetCoverY = 0
    this.targetCoverWidth = 0
    this.targetCoverHeight = 0
    this.targetCoverRadius = 0
    this.targetCoverRootWidth = 0
    this.targetCoverRootHeight = 0
    this.sourceSnapshotX = 0
    this.sourceSnapshotY = 0
    this.sourceSnapshotWidth = 0
    this.sourceSnapshotHeight = 0
    this.sourceSnapshotFreshForCurrentRoot = false
    this.sourceSnapshot = undefined
    this.detailSnapshot = undefined
    this.cardSnapshot = undefined
    this.coverSnapshot = undefined
  }

  private releaseCurrentSnapshots(): void {
    const sourceSnapshot: image.PixelMap | undefined = this.sourceSnapshot
    const detailSnapshot: image.PixelMap | undefined = this.detailSnapshot
    const cardSnapshot: image.PixelMap | undefined = this.cardSnapshot
    const coverSnapshot: image.PixelMap | undefined = this.coverSnapshot
    this.sourceSnapshot = undefined
    this.detailSnapshot = undefined
    this.cardSnapshot = undefined
    this.coverSnapshot = undefined
    if (sourceSnapshot !== undefined) {
      sourceSnapshot.release().catch((_error: Error) => {})
    }
    if (detailSnapshot !== undefined) {
      detailSnapshot.release().catch((_error: Error) => {})
    }
    if (cardSnapshot !== undefined) {
      cardSnapshot.release().catch((_error: Error) => {})
    }
    if (coverSnapshot !== undefined) {
      coverSnapshot.release().catch((_error: Error) => {})
    }
  }

  private releaseSuspendedContext(context: SuspendedGalleryDetailTransitionContext): void {
    if (context.sourceSnapshot !== undefined) {
      context.sourceSnapshot.release().catch((_error: Error) => {})
    }
    if (context.cardSnapshot !== undefined) {
      context.cardSnapshot.release().catch((_error: Error) => {})
    }
    if (context.coverSnapshot !== undefined) {
      context.coverSnapshot.release().catch((_error: Error) => {})
    }
  }

  reset(): void {
    this.releaseCurrentSnapshots()
    this.clearCurrentFields()
    for (let i: number = 0; i < this.suspendedContexts.length; i++) {
      this.releaseSuspendedContext(this.suspendedContexts[i])
    }
    this.suspendedContexts = []
  }
}

const GALLERY_DETAIL_TRANSITION_KEY: string = 'v2_galleryDetailTransition'

export function connectGalleryDetailTransition(): GalleryDetailTransitionState {
  return AppStorageV2.connect(
    GalleryDetailTransitionState,
    GALLERY_DETAIL_TRANSITION_KEY,
    () => new GalleryDetailTransitionState(),
  )!
}
