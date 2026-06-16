import { ThemeConstants, EhGallery, EhConstants, GroupedListSection, RatingStars } from 'shared'

/**
 * Structured detail info bar. Mirrors eros_fe `GalleryInfoBarSliver`'s information set, but rendered for
 * NextE's bordered GroupedListSection card (NOT a pixel copy of the Flutter sliver):
 *   Row 1  rating number + stars (left) · category badge (right)  — rating-count is NOT inline here
 *   Below  a 2-column grid of icon-labeled cells, filled row by row:
 *            language(translate) · filecount(picture)
 *            filesize(doc)        · favourited-count(heart)
 *            rating-count(star)   · posted-time(clock)
 * No left accent bar: eros_fe's bar groups this metadata inside a borderless sliver flow, but the NextE
 * card already supplies that boundary, so the bar would only add duplicate grouping noise. Icons are a
 * single quiet OUTLINE family at the weakest tertiary weight/size so the block stays readable and calm
 * (filled heart/star would read louder than the line icons). Read-only; each cell hides when empty.
 */
@ComponentV2
export struct GalleryInfoBar {
  @Require @Param gallery: EhGallery;

  // One grid cell: a quiet tertiary outline glyph + the primary value, taking half the grid width.
  @Builder
  metaItem(icon: Resource, value: string) {
    Row({ space: ThemeConstants.SPACE_XS }) {
      SymbolGlyph(icon)
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontColor([$r('sys.color.font_tertiary')])
      Text(value)
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('50%')
    .padding({ top: ThemeConstants.SPACE_XS, bottom: ThemeConstants.SPACE_XS })
  }

  private hasMeta(): boolean {
    return (
      this.gallery.language.length > 0 ||
      this.gallery.fileCount.length > 0 ||
      this.gallery.fileSizeText.length > 0 ||
      this.gallery.favoritedCount.length > 0 ||
      this.gallery.ratingCount.length > 0 ||
      this.gallery.postTime.length > 0
    )
  }

  build() {
    GroupedListSection({ inset: ThemeConstants.SPACE_MD }) {
      Column({ space: ThemeConstants.SPACE_SM }) {
        // Row 1 — rating number + stars (left), category badge pinned right.
        Row({ space: ThemeConstants.SPACE_XS }) {
          Text(this.gallery.rating.toFixed(2))
            .fontSize(ThemeConstants.FONT_SIZE_BODY)
            .fontColor($r('sys.color.font_primary'))
          // Tinted star row (eros_fe GalleryRating): community orange by default, or the personal-rating
          // variant (red/green/blue) when the gallery is personally rated, via ratingStarColor(colorRating)
          // — NOT the system default yellow. Fill prefers ratingFallBack (display rating before the user's
          // personal vote); the detail parser does not populate ratingFallBack yet, so fall back to the raw
          // rating when it is 0 (otherwise the stars render empty). The number above stays the raw rating.
          RatingStars({
            rating: this.gallery.ratingFallBack > 0 ? this.gallery.ratingFallBack : this.gallery.rating,
            color: EhConstants.ratingStarColor(this.gallery.colorRating),
            starSize: 15,
          })
          Blank()
          if (this.gallery.category.length > 0) {
            Text(this.gallery.category)
              .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
              .fontColor(ThemeConstants.TEXT_ON_BRAND)
              .backgroundColor(EhConstants.categoryColor(this.gallery.category))
              .borderRadius(ThemeConstants.RADIUS_SM)
              .padding({
                left: ThemeConstants.SPACE_SM,
                right: ThemeConstants.SPACE_SM,
                top: ThemeConstants.SPACE_XS,
                bottom: ThemeConstants.SPACE_XS,
              })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        // Metadata — 2-column icon grid (filled row by row), no accent bar (the card is the boundary).
        if (this.hasMeta()) {
          Flex({ wrap: FlexWrap.Wrap }) {
            if (this.gallery.language.length > 0) {
              this.metaItem($r('sys.symbol.translate'), this.gallery.language)
            }
            if (this.gallery.fileCount.length > 0) {
              this.metaItem($r('sys.symbol.picture'), this.gallery.fileCount)
            }
            if (this.gallery.fileSizeText.length > 0) {
              this.metaItem($r('sys.symbol.doc_plaintext'), this.gallery.fileSizeText)
            }
            if (this.gallery.favoritedCount.length > 0) {
              this.metaItem($r('sys.symbol.heart'), this.gallery.favoritedCount)
            }
            if (this.gallery.ratingCount.length > 0) {
              this.metaItem($r('sys.symbol.star'), this.gallery.ratingCount)
            }
            if (this.gallery.postTime.length > 0) {
              this.metaItem($r('sys.symbol.clock'), this.gallery.postTime)
            }
          }
          .width('100%')
        }
      }.width('100%')
    }
  }
}
