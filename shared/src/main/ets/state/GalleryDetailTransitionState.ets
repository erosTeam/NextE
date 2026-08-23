import { AppStorageV2 } from '@kit.ArkUI'
import { image } from '@kit.ImageKit'

/** Runtime-only state for the optional gallery card -> GalleryDetail transition. */
@ObservedV2
export class GalleryDetailTransitionState {
  @Trace eligible: boolean = false
  @Trace active: boolean = false
  @Trace galleryId: string = ''
  @Trace scaleX: number = 1
  @Trace scaleY: number = 1
  @Trace translateX: number = 0
  @Trace translateY: number = 0
  @Trace radius: number = 0
  @Trace surfaceOpacity: number = 1
  @Trace cardOpacity: number = 0
  @Trace contentOpacity: number = 1
  @Trace chromeVisible: boolean = true
  sourceSnapshot: image.PixelMap | undefined = undefined
  cardSnapshot: image.PixelMap | undefined = undefined

  private collapsedScaleX: number = 1
  private collapsedScaleY: number = 1
  private collapsedTranslateX: number = 0
  private collapsedTranslateY: number = 0

  prepare(
    galleryId: string,
    scaleX: number,
    scaleY: number,
    translateX: number,
    translateY: number,
    radius: number,
    sourceSnapshot: image.PixelMap,
    cardSnapshot: image.PixelMap,
  ): void {
    this.galleryId = galleryId
    this.collapsedScaleX = scaleX
    this.collapsedScaleY = scaleY
    this.collapsedTranslateX = translateX
    this.collapsedTranslateY = translateY
    this.scaleX = scaleX
    this.scaleY = scaleY
    this.translateX = translateX
    this.translateY = translateY
    this.radius = radius
    this.surfaceOpacity = 0
    this.cardOpacity = 1
    this.contentOpacity = 0
    this.chromeVisible = false
    this.sourceSnapshot = sourceSnapshot
    this.cardSnapshot = cardSnapshot
    this.active = false
    this.eligible = true
  }

  expandWindow(): void {
    this.scaleX = 1
    this.scaleY = 1
    this.translateX = 0
    this.translateY = 0
    this.radius = 0
  }

  crossfadeToDetail(): void {
    this.surfaceOpacity = 1
    this.cardOpacity = 0
    this.contentOpacity = 1
    this.chromeVisible = true
  }

  crossfadeToCard(): void {
    this.surfaceOpacity = 0
    this.cardOpacity = 1
    this.contentOpacity = 0
    this.chromeVisible = false
  }

  collapseWindow(radius: number): void {
    this.scaleX = this.collapsedScaleX
    this.scaleY = this.collapsedScaleY
    this.translateX = this.collapsedTranslateX
    this.translateY = this.collapsedTranslateY
    this.radius = radius
  }

  markPushSettled(success: boolean): void {
    if (!success) {
      this.reset()
      return
    }
    this.active = true
    this.cardOpacity = 0
    this.contentOpacity = 1
    this.chromeVisible = true
  }

  reset(): void {
    this.eligible = false
    this.active = false
    this.galleryId = ''
    this.scaleX = 1
    this.scaleY = 1
    this.translateX = 0
    this.translateY = 0
    this.radius = 0
    this.surfaceOpacity = 1
    this.cardOpacity = 0
    this.contentOpacity = 1
    this.chromeVisible = true
    this.collapsedScaleX = 1
    this.collapsedScaleY = 1
    this.collapsedTranslateX = 0
    this.collapsedTranslateY = 0
    const sourceSnapshot: image.PixelMap | undefined = this.sourceSnapshot
    const cardSnapshot: image.PixelMap | undefined = this.cardSnapshot
    this.sourceSnapshot = undefined
    this.cardSnapshot = undefined
    if (sourceSnapshot !== undefined) {
      sourceSnapshot.release().catch((_error: Error) => {})
    }
    if (cardSnapshot !== undefined) {
      cardSnapshot.release().catch((_error: Error) => {})
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
