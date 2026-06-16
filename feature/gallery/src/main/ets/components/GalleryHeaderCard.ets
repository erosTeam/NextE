import { ThemeConstants, EhGallery, EhThumbnail, GroupedListSection, EhConstants } from 'shared'

const COVER_W: number = 124
const COVER_H: number = 175

/**
 * Detail-page header card: cover on the left; the right column holds title (+ JP title) + uploader at
 * the top and the READ button at the bottom, bracketing the cover (eros_fe places read+fav beside the
 * cover, not as a separate full-width slab). Rating/category/meta live in the GalleryInfoBar below.
 */
@ComponentV2
export struct GalleryHeaderCard {
  @Require @Param gallery: EhGallery;
  // Saved reading position (0 = none). >0 turns the READ button into a resume affordance (eros_fe).
  @Param resumeIndex: number = 0;
  @Event onRead: () => void = () => {};
  @Event onUploader: (name: string) => void = (_name: string) => {};

  // Resume at the saved page when there is progress; otherwise plain Read.
  // Total page count belongs to the InfoBar; putting it in the CTA makes the button oversized and
  // duplicates metadata (`阅读 (609P)`), so the first-read CTA stays semantic and compact.
  private readLabel(): ResourceStr {
    if (this.resumeIndex > 0) {
      return $r('app.string.detail_read_resume', (this.resumeIndex + 1).toString())
    }
    return $r('app.string.detail_read')
  }

  build() {
    GroupedListSection({ inset: ThemeConstants.SPACE_MD }) {
      Row({ space: ThemeConstants.SPACE_MD }) {
        EhThumbnail({
          url: this.gallery.thumbUrl,
          thumbWidth: COVER_W,
          thumbHeight: COVER_H,
          radius: ThemeConstants.RADIUS_SM,
        })
        Column({ space: ThemeConstants.SPACE_XS }) {
          // English (primary) title.
          Text(this.gallery.title())
            .fontSize(ThemeConstants.FONT_SIZE_TITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .lineHeight(ThemeConstants.LINE_HEIGHT_TITLE)
            // eros_fe GalleryTitle allows up to 6 lines (no ellipsis); the cover-height-bound column
            // can't take 6, but 3 over-truncated long titles — 4 is the practical fit before the action row.
            .maxLines(4)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          // Japanese title, shown separately when present and distinct from the primary.
          if (
            this.gallery.japaneseTitle.length > 0 &&
            this.gallery.japaneseTitle !== this.gallery.title()
          ) {
            Text(this.gallery.japaneseTitle)
              .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
              .fontColor($r('sys.color.font_secondary'))
              .lineHeight(ThemeConstants.LINE_HEIGHT_BODY)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          if (this.gallery.uploader.length > 0) {
            // Tappable → search this uploader's galleries (eros_fe GalleryUploader). eros_fe styles the
            // uploader as muted secondaryLabel GREY (w500), NOT a colored link — it's metadata that
            // happens to be tappable, distinct from the blue Similar/Parent action links.
            Text(this.gallery.uploader)
              .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .onClick(() => {
                this.onUploader(this.gallery.uploader)
              })
          }
          // Spacer pushes the action row to the bottom edge, aligned with the cover (eros_fe layout).
          Blank()
          // Bottom action row — eros_fe header_sliver clusters BOTH to the right: [Spacer][Fav][Read],
          // with READ the rightmost element and the favourite to its left, center-aligned. The favourite
          // and read read as a coordinated family: a vertically-centred favcat heart (16) + label (12,
          // same as the read text) sits left of the read capsule — not a tiny tail, and not stealing the
          // CTA. READ button label/size are untouched (forbidden); only its position in the row moves.
          Row({ space: ThemeConstants.SPACE_MD }) {
            Blank()
            // Read-only favourite-state — eros_fe GalleryFavButton: TEXT then favcat-coloured heart
            // (`name ♥`). Gated on the favcat SLOT (the canonical favourited signal that also supplies
            // the colour), so the heart colour is ALWAYS a real EH favcat-slot colour — never a brand /
            // accent token, and nothing is shown when not favourited. Add/move toggle is deferred.
            if (this.gallery.favcat.length > 0) {
              Row({ space: ThemeConstants.SPACE_XS }) {
                if (this.gallery.favTitle.length > 0) {
                  Text(this.gallery.favTitle)
                    .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
                    .fontColor($r('sys.color.font_secondary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                SymbolGlyph($r('sys.symbol.heart_fill'))
                  .fontSize(ThemeConstants.FONT_SIZE_TITLE)
                  .fontColor([EhConstants.favCatColor(this.gallery.favcat)])
              }
              .flexShrink(1)
              .constraintSize({ maxWidth: '55%' })
            }
            // Content-width capsule, RIGHTMOST (eros_fe compact 阅读 capsule, read as the last element).
            Button(this.readLabel())
              .type(ButtonType.Capsule)
              .height(36)
              .padding({ left: ThemeConstants.SPACE_XL, right: ThemeConstants.SPACE_XL })
              .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
              .flexShrink(0)
              .onClick(() => {
                this.onRead()
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .layoutWeight(1)
        .height(COVER_H)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
  }
}
