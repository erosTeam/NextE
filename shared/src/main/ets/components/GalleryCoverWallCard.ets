import { EhGallery } from '../model/EhGallery'
import { ThemeConstants } from '../theme/ThemeConstants'
import { EhThumbnail } from './EhThumbnail'
import {
  CATEGORY_BADGE_COMPACT_TEXT_CENTER_X_RATIO,
  CATEGORY_BADGE_COMPACT_TEXT_CENTER_Y_RATIO,
  GalleryCategoryCornerBadge,
} from './GalleryCategoryCornerBadge'

const COVER_WALL_MIN_COVER_RATIO: number = 0.5
const COVER_WALL_MAX_COVER_RATIO: number = 1.35

/**
 * Minimal cover wall card: WaterFlow rhythm with only the cover and category/language badge.
 */
@ComponentV2
export struct GalleryCoverWallCard {
  @Require @Param gallery: EhGallery;
  @Param selected: boolean = false;

  private coverRatio(): number {
    if (this.gallery.imgWidth <= 0 || this.gallery.imgHeight <= 0) {
      return ThemeConstants.GALLERY_GRID_COVER_RATIO
    }
    const ratio: number = this.gallery.imgWidth / this.gallery.imgHeight
    if (ratio < COVER_WALL_MIN_COVER_RATIO) {
      return COVER_WALL_MIN_COVER_RATIO
    }
    if (ratio > COVER_WALL_MAX_COVER_RATIO) {
      return COVER_WALL_MAX_COVER_RATIO
    }
    return ratio
  }

  private sourceCoverRatio(): number {
    if (this.gallery.imgWidth <= 0 || this.gallery.imgHeight <= 0) {
      return this.coverRatio()
    }
    return this.gallery.imgWidth / this.gallery.imgHeight
  }

  private isExtremeTallCover(): boolean {
    return this.sourceCoverRatio() < COVER_WALL_MIN_COVER_RATIO
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      EhThumbnail({
        url: this.gallery.thumbUrl,
        coverRatio: this.coverRatio(),
        radius: ThemeConstants.GALLERY_GRID_CARD_RADIUS,
        forceCoverFit: !this.isExtremeTallCover(),
        containFit: this.isExtremeTallCover(),
        sourceWidth: this.gallery.imgWidth,
        sourceHeight: this.gallery.imgHeight,
        letterboxBackground: true,
      })
      .brightness(this.selected ? 0.86 : 1)
      GalleryCategoryCornerBadge({
        category: this.gallery.category,
        translated: this.gallery.translated,
        textCenterXRatio: CATEGORY_BADGE_COMPACT_TEXT_CENTER_X_RATIO,
        textCenterYRatio: CATEGORY_BADGE_COMPACT_TEXT_CENTER_Y_RATIO,
      })
    }
    .width('100%')
    .borderRadius(ThemeConstants.GALLERY_GRID_CARD_RADIUS)
    .clip(true)
  }
}
