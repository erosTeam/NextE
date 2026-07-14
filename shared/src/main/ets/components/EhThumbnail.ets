import { ThemeConstants } from '../theme/ThemeConstants'
import { EhConstants } from '../constants/EhConstants'
import { CoverColorService } from '../services/CoverColorService'
import { connectCoverBackground, CoverBackgroundState } from '../state/CoverBackgroundState'
import { connectGalleryCoverRetry, GalleryCoverRetryState } from '../state/GalleryCoverRetryState'
import {
  EH_THUMBNAIL_CONNECT_TIMEOUT_MS,
  EH_THUMBNAIL_READ_TIMEOUT_MS,
} from '../services/ImagePipelineTypes'
import { EhImageKnifeImage, EH_IMAGE_PRIORITY_LOW } from './EhImageKnifeImage'

export const THUMBNAIL_VISUAL_AUTO: number = 0
export const THUMBNAIL_VISUAL_LOADING: number = 1
export const THUMBNAIL_VISUAL_ERROR: number = 2

const COVER_LOADER_SIZE: number = 22
const COVER_ERROR_ICON_SIZE: number = 24
const GRID_COVER_MIN_CONTAIN_SOURCE_RATIO: number = 0.8
const GRID_COVER_MAX_CONTAIN_SOURCE_RATIO: number = 2.2
const THUMBNAIL_MAX_RETRIES: number = 1
const THUMBNAIL_RETRY_DELAY_MS: number = 200
const THUMBNAIL_SETTLE_TIMEOUT_MS: number = 8000

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
  // Opt-in: fill an off-aspect (Contain) cover's letterbox gaps with a background instead of leaving them
  // transparent/grey. Only the browsing-list surfaces (list/grid/waterfall cards) pass true; detail header,
  // preview grids, etc. keep the default false so they are untouched. The fill is the cover-color gradient
  // by default, or a blurred copy of the cover when the user enables blurringOfCoverBackground.
  @Param letterboxBackground: boolean = false;
  // Internal QA probe only. Default AUTO preserves production network/image behavior.
  @Param visualState: number = THUMBNAIL_VISUAL_AUTO;
  // Cover painted yet? Drives the placeholder spinner. Resets when the row is recycled to a new url.
  @Local loaded: boolean = false;
  @Local failed: boolean = false;
  @Local reloadToken: number = 0;
  // The cover's extracted dominant color (packed 0xAARRGGBB), 0 until resolved. Backs the gradient fill.
  @Local coverBgColor: number = 0;
  // Cover-background preference (gradient vs blur). Read in build()/maybeResolveCoverColor so a live toggle
  // re-flows the fill.
  @Local coverBgState: CoverBackgroundState = connectCoverBackground();
  @Local coverRetryState: GalleryCoverRetryState = connectGalleryCoverRetry();

  aboutToAppear(): void {
    this.applyVisualState()
    this.maybeResolveCoverColor()
  }

  @Monitor('url')
  onUrlChange() {
    if (this.visualState !== THUMBNAIL_VISUAL_AUTO) {
      this.applyVisualState()
      return
    }
    this.loaded = false
    this.failed = false
    // Recycled row: drop the previous cover's color and resolve the new one (cache hit repaints instantly).
    this.coverBgColor = 0
    this.maybeResolveCoverColor()
  }

  // Re-flow the gap fill when the user flips gradient ↔ blur at runtime: turning blur OFF needs a color.
  @Monitor('coverBgState.blurringOfCoverBackground')
  onCoverBgPrefChange() {
    this.maybeResolveCoverColor()
  }

  @Monitor('visualState')
  onVisualStateChange() {
    this.applyVisualState()
  }

  @Monitor('coverRetryState.epoch')
  onCoverRetryRequested(): void {
    if (this.visualState !== THUMBNAIL_VISUAL_AUTO || (this.loaded && !this.failed)) {
      return
    }
    this.loaded = false
    this.failed = false
    this.reloadToken += 1
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
      return (this.thumbHeight * this.sourceWidth) / this.sourceHeight
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
    return (this.thumbWidth * this.sourceHeight) / this.sourceWidth
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

  // True when this cover renders letterboxed (Contain) AND a gradient color is what fills the gaps — i.e.
  // the gap-fill is enabled, blur is off, and the active branch is a Contain one. Gates color extraction so
  // we never fetch+decode for covers that fill (Cover) or use the blurred-image fill.
  private needsCoverColorBg(): boolean {
    if (!this.letterboxBackground || this.coverBgState.blurringOfCoverBackground) {
      return false
    }
    if (this.containFit && this.hasSourceSize() && !this.fillHeight && !this.stretchHeight) {
      return true
    }
    return this.coverRatio > 0 && this.coverObjectFit() === ImageFit.Contain
  }

  // Kick off (or reuse) the dominant-color extraction for the current cover. A cached color paints at once;
  // otherwise the async result is applied only if the row has not been recycled to a different url meanwhile.
  private maybeResolveCoverColor(): void {
    if (!this.needsCoverColorBg()) {
      return
    }
    const url: string = EhConstants.cdnThumb(this.url)
    const hit: number = CoverColorService.getInstance().cached(url)
    if (hit !== 0) {
      this.coverBgColor = hit
      return
    }
    CoverColorService.getInstance()
      .resolve(url)
      .then((color: number) => {
        if (EhConstants.cdnThumb(this.url) === url) {
          this.coverBgColor = color
        }
      })
  }

  // The fully-transparent twin of the extracted color for the gradient's bottom stop. Uses the '#AARRGGBB'
  // string form: a bare number like 0x00RRGGBB would be read as opaque RGB, not transparent.
  private fadeColor(): string {
    const rgb: number = this.coverBgColor & 0x00ffffff
    return '#00' + rgb.toString(16).padStart(6, '0')
  }

  // Bottom layer behind an off-aspect cover: a blurred Cover copy of the same image when the user enables
  // blurringOfCoverBackground, else a vertical gradient from the cover's dominant color fading to transparent
  // (so it blends into the card). Renders nothing until the image loads (blur) or the color resolves.
  @Builder
  coverBackgroundLayer() {
    if (this.coverBgState.blurringOfCoverBackground) {
      EhImageKnifeImage({
        src: EhConstants.cdnThumb(this.url),
        widthValue: '100%',
        heightValue: '100%',
        objectFit: ImageFit.Cover,
        radius: this.radius,
        priority: EH_IMAGE_PRIORITY_LOW,
        connectTimeoutMs: EH_THUMBNAIL_CONNECT_TIMEOUT_MS,
        readTimeoutMs: EH_THUMBNAIL_READ_TIMEOUT_MS,
        reloadToken: this.reloadToken,
      })
        .blur(ThemeConstants.COVER_BG_BLUR_RADIUS)
        .renderGroup(true)
    } else if (this.coverBgColor !== 0) {
      Column()
        .width('100%')
        .height('100%')
        .borderRadius(this.radius)
        .clip(true)
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [
            [this.coverBgColor, 0.0],
            [this.fadeColor(), 1.0],
          ],
        })
    }
  }

  build() {
    if (this.visualState !== THUMBNAIL_VISUAL_AUTO) {
      Stack({ alignContent: Alignment.Center }) {
        this.coverOverlay()
      }
      .width(this.thumbWidth)
      .height(this.thumbHeight)
      .backgroundColor(ThemeConstants.COVER_PLACEHOLDER)
      .borderRadius(this.radius)
      .clip(true)
    } else if (this.coverRatio > 0) {
      Stack({ alignContent: Alignment.Center }) {
        if (this.letterboxBackground && this.coverObjectFit() === ImageFit.Contain) {
          this.coverBackgroundLayer()
        }
        EhImageKnifeImage({
          src: EhConstants.cdnThumb(this.url),
          widthValue: '100%',
          heightValue: '100%',
          objectFit: this.coverObjectFit(),
          radius: this.radius,
          maxRetries: THUMBNAIL_MAX_RETRIES,
          retryDelayMs: THUMBNAIL_RETRY_DELAY_MS,
          settleTimeoutMs: THUMBNAIL_SETTLE_TIMEOUT_MS,
          connectTimeoutMs: EH_THUMBNAIL_CONNECT_TIMEOUT_MS,
          readTimeoutMs: EH_THUMBNAIL_READ_TIMEOUT_MS,
          reloadToken: this.reloadToken,
          onComplete: () => {
            this.loaded = true
            this.failed = false
          },
          onError: () => {
            this.loaded = true
            this.failed = true
          },
        })
        this.coverOverlay()
      }
      .width('100%')
      .aspectRatio(this.coverRatio)
      .backgroundColor(ThemeConstants.COVER_PLACEHOLDER)
      .borderRadius(this.radius)
      .clip(true)
    } else if (this.containFit && this.hasSourceSize() && !this.fillHeight && !this.stretchHeight) {
      // Transparent layout slot. Only the REAL image surface is visible; its size follows the EH cover
      // dimensions, and the radius clips that visible image instead of a permanent grey frame. When the
      // caller opts in, the otherwise-transparent gaps are filled by the cover-color gradient (or blur).
      Stack({ alignContent: Alignment.Center }) {
        if (this.letterboxBackground) {
          this.coverBackgroundLayer()
        }
        EhImageKnifeImage({
          src: EhConstants.cdnThumb(this.url),
          widthValue: this.fittedWidth(),
          heightValue: this.fittedHeight(),
          objectFit: ImageFit.Fill,
          radius: this.radius,
          maxRetries: THUMBNAIL_MAX_RETRIES,
          retryDelayMs: THUMBNAIL_RETRY_DELAY_MS,
          settleTimeoutMs: THUMBNAIL_SETTLE_TIMEOUT_MS,
          connectTimeoutMs: EH_THUMBNAIL_CONNECT_TIMEOUT_MS,
          readTimeoutMs: EH_THUMBNAIL_READ_TIMEOUT_MS,
          reloadToken: this.reloadToken,
          onComplete: () => {
            this.loaded = true
            this.failed = false
          },
          onError: () => {
            this.loaded = true
            this.failed = true
          },
        })
        this.coverOverlay()
      }
      .width(this.thumbWidth)
      .height(this.thumbHeight)
    } else if (this.stretchHeight) {
      EhImageKnifeImage({
        src: EhConstants.cdnThumb(this.url),
        widthValue: this.thumbWidth,
        heightValue: '100%',
        objectFit: this.containFit ? ImageFit.Contain : ImageFit.Cover,
        radius: this.radius,
        maxRetries: THUMBNAIL_MAX_RETRIES,
        retryDelayMs: THUMBNAIL_RETRY_DELAY_MS,
        settleTimeoutMs: THUMBNAIL_SETTLE_TIMEOUT_MS,
        connectTimeoutMs: EH_THUMBNAIL_CONNECT_TIMEOUT_MS,
        readTimeoutMs: EH_THUMBNAIL_READ_TIMEOUT_MS,
        reloadToken: this.reloadToken,
        onComplete: () => {
          this.loaded = true
          this.failed = false
        },
        onError: () => {
          this.loaded = true
          this.failed = true
        },
      })
        .backgroundColor(ThemeConstants.COVER_PLACEHOLDER)
        .overlay(this.coverOverlay(), { align: Alignment.Center })
    } else {
      Stack({ alignContent: Alignment.Center }) {
        EhImageKnifeImage({
          src: EhConstants.cdnThumb(this.url),
          widthValue: this.thumbWidth,
          heightValue: this.fillHeight ? '100%' : this.thumbHeight,
          objectFit: this.containFit ? ImageFit.Contain : ImageFit.Cover,
          radius: this.radius,
          maxRetries: THUMBNAIL_MAX_RETRIES,
          retryDelayMs: THUMBNAIL_RETRY_DELAY_MS,
          settleTimeoutMs: THUMBNAIL_SETTLE_TIMEOUT_MS,
          connectTimeoutMs: EH_THUMBNAIL_CONNECT_TIMEOUT_MS,
          readTimeoutMs: EH_THUMBNAIL_READ_TIMEOUT_MS,
          reloadToken: this.reloadToken,
          onComplete: () => {
            this.loaded = true
            this.failed = false
          },
          onError: () => {
            this.loaded = true
            this.failed = true
          },
        })
        this.coverOverlay()
      }
      .width(this.thumbWidth)
      .height(this.fillHeight ? '100%' : this.thumbHeight)
    }
  }
}
