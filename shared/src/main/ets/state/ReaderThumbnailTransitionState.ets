import { AppStorageV2 } from '@kit.ArkUI'
import { image } from '@kit.ImageKit'
import { EhGalleryImage } from '../model/EhGalleryImage'

export enum ReaderThumbnailTransitionPhase {
  IDLE = 'idle',
  WAITING_READER = 'waitingReader',
  OPENING = 'opening',
  WAITING_READER_CONTENT = 'waitingReaderContent',
  OPEN = 'open',
  PREPARING_CLOSE = 'preparingClose',
  CLOSING = 'closing',
}

/** Runtime-only shared-element state for a preview thumbnail <-> Reader handoff. */
@ObservedV2
export class ReaderThumbnailTransitionState {
  @Trace phase: ReaderThumbnailTransitionPhase = ReaderThumbnailTransitionPhase.IDLE
  @Trace sourceScope: string = ''
  @Trace sourceComponentId: string = ''
  @Trace sharedGeometryId: string = ''
  @Trace galleryId: string = ''
  @Trace currentIndex: number = 0
  @Trace image: EhGalleryImage = new EhGalleryImage()
  @Trace rootWidth: number = 0
  @Trace rootHeight: number = 0
  @Trace proxyX: number = 0
  @Trace proxyY: number = 0
  @Trace proxyWidth: number = 0
  @Trace proxyHeight: number = 0
  @Trace proxyRadius: number = 0
  @Trace overlayOpacity: number = 1
  @Trace readerImageReady: boolean = false
  @Trace readerSnapshotAspectRatio: number = 1
  readerSnapshot: image.PixelMap | undefined = undefined
  private closeTargetX: number = 0
  private closeTargetY: number = 0
  private closeTargetWidth: number = 0
  private closeTargetHeight: number = 0
  private closeTargetRadius: number = 0

  active(): boolean {
    return this.phase !== ReaderThumbnailTransitionPhase.IDLE
  }

  waitingReader(): boolean {
    return this.phase === ReaderThumbnailTransitionPhase.WAITING_READER
  }

  opened(): boolean {
    return this.phase === ReaderThumbnailTransitionPhase.OPEN
  }

  targetVisible(): boolean {
    return this.phase === ReaderThumbnailTransitionPhase.OPENING ||
      this.phase === ReaderThumbnailTransitionPhase.WAITING_READER_CONTENT ||
      this.phase === ReaderThumbnailTransitionPhase.PREPARING_CLOSE ||
      this.phase === ReaderThumbnailTransitionPhase.CLOSING
  }

  sourceHidden(componentId: string): boolean {
    return componentId.length > 0 && componentId === this.sourceComponentId &&
      (this.phase === ReaderThumbnailTransitionPhase.OPENING ||
        this.phase === ReaderThumbnailTransitionPhase.WAITING_READER_CONTENT ||
        this.phase === ReaderThumbnailTransitionPhase.PREPARING_CLOSE ||
        this.phase === ReaderThumbnailTransitionPhase.CLOSING)
  }

  sourceGeometryId(componentId: string): string {
    if (componentId.length === 0 || componentId !== this.sourceComponentId) {
      return ''
    }
    if (this.phase === ReaderThumbnailTransitionPhase.WAITING_READER) {
      return this.sharedGeometryId
    }
    return ''
  }

  targetGeometryId(): string {
    return this.phase === ReaderThumbnailTransitionPhase.OPENING ||
      this.phase === ReaderThumbnailTransitionPhase.WAITING_READER_CONTENT ||
      this.phase === ReaderThumbnailTransitionPhase.PREPARING_CLOSE
      ? this.sharedGeometryId
      : ''
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
    geometryId: string,
    galleryId: string,
    index: number,
    image: EhGalleryImage,
    rootWidth: number,
    rootHeight: number,
  ): void {
    this.sourceScope = sourceScope
    this.sourceComponentId = sourceComponentId
    this.sharedGeometryId = geometryId
    this.galleryId = galleryId
    this.currentIndex = index
    this.image = image.copy()
    this.rootWidth = rootWidth
    this.rootHeight = rootHeight
    this.prepareFullscreenProxy(image)
    this.overlayOpacity = 0
    this.readerImageReady = false
    this.phase = ReaderThumbnailTransitionPhase.WAITING_READER
  }

  startOpening(): void {
    this.phase = ReaderThumbnailTransitionPhase.OPENING
  }

  finishOpeningGeometry(): boolean {
    if (this.phase === ReaderThumbnailTransitionPhase.OPENING) {
      this.phase = ReaderThumbnailTransitionPhase.WAITING_READER_CONTENT
      return this.completeOpeningIfReady()
    }
    return false
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
    // Hand the full-size proxy to the decoded Reader image in one frame. The proxy remains mounted
    // after its geometry flight if Reader is still resolving, so no loading surface flashes through.
    this.overlayOpacity = 1
    this.phase = ReaderThumbnailTransitionPhase.OPEN
    return true
  }

  updateCurrent(index: number, image: EhGalleryImage): void {
    if (!this.active() || index < 0) {
      return
    }
    this.currentIndex = index
    this.image = image.copy()
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
    readerSnapshot: image.PixelMap,
    readerSnapshotAspectRatio: number,
  ): void {
    this.sourceComponentId = sourceComponentId
    this.currentIndex = index
    this.image = image.copy()
    this.readerSnapshot = readerSnapshot
    this.readerSnapshotAspectRatio = readerSnapshotAspectRatio
    this.prepareFullscreenProxy(image, readerSnapshotAspectRatio)
    this.closeTargetX = targetX
    this.closeTargetY = targetY
    this.closeTargetWidth = targetWidth
    this.closeTargetHeight = targetHeight
    this.closeTargetRadius = targetRadius
    // Replace Reader with the full-size proxy before the closing geometry animation starts.
    // The overlay must not fade during the flight because it also owns loading/background layers.
    this.overlayOpacity = 0
    this.phase = ReaderThumbnailTransitionPhase.PREPARING_CLOSE
  }

  startClosing(): void {
    this.phase = ReaderThumbnailTransitionPhase.CLOSING
    this.proxyX = this.closeTargetX
    this.proxyY = this.closeTargetY
    this.proxyWidth = this.closeTargetWidth
    this.proxyHeight = this.closeTargetHeight
    this.proxyRadius = this.closeTargetRadius
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
    const readerSnapshot: image.PixelMap | undefined = this.readerSnapshot
    this.readerSnapshot = undefined
    this.phase = ReaderThumbnailTransitionPhase.IDLE
    this.sourceScope = ''
    this.sourceComponentId = ''
    this.sharedGeometryId = ''
    this.galleryId = ''
    this.currentIndex = 0
    this.image = new EhGalleryImage()
    this.rootWidth = 0
    this.rootHeight = 0
    this.proxyX = 0
    this.proxyY = 0
    this.proxyWidth = 0
    this.proxyHeight = 0
    this.proxyRadius = 0
    this.overlayOpacity = 1
    this.readerImageReady = false
    this.readerSnapshotAspectRatio = 1
    this.closeTargetX = 0
    this.closeTargetY = 0
    this.closeTargetWidth = 0
    this.closeTargetHeight = 0
    this.closeTargetRadius = 0
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
