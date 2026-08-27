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
}

@ObservedV2
export class GalleryDetailTransitionState {
  @Trace eligible: boolean = false
  @Trace phase: GalleryDetailTransitionPhase = GalleryDetailTransitionPhase.IDLE
  @Trace mode: string = GalleryDetailTransitionMode.SEAMLESS
  @Trace galleryId: string = ''
  @Trace sourceComponentId: string = ''
  @Trace sourceCoverComponentId: string = ''
  @Trace preserveSourceCoverBackground: boolean = false
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
  sourceSnapshot: image.PixelMap | undefined = undefined
  cardSnapshot: image.PixelMap | undefined = undefined
  coverSnapshot: image.PixelMap | undefined = undefined

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

  beginSourceHandoff(
    mode: string,
    componentId: string,
    sourceCoverComponentId: string,
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
        this.phase === GalleryDetailTransitionPhase.CLOSING)
  }

  coverMaskVisible(): boolean {
    return this.isCoverExpand() && (this.coverPopPrepared || this.coverFlightVisible())
  }

  fallbackCoverVisible(): boolean {
    return this.isCoverExpand() &&
      this.coverFadePopFallback &&
      this.coverSnapshot !== undefined &&
      this.phase === GalleryDetailTransitionPhase.CLOSING
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
  ): void {
    if (!this.isCoverExpand() || width <= 0 || height <= 0) {
      return
    }
    this.targetCoverX = x
    this.targetCoverY = y
    this.targetCoverWidth = width
    this.targetCoverHeight = height
    this.targetCoverRadius = radius
    this.targetCoverReady = true
  }

  clearCoverTarget(): void {
    this.targetCoverReady = false
    this.targetCoverX = 0
    this.targetCoverY = 0
    this.targetCoverWidth = 0
    this.targetCoverHeight = 0
    this.targetCoverRadius = 0
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
      this.reset()
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

  markPopSettled(success: boolean): void {
    if (this.phase !== GalleryDetailTransitionPhase.CLOSING) {
      return
    }
    if (success) {
      this.reset()
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

  reset(): void {
    this.eligible = false
    this.phase = GalleryDetailTransitionPhase.IDLE
    this.mode = GalleryDetailTransitionMode.SEAMLESS
    this.galleryId = ''
    this.sourceComponentId = ''
    this.sourceCoverComponentId = ''
    this.preserveSourceCoverBackground = false
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
    const sourceSnapshot: image.PixelMap | undefined = this.sourceSnapshot
    const cardSnapshot: image.PixelMap | undefined = this.cardSnapshot
    const coverSnapshot: image.PixelMap | undefined = this.coverSnapshot
    this.sourceSnapshot = undefined
    this.cardSnapshot = undefined
    this.coverSnapshot = undefined
    if (sourceSnapshot !== undefined) {
      sourceSnapshot.release().catch((_error: Error) => {})
    }
    if (cardSnapshot !== undefined) {
      cardSnapshot.release().catch((_error: Error) => {})
    }
    if (coverSnapshot !== undefined) {
      coverSnapshot.release().catch((_error: Error) => {})
    }
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
