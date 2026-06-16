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

  // Title line budget against the FIXED card height (COVER_H) so the JP title, uploader, favourite
  // state, and the Read/resume action row always stay inside the card — the title truncates first.
  // The layoutWeight+clip text group in build() is the structural backstop if real font metrics differ.
  private titleMaxLines(): number {
    const hasJp: boolean =
      this.gallery.japaneseTitle.length > 0 && this.gallery.japaneseTitle !== this.gallery.title()
    const hasUploader: boolean = this.gallery.uploader.length > 0
    // Space above the reserved action row (minus the outer gap), then minus the JP (2 lines) +
    // uploader (1 line) reserves; the remainder is title lines at LINE_HEIGHT_TITLE.
    const textArea: number = COVER_H - ThemeConstants.ACTION_HEIGHT - ThemeConstants.SPACE_XS
    const jpReserve: number = hasJp
      ? 2 * ThemeConstants.LINE_HEIGHT_BODY + ThemeConstants.SPACE_XS
      : 0
    const uploaderReserve: number = hasUploader
      ? ThemeConstants.LINE_HEIGHT_BODY + ThemeConstants.SPACE_XS
      : 0
    const lines: number = Math.floor(
      (textArea - jpReserve - uploaderReserve) / ThemeConstants.LINE_HEIGHT_TITLE,
    )
    // At least 1 line; cap at eros_fe's 6-line maximum.
    return Math.min(Math.max(lines, 1), 6)
  }

  build() {
    GroupedListSection({ inset: ThemeConstants.SPACE_MD }) {
      Row({ space: ThemeConstants.SPACE_MD }) {
        EhThumbnail({
          url: this.gallery.thumbUrl,
          thumbWidth: COVER_W,
          thumbHeight: COVER_H,
          radius: ThemeConstants.RADIUS_SM,
          // The detail cover box is a FIXED COVER_W×COVER_H; a cover whose aspect differs would be
          // side/top cropped by Cover, so Contain fits the whole cover over the grey backdrop (eros_fe).
          containFit: true,
        })
        Column({ space: ThemeConstants.SPACE_XS }) {
          // Flexible text group: takes all space ABOVE the reserved action row and CLIPS, so a long
          // title can never push the Read/favourite action row out of (or overlapping) the card. The
          // title line count is budgeted by titleMaxLines() so the JP title + uploader stay visible.
          Column({ space: ThemeConstants.SPACE_XS }) {
            // English (primary) title.
            Text(this.gallery.title())
              .fontSize(ThemeConstants.FONT_SIZE_TITLE)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary'))
              .lineHeight(ThemeConstants.LINE_HEIGHT_TITLE)
              // Budgeted line count (titleMaxLines): fills the space when alone, fewer when the JP title
              // / uploader are also shown — the title truncates, the metadata + action row never overflow.
              .maxLines(this.titleMaxLines())
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
                .lineHeight(ThemeConstants.LINE_HEIGHT_BODY)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
                .onClick(() => {
                  this.onUploader(this.gallery.uploader)
                })
            }
          }
          .layoutWeight(1)
          .width('100%')
          .clip(true)
          .alignItems(HorizontalAlign.Start)

          // Bottom action row — a RESERVED fixed-height sibling (no Blank spacer), so a long title can
          // never push it out. eros_fe header_sliver clusters BOTH to the right: [Spacer][Fav][Read],
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
              // Favourite block: the SAME ACTION_HEIGHT + vertical center as the Read pill so the two
              // share a height baseline and read as one coordinated row — eros_fe's bare-heart secondary
              // sitting beside the filled-pill primary, not a tiny floating tail.
              Row({ space: ThemeConstants.SPACE_XS }) {
                if (this.gallery.favTitle.length > 0) {
                  Text(this.gallery.favTitle)
                    .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
                    .fontColor($r('sys.color.font_secondary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                SymbolGlyph($r('sys.symbol.heart_fill'))
                  .fontSize(ThemeConstants.ACTION_FAV_ICON)
                  .fontColor([EhConstants.favCatColor(this.gallery.favcat)])
              }
              .height(ThemeConstants.ACTION_HEIGHT)
              .alignItems(VerticalAlign.Center)
              .flexShrink(1)
              .constraintSize({ maxWidth: '55%' })
            }
            // Content-width capsule, RIGHTMOST (eros_fe compact 阅读 capsule, read as the last element).
            // Shares ACTION_HEIGHT with the favourite block; BODY label gives the filled pill a CTA weight.
            Button(this.readLabel())
              .type(ButtonType.Capsule)
              .height(ThemeConstants.ACTION_HEIGHT)
              .padding({ left: ThemeConstants.SPACE_XL, right: ThemeConstants.SPACE_XL })
              .fontSize(ThemeConstants.FONT_SIZE_BODY)
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
