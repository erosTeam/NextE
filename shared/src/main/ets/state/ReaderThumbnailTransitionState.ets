import { AppStorageV2 } from '@kit.ArkUI'
import { image } from '@kit.ImageKit'
import { EhGalleryImage } from '../model/EhGalleryImage'

export enum ReaderThumbnailTransitionPhase {
  IDLE = 'idle',
  WAITING_READER = 'waitingReader',
  OPENING = 'opening',
  OPEN_PROXY_HANDOFF = 'openProxyHandoff',
  WAITING_READER_CONTENT = 'waitingReaderContent',
  OPEN_HANDOFF = 'openHandoff',
  REVERSING_OPEN = 'reversingOpen',
  OPEN = 'open',
  PREPARING_CLOSE = 'preparingClose',
  CLOSING = 'closing',
  CLOSE_HANDOFF = 'closeHandoff',
}

/** Runtime-only shared-element state for a preview thumbnail <-> Reader handoff. */
@ObservedV2
export class ReaderThumbnailTransitionState {
  @Trace phase: ReaderThumbnailTransitionPhase = ReaderThumbnailTransitionPhase.IDLE
  @Trace sourceScope: string = ''
  @Trace sourceComponentId: string = ''
  @Trace galleryId: string = ''
  @Trace currentIndex: number = 0
  @Trace image: EhGalleryImage = new EhGalleryImage()
  @Trace rootWidth: number = 0
  @Trace rootHeight: number = 0
  @Trace sourceX: number = 0
  @Trace sourceY: number = 0
  @Trace sourceWidth: number = 0
  @Trace sourceHeight: number = 0
  @Trace sourceRadius: number = 0
  @Trace proxyX: number = 0
  @Trace proxyY: number = 0
  @Trace proxyWidth: number = 0
  @Trace proxyHeight: number = 0
  @Trace proxyRadius: number = 0
  @Trace overlayOpacity: number = 1
  @Trace backdropOpacity: number = 1
  @Trace openingProxyOpacity: number = 1
  @Trace closeTargetSnapshotOpacity: number = 0
  @Trace readerImageReady: boolean = false
  @Trace presentationEpoch: number = 0
  @Trace presentationGalleryId: string = ''
  @Trace readerSnapshotAspectRatio: number = 1
  sourceSnapshot: image.PixelMap | undefined = undefined
  openingReverseSnapshot: image.PixelMap | undefined = undefined
  closeTargetSnapshot: image.PixelMap | undefined = undefined
  readerSnapshot: image.PixelMap | undefined = undefined
  private closeTargetX: number = 0
  private closeTargetY: number = 0
  private closeTargetWidth: number = 0
  private closeTargetHeight: number = 0
  private closeTargetRadius: number = 0
  private openTargetX: number = 0
  private openTargetY: number = 0
  private openTargetWidth: number = 0
  private openTargetHeight: number = 0
  private openTargetRadius: number = 0

  active(): boolean {
    return this.phase !== ReaderThumbnailTransitionPhase.IDLE
  }

  waitingReader(): boolean {
    return this.phase === ReaderThumbnailTransitionPhase.WAITING_READER
  }

  opening(): boolean {
    return this.phase === ReaderThumbnailTransitionPhase.OPENING
  }

  opened(): boolean {
    return this.phase === ReaderThumbnailTransitionPhase.OPEN
  }

  openingHandoff(): boolean {
    return this.phase === ReaderThumbnailTransitionPhase.OPEN_HANDOFF
  }

  waitingReaderContent(): boolean {
    return this.phase === ReaderThumbnailTransitionPhase.WAITING_READER_CONTENT
  }

  openingProxyHandoff(): boolean {
    return this.phase === ReaderThumbnailTransitionPhase.OPEN_PROXY_HANDOFF
  }

  readerOpeningProxyVisible(): boolean {
    return this.phase === ReaderThumbnailTransitionPhase.OPEN_PROXY_HANDOFF ||
      this.phase === ReaderThumbnailTransitionPhase.WAITING_READER_CONTENT ||
      this.phase === ReaderThumbnailTransitionPhase.OPEN_HANDOFF
  }

