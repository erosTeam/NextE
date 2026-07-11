import { common } from '@kit.AbilityKit'
import { ThemeConstants } from '../theme/ThemeConstants'
import { EhConstants } from '../constants/EhConstants'
import { EhImageKnifeImage, EH_IMAGE_PRIORITY_LOW } from './EhImageKnifeImage'
import { ImageBlockDecision } from '../model/ImageBlockRule'
import { ImageBlockRuntimeService } from '../services/ImageBlockRuntimeService'
import {
  ImageBlockRuntimeState,
  connectImageBlockRuntime,
} from '../state/ImageBlockRuntimeState'

/**
 * Renders ONE EH preview thumbnail. EH serves a whole preview page's thumbnails as a single sprite
 * sheet; each preview is the sub-rect (offsetX, 0, thumbW, thumbH). We use a container whose CSS-like
 * background (image + size + position) shows exactly that sub-rect, scaled by a single factor — the
 * eros_fe sourceRect crop done natively. Without sprite metadata it falls back to the whole image.
 *
 * The box is sized to the thumb's TRUE aspect so there is never blank padding around it:
 *  - width mode (default): factor = displayWidth / thumbWidth; box = displayWidth × (thumbHeight·factor)
 *  - fitHeight mode:       factor = displayHeight / thumbHeight; box = (thumbWidth·factor) × displayHeight
 * eros_fe's ThumbHorizontalList uses the fitHeight model (a fixed row height, width follows each thumb's
 * aspect) so portrait/landscape previews sit side by side with no white border.
 */
// Subset of ArkUI's Image onComplete event we read: the DECODED source pixel size of the sprite sheet.
// Optional because the callback can fire with no payload (first pass / error).
class SpriteLoadEvent {
  loadingStatus: number = 0
  width?: number
  height?: number

  constructor(width: number = 0, height: number = 0) {
    this.width = width
    this.height = height
  }
}

const IMAGE_BLOCK_COMPUTE_DELAY_MS: number = 120
const SPRITE_THUMB_ERROR_ICON_SIZE: number = 22

@ComponentV2
export struct EhSpriteThumbnail {
  @Param url: string = '';
  @Param thumbWidth: number = 0;
  @Param thumbHeight: number = 0;
  @Param offsetX: number = 0;
  @Param imageKey: string = '';
  @Param spriteWidth: number = 0;
  @Param spriteHeight: number = 0;
  @Param displayWidth: number = 78;
  @Param displayHeight: number = 0;
  @Param enableImageBlock: boolean = false;
  @Param forceImageBlocked: boolean = false;
  @Param imageBlockRevision: number = 0;
  @Event onImageBlockStateChange: (blocked: boolean) => void = () => {};
  @Event onImageBlockDecisionChange: (decision: ImageBlockDecision) => void = () => {};
  // When true the thumb is sized by displayHeight (row-height layout) and its width follows the true
  // aspect; otherwise it is sized by displayWidth and its height follows the true aspect. Either way the
  // box matches the thumb exactly — no fixed-height overhang that would show a blank strip.
  @Param fitHeight: boolean = false;
  @Param radius: number = ThemeConstants.THUMB_RADIUS;
  // The sprite sheet's REAL decoded pixel size (from Image.onComplete); 0 until the sheet loads. The sheet
  // is scaled UNIFORMLY by `factor` relative to THESE real pixels — never Fill-stretched to the parsed
  // max-extent — so the cropped thumb is never axis-distorted when the sheet canvas has padding beyond the
  // last cell (the parsed spriteWidth/spriteHeight can under-measure the true canvas).
  @Local sheetRealW: number = 0;
  @Local sheetRealH: number = 0;
  @Local loaded: boolean = false;
  @Local failed: boolean = false;
  @Local imageBlocked: boolean = false;
  @Local imageBlockRuntime: ImageBlockRuntimeState = connectImageBlockRuntime();
  private blockSeq: number = 0;
  private lastBlockKey: string = '';
  private computeTimerId: number = 0;

