import { ThemeConstants } from '../theme/ThemeConstants'
import { EhConstants } from '../constants/EhConstants'

export const THUMBNAIL_VISUAL_AUTO: number = 0
export const THUMBNAIL_VISUAL_LOADING: number = 1
export const THUMBNAIL_VISUAL_ERROR: number = 2

const COVER_LOADER_SIZE: number = 22
const COVER_ERROR_ICON_SIZE: number = 24
const GRID_COVER_MIN_CONTAIN_SOURCE_RATIO: number = 0.8
const GRID_COVER_MAX_CONTAIN_SOURCE_RATIO: number = 2.2

/**
 * Gallery thumbnail. M1 loads the ehgt.org/s.exhentai.org thumb URL directly (public CDN, no auth).
 * A grey backing + a centered spinner (only while loading, via overlay) stand in for an unresolved
 * cover (eros_fe CoverImg: systemGrey5 + CupertinoActivityIndicator) so it's never a transparent hole.
 *
 * In stretch mode the Image sets NO height of its own so an `ItemAlign.Stretch` parent stretches it to
 * the sibling column's height — using height('100%') here would resolve against the list viewport and
 * blow the card up to full-screen, so we must NOT wrap it in a sized container.
 */
@ComponentV2
export struct EhThumbnail {
  @Param url: string = '';
  @Param thumbWidth: number = 90;
  @Param thumbHeight: number = 127;
  @Param radius: number = ThemeConstants.THUMB_RADIUS;
  @Param fillHeight: boolean = false;
  @Param stretchHeight: boolean = false;
  // When > 0 the cover is full-width with this w/h ratio (the grid card's cell-filling cover), so a
  // grid thumbnail gets the same grey backing + load spinner as the list cover instead of a bare Image.
  // (Named coverRatio, not aspectRatio — the latter collides with the built-in component attribute.)
  @Param coverRatio: number = 0;
  // Force crop inside a coverRatio slot. Waterfall uses this with a clamped source ratio: the card height
  // remains bounded for extreme strip covers, but the image itself crops instead of letterboxing grey.
  @Param forceCoverFit: boolean = false;
  // Fit the WHOLE cover inside its frame instead of center-cropping. When source dimensions are known,
  // the frame is only a transparent layout slot; the visible image is sized to the real cover aspect and
  // clipped to its own rounded boundary. This avoids a permanent grey letterbox container around a loaded
  // cover while preserving the real image/proportion.
  @Param containFit: boolean = false;
  @Param sourceWidth: number = 0;
  @Param sourceHeight: number = 0;
  // Internal QA probe only. Default AUTO preserves production network/image behavior.
  @Param visualState: number = THUMBNAIL_VISUAL_AUTO;
  // Cover painted yet? Drives the placeholder spinner. Resets when the row is recycled to a new url.
  @Local loaded: boolean = false;
  @Local failed: boolean = false;

  aboutToAppear(): void {
    this.applyVisualState()
  }

  @Monitor('url')
  onUrlChange() {
    if (this.visualState !== THUMBNAIL_VISUAL_AUTO) {
      this.applyVisualState()
      return
    }
    this.loaded = false
    this.failed = false
  }

  @Monitor('visualState')
  onVisualStateChange() {
    this.applyVisualState()
  }

  private applyVisualState(): void {
    if (this.visualState === THUMBNAIL_VISUAL_LOADING) {
      this.loaded = false
      this.failed = false
    } else if (this.visualState === THUMBNAIL_VISUAL_ERROR) {
      this.loaded = true
      this.failed = true
    }
  }

  // Centered spinner, only while the cover is loading; collapses to nothing once it paints.
  @Builder
  loaderOverlay() {
    if (!this.loaded && !this.failed) {
      LoadingProgress()
        .width(COVER_LOADER_SIZE)
        .height(COVER_LOADER_SIZE)
        .color($r('sys.color.font_tertiary'))
    }
  }

  // Error fallback: keep the distinct cover placeholder visible, but show an explicit image marker so a
  // failed remote cover does not look like an intentionally blank loaded card.
  @Builder
  errorOverlay() {
    if (this.failed) {
      SymbolGlyph($r('sys.symbol.picture'))
        .fontSize(COVER_ERROR_ICON_SIZE)
        .fontColor([ThemeConstants.TEXT_TERTIARY])
    }
  }