  openingCanReverse(): boolean {
    return this.phase === ReaderThumbnailTransitionPhase.OPENING ||
      this.phase === ReaderThumbnailTransitionPhase.OPEN_PROXY_HANDOFF ||
      this.phase === ReaderThumbnailTransitionPhase.WAITING_READER_CONTENT ||
      this.phase === ReaderThumbnailTransitionPhase.OPEN_HANDOFF
  }

  openingReverse(): boolean {
    return this.phase === ReaderThumbnailTransitionPhase.REVERSING_OPEN
  }

  targetVisible(): boolean {
    return this.phase === ReaderThumbnailTransitionPhase.OPENING ||
      this.phase === ReaderThumbnailTransitionPhase.OPEN_PROXY_HANDOFF ||
      this.phase === ReaderThumbnailTransitionPhase.REVERSING_OPEN
  }

  closingProxyVisible(): boolean {
    return this.phase === ReaderThumbnailTransitionPhase.PREPARING_CLOSE ||
      this.phase === ReaderThumbnailTransitionPhase.CLOSING ||
      this.phase === ReaderThumbnailTransitionPhase.CLOSE_HANDOFF
  }

  closeHandoff(): boolean {
    return this.phase === ReaderThumbnailTransitionPhase.CLOSE_HANDOFF
  }

  sourceHidden(componentId: string): boolean {
    return componentId.length > 0 && componentId === this.sourceComponentId &&
      (this.phase === ReaderThumbnailTransitionPhase.OPENING ||
        this.phase === ReaderThumbnailTransitionPhase.OPEN_PROXY_HANDOFF ||
        this.phase === ReaderThumbnailTransitionPhase.WAITING_READER_CONTENT ||
        this.phase === ReaderThumbnailTransitionPhase.OPEN_HANDOFF ||
        this.phase === ReaderThumbnailTransitionPhase.REVERSING_OPEN ||
        this.phase === ReaderThumbnailTransitionPhase.PREPARING_CLOSE ||
        this.phase === ReaderThumbnailTransitionPhase.CLOSING)
  }

  presentationSettledFor(galleryId: string): boolean {
    return galleryId.length > 0 && this.presentationGalleryId === galleryId
  }

  markPresentationSettled(galleryId: string): boolean {
    if (galleryId.length === 0 || this.presentationSettledFor(galleryId)) {
      return false
    }
    this.presentationGalleryId = galleryId
    this.presentationEpoch += 1
    return true
  }

  readerImageHidden(page: number): boolean {
    return page > 0 && page === this.image.page &&
      (this.phase === ReaderThumbnailTransitionPhase.OPENING ||
        this.phase === ReaderThumbnailTransitionPhase.OPEN_PROXY_HANDOFF ||
        this.phase === ReaderThumbnailTransitionPhase.WAITING_READER_CONTENT ||
        this.phase === ReaderThumbnailTransitionPhase.REVERSING_OPEN)
  }

  private imageRatio(image: EhGalleryImage): number {
    if (image.thumbWidth > 0 && image.thumbHeight > 0) {
      return image.thumbWidth / image.thumbHeight
    }
    return this.rootHeight > 0 ? this.rootWidth / this.rootHeight : 1
  }

  private prepareFullscreenProxy(image: EhGalleryImage, requestedRatio: number = 0): void {
    const ratio: number = requestedRatio > 0 ? requestedRatio : this.imageRatio(image)
    const rootRatio: number = this.rootHeight > 0
      ? this.rootWidth / this.rootHeight
      : ratio
    this.proxyWidth = rootRatio > ratio
      ? this.rootHeight * ratio
      : this.rootWidth
    this.proxyHeight = ratio > 0 ? this.proxyWidth / ratio : this.rootHeight
    this.proxyX = (this.rootWidth - this.proxyWidth) / 2
    this.proxyY = (this.rootHeight - this.proxyHeight) / 2
    this.proxyRadius = 0
  }

