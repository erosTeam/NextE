import { EhConstants } from '../constants/EhConstants'
import { EhGallery } from '../model/EhGallery'
import { SimpleTag } from '../model/SimpleTag'
import { connectSearchAction } from '../state/SearchActionState'
import { ThemeConstants } from '../theme/ThemeConstants'
import { EhThumbnail } from './EhThumbnail'
import { GalleryCategoryCornerBadge } from './GalleryCategoryCornerBadge'

const WATERFALL_MIN_COVER_RATIO: number = 0.5
const WATERFALL_MAX_COVER_RATIO: number = 1.35

/**
 * Masonry card for ListMode.WATERFALL. Unlike GalleryGridCard, this deliberately allows variable
 * height: the cover follows the EH source aspect ratio and the compact info block can grow within
 * bounded text/tag lines. Grid remains the uniform-cell browsing mode.
 */
@ComponentV2
export struct GalleryWaterfallCard {
  @Require @Param gallery: EhGallery;

  private coverRatio(): number {
    if (this.gallery.imgWidth <= 0 || this.gallery.imgHeight <= 0) {
      return ThemeConstants.GALLERY_GRID_COVER_RATIO
    }
    const ratio: number = this.gallery.imgWidth / this.gallery.imgHeight
    if (ratio < WATERFALL_MIN_COVER_RATIO) {
      return WATERFALL_MIN_COVER_RATIO
    }
    if (ratio > WATERFALL_MAX_COVER_RATIO) {
      return WATERFALL_MAX_COVER_RATIO
    }
    return ratio
  }

  private ratingText(): string {
    if (this.gallery.ratingFallBack > 0) {
      return this.gallery.ratingFallBack.toFixed(2)
    }
    if (this.gallery.rating > 0) {
      return this.gallery.rating.toFixed(2)
    }
    return ''
  }

  private searchTag(t: SimpleTag): void {
    const query: string = EhConstants.exactTagSearchQuery(t.namespace, t.text)
    if (query.length === 0) {
      return
    }
    connectSearchAction().publishQuery(query)
  }

  @Builder
  private Tags() {
    if (this.gallery.simpleTags.length > 0) {
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(
          this.gallery.simpleTags.slice(0, 4),
          (t: SimpleTag) => {
            Text(t.display())
              .fontSize(ThemeConstants.FONT_SIZE_TINY)
              .fontColor($r('sys.color.font_secondary'))
              .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
              .borderRadius(ThemeConstants.RADIUS_SM)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: 130 })
              .margin({ right: ThemeConstants.SPACE_XS, bottom: ThemeConstants.SPACE_XS })
              .onClick(() => {
                this.searchTag(t)
              })
          },
          (t: SimpleTag) => `${t.namespace}:${t.text}`,
        )
      }
      .width('100%')
    }
  }

  build() {
    Column({ space: ThemeConstants.SPACE_SM }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        EhThumbnail({
          url: this.gallery.thumbUrl,
          coverRatio: this.coverRatio(),
          radius: ThemeConstants.THUMB_RADIUS,
          forceCoverFit: true,
          sourceWidth: this.gallery.imgWidth,
          sourceHeight: this.gallery.imgHeight,
        })
        GalleryCategoryCornerBadge({
          category: this.gallery.category,
          translated: this.gallery.translated,
        })
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
        .padding({ left: 7, right: 7, top: 3, bottom: 3 })
        .position({ right: ThemeConstants.SPACE_XS, bottom: ThemeConstants.SPACE_XS })
      }
      .width('100%')
      Column({ space: ThemeConstants.SPACE_XS }) {
        Row({ space: ThemeConstants.SPACE_XS }) {
          if (this.ratingText().length > 0) {
            SymbolGlyph($r('sys.symbol.star_fill'))
              .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
              .fontColor([EhConstants.ratingStarColor(this.gallery.colorRating)])
            Text(this.ratingText())
              .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_secondary'))
          }
          Blank()
          Text(this.gallery.postTime.length > 0 ? this.gallery.postTime : this.gallery.category)
            .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        Text(this.gallery.title())
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        this.Tags()
      }
      .width('100%')
      .padding({
        left: ThemeConstants.SPACE_SM,
        right: ThemeConstants.SPACE_SM,
        bottom: ThemeConstants.SPACE_SM,
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .borderRadius(ThemeConstants.RADIUS_CARD)
    .backgroundColor($r('app.color.card_background'))
    .clip(true)
  }
}
