import { ThemeConstants } from '../theme/ThemeConstants'
import { EhConstants } from '../constants/EhConstants'

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
  // When true the thumb is sized by displayHeight (row-height layout) and its width follows the true
  // aspect; otherwise it is sized by displayWidth and its height follows the true aspect. Either way the
  // box matches the thumb exactly — no fixed-height overhang that would show a blank strip.
  @Param fitHeight: boolean = false;
  @Param radius: number = ThemeConstants.RADIUS_SM;

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

  build() {
    if (this.spriteWidth > 0 && this.thumbWidth > 0 && this.thumbHeight > 0) {
      // Crop ONE thumb out of EH's sprite sheet. The sheet is an Image CHILD (not a backgroundImage)
      // inside a fixed box that clips to `radius`. This is deliberate: on HarmonyOS a backgroundImage is
      // NOT clipped by borderRadius + clip(true) (device-verified — the thumb rendered square), but Image
      // CONTENT is. The Image is the whole sheet scaled by `factor` and shifted left to this thumb's
      // column; the box is exactly the scaled thumb, so only this thumb shows — with real rounded corners.
      Stack({ alignContent: Alignment.TopStart }) {
        Image(EhConstants.cdnThumb(this.url))
          .width(this.spriteWidth * this.factor())
          .height(this.spriteHeight * this.factor())
          .objectFit(ImageFit.Fill)
          .offset({ x: -(this.offsetX * this.factor()), y: 0 })
          .draggable(false)
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
        .aspectRatio(0.7)
        .objectFit(ImageFit.Cover)
        .borderRadius(this.radius)
        .clip(true)
        .draggable(false)
    } else {
      // No sprite metadata: whole image, width-driven (same clip(true) so the radius actually rounds).
      Image(EhConstants.cdnThumb(this.url))
        .width(this.displayWidth)
        .aspectRatio(0.7)
        .objectFit(ImageFit.Cover)
        .borderRadius(this.radius)
        .clip(true)
        .draggable(false)
    }
  }
}