  arm(
    sourceScope: string,
    sourceComponentId: string,
    galleryId: string,
    index: number,
    image: EhGalleryImage,
    rootWidth: number,
    rootHeight: number,
    sourceX: number,
    sourceY: number,
    sourceWidth: number,
    sourceHeight: number,
    sourceRadius: number,
    sourceSnapshot: image.PixelMap,
  ): void {
    this.sourceScope = sourceScope
    this.sourceComponentId = sourceComponentId
    this.galleryId = galleryId
    this.currentIndex = index
    this.image = image.copy()
    this.rootWidth = rootWidth
    this.rootHeight = rootHeight
    this.sourceX = sourceX
    this.sourceY = sourceY
    this.sourceWidth = sourceWidth
    this.sourceHeight = sourceHeight
    this.sourceRadius = sourceRadius
    this.sourceSnapshot = sourceSnapshot
    this.prepareFullscreenProxy(image)
    this.openTargetX = this.proxyX
    this.openTargetY = this.proxyY
    this.openTargetWidth = this.proxyWidth
    this.openTargetHeight = this.proxyHeight
    this.openTargetRadius = this.proxyRadius
    this.proxyX = sourceX
    this.proxyY = sourceY
    this.proxyWidth = sourceWidth
    this.proxyHeight = sourceHeight
    this.proxyRadius = sourceRadius
    this.overlayOpacity = 0
    this.backdropOpacity = 1
    this.openingProxyOpacity = 1
    this.closeTargetSnapshotOpacity = 0
    this.readerImageReady = false
    this.phase = ReaderThumbnailTransitionPhase.WAITING_READER
  }

  prepareOpening(): void {
    // Change ownership outside animateTo. The real thumbnail stops painting while the root proxy is
    // still at the identical source rectangle, so the source itself can never fade under the flight.
    this.phase = ReaderThumbnailTransitionPhase.OPENING
  }

  startOpeningFlight(): void {
    this.overlayOpacity = 1
    this.proxyX = this.openTargetX
    this.proxyY = this.openTargetY
    this.proxyWidth = this.openTargetWidth
    this.proxyHeight = this.openTargetHeight
    this.proxyRadius = this.openTargetRadius
  }

  finishOpeningFlight(): boolean {
    if (this.phase === ReaderThumbnailTransitionPhase.OPENING) {
      // Mount the identical Reader-owned placeholder below the root flight proxy first. The root
      // copy stays opaque for one frame, so the two render trees can exchange ownership without a
      // blank frame. Reader chrome is independent of the full-image decode after this handoff.
      this.phase = ReaderThumbnailTransitionPhase.OPEN_PROXY_HANDOFF
      return true
    }
    return false
  }

  finishOpeningProxyHandoff(): boolean {
    if (this.phase !== ReaderThumbnailTransitionPhase.OPEN_PROXY_HANDOFF) {
      return false
    }
    this.phase = ReaderThumbnailTransitionPhase.WAITING_READER_CONTENT
    return this.completeOpeningIfReady()
  }

  markReaderImageReady(page: number): boolean {
    if (!this.active() || page <= 0 || this.image.page !== page) {
      return false
    }
    this.readerImageReady = true
    return this.completeOpeningIfReady()
  }

  private completeOpeningIfReady(): boolean {
    if (
      this.phase !== ReaderThumbnailTransitionPhase.WAITING_READER_CONTENT ||
      !this.readerImageReady
    ) {
      return false
    }
    // The Reader image is ready under the full-size proxy. Keep both at the identical geometry for
    // a short opacity handoff instead of replacing low-resolution thumbnail pixels in one frame.
    this.overlayOpacity = 1
    this.phase = ReaderThumbnailTransitionPhase.OPEN_HANDOFF
    return true
  }

  startOpeningHandoff(): void {
    if (this.phase === ReaderThumbnailTransitionPhase.OPEN_HANDOFF) {
      this.openingProxyOpacity = 0
    }
  }

  finishOpeningHandoff(): boolean {
    if (this.phase !== ReaderThumbnailTransitionPhase.OPEN_HANDOFF) {
      return false
    }
    this.phase = ReaderThumbnailTransitionPhase.OPEN
    this.openingProxyOpacity = 1
    return true
  }

