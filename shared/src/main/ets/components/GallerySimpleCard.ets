import { ThemeConstants } from '../theme/ThemeConstants'
import { EhGallery } from '../model/EhGallery'
import { EhConstants } from '../constants/EhConstants'
import { EhThumbnail } from './EhThumbnail'
import { RatingStars } from './RatingStars'

const SIMPLE_THUMB_W: number = 72
const SIMPLE_THUMB_H: number = 102

/**
 * Compact gallery row for ListMode.SIMPLE_LIST (eros_fe `GalleryItemSimpleWidget`): denser than
 * GalleryCard — smaller cover, no rounded card chrome, a hairline bottom divider instead of card
 * separation, and a tighter info column (title · uploader · rating/heart/lang/pages · category/time).
 * Read-only render of an EhGallery; the row onClick (navigation) is owned by the list.
 */
@ComponentV2
export struct GallerySimpleCard {
  @Require @Param gallery: EhGallery;

  build() {
    Row({ space: ThemeConstants.SPACE_SM }) {
      EhThumbnail({
        url: this.gallery.thumbUrl,
        thumbWidth: SIMPLE_THUMB_W,
        thumbHeight: SIMPLE_THUMB_H,
        radius: ThemeConstants.THUMB_RADIUS,
      })
      Column({ space: ThemeConstants.SPACE_XS }) {
        Text(this.gallery.title())
          .fontSize(ThemeConstants.FONT_SIZE_META)
          .fontColor($r('sys.color.font_primary'))
          .lineHeight(ThemeConstants.LINE_HEIGHT_BODY)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        // eros_fe's simple item shows the uploader under the title (fills the fixed-height row).
        if (this.gallery.uploader.length > 0) {
          Text(this.gallery.uploader)
            .fontSize(ThemeConstants.FONT_SIZE_TINY)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        Blank()
        Row({ space: ThemeConstants.SPACE_XS }) {
          RatingStars({
            rating: this.gallery.ratingFallBack,
            color: EhConstants.ratingStarColor(this.gallery.colorRating),
            starSize: 12,
          })
          Text(this.gallery.ratingFallBack.toFixed(2))
            .fontSize(ThemeConstants.FONT_SIZE_TINY)
            .fontColor($r('sys.color.font_tertiary'))
          if (this.gallery.favcat.length > 0 || this.gallery.favTitle.length > 0) {
            SymbolGlyph($r('sys.symbol.heart_fill'))
              .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
              .fontColor([
                this.gallery.favcat.length > 0
                  ? EhConstants.favCatColor(this.gallery.favcat)
                  : ThemeConstants.FAV_HEART_DEFAULT,
              ])
          }
          Blank()
          if (this.gallery.translated.length > 0) {
            Text(this.gallery.translated)
              .fontSize(ThemeConstants.FONT_SIZE_TINY)
              .fontColor($r('sys.color.font_tertiary'))
              .margin({ right: ThemeConstants.SPACE_XS })
          }
          Text(`${this.gallery.fileCount}P`)
            .fontSize(ThemeConstants.FONT_SIZE_TINY)
            .fontColor($r('sys.color.font_secondary'))
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
          Text(this.gallery.postTime)
            .fontSize(ThemeConstants.FONT_SIZE_TINY)
            .fontColor($r('sys.color.font_tertiary'))
            .decoration({
              type: this.gallery.expunged
                ? TextDecorationType.LineThrough
                : TextDecorationType.None,
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .height(SIMPLE_THUMB_H)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({
      left: ThemeConstants.SPACE_MD,
      right: ThemeConstants.SPACE_MD,
      top: ThemeConstants.SPACE_SM,
      bottom: ThemeConstants.SPACE_SM,
    })
    .border({ width: { bottom: 0.5 }, color: ThemeConstants.DIVIDER })
  }
}
