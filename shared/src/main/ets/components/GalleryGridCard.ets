import { EhGallery } from '../model/EhGallery'
import { EhConstants } from '../constants/EhConstants'
import { ThemeConstants } from '../theme/ThemeConstants'
import { EhThumbnail } from './EhThumbnail'
import { GalleryCategoryCornerBadge } from './GalleryCategoryCornerBadge'

const COVER_META_PAD_X: number = 7
const COVER_META_PAD_Y: number = 3

/**
 * Compact cover-first card for ListMode.GRID.
 *
 * Grid is a fast browsing wall: fixed card rhythm, full-width cover, small category/language signal,
 * page/favorite overlay, then title + simple date/meta. Rich tags/ratings belong to Waterfall.
 */
@ComponentV2
export struct GalleryGridCard {
  @Require @Param gallery: EhGallery;

  private metaText(): string {
    if (this.gallery.postTime.length > 0) {
      return this.gallery.postTime
    }
    if (this.gallery.fileCount.length > 0) {
      return `${this.gallery.fileCount}P`
    }
    return this.gallery.category
  }

  @Builder
  private CoverMeta() {
    Row({ space: ThemeConstants.SPACE_XS }) {
      if (this.gallery.favcat.length > 0 || this.gallery.favTitle.length > 0) {
        SymbolGlyph($r('sys.symbol.heart_fill'))
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontColor([
            this.gallery.favcat.length > 0
              ? EhConstants.favCatColor(this.gallery.favcat)
              : ThemeConstants.FAV_HEART_DEFAULT,
          ])
      }
      Text(`${this.gallery.fileCount}P`)
        .fontSize(ThemeConstants.FONT_SIZE_TINY)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeConstants.TEXT_ON_BRAND)
    }
    .alignItems(VerticalAlign.Center)
    .backgroundColor('rgba(0, 0, 0, 0.48)')
    .borderRadius(ThemeConstants.RADIUS_MD)
    .padding({
      left: COVER_META_PAD_X,
      right: COVER_META_PAD_X,
      top: COVER_META_PAD_Y,
      bottom: COVER_META_PAD_Y,
    })
    .position({ right: ThemeConstants.SPACE_XS, bottom: ThemeConstants.SPACE_XS })
  }

  @Builder
  private Cover() {
    Stack({ alignContent: Alignment.TopEnd }) {
      EhThumbnail({
        url: this.gallery.thumbUrl,
        coverRatio: ThemeConstants.GALLERY_GRID_COVER_RATIO,
        radius: ThemeConstants.THUMB_RADIUS,
        sourceWidth: this.gallery.imgWidth,
        sourceHeight: this.gallery.imgHeight,
        letterboxBackground: true,
      })
      GalleryCategoryCornerBadge({
        category: this.gallery.category,
        translated: this.gallery.translated,
      })
      this.CoverMeta()
    }
    .width('100%')
    .borderRadius(ThemeConstants.THUMB_RADIUS)
    .clip(true)
  }

  @Builder
  private Info() {
    Column({ space: ThemeConstants.SPACE_XS }) {
      Text(this.gallery.title())
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .height(ThemeConstants.GALLERY_GRID_TITLE_HEIGHT)
        .width('100%')
      Text(this.metaText())
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontColor($r('sys.color.font_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .height(ThemeConstants.GALLERY_GRID_META_HEIGHT)
        .width('100%')
    }
    .width('100%')
    .height(ThemeConstants.GALLERY_GRID_INFO_HEIGHT)
    .justifyContent(FlexAlign.Start)
    .padding({ left: ThemeConstants.SPACE_XS, right: ThemeConstants.SPACE_XS })
  }

  build() {
    Column({ space: ThemeConstants.SPACE_XS }) {
      this.Cover()
      this.Info()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .borderRadius(ThemeConstants.RADIUS_CARD)
    .backgroundColor($r('app.color.card_background'))
    .clip(true)
  }
}