  @Builder
  coverOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      this.loaderOverlay()
      this.errorOverlay()
    }
  }

  private hasSourceSize(): boolean {
    return this.sourceWidth > 0 && this.sourceHeight > 0
  }

  private fittedByHeight(): boolean {
    if (!this.hasSourceSize()) {
      return false
    }
    return this.sourceHeight / this.sourceWidth > this.thumbHeight / this.thumbWidth
  }

  private fittedWidth(): number {
    if (!this.hasSourceSize()) {
      return this.thumbWidth
    }
    if (this.fittedByHeight()) {
      return this.thumbHeight * this.sourceWidth / this.sourceHeight
    }
    return this.thumbWidth
  }

  private fittedHeight(): number {
    if (!this.hasSourceSize()) {
      return this.thumbHeight
    }
    if (this.fittedByHeight()) {
      return this.thumbHeight
    }
    return this.thumbWidth * this.sourceHeight / this.sourceWidth
  }

  private coverObjectFit(): ImageFit {
    if (this.forceCoverFit) {
      return ImageFit.Cover
    }
    if (this.containFit) {
      return ImageFit.Contain
    }
    if (!this.hasSourceSize() || this.coverRatio <= 0) {
      return ImageFit.Cover
    }
    const sourceRatio: number = this.sourceHeight / this.sourceWidth
    if (sourceRatio <= GRID_COVER_MIN_CONTAIN_SOURCE_RATIO) {
      return ImageFit.Contain
    }
    if (sourceRatio >= GRID_COVER_MAX_CONTAIN_SOURCE_RATIO) {
      return ImageFit.Contain
    }
    return ImageFit.Cover
  }

  build() {
    if (this.visualState !== THUMBNAIL_VISUAL_AUTO) {
      Stack({ alignContent: Alignment.Center }) {}
        .width(this.thumbWidth)
        .height(this.thumbHeight)
        .backgroundColor(ThemeConstants.COVER_PLACEHOLDER)
        .borderRadius(this.radius)
        .clip(true)
        .overlay(this.coverOverlay(), { align: Alignment.Center })
    } else if (this.coverRatio > 0) {
      Stack({ alignContent: Alignment.Center }) {
        Image(EhConstants.cdnThumb(this.url))
          .width('100%')
          .height('100%')
          .objectFit(this.coverObjectFit())
          .draggable(false)
          .onComplete(() => {
            this.loaded = true
            this.failed = false
          })
          .onError(() => {
            this.loaded = true
            this.failed = true
          })
      }
        .width('100%')
        .aspectRatio(this.coverRatio)
        .backgroundColor(ThemeConstants.COVER_PLACEHOLDER)
        .borderRadius(this.radius)
        .clip(true)
        .overlay(this.coverOverlay(), { align: Alignment.Center })
    } else if (this.containFit && this.hasSourceSize() && !this.fillHeight && !this.stretchHeight) {
      // Transparent layout slot. Only the REAL image surface is visible; its size follows the EH cover
      // dimensions, and the radius clips that visible image instead of a permanent grey frame.
      Stack({ alignContent: Alignment.Center }) {
        Image(EhConstants.cdnThumb(this.url))
          .width(this.fittedWidth())
          .height(this.fittedHeight())
          .objectFit(ImageFit.Fill)
          .borderRadius(this.radius)
          .clip(true)
          .draggable(false)
          .onComplete(() => {
            this.loaded = true
            this.failed = false
          })
          .onError(() => {
            this.loaded = true
            this.failed = true
          })
      }
      .width(this.thumbWidth)
      .height(this.thumbHeight)
      .overlay(this.coverOverlay(), { align: Alignment.Center })
    } else if (this.stretchHeight) {
      Image(EhConstants.cdnThumb(this.url))
        .width(this.thumbWidth)
        .objectFit(this.containFit ? ImageFit.Contain : ImageFit.Cover)
        .backgroundColor(ThemeConstants.COVER_PLACEHOLDER)
        .borderRadius(this.radius)
        .draggable(false)
        .onComplete(() => {
          this.loaded = true
          this.failed = false
        })
        .onError(() => {
          this.loaded = true
          this.failed = true
        })
        .overlay(this.coverOverlay(), { align: Alignment.Center })
    } else {
      Image(EhConstants.cdnThumb(this.url))
        .width(this.thumbWidth)
        .height(this.fillHeight ? '100%' : this.thumbHeight)
        .objectFit(this.containFit ? ImageFit.Contain : ImageFit.Cover)
        .backgroundColor(ThemeConstants.COVER_PLACEHOLDER)
        .borderRadius(this.radius)
        .draggable(false)
        .onComplete(() => {
          this.loaded = true
          this.failed = false
        })
        .onError(() => {
          this.loaded = true
          this.failed = true
        })
        .overlay(this.coverOverlay(), { align: Alignment.Center })
    }
  }
}
