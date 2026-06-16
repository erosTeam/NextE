import { display } from '@kit.ArkUI'
import { ThemeConstants } from '../theme/ThemeConstants'
import { EhGallery } from '../model/EhGallery'
import { SimpleTag } from '../model/SimpleTag'
import { EhUsertag } from '../model/EhMytags'
import { EhConstants } from '../constants/EhConstants'
import { EhThumbnail } from './EhThumbnail'
import { RatingStars } from './RatingStars'
import { UserTagStore } from '../state/UserTagStore'
import { connectUserTagSignal, UserTagSignal } from '../state/UserTagSignal'

// eros_fe sizes the list cover to 1/3 of the screen's shortest side (gallery_item.dart _CoverImage) —
// a deliberate proportion, not a magic width. Cached once (phone width is stable within a session).
let _coverW: number = 0
function cardCoverWidth(): number {
  if (_coverW <= 0) {
    const info: display.Display = display.getDefaultDisplaySync()
    const shortSide: number = info.width < info.height ? info.width : info.height
    _coverW = px2vp(shortSide) / 3
  }
  return _coverW
}

// EH thumbnail w/h ratio; anchors a sparse-tag card to a portrait cover height so it never collapses
// shorter than a cover. Tag-rich cards grow past it and the cover stretches to follow.
const COVER_ASPECT: number = 0.71
function cardMinHeight(): number {
  return cardCoverWidth() / COVER_ASPECT
}

// Cap list-card tags so the wrapped chips fill ~3 rows (eros_fe's listViewTagLimit keeps cards balanced).
const CARD_TAG_LIMIT: number = 8

/**
 * Gallery list-row card (eros_fe list card on V2Next TopicCard structure): a rounded `card_background`
 * card on the page sub-background. The cover is flush to the card's left/top/bottom edges and fills its
 * height; the right column flows title → uploader → tags → (spacer) → rating/meta → category/date.
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
  // Reactive bump from the usertag loader; read in the chip key so cards re-color on a late My Tags load.
  private tagSig: UserTagSignal = connectUserTagSignal();

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

  build() {
    // Flex with ItemAlign.Stretch: the text column defines the card height (its content, min cardMinHeight);
    // the cover is stretched to that height instead of using height('100%'), which would resolve against
    // the list viewport and blow the card up to full-screen.
    Flex({ direction: FlexDirection.Row, alignItems: ItemAlign.Stretch }) {
      // Cover: radius 0 here — the card's rounded `.clip(true)` mask rounds its left corners flush to
      // the card edge while leaving the inner (right) edge square against the text column.
      EhThumbnail({
        url: this.gallery.thumbUrl,
        thumbWidth: cardCoverWidth(),
        stretchHeight: true,
        radius: 0,
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

        // Two spacers (this one + the one below the tags) distribute the slack like eros_fe's two Spacers:
        // on a sparse-tag card the tag block floats centered while the meta stays foot-anchored.
        Blank()
        // Neutral tag chips (flat light-grey fill, no stroke) wrapping up to CARD_TAG_LIMIT. A chip only
        // colors when the tag carries the user's own per-tag color value — never by namespace.
        if (this.gallery.simpleTags.length > 0) {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(
              this.gallery.simpleTags.slice(0, CARD_TAG_LIMIT),
              (t: SimpleTag) => {
                Text(t.display())
                  .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
                  .fontColor(this.chipText(t))
                  .backgroundColor(this.chipBg(t))
                  .borderRadius(ThemeConstants.RADIUS_SM)
                  // Snug padding so short tags hug their text (eros_fe TagItem is 4/2; 6/3 is the
                  // native-snug equivalent — 8/4 ballooned short chips into wide pills with grey flanks).
                  .padding({ left: 6, right: 6, top: 3, bottom: 3 })
                  .margin({ right: ThemeConstants.SPACE_XS, bottom: ThemeConstants.SPACE_XS })
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .constraintSize({ maxWidth: 160 })
              },
              // Key carries tagSig.version: the keyGen runs during build, so reading it subscribes the
              // card; when My Tags load and bump it, the keys change → chips rebuild → re-color.
              (t: SimpleTag) => `${this.tagSig.version}:${t.namespace}:${t.text}`,
            )
          }.width('100%')
        }
        // Spacer pins the meta block to the bottom so the card reads as cover-height (eros_fe meta sits
        // at the card foot); for tag-rich cards the tags fill the space and the gap collapses.
        Blank()
        // Meta row 1 — rating stars (left, fills) · favcat heart · translated-language + page count.
        // eros_fe puts the favcat heart here (between rating and filecount), shows stars only (no number).
        Row({ space: ThemeConstants.SPACE_XS }) {
          // eros_fe StaticRatingBar (gallery_item.dart:478-482): stars tinted by colorRatingMap[colorRating]
          // (community orange / personal-rating variant), NOT system yellow. RatingStars is an intrinsic
          // 5-star cluster (width = 5·starSize), so the bar stays tight like eros_fe — no layoutWeight spread.
          RatingStars({
            rating: this.gallery.ratingFallBack,
            color: EhConstants.ratingStarColor(this.gallery.colorRating),
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
              .borderRadius(ThemeConstants.RADIUS_SM)
              .padding({ left: ThemeConstants.SPACE_SM, right: ThemeConstants.SPACE_SM, top: 3, bottom: 3 })
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
      // Anchor the card (and thus the full-height cover) to at least a portrait cover's height so sparse
      // cards don't collapse; grows past it when 2-line title + wrapped tags need more room.
      .constraintSize({ minHeight: cardMinHeight() })
    }
    .width('100%')
    .borderRadius(ThemeConstants.RADIUS_MD)
    .clip(true)
    .backgroundColor($r('app.color.card_background'))
  }
}