  @Monitor('url')
  onUrlChange() {
    this.clearComputeTimer()
    this.sheetRealW = 0
    this.sheetRealH = 0
    this.loaded = false
    this.failed = false
    this.imageBlocked = false
    this.checkImageBlock()
  }

  @Monitor('enableImageBlock')
  onImageBlockToggle() {
    this.imageBlocked = false
    this.checkImageBlock()
  }

  @Monitor('imageBlockRevision')
  onImageBlockRevisionChange() {
    this.checkImageBlock()
  }

  @Monitor('imageBlockRuntime.signal')
  onImageBlockRuntimeChange() {
    this.checkImageBlock()
  }

  aboutToAppear(): void {
    this.checkImageBlock()
    // A bounded automatic hash queue can discard stale waiting work during a rapid scroll. Cached sprite
    // images may not emit onComplete again when this recycled tile becomes visible, so re-queue one
    // best-effort compute pass here instead of leaving the tile permanently cache-only.
    if (this.loaded && !this.failed) {
      this.scheduleImageBlockCompute()
    }
  }

  aboutToDisappear(): void {
    this.clearComputeTimer()
    this.blockSeq++
  }

  // Sprite scale factor: thumb's source dimension → its display dimension.
  private factor(): number {
    if (this.fitHeight) {
      return this.thumbHeight > 0 ? this.displayHeight / this.thumbHeight : 1
    }
    return this.thumbWidth > 0 ? this.displayWidth / this.thumbWidth : 1
  }

  private boxWidth(): number {
    if (this.fitHeight && (this.thumbWidth <= 0 || this.thumbHeight <= 0)) {
      return this.displayHeight * this.wholeImageAspect()
    }
    return this.fitHeight ? this.thumbWidth * this.factor() : this.displayWidth
  }

  private boxHeight(): number {
    if (!this.fitHeight && (this.thumbWidth <= 0 || this.thumbHeight <= 0)) {
      return this.displayWidth / this.wholeImageAspect()
    }
    return this.fitHeight ? this.displayHeight : this.thumbHeight * this.factor()
  }

  // The whole sheet rendered at a UNIFORM scale = (real decoded pixels) × factor. Same `factor` on BOTH
  // axes ⇒ the cropped source rect keeps its true proportion (no axis distortion). Before the sheet loads,
  // fall back to the parsed extent (spriteWidth/spriteHeight) — identical when the canvas is tightly packed,
  // and corrected to the true uniform scale the instant onComplete reports the real pixel size.
  private sheetRenderWidth(): number {
    return (this.sheetRealW > 0 ? this.sheetRealW : this.spriteWidth) * this.factor()
  }

  private sheetRenderHeight(): number {
    return (this.sheetRealH > 0 ? this.sheetRealH : this.spriteHeight) * this.factor()
  }

  private wholeImageAspect(): number {
    return this.thumbWidth > 0 && this.thumbHeight > 0 ? this.thumbWidth / this.thumbHeight : 0.7
  }

  private imageBlockKey(): string {
    return `${this.imageKey}:${this.url}:${this.thumbWidth}:${this.thumbHeight}:${this.offsetX}:${this.spriteWidth}:${this.spriteHeight}:${this.imageBlockRevision}:${this.imageBlockRuntime.signal}`
  }

