import { EhGallery } from '../model/EhGallery'
import { SimpleTag } from '../model/SimpleTag'
import { EhUsertag } from '../model/EhMytags'
import { ThemeConstants } from '../theme/ThemeConstants'
import { EhConstants } from '../constants/EhConstants'
import { EhThumbnail } from './EhThumbnail'
import { UserTagStore } from '../state/UserTagStore'
import { connectUserTagSignal, UserTagSignal } from '../state/UserTagSignal'
import { connectSearchAction } from '../state/SearchActionState'

const GRID_TAG_LIMIT: number = 8

/**
 * Cover-first gallery card for the grid view. eros_fe's grid is a browsing wall: the cover is the
 * primary information, title + tags are secondary, and page/fav/language state is overlaid on the image.
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

  @Builder
  tagChips() {
    if (this.gallery.simpleTags.length > 0) {
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(
          this.gallery.simpleTags.slice(0, GRID_TAG_LIMIT),
          (t: SimpleTag) => {
            Text(t.display())
              .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.chipText(t))
              .backgroundColor(this.chipBg(t))
              .borderRadius(ThemeConstants.RADIUS_SM)
              .padding({ left: 6, right: 6, top: 3, bottom: 3 })
              .margin({ right: ThemeConstants.SPACE_XS, bottom: ThemeConstants.SPACE_XS })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: 148 })
              .onClick(() => {
                this.searchTag(t)
              })
          },
          (t: SimpleTag) => `${this.tagSig.version}:${t.namespace}:${t.text}`,
        )
      }.width('100%')
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
      Text(this.gallery.title())
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      this.tagChips()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(ThemeConstants.SPACE_SM)
    .borderRadius(ThemeConstants.RADIUS_CARD)
    .backgroundColor($r('app.color.card_background'))
  }
}
