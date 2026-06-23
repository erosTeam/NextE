import { ThemeConstants } from '../theme/ThemeConstants'
import { EhGallery } from '../model/EhGallery'
import { SimpleTag } from '../model/SimpleTag'
import { EhUsertag } from '../model/EhMytags'
import { EhConstants } from '../constants/EhConstants'
import { EhThumbnail } from './EhThumbnail'
import { RatingStars } from './RatingStars'
import { UserTagStore } from '../state/UserTagStore'
import { connectUserTagSignal, UserTagSignal } from '../state/UserTagSignal'
import { connectListMode, ListModeState } from '../state/ListModeState'
import { connectSearchAction } from '../state/SearchActionState'
import {
  connectTagTranslationSettings,
  TagTranslationSettingsState,
} from '../state/TagTranslationSettingsState'

// Cap list-card tags so the wrapped chips fill ~3 rows (eros_fe's listViewTagLimit keeps cards balanced).
const CARD_TAG_LIMIT: number = 8

/**
 * Gallery list-row card (eros_fe list card on V2Next TopicCard structure): a rounded `card_background`
 * card on the page sub-background. The cover is an explicit row-height slot, so a very tall source cover
 * cannot contribute intrinsic height and blow up the list rhythm. The right column flows title → uploader
 * → tags → (spacer) → rating/meta → category/date.
 *
 * Tag chips are NEUTRAL by default (a flat light-grey fill, no stroke — verified against eros_fe source:
 * TagItem has no border). A chip only takes color when the USER colored that exact tag in "My Tags"
 * (looked up at render in UserTagStore, eros_fe's getColorCode) — list tags are NOT colored by namespace.
 * Reading `tagSig.version` subscribes the card so chips re-color the moment My Tags finish loading.
 * Read-only render of an EhGallery; the row's onClick (navigation) is owned by the list.
 */
@ComponentV2
export struct GalleryCard {
  @Require @Param gallery: EhGallery;
  // Current list content width (vp), measured by PullRefreshListScaffold after horizontal padding. This is
  // pane-local so fold/unfold and split-pane changes recompute in the same app process.
  @Param listContentWidth: number = 0;
  // Reactive bump from the usertag loader; read in the chip key so cards re-color on a late My Tags load.
  private tagSig: UserTagSignal = connectUserTagSignal();
  @Local tagTranslation: TagTranslationSettingsState = connectTagTranslationSettings();
  // eros_fe `fixedHeightOfListItems` (default true). FIXED → every row is one portrait-cover height with
  // title/tags clipped and the meta foot-anchored (uniform list rhythm); ADAPTIVE → the row grows with its
  // content. Read reactively (@Trace) so flipping the setting re-lays the visible cards live.
  private listMode: ListModeState = connectListMode();
  @Local coverSlotHeight: number = 0;

  private coverWidth(): number {
    const contentWidth: number =
      this.listContentWidth > 0
        ? this.listContentWidth
        : ThemeConstants.LIST_CARD_WIDE_COVER_WIDTH * 3
    const narrowWidth: number = contentWidth / 3
    return narrowWidth < ThemeConstants.LIST_CARD_WIDE_COVER_WIDTH
      ? narrowWidth
      : ThemeConstants.LIST_CARD_WIDE_COVER_WIDTH
  }

  private adaptiveMinHeight(): number {
    return this.coverWidth() / ThemeConstants.LIST_CARD_COVER_ASPECT
  }

  private coverHeight(): number {
    return this.listMode.fixedHeight
      ? ThemeConstants.LIST_CARD_FIXED_HEIGHT
      : this.adaptiveMinHeight()
  }

  private activeCoverHeight(): number {
    if (!this.listMode.fixedHeight && this.coverSlotHeight > 0) {
      return this.coverSlotHeight
    }
    return this.coverHeight()
  }

  // eros_fe cover fit (gallery_item.dart _fit): when the source cover ratio is close to the card cover slot,
  // fill it (Cover, light crop); when it is far (very wide / very tall), letterbox it (Contain) so the whole
  // cover shows and EhThumbnail fills the gaps with the cover-color gradient (or blur). The slot ratio uses
  // the actual stretched cover slot when adaptive rows are taller than the initial estimate.
  private coverFillsSlot(): boolean {
    if (this.gallery.imgWidth <= 0 || this.gallery.imgHeight <= 0) {
      return false
    }
    const imageRatio: number = this.gallery.imgWidth / this.gallery.imgHeight
    const slotRatio: number = this.coverWidth() / this.activeCoverHeight()
    return imageRatio - slotRatio <= 0.28 && slotRatio - imageRatio <= 0.2
  }