  private checkImageBlock(computeWhenMissing: boolean = false): void {
    if (!this.enableImageBlock || this.url.length === 0) {
      this.lastBlockKey = ''
      this.imageBlocked = false
      this.onImageBlockStateChange(false)
      this.onImageBlockDecisionChange(new ImageBlockDecision())
      return
    }
    const key: string = `${this.imageBlockKey()}:${computeWhenMissing ? 'compute' : 'cache'}`
    if (key === this.lastBlockKey) {
      return
    }
    this.lastBlockKey = key
    const seq: number = ++this.blockSeq
    ImageBlockRuntimeService.decisionForThumbnail(
      this.getUIContext().getHostContext() as common.UIAbilityContext,
      this.url,
      this.thumbWidth,
      this.thumbHeight,
      this.offsetX,
      this.spriteWidth,
      this.spriteHeight,
      this.imageKey,
      computeWhenMissing,
    )
      .then((decision) => {
        if (seq === this.blockSeq) {
          this.imageBlocked = decision.blocked
          this.onImageBlockStateChange(decision.blocked)
          this.onImageBlockDecisionChange(decision)
        }
      })
      .catch((_error: Error) => {
        if (seq === this.blockSeq) {
          this.imageBlocked = false
          this.onImageBlockStateChange(false)
          this.onImageBlockDecisionChange(new ImageBlockDecision())
        }
      })
  }

  private onThumbComplete(event?: SpriteLoadEvent): void {
    this.loaded = true
    this.failed = false
    if (
      event !== undefined &&
      event.width !== undefined &&
      event.height !== undefined &&
      event.width > 0 &&
      event.height > 0
    ) {
      this.sheetRealW = event.width
      this.sheetRealH = event.height
    }
    this.scheduleImageBlockCompute()
  }

  private onThumbError(): void {
    this.loaded = true
    this.failed = true
  }

  private scheduleImageBlockCompute(): void {
    this.clearComputeTimer()
    if (!this.enableImageBlock || this.url.length === 0) {
      return
    }
    this.computeTimerId = setTimeout((): void => {
      this.computeTimerId = 0
      this.checkImageBlock(true)
    }, IMAGE_BLOCK_COMPUTE_DELAY_MS)
  }

  private clearComputeTimer(): void {
    if (this.computeTimerId > 0) {
      clearTimeout(this.computeTimerId)
      this.computeTimerId = 0
    }
  }

  @Builder
  private statusOverlay() {
    if (!this.loaded || this.failed) {
      Stack({ alignContent: Alignment.Center }) {
        if (this.failed) {
          SymbolGlyph($r('sys.symbol.picture'))
            .fontSize(SPRITE_THUMB_ERROR_ICON_SIZE)
            .fontColor([$r('sys.color.font_tertiary')])
        } else {
          LoadingProgress()
            .width(ThemeConstants.LOADING_SIZE_SMALL)
            .height(ThemeConstants.LOADING_SIZE_SMALL)
            .color($r('sys.color.font_tertiary'))
        }
      }
      .width(this.boxWidth())
      .height(this.boxHeight())
      .backgroundColor(ThemeConstants.COVER_PLACEHOLDER)
    }
  }

