import { EhConstants } from '../constants/EhConstants'
import { ThemeConstants } from '../theme/ThemeConstants'

const CATEGORY_BADGE_W: number = 36
const CATEGORY_BADGE_H: number = 28
const CATEGORY_BADGE_TEXT_W: number = 24
const CATEGORY_BADGE_TEXT_H: number = 12
const CATEGORY_BADGE_DEFAULT_TEXT_CENTER_X_RATIO: number = 0.58
const CATEGORY_BADGE_DEFAULT_TEXT_CENTER_Y_RATIO: number = 0.37
export const CATEGORY_BADGE_COMPACT_TEXT_CENTER_X_RATIO: number = 0.62
export const CATEGORY_BADGE_COMPACT_TEXT_CENTER_Y_RATIO: number = 0.35
const CATEGORY_BADGE_TEXT_SIZE: number = 8
const CATEGORY_BADGE_TEXT_ANGLE: number =
  Math.atan(CATEGORY_BADGE_H / CATEGORY_BADGE_W) * 180 / Math.PI
const CATEGORY_BADGE_OPACITY: number = 0.88

/**
 * Shared gallery category/language corner signal for Grid and Waterfall cards.
 * The triangle is a small identity marker, not a large decorative ribbon.
 */
@ComponentV2
export struct GalleryCategoryCornerBadge {
  @Param category: string = '';
  @Param translated: string = '';
  @Param textCenterXRatio: number = CATEGORY_BADGE_DEFAULT_TEXT_CENTER_X_RATIO;
  @Param textCenterYRatio: number = CATEGORY_BADGE_DEFAULT_TEXT_CENTER_Y_RATIO;

  private textTop(): number {
    return CATEGORY_BADGE_H * this.textCenterYRatio - CATEGORY_BADGE_TEXT_H / 2
  }

  private textRight(): number {
    return CATEGORY_BADGE_W - CATEGORY_BADGE_W * this.textCenterXRatio - CATEGORY_BADGE_TEXT_W / 2
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Polygon({ width: CATEGORY_BADGE_W, height: CATEGORY_BADGE_H })
        .points([[0, 0], [CATEGORY_BADGE_W, 0], [CATEGORY_BADGE_W, CATEGORY_BADGE_H]])
        .fill(EhConstants.categoryColor(this.category))
        .fillOpacity(CATEGORY_BADGE_OPACITY)
      if (this.translated.length > 0) {
        Text(this.translated)
          .fontSize(CATEGORY_BADGE_TEXT_SIZE)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeConstants.TEXT_ON_BRAND)
          .maxLines(1)
          .textAlign(TextAlign.Center)
          .width(CATEGORY_BADGE_TEXT_W)
          .height(CATEGORY_BADGE_TEXT_H)
          .rotate({ angle: CATEGORY_BADGE_TEXT_ANGLE })
          .position({ right: this.textRight(), top: this.textTop() })
      }
    }
    .width(CATEGORY_BADGE_W)
    .height(CATEGORY_BADGE_H)
    .borderRadius({ topRight: ThemeConstants.THUMB_RADIUS })
    .clip(true)
  }
}