  // Chip background: the user's own fill color for this tag, else the inline-style color (future), else
  // neutral grey. Never namespace-derived.
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

  // Chip text: the user's own (EH-chosen readable) text color for this tag, else inline-style, else grey.
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
    const query: string = EhConstants.exactTagSearchQuery(t.namespace, t.text)
    if (query.length === 0) {
      return
    }
    connectSearchAction().publishQuery(query)
  }

  private tagLabel(t: SimpleTag): string {
    return this.tagTranslation.enabled ? t.display() : t.text
  }

  // Neutral tag chips (flat light-grey fill, no stroke) wrapping up to CARD_TAG_LIMIT. A chip only colors
  // when the tag carries the user's own per-tag color value — never by namespace. Shared by both height
  // modes; the FIXED-mode wrapper clips overflow, the ADAPTIVE-mode card grows to show every row.
  @Builder
  tagChips() {
    if (this.gallery.simpleTags.length > 0) {
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(
          this.gallery.simpleTags.slice(0, CARD_TAG_LIMIT),
          (t: SimpleTag) => {
            Text(this.tagLabel(t))
              .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
              .fontColor(this.chipText(t))
              .backgroundColor(this.chipBg(t))
              .borderRadius(ThemeConstants.LIST_TAG_RADIUS)
              // Snug padding so short tags hug their text (eros_fe TagItem is 4/2; 6/3 is the
              // native-snug equivalent — 8/4 ballooned short chips into wide pills with grey flanks).
              .padding({ left: 6, right: 6, top: 3, bottom: 3 })
              .margin({ right: ThemeConstants.SPACE_XS, bottom: ThemeConstants.SPACE_XS })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: 160 })
              .onClick(() => {
                this.searchTag(t)
              })
          },
          // Key carries tagSig.version: the keyGen runs during build, so reading it subscribes the
          // card; when My Tags load and bump it, the keys change → chips rebuild → re-color.
          (t: SimpleTag) => `${this.tagSig.version}:${t.namespace}:${t.text}`,
        )
      }.width('100%')
    }
  }

  build() {
    // Flex with ItemAlign.Stretch: the text column defines the card height (its content, responsive min).
    // The cover itself is an explicit slot; otherwise a very tall EH cover can feed intrinsic height back
    // into the row before the right column's fixed-height constraint settles.
    Flex({ direction: FlexDirection.Row, alignItems: ItemAlign.Stretch }) {
      // Cover: the wrapper is stretched by the row, so adaptive cards compare the image ratio against the
      // real container height after tags/title have laid out. The thumbnail still receives explicit numbers.
      Stack({ alignContent: Alignment.Center }) {
        EhThumbnail({
          url: this.gallery.thumbUrl,
          thumbWidth: this.coverWidth(),
          thumbHeight: this.activeCoverHeight(),
          radius: 0,
          sourceWidth: this.gallery.imgWidth,
          sourceHeight: this.gallery.imgHeight,
          // Close cover ratios fill the slot (Cover, light crop); far ratios (very wide/tall) letterbox
          // (Contain) so the whole cover shows, and the cover-color gradient (or blur) fills the gaps.
          containFit: !this.coverFillsSlot(),
          letterboxBackground: true,
        })
      }
      .width(this.coverWidth())
      .onAreaChange((_oldArea: Area, area: Area) => {
        if (this.listMode.fixedHeight) {
          return
        }
        const height: number = area.height as number
        if (height > 0 && Math.abs(height - this.coverSlotHeight) > 0.5) {
          this.coverSlotHeight = height
        }
      })
      Column({ space: ThemeConstants.SPACE_XS }) {
        Text(this.gallery.title())
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontColor($r('sys.color.font_primary'))
          .lineHeight(ThemeConstants.LINE_HEIGHT_TITLE)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        // Uploader sits right under the title (eros_fe placement). A fav note (favorites scope) replaces
        // the uploader when there is no uploader, emphasized.
        Text(
          this.gallery.uploader.length > 0
            ? this.gallery.uploader
            : this.gallery.favNote.length > 0
              ? $r('app.string.gallery_fav_note', this.gallery.favNote)
              : '',
        )
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor(
            this.gallery.uploader.length === 0 && this.gallery.favNote.length > 0
              ? $r('sys.color.font_emphasize')
              : $r('sys.color.font_secondary'),
          )
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        // Middle (tags). FIXED: the tag block fills the uniform row's slack and CLIPS overflow so the row
        // stays one cover height with the meta foot-anchored (eros_fe's fixed-height tag waterfall truncates
        // the same way). ADAPTIVE: the tags float centered between two springs (eros_fe's two Spacers) and
        // the card grows to fit every wrapped row.
        if (this.listMode.fixedHeight) {
          Column() {
            this.tagChips()
          }
          .width('100%')
          .layoutWeight(1)
          .clip(true)
          .alignItems(HorizontalAlign.Start)
        } else {
          Blank()
          this.tagChips()
          Blank()
        }
        // Meta row 1 — rating stars (left, fills) · favcat heart · translated-language + page count.
        // eros_fe puts the favcat heart here (between rating and filecount), shows stars only (no number).
        Row({ space: ThemeConstants.SPACE_XS }) {
          // eros_fe StaticRatingBar (gallery_item.dart:478-482): stars tinted by colorRatingMap[colorRating]
          // (community orange / personal-rating variant), NOT system yellow. RatingStars is an intrinsic
          // 5-star cluster (width = 5·starSize), so the bar stays tight like eros_fe — no layoutWeight spread.
          RatingStars({
            rating: this.gallery.ratingFallBack,
            colorRating: this.gallery.colorRating,
            starSize: 16,
          })
          Blank()
          if (this.gallery.favcat.length > 0 || this.gallery.favTitle.length > 0) {
            SymbolGlyph($r('sys.symbol.heart_fill'))
              .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
              .fontColor([
                this.gallery.favcat.length > 0
                  ? EhConstants.favCatColor(this.gallery.favcat)
                  : ThemeConstants.FAV_HEART_DEFAULT,
              ])
          }
          if (this.gallery.translated.length > 0) {
            Text(this.gallery.translated)
              .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
              .fontColor($r('sys.color.font_tertiary'))
          }
          Text(`${this.gallery.fileCount}P`)
            .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
            .fontColor($r('sys.color.font_secondary'))
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        // Meta row 2 — category badge (left, solid, white text), post date (right).
        Row() {
          if (this.gallery.category.length > 0) {
            Text(this.gallery.category)
              .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeConstants.TEXT_ON_BRAND)
              .backgroundColor(EhConstants.categoryColor(this.gallery.category))
              .borderRadius(ThemeConstants.LIST_TAG_RADIUS)
              .padding({
                left: ThemeConstants.SPACE_SM,
                right: ThemeConstants.SPACE_SM,
                top: 3,
                bottom: 3,
              })
          }
          Blank()
          Text(this.gallery.postTime)
            .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
            // Expunged/replaced galleries show a struck-through date (eros_fe PostTime lineThrough).
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
      .alignItems(HorizontalAlign.Start)
      .padding({
        left: ThemeConstants.SPACE_SM,
        right: ThemeConstants.SPACE_MD,
        top: ThemeConstants.SPACE_SM,
        bottom: ThemeConstants.SPACE_SM,
      })
      // FIXED → pin every row to eros_fe's kFixedHeight rhythm (min=max);
      // ADAPTIVE → floor at a responsive cover slot height so sparse cards don't collapse, but grow past it
      // for a 2-line title + wrapped tags. The cover stays in its slot instead of driving row height.
      .constraintSize(
        this.listMode.fixedHeight
          ? {
              minHeight: ThemeConstants.LIST_CARD_FIXED_HEIGHT,
              maxHeight: ThemeConstants.LIST_CARD_FIXED_HEIGHT,
            }
          : { minHeight: this.adaptiveMinHeight() },
      )
    }
    .width('100%')
    .borderRadius(ThemeConstants.RADIUS_MD)
    .clip(true)
    .backgroundColor($r('app.color.card_background'))
  }
}