  @Builder
  private blockedThumb() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.spriteWidth > 0 && this.thumbWidth > 0 && this.thumbHeight > 0) {
        Stack({ alignContent: Alignment.TopStart }) {
          EhImageKnifeImage({
            src: EhConstants.cdnThumb(this.url),
            widthValue: this.sheetRenderWidth(),
            heightValue: this.sheetRenderHeight(),
            objectFit: ImageFit.Fill,
            priority: EH_IMAGE_PRIORITY_LOW,
            onImageInfo: (width: number, height: number) => {
              this.sheetRealW = width
              this.sheetRealH = height
            },
          })
            .offset({ x: -(this.offsetX * this.factor()), y: 0 })
            .blur(18)
            .opacity(0.9)
        }
        .width(this.boxWidth())
        .height(this.boxHeight())
      } else if (this.fitHeight) {
        EhImageKnifeImage({
          src: EhConstants.cdnThumb(this.url),
          widthValue: this.boxWidth(),
          heightValue: this.boxHeight(),
          objectFit: ImageFit.Cover,
          priority: EH_IMAGE_PRIORITY_LOW,
        })
          .blur(18)
          .opacity(0.9)
      } else {
        EhImageKnifeImage({
          src: EhConstants.cdnThumb(this.url),
          widthValue: this.boxWidth(),
          heightValue: this.boxHeight(),
          objectFit: ImageFit.Cover,
          priority: EH_IMAGE_PRIORITY_LOW,
        })
          .blur(18)
          .opacity(0.9)
      }
      Column()
        .width(this.boxWidth())
        .height(this.boxHeight())
        .backgroundColor('#33000000')
      SymbolGlyph($r('sys.symbol.eye_slash'))
        .fontSize(28)
        .fontColor([Color.White])
    }
    .width(this.boxWidth())
    .height(this.boxHeight())
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .borderRadius(this.radius)
    .clip(true)
  }

  build() {
    if (this.forceImageBlocked || this.imageBlocked) {
      this.blockedThumb()
    } else if (this.spriteWidth > 0 && this.thumbWidth > 0 && this.thumbHeight > 0) {
      // Crop ONE thumb out of EH's sprite sheet. The sheet is an Image CHILD (not a backgroundImage)
      // inside a fixed box that clips to `radius`. This is deliberate: on HarmonyOS a backgroundImage is
      // NOT clipped by borderRadius + clip(true) (device-verified — the thumb rendered square), but Image
      // CONTENT is. The sheet is scaled UNIFORMLY by `factor` from its REAL decoded pixels (not Fill-fitted
      // to the parsed max-extent, which would compress an axis when the canvas has padding) and shifted left
      // to this thumb's column; the box is exactly the scaled thumb, so only this thumb shows — undistorted,
      // rounded.
      Stack({ alignContent: Alignment.TopStart }) {
        EhImageKnifeImage({
          src: EhConstants.cdnThumb(this.url),
          widthValue: this.sheetRenderWidth(),
          heightValue: this.sheetRenderHeight(),
          objectFit: ImageFit.Fill,
          onComplete: () => {
            this.onThumbComplete()
          },
          onImageInfo: (width: number, height: number) => {
            this.onThumbComplete(new SpriteLoadEvent(width, height))
          },
          onError: () => {
            this.onThumbError()
          },
        })
          .offset({ x: -(this.offsetX * this.factor()), y: 0 })
        this.statusOverlay()
      }
      .width(this.boxWidth())
      .height(this.boxHeight())
      .borderRadius(this.radius)
      .clip(true)
    } else if (this.fitHeight) {
      // No sprite metadata (legacy/large-thumb layout): whole image, height-driven. clip(true) so the
      // Cover-fit image is actually rounded to `radius` — borderRadius alone does not clip an Image.
      Stack({ alignContent: Alignment.Center }) {
        EhImageKnifeImage({
          src: EhConstants.cdnThumb(this.url),
          widthValue: this.boxWidth(),
          heightValue: this.boxHeight(),
          objectFit: ImageFit.Cover,
          radius: this.radius,
          onComplete: () => {
            this.onThumbComplete()
          },
          onImageInfo: (width: number, height: number) => {
            this.onThumbComplete(new SpriteLoadEvent(width, height))
          },
          onError: () => {
            this.onThumbError()
          },
        })
        this.statusOverlay()
      }
      .width(this.boxWidth())
      .height(this.boxHeight())
      .borderRadius(this.radius)
      .clip(true)
    } else {
      // No sprite metadata: whole image, width-driven (same clip(true) so the radius actually rounds).
      Stack({ alignContent: Alignment.Center }) {
        EhImageKnifeImage({
          src: EhConstants.cdnThumb(this.url),
          widthValue: this.boxWidth(),
          heightValue: this.boxHeight(),
          objectFit: ImageFit.Cover,
          radius: this.radius,
          onComplete: () => {
            this.onThumbComplete()
          },
          onImageInfo: (width: number, height: number) => {
            this.onThumbComplete(new SpriteLoadEvent(width, height))
          },
          onError: () => {
            this.onThumbError()
          },
        })
        this.statusOverlay()
      }
      .width(this.boxWidth())
      .height(this.boxHeight())
      .borderRadius(this.radius)
      .clip(true)
    }
  }
}
