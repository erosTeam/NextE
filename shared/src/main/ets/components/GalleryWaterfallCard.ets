import { EhConstants } from '../constants/EhConstants'
import { EhGallery } from '../model/EhGallery'
import { EhUsertag } from '../model/EhMytags'
import { SimpleTag } from '../model/SimpleTag'
import { connectSearchAction } from '../state/SearchActionState'
import {
  connectTagTranslationSettings,
  TagTranslationSettingsState,
} from '../state/TagTranslationSettingsState'
import { connectUserTagSignal, UserTagSignal } from '../state/UserTagSignal'
import { UserTagStore } from '../state/UserTagStore'
import { ThemeConstants } from '../theme/ThemeConstants'
import { EhThumbnail } from './EhThumbnail'
import { GalleryCategoryCornerBadge } from './GalleryCategoryCornerBadge'

const WATERFALL_MIN_COVER_RATIO: number = 0.5
const WATERFALL_MAX_COVER_RATIO: number = 1.35
const WATERFALL_TAG_LIMIT: number = 8
const WATERFALL_TAG_STRIP_HEIGHT: number = 48

/**
 * Masonry card for ListMode.WATERFALL. Unlike GalleryGridCard, this deliberately allows variable
 * height: the cover follows the EH source aspect ratio and the compact info block can grow within
 * bounded text/tag lines. Grid remains the uniform-cell browsing mode.
 */
@ComponentV2
export struct GalleryWaterfallCard {
  @Require @Param gallery: EhGallery;
  private tagSig: UserTagSignal = connectUserTagSignal();
  @Local tagTranslation: TagTranslationSettingsState = connectTagTranslationSettings();
  private tagScroller: Scroller = new Scroller();

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

  private sourceCoverRatio(): number {
    if (this.gallery.imgWidth <= 0 || this.gallery.imgHeight <= 0) {
      return this.coverRatio()
    }
    return this.gallery.imgWidth / this.gallery.imgHeight
  }

  private isExtremeTallCover(): boolean {
    return this.sourceCoverRatio() < WATERFALL_MIN_COVER_RATIO
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

  private tagLabel(t: SimpleTag): string {
    return this.tagTranslation.enabled ? t.display() : t.text
  }

  private chipBg(t: SimpleTag): ResourceColor {
    const u: EhUsertag | undefined = UserTagStore.getInstance().lookup(t.namespace, t.text)
    if (u !== undefined && u.fillColor.length > 0) {
      return u.fillColor
    }
    if (t.backgroundColor.length > 0) {
      return t.backgroundColor
    }
    return $r('sys.color.ohos_id_color_button_normal')
  }

  private chipText(t: SimpleTag): ResourceColor {
    const u: EhUsertag | undefined = UserTagStore.getInstance().lookup(t.namespace, t.text)
    if (u !== undefined && u.textColor.length > 0) {
      return u.textColor
    }
    if (t.color.length > 0) {
      return t.color
    }
    return $r('sys.color.font_secondary')
  }

  private tagRowIndexes(remainder: number): number[] {
    const total: number = Math.min(this.gallery.simpleTags.length, WATERFALL_TAG_LIMIT)
    const indexes: number[] = []
    for (let i = 0; i < total; i++) {
      if (i % 2 === remainder) {
        indexes.push(i)
      }
    }
    return indexes
  }

  @Builder
  private TagChip(t: SimpleTag) {
    Text(this.tagLabel(t))
      .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
      .fontColor(this.chipText(t))
      .backgroundColor(this.chipBg(t))
      .borderRadius(ThemeConstants.LIST_TAG_RADIUS)
      .padding({ left: 6, right: 6, top: 3, bottom: 3 })
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .constraintSize({ maxWidth: 150 })
      .onClick(() => {
        this.searchTag(t)
      })
  }

  @Builder
  private TagRow(remainder: number) {
    Row({ space: ThemeConstants.SPACE_XS }) {
      ForEach(
        this.tagRowIndexes(remainder),
        (index: number) => {
          this.TagChip(this.gallery.simpleTags[index])
        },
        (index: number) => `${this.tagSig.version}:row:${remainder}:${index}`,
      )
    }
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private Tags() {
    if (this.gallery.simpleTags.length > 0) {
      Scroll(this.tagScroller) {
        Column({ space: ThemeConstants.SPACE_XS }) {
          this.TagRow(0)
          this.TagRow(1)
        }
        .alignItems(HorizontalAlign.Start)
      }
      .scrollable(ScrollDirection.Horizontal)
      .nestedScroll({
        scrollForward: NestedScrollMode.SELF_ONLY,
        scrollBackward: NestedScrollMode.SELF_ONLY,
      })
      .scrollBar(BarState.Off)
      .align(Alignment.Start)
      .width('100%')
      .height(WATERFALL_TAG_STRIP_HEIGHT)
    }
  }

  build() {
    Column({ space: ThemeConstants.SPACE_SM }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        EhThumbnail({
          url: this.gallery.thumbUrl,
          coverRatio: this.coverRatio(),
          radius: ThemeConstants.THUMB_RADIUS,
          forceCoverFit: !this.isExtremeTallCover(),
          containFit: this.isExtremeTallCover(),
          sourceWidth: this.gallery.imgWidth,
          sourceHeight: this.gallery.imgHeight,
          letterboxBackground: true,
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
      }.width('100%')
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