  prepareOpeningReverse(reverseSnapshot: image.PixelMap | undefined = undefined): boolean {
    if (!this.openingCanReverse()) {
      return false
    }
    // If Back lands during the endpoint image handoff, atomically return visual ownership to the
    // click-time proxy before it moves. The live Reader image is hidden in REVERSING_OPEN, so there
    // is still exactly one image surface throughout the reverse flight.
    this.openingReverseSnapshot = reverseSnapshot
    this.openingProxyOpacity = 1
    this.phase = ReaderThumbnailTransitionPhase.REVERSING_OPEN
    return true
  }

  startOpeningReverse(): void {
    if (!this.openingReverse()) {
      return
    }
    this.overlayOpacity = 0
    this.proxyX = this.sourceX
    this.proxyY = this.sourceY
    this.proxyWidth = this.sourceWidth
    this.proxyHeight = this.sourceHeight
    this.proxyRadius = this.sourceRadius
  }

  updateCurrent(index: number, image: EhGalleryImage): void {
    if (!this.active() || index < 0) {
      return
    }
    const pageChanged: boolean = this.currentIndex !== index
    const pageTurnDuringProxyHandoff: boolean = pageChanged &&
      this.phase === ReaderThumbnailTransitionPhase.OPEN_PROXY_HANDOFF
    this.currentIndex = index
    this.image = image.copy()
    if (pageChanged && (
      this.phase === ReaderThumbnailTransitionPhase.OPEN_PROXY_HANDOFF ||
      this.phase === ReaderThumbnailTransitionPhase.WAITING_READER_CONTENT ||
      this.phase === ReaderThumbnailTransitionPhase.OPEN_HANDOFF
    )) {
      // Once the user turns away from the entry page, the click-time thumbnail is no longer a
      // valid placeholder. Release visual ownership immediately so the new page's own loading UI
      // and gestures remain observable instead of appearing frozen behind the old thumbnail.
      this.phase = ReaderThumbnailTransitionPhase.OPEN
      this.openingProxyOpacity = 1
      this.readerImageReady = false
      // The scheduled handoff callback now sees OPEN and intentionally exits. Preserve the same
      // presentation-settled signal here so a page turn in that one-frame ownership window cannot
      // suppress progress publication for the rest of the Reader session.
      if (pageTurnDuringProxyHandoff) {
        this.markPresentationSettled(this.galleryId)
      }
    }
  }

  prepareClose(
    sourceComponentId: string,
    index: number,
    image: EhGalleryImage,
    targetX: number,
    targetY: number,
    targetWidth: number,
    targetHeight: number,
    targetRadius: number,
    readerSnapshot: image.PixelMap | undefined,
    readerSnapshotAspectRatio: number,
    closeTargetSnapshot: image.PixelMap | undefined,
  ): void {
    this.sourceComponentId = sourceComponentId
    this.currentIndex = index
    this.image = image.copy()
    this.readerSnapshot = readerSnapshot
    this.readerSnapshotAspectRatio = readerSnapshot !== undefined
      ? readerSnapshotAspectRatio
      : this.imageRatio(image)
    this.closeTargetSnapshot = closeTargetSnapshot
    this.closeTargetSnapshotOpacity = 0
    this.prepareFullscreenProxy(image, this.readerSnapshotAspectRatio)
    this.closeTargetX = targetX
    this.closeTargetY = targetY
    this.closeTargetWidth = targetWidth
    this.closeTargetHeight = targetHeight
    this.closeTargetRadius = targetRadius
    this.sourceX = targetX
    this.sourceY = targetY
    this.sourceWidth = targetWidth
    this.sourceHeight = targetHeight
    this.sourceRadius = targetRadius
    // Reader owns the close proxy because its NavDestination is composited above the root Stack.
    // Keep that surface visible; a root-level proxy can be hidden behind the native navigation layer.
    this.overlayOpacity = 1
    this.backdropOpacity = 1
    this.phase = ReaderThumbnailTransitionPhase.PREPARING_CLOSE
  }

