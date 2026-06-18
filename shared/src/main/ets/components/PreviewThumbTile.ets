import { ThemeConstants } from '../theme/ThemeConstants'
import { EhSpriteThumbnail } from './EhSpriteThumbnail'
import { EhGalleryImage } from '../model/EhGalleryImage'

// Tile image-frame aspect (height = width * aspect). A FIXED portrait frame so every tile — and thus
// every page number below it — sits at the same height regardless of each thumb's true aspect or a
// misdetected source dimension. EH manga previews are mostly portrait, so this fits the common case
// snugly while flat/wide thumbs letterbox (centered) inside the stable frame instead of shrinking the
// row and dragging the label baseline around.
const FRAME_ASPECT: number = 1.4

/**
 * One responsive preview-grid tile (detail inline GRID + the all-thumbnails page share it). The image
 * is CONTAINED + centered inside a fixed-size frame (no crop — the smaller of width-fit / height-fit is
 * chosen so the whole thumb shows, letterboxed over BG_SUB), and the page number sits at a fixed
 * position below the frame. So a flat/wide thumb, or a thumb whose sprite dimensions were misdetected,
 * never pulls the number or the row baseline — the tile geometry is constant.
 */
@ComponentV2
export struct PreviewThumbTile {
  @Require @Param image: EhGalleryImage;
  @Param tileWidth: number = ThemeConstants.PREVIEW_THUMB_MIN_W;
  @Event onTap: () => void = () => {};

  private frameHeight(): number {
    return this.tileWidth * FRAME_ASPECT
  }

  // Thumb true aspect (height / width); 0 when sprite dimensions are missing/misdetected.
  private thumbAspect(): number {
    return this.image.thumbWidth > 0 && this.image.thumbHeight > 0
      ? this.image.thumbHeight / this.image.thumbWidth
      : 0
  }

  // Contain: a thumb taller than the frame is fit by HEIGHT (its width then ≤ frame width); anything
  // else is fit by WIDTH (its height then ≤ frame height). Either way it fits inside the fixed frame.
  private fitByHeight(): boolean {
    const a: number = this.thumbAspect()
    return a > 0 && a > FRAME_ASPECT
  }

  build() {
    Column({ space: ThemeConstants.SPACE_XS }) {
      // Transparent layout slot: constant width × height only reserves alignment for the page number.
      // The visible sprite/image keeps its real aspect and owns the rounded clip; the slot must not render
      // as a grey letterbox container after the real thumbnail is loaded.
      Stack() {
        if (this.fitByHeight()) {
          EhSpriteThumbnail({
            url: this.image.thumbUrl,
            thumbWidth: this.image.thumbWidth,
            thumbHeight: this.image.thumbHeight,
            offsetX: this.image.thumbOffsetX,
            spriteWidth: this.image.spriteWidth,
            spriteHeight: this.image.spriteHeight,
            fitHeight: true,
            displayHeight: this.frameHeight(),
            // Radius lives on the SPRITE/IMAGE itself (EhSpriteThumbnail clips its sprite to this radius),
            // not on a decorative outer layer — so the visible thumb has real rounded corners even when it
            // fills the frame. Matches the frame's THUMB_RADIUS so the silhouette is one consistent rounded rect.
            radius: ThemeConstants.THUMB_RADIUS,
          })
        } else {
          EhSpriteThumbnail({
            url: this.image.thumbUrl,
            thumbWidth: this.image.thumbWidth,
            thumbHeight: this.image.thumbHeight,
            offsetX: this.image.thumbOffsetX,
            spriteWidth: this.image.spriteWidth,
            spriteHeight: this.image.spriteHeight,
            displayWidth: this.tileWidth,
            radius: ThemeConstants.THUMB_RADIUS,
          })
        }
      }
      .width(this.tileWidth)
      .height(this.frameHeight())
      .clip(true)
      .alignContent(Alignment.Center)

      // Page number — fixed position below the fixed frame, identical for every tile.
      Text(`${this.image.page}`)
        .fontSize(ThemeConstants.FONT_SIZE_TINY)
        .fontColor($r('sys.color.font_tertiary'))
    }
    .width(this.tileWidth)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.onTap()
    })
  }
}
