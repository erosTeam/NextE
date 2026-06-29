import { common } from '@kit.AbilityKit'
import { ThemeConstants } from '../theme/ThemeConstants'
import { EhConstants } from '../constants/EhConstants'
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
interface SpriteLoadEvent {
  loadingStatus: number
  width?: number
  height?: number
}
@ComponentV2
export struct EhSpriteThumbnail {
  @Param url: string = '';
  @Param thumbWidth: number = 0;
  @Param thumbHeight: number = 0;
  @Param offsetX: number = 0;
  @Param spriteWidth: number = 0;
  @Param spriteHeight: number = 0;
  @Param displayWidth: number = 78;
  @Param displayHeight: number = 0;
  @Param enableImageBlock: boolean = false;
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
  @Local imageBlocked: boolean = false;
  @Local imageBlockRuntime: ImageBlockRuntimeState = connectImageBlockRuntime();
  private blockSeq: number = 0;

  @Monitor('url')
  onUrlChange() {
    this.sheetRealW = 0
    this.sheetRealH = 0
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
    this.imageBlocked = false
    this.checkImageBlock()
  }

  @Monitor('imageBlockRuntime.signal')
  onImageBlockRuntimeChange() {
    this.imageBlocked = false
    this.checkImageBlock()
  }

  aboutToAppear(): void {
    this.checkImageBlock()
  }

  // Sprite scale factor: thumb's source dimension → its display dimension.
  private factor(): number {
    if (this.fitHeight) {
      return this.thumbHeight > 0 ? this.displayHeight / this.thumbHeight : 1
    }
    return this.thumbWidth > 0 ? this.displayWidth / this.thumbWidth : 1
  }

  private boxWidth(): number {
    return this.fitHeight ? this.thumbWidth * this.factor() : this.displayWidth
  }

  private boxHeight(): number {
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

  private checkImageBlock(): void {
    const seq: number = ++this.blockSeq
    if (!this.enableImageBlock || this.url.length === 0) {
      this.imageBlocked = false
      this.onImageBlockStateChange(false)
      this.onImageBlockDecisionChange(new ImageBlockDecision())
      return
    }
    ImageBlockRuntimeService.decisionForThumbnail(
      this.getUIContext().getHostContext() as common.UIAbilityContext,
      this.url,
      this.thumbWidth,
      this.thumbHeight,
      this.offsetX,
      this.spriteWidth,
      this.spriteHeight,
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

  @Builder
  private blockedThumb() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.spriteWidth > 0 && this.thumbWidth > 0 && this.thumbHeight > 0) {
        Stack({ alignContent: Alignment.TopStart }) {
          Image(EhConstants.cdnThumb(this.url))
            .width(this.sheetRenderWidth())
            .height(this.sheetRenderHeight())
            .objectFit(ImageFit.Fill)
            .offset({ x: -(this.offsetX * this.factor()), y: 0 })
            .blur(18)
            .opacity(0.9)
            .draggable(false)
        }
        .width(this.boxWidth())
        .height(this.boxHeight())
      } else if (this.fitHeight) {
        Image(EhConstants.cdnThumb(this.url))
          .height(this.displayHeight)
          .aspectRatio(this.wholeImageAspect())
          .objectFit(ImageFit.Cover)
          .blur(18)
          .opacity(0.9)
          .draggable(false)
      } else {
        Image(EhConstants.cdnThumb(this.url))
          .width(this.displayWidth)
          .aspectRatio(this.wholeImageAspect())
          .objectFit(ImageFit.Cover)
          .blur(18)
          .opacity(0.9)
          .draggable(false)
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
    if (this.imageBlocked) {
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
        Image(EhConstants.cdnThumb(this.url))
          .width(this.sheetRenderWidth())
          .height(this.sheetRenderHeight())
          .objectFit(ImageFit.Fill)
          .offset({ x: -(this.offsetX * this.factor()), y: 0 })
          .draggable(false)
          .onComplete((event?: SpriteLoadEvent) => {
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
          })
      }
      .width(this.boxWidth())
      .height(this.boxHeight())
      .borderRadius(this.radius)
      .clip(true)
    } else if (this.fitHeight) {
      // No sprite metadata (legacy/large-thumb layout): whole image, height-driven. clip(true) so the
      // Cover-fit image is actually rounded to `radius` — borderRadius alone does not clip an Image.
      Image(EhConstants.cdnThumb(this.url))
        .height(this.displayHeight)
        .aspectRatio(this.wholeImageAspect())
        .objectFit(ImageFit.Cover)
        .borderRadius(this.radius)
        .clip(true)
        .draggable(false)
    } else {
      // No sprite metadata: whole image, width-driven (same clip(true) so the radius actually rounds).
      Image(EhConstants.cdnThumb(this.url))
        .width(this.displayWidth)
        .aspectRatio(this.wholeImageAspect())
        .objectFit(ImageFit.Cover)
        .borderRadius(this.radius)
        .clip(true)
        .draggable(false)
    }
  }
}