  startClosing(): void {
    this.phase = ReaderThumbnailTransitionPhase.CLOSING
    this.backdropOpacity = 0
    this.proxyX = this.closeTargetX
    this.proxyY = this.closeTargetY
    this.proxyWidth = this.closeTargetWidth
    this.proxyHeight = this.closeTargetHeight
    this.proxyRadius = this.closeTargetRadius
  }

  showCloseTargetSnapshot(): void {
    if (this.phase === ReaderThumbnailTransitionPhase.CLOSING) {
      this.closeTargetSnapshotOpacity = 1
    }
  }

  finishClosingFlight(): boolean {
    if (this.phase !== ReaderThumbnailTransitionPhase.CLOSING) {
      return false
    }
    // Restore the real thumbnail under the fully opaque endpoint proxy. The proxy remains the
    // visible owner for one rendered frame, so removing Reader cannot expose a blank repaint gap.
    this.phase = ReaderThumbnailTransitionPhase.CLOSE_HANDOFF
    return true
  }

  proxyContentWidth(): number {
    if (this.proxyWidth <= 0 || this.proxyHeight <= 0 || this.readerSnapshotAspectRatio <= 0) {
      return 0
    }
    return this.proxyWidth / this.proxyHeight > this.readerSnapshotAspectRatio
      ? this.proxyHeight * this.readerSnapshotAspectRatio
      : this.proxyWidth
  }

  proxyContentHeight(): number {
    const width: number = this.proxyContentWidth()
    return this.readerSnapshotAspectRatio > 0 ? width / this.readerSnapshotAspectRatio : 0
  }

  reset(): void {
    const sourceSnapshot: image.PixelMap | undefined = this.sourceSnapshot
    const openingReverseSnapshot: image.PixelMap | undefined = this.openingReverseSnapshot
    const closeTargetSnapshot: image.PixelMap | undefined = this.closeTargetSnapshot
    const readerSnapshot: image.PixelMap | undefined = this.readerSnapshot
    this.sourceSnapshot = undefined
    this.openingReverseSnapshot = undefined
    this.closeTargetSnapshot = undefined
    this.readerSnapshot = undefined
    this.phase = ReaderThumbnailTransitionPhase.IDLE
    this.sourceScope = ''
    this.sourceComponentId = ''
    this.galleryId = ''
    this.currentIndex = 0
    this.image = new EhGalleryImage()
    this.rootWidth = 0
    this.rootHeight = 0
    this.sourceX = 0
    this.sourceY = 0
    this.sourceWidth = 0
    this.sourceHeight = 0
    this.sourceRadius = 0
    this.proxyX = 0
    this.proxyY = 0
    this.proxyWidth = 0
    this.proxyHeight = 0
    this.proxyRadius = 0
    this.overlayOpacity = 1
    this.backdropOpacity = 1
    this.openingProxyOpacity = 1
    this.closeTargetSnapshotOpacity = 0
    this.readerImageReady = false
    this.presentationGalleryId = ''
    this.readerSnapshotAspectRatio = 1
    this.closeTargetX = 0
    this.closeTargetY = 0
    this.closeTargetWidth = 0
    this.closeTargetHeight = 0
    this.closeTargetRadius = 0
    this.openTargetX = 0
    this.openTargetY = 0
    this.openTargetWidth = 0
    this.openTargetHeight = 0
    this.openTargetRadius = 0
    if (sourceSnapshot !== undefined) {
      sourceSnapshot.release().catch((_error: Error) => {})
    }
    if (openingReverseSnapshot !== undefined) {
      openingReverseSnapshot.release().catch((_error: Error) => {})
    }
    if (closeTargetSnapshot !== undefined) {
      closeTargetSnapshot.release().catch((_error: Error) => {})
    }
    if (readerSnapshot !== undefined) {
      readerSnapshot.release().catch((_error: Error) => {})
    }
  }
}

const READER_THUMBNAIL_TRANSITION_KEY: string = 'v2_readerThumbnailTransition'

export function connectReaderThumbnailTransition(): ReaderThumbnailTransitionState {
  return AppStorageV2.connect(
    ReaderThumbnailTransitionState,
    READER_THUMBNAIL_TRANSITION_KEY,
    () => new ReaderThumbnailTransitionState(),
  )!
}
