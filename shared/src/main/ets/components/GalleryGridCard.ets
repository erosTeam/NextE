import { EhGallery } from '../model/EhGallery'
import { ThemeConstants } from '../theme/ThemeConstants'
import { EhConstants } from '../constants/EhConstants'
import { EhThumbnail } from './EhThumbnail'
import { RatingStars } from './RatingStars'

/**
 * Compact vertical gallery card for the grid view: full-width cover (gallery aspect ~0.7),
 * 2-line title, category + page count. Fills its grid cell; chrome matches GalleryCard.
 */
@ComponentV2
export struct GalleryGridCard {
  @Require @Param gallery: EhGallery;

  build() {
    Column({ space: ThemeConstants.SPACE_XS }) {
      Stack({ alignContent: Alignment.TopStart }) {
        // Shared cover component: full-width with the EH thumb ratio, with the same grey backing +
        // load spinner as the list cover (was a bare Image with no placeholder spinner).
        EhThumbnail({
          url: this.gallery.thumbUrl,
          coverRatio: 0.7,
          radius: ThemeConstants.THUMB_RADIUS,
        })
        // Language code corner badge (eros_fe flow/grid corner). Category-colored styling is a
        // follow-up once the shared category-color map lands; a legible dark pill for now.
        if (this.gallery.translated.length > 0) {
          Text(this.gallery.translated)
            .fontSize(ThemeConstants.FONT_SIZE_TINY)
            .fontColor(ThemeConstants.TEXT_ON_BRAND)
            .backgroundColor('rgba(0, 0, 0, 0.55)')
            .borderRadius(ThemeConstants.RADIUS_SM)
            .padding({ left: 5, right: 5, top: 1, bottom: 1 })
            .margin({ left: 4, top: 4 })
        }
      }.width('100%')
      Text(this.gallery.title())
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Row({ space: ThemeConstants.SPACE_XS }) {
        RatingStars({
          rating: this.gallery.ratingFallBack,
          color: EhConstants.ratingStarColor(this.gallery.colorRating),
          starSize: 12,
        })
        if (this.gallery.favcat.length > 0 || this.gallery.favTitle.length > 0) {
          SymbolGlyph($r('sys.symbol.heart_fill'))
            .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
            .fontColor([
              this.gallery.favcat.length > 0
                ? EhConstants.favCatColor(this.gallery.favcat)
                : ThemeConstants.FAV_HEART_DEFAULT,
            ])
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Row() {
        Text(this.gallery.category)
          .fontSize(ThemeConstants.FONT_SIZE_TINY)
          .fontColor(ThemeConstants.TEXT_ON_BRAND)
          .backgroundColor(EhConstants.categoryColor(this.gallery.category))
          .borderRadius(ThemeConstants.RADIUS_SM)
          .padding({ left: 6, right: 6, top: 1, bottom: 1 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Blank()
        Text(`${this.gallery.fileCount}P`)
          .fontSize(ThemeConstants.FONT_SIZE_TINY)
          .fontColor($r('sys.color.font_tertiary'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(ThemeConstants.SPACE_SM)
    .borderRadius(ThemeConstants.RADIUS_CARD)
    .backgroundColor($r('app.color.card_background'))
  }
}
