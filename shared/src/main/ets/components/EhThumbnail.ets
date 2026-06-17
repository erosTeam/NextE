import { ThemeConstants } from '../theme/ThemeConstants'
import { EhConstants } from '../constants/EhConstants'

const COVER_LOADER_SIZE: number = 22

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
  @Param radius: number = ThemeConstants.RADIUS_SM;
  @Param fillHeight: boolean = false;
  @Param stretchHeight: boolean = false;
  // When > 0 the cover is full-width with this w/h ratio (the grid card's cell-filling cover), so a
  // grid thumbnail gets the same grey backing + load spinner as the list cover instead of a bare Image.
  // (Named coverRatio, not aspectRatio — the latter collides with the built-in component attribute.)
  @Param coverRatio: number = 0;
  // Fit the WHOLE cover inside its frame instead of center-cropping. When source dimensions are known,
  // the frame is only a transparent layout slot; the visible image is sized to the real cover aspect and
  // clipped to its own rounded boundary. This avoids a permanent grey letterbox container around a loaded
  // cover while preserving the real image/proportion.
  @Param containFit: boolean = false;
  @Param sourceWidth: number = 0;
  @Param sourceHeight: number = 0;
  // Cover painted yet? Drives the placeholder spinner. Resets when the row is recycled to a new url.
  @Local loaded: boolean = false;

  @Monitor('url')
  onUrlChange() {
    this.loaded = false
  }

  // Centered spinner, only while the cover is loading; collapses to nothing once it paints.
  @Builder
  loaderOverlay() {
    if (!this.loaded) {
      LoadingProgress()
        .width(COVER_LOADER_SIZE)
        .height(COVER_LOADER_SIZE)
        .color($r('sys.color.font_tertiary'))
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

  build() {
    if (this.coverRatio > 0) {
      Image(EhConstants.cdnThumb(this.url))
        .width('100%')
        .aspectRatio(this.coverRatio)
        .objectFit(this.containFit ? ImageFit.Contain : ImageFit.Cover)
        .backgroundColor(ThemeConstants.COVER_PLACEHOLDER)
        .borderRadius(this.radius)
        .draggable(false)
        .onComplete(() => {
          this.loaded = true
        })
        .onError(() => {
          this.loaded = true
        })
        .overlay(this.loaderOverlay(), { align: Alignment.Center })
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
          })
          .onError(() => {
            this.loaded = true
          })
      }
      .width(this.thumbWidth)
      .height(this.thumbHeight)
      .overlay(this.loaderOverlay(), { align: Alignment.Center })
    } else if (this.stretchHeight) {
      Image(EhConstants.cdnThumb(this.url))
        .width(this.thumbWidth)
        .objectFit(this.containFit ? ImageFit.Contain : ImageFit.Cover)
        .backgroundColor(ThemeConstants.COVER_PLACEHOLDER)
        .borderRadius(this.radius)
        .draggable(false)
        .onComplete(() => {
          this.loaded = true
        })
        .onError(() => {
          this.loaded = true
        })
        .overlay(this.loaderOverlay(), { align: Alignment.Center })
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
        })
        .onError(() => {
          this.loaded = true
        })
        .overlay(this.loaderOverlay(), { align: Alignment.Center })
    }
  }
}
