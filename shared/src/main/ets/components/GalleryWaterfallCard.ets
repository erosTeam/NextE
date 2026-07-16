import { EhConstants } from '../constants/EhConstants'
import { EhGallery } from '../model/EhGallery'
import { EhUsertag } from '../model/EhMytags'
import { SimpleTag } from '../model/SimpleTag'
import { connectSearchAction } from '../state/SearchActionState'
import { TagTranslationSettingsState } from '../state/TagTranslationSettingsState'
import { UserTagSignal } from '../state/UserTagSignal'
import { UserTagStore } from '../state/UserTagStore'
import { ThemeConstants } from '../theme/ThemeConstants'
import { EhThumbnail } from './EhThumbnail'
import { GalleryCategoryCornerBadge } from './GalleryCategoryCornerBadge'

const WATERFALL_MIN_COVER_RATIO: number = 0.5
const WATERFALL_MAX_COVER_RATIO: number = 1.35
const WATERFALL_TAG_LIMIT: number = 8
const WATERFALL_TAG_STRIP_HEIGHT: number = 48

// Reuse only cards whose conditional subtree shape matches. The identifiers deliberately use
// letters and underscores only, so they are also valid ArkUI state-management keys.
export function galleryWaterfallReuseId(gallery: EhGallery): string {
  const sourceRatio: number = gallery.imgWidth > 0 && gallery.imgHeight > 0
    ? gallery.imgWidth / gallery.imgHeight
    : ThemeConstants.GALLERY_GRID_COVER_RATIO
  const coverShape: string = sourceRatio < WATERFALL_MIN_COVER_RATIO ? 'contain' : 'cover'
  const favoriteShape: string = gallery.favcat.length > 0 || gallery.favTitle.length > 0
    ? 'favorite'
    : 'plain'
  const ratingShape: string = gallery.ratingFallBack > 0 || gallery.rating > 0
    ? 'rated'
    : 'unrated'
  const tagShape: string = gallery.simpleTags.length > 0 ? 'tags' : 'no_tags'
  const languageShape: string = gallery.translated.length > 0 ? 'translated' : 'no_translation'
  return `waterfall_${coverShape}_${favoriteShape}_${ratingShape}_${tagShape}_${languageShape}`
}

/**
 * Masonry card for ListMode.WATERFALL. Unlike GalleryGridCard, this deliberately allows variable
 * height: the cover follows the EH source aspect ratio and the compact info block can grow within
 * bounded text/tag lines. Grid remains the uniform-cell browsing mode.
 */
@ReusableV2
@ComponentV2
export struct GalleryWaterfallCard {
  @Require @Param gallery: EhGallery;
  @Param selected: boolean = false;
  // Page-owned shared signals avoid reconnecting AppStorageV2 for every prebuilt/reused card.
  @Require @Param tagSig: UserTagSignal;
  @Require @Param tagTranslation: TagTranslationSettingsState;
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

  /**
   * The store is intentionally a plain Map. Its snapshot version is therefore an explicit render
   * dependency for the chip colors, while the ForEach key stays tied to the tag item's identity.
   */
  private userTagAtSnapshot(t: SimpleTag, _revision: number): EhUsertag | undefined {
    return UserTagStore.getInstance().lookup(t.namespace, t.text)
  }

  private chipBg(t: SimpleTag, u: EhUsertag | undefined): ResourceColor {
    if (u !== undefined && u.colorCode.length > 0) {
      return u.colorCode
    }
    if (u !== undefined && u.fillColor.length > 0) {
      return u.fillColor
    }
    if (t.backgroundColor.length > 0) {
      return t.backgroundColor
    }
    return $r('sys.color.ohos_id_color_button_normal')
  }

  private chipText(t: SimpleTag, u: EhUsertag | undefined): ResourceColor {
    if (u !== undefined && u.textColor.length > 0) {
      return u.textColor
    }
    if (t.color.length > 0) {
      return t.color
    }
    return $r('sys.color.font_secondary')
  }

  private tagAt(index: number): SimpleTag | undefined {
    if (index < 0 || index >= WATERFALL_TAG_LIMIT || index >= this.gallery.simpleTags.length) {
      return undefined
    }
    return this.gallery.simpleTags[index]
  }

  private tagLabelAt(index: number): string {
    const t: SimpleTag | undefined = this.tagAt(index)
    return t === undefined ? '' : this.tagLabel(t)
  }

  private chipBgAt(index: number): ResourceColor {
    const t: SimpleTag | undefined = this.tagAt(index)
    if (t === undefined) {
      return Color.Transparent
    }
    return this.chipBg(t, this.userTagAtSnapshot(t, this.tagSig.version))
  }

  private chipTextAt(index: number): ResourceColor {
    const t: SimpleTag | undefined = this.tagAt(index)
    if (t === undefined) {
      return Color.Transparent
    }
    return this.chipText(t, this.userTagAtSnapshot(t, this.tagSig.version))
  }

  private searchTagAt(index: number): void {
    const t: SimpleTag | undefined = this.tagAt(index)
    if (t !== undefined) {
      this.searchTag(t)
    }
  }

  @Builder
  private TagChipAt(index: number) {
    if (this.tagAt(index) !== undefined) {
      Text(this.tagLabelAt(index))
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontColor(this.chipTextAt(index))
        .backgroundColor(this.chipBgAt(index))
        .borderRadius(ThemeConstants.LIST_TAG_RADIUS)
        .padding({ left: 6, right: 6, top: 3, bottom: 3 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: 150 })
        .onClick(() => {
          // Resolve through the current @Param instead of capturing the gallery that first built this slot.
          this.searchTagAt(index)
        })
    }
  }

  @Builder
  private TagRow(remainder: number) {
    Row({ space: ThemeConstants.SPACE_XS }) {
      this.TagChipAt(remainder)
      this.TagChipAt(remainder + 2)
      this.TagChipAt(remainder + 4)
      this.TagChipAt(remainder + 6)
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
        scrollForward: NestedScrollMode.SELF_FIRST,
        scrollBackward: NestedScrollMode.SELF_FIRST,
      })
      .scrollBar(BarState.Off)
      .align(Alignment.Start)
      .width('100%')
      .height(WATERFALL_TAG_STRIP_HEIGHT)
      // Tags stay unchanged while the card moves through WaterFlow. Cache this bounded subtree as one
      // drawing group instead of traversing every chip on each scroll frame; reuse invalidates it per item.
      .renderGroup(true)
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
    .backgroundColor(
      this.selected
        ? $r('app.color.navigation_item_selected')
        : $r('app.color.card_background'),
    )
    .clip(true)
  }
}
