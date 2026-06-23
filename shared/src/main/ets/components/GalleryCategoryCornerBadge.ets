import { EhConstants } from '../constants/EhConstants'
import { ThemeConstants } from '../theme/ThemeConstants'

const CATEGORY_BADGE_W: number = 30
const CATEGORY_BADGE_H: number = 22
const CATEGORY_BADGE_TEXT_W: number = 22
const CATEGORY_BADGE_TEXT_H: number = 11
const CATEGORY_BADGE_TEXT_CENTER_X: number = CATEGORY_BADGE_W * 2 / 3 - 1
const CATEGORY_BADGE_TEXT_CENTER_Y: number = CATEGORY_BADGE_H / 3 + 1 / 6
const CATEGORY_BADGE_TEXT_TOP: number = CATEGORY_BADGE_TEXT_CENTER_Y - CATEGORY_BADGE_TEXT_H / 2
const CATEGORY_BADGE_TEXT_RIGHT: number =
  CATEGORY_BADGE_W - CATEGORY_BADGE_TEXT_CENTER_X - CATEGORY_BADGE_TEXT_W / 2
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
  @Param rightInset: number = 0;
  @Param topInset: number = 0;

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
          .position({ right: CATEGORY_BADGE_TEXT_RIGHT, top: CATEGORY_BADGE_TEXT_TOP })
      }
    }
    .width(CATEGORY_BADGE_W)
    .height(CATEGORY_BADGE_H)
    .borderRadius({ topRight: ThemeConstants.THUMB_RADIUS })
    .clip(true)
    .position({ right: this.rightInset, top: this.topInset })
  }
}
