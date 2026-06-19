import { EhGallery } from '../model/EhGallery'
import { SimpleTag } from '../model/SimpleTag'
import { EhUsertag } from '../model/EhMytags'
import { ThemeConstants } from '../theme/ThemeConstants'
import { EhConstants } from '../constants/EhConstants'
import { EhThumbnail } from './EhThumbnail'
import { UserTagStore } from '../state/UserTagStore'
import { connectUserTagSignal, UserTagSignal } from '../state/UserTagSignal'
import { connectSearchAction } from '../state/SearchActionState'

/**
 * Cover-first gallery card for the grid view. eros_fe's grid is a browsing wall: the cover is primary,
 * title + post time are the fast scanning cues, and page/fav/language state stays overlaid on the
 * image. Tags are a one-line sample only; the info block is fixed-height so Grid rows stay aligned
 * instead of drifting into masonry.
 */
@ComponentV2
export struct GalleryGridCard {
  @Require @Param gallery: EhGallery;
  private tagSig: UserTagSignal = connectUserTagSignal();

  chipBg(t: SimpleTag): ResourceColor {
    const u: EhUsertag | undefined = UserTagStore.getInstance().lookup(t.namespace, t.text)
    if (u !== undefined && u.fillColor.length > 0) {
      return u.fillColor
    }
    if (t.backgroundColor.length > 0) {
      return t.backgroundColor
    }
    return $r('sys.color.ohos_id_color_button_normal')
  }

  chipText(t: SimpleTag): ResourceColor {
    const u: EhUsertag | undefined = UserTagStore.getInstance().lookup(t.namespace, t.text)
    if (u !== undefined && u.textColor.length > 0) {
      return u.textColor
    }
    if (t.color.length > 0) {
      return t.color
    }
    return $r('sys.color.font_secondary')
  }

  private searchTag(t: SimpleTag): void {
    const namespace: string = t.namespace.trim()
    const tag: string = t.text.trim()
    if (namespace.length === 0 || tag.length === 0) {
      return
    }
    connectSearchAction().publishQuery(`${namespace}:${this.queryTagValue(tag)}`)
  }

  private queryTagValue(tag: string): string {
    if (tag.indexOf(' ') >= 0) {
      return `"${tag}"`
    }
    return tag
  }

  private metaText(): string {
    if (this.gallery.postTime.length > 0) {
      return this.gallery.postTime
    }
    if (this.gallery.uploader.length > 0) {
      return this.gallery.uploader
    }
    return this.gallery.category
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

  @Builder
  tagChips() {
    if (this.gallery.simpleTags.length > 0) {
      Row({ space: ThemeConstants.SPACE_XS }) {
        ForEach(
          this.gallery.simpleTags.slice(0, ThemeConstants.GALLERY_GRID_TAG_LIMIT),
          (t: SimpleTag) => {
            Text(t.display())
              .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.chipText(t))
              .backgroundColor(this.chipBg(t))
              .borderRadius(ThemeConstants.RADIUS_SM)
              .padding({ left: 6, right: 6, top: 3, bottom: 3 })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: 148 })
              .onClick(() => {
                this.searchTag(t)
              })
          },
          (t: SimpleTag) => `${this.tagSig.version}:${t.namespace}:${t.text}`,
        )
      }
      .width('100%')
    }
  }

  build() {
    Column({ space: ThemeConstants.SPACE_SM }) {
      Stack({ alignContent: Alignment.TopStart }) {
        EhThumbnail({
          url: this.gallery.thumbUrl,
          coverRatio: ThemeConstants.GALLERY_GRID_COVER_RATIO,
          radius: ThemeConstants.THUMB_RADIUS,
        })
        if (this.gallery.translated.length > 0) {
          Text(this.gallery.translated)
            .fontSize(ThemeConstants.FONT_SIZE_TINY)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeConstants.TEXT_ON_BRAND)
            .backgroundColor(EhConstants.categoryColor(this.gallery.category))
            .borderRadius({ topLeft: ThemeConstants.THUMB_RADIUS, bottomRight: ThemeConstants.RADIUS_SM })
            .padding({ left: 7, right: 7, top: 3, bottom: 3 })
        }
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
      }.width('100%')
      Column({ space: ThemeConstants.SPACE_XS }) {
        Text(this.gallery.title())
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .height(ThemeConstants.GALLERY_GRID_TITLE_HEIGHT)
          .width('100%')
        Row({ space: ThemeConstants.SPACE_XS }) {
          Text(this.metaText())
            .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (this.ratingText().length > 0) {
            Row({ space: 2 }) {
              SymbolGlyph($r('sys.symbol.star_fill'))
                .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
                .fontColor([EhConstants.ratingStarColor(this.gallery.colorRating)])
              Text(this.ratingText())
                .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('sys.color.font_secondary'))
                .maxLines(1)
            }
            .alignItems(VerticalAlign.Center)
          }
        }
        .height(ThemeConstants.GALLERY_GRID_META_HEIGHT)
        .width('100%')
        .alignItems(VerticalAlign.Center)
        Stack({ alignContent: Alignment.TopStart }) {
          this.tagChips()
        }
        .height(ThemeConstants.GALLERY_GRID_TAG_AREA_HEIGHT)
        .width('100%')
        .clip(true)
      }
      .width('100%')
      .height(ThemeConstants.GALLERY_GRID_INFO_HEIGHT)
      .justifyContent(FlexAlign.Start)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(ThemeConstants.SPACE_SM)
    .borderRadius(ThemeConstants.RADIUS_CARD)
    .backgroundColor($r('app.color.card_background'))
  }
}
