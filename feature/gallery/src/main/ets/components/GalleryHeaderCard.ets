import {
  ThemeConstants,
  EhGallery,
  EhThumbnail,
  GroupedListSection,
  GalleryTitleState,
  connectGalleryTitle,
  appSheetOptions,
} from 'shared'

const COVER_W: number = 124
const COVER_H: number = 175

/**
 * Detail-page header card: cover on the left; the right column holds title (+ JP title) + uploader at
 * the top. Rating/category/meta live in the GalleryInfoBar below, while the primary read/resume action
 * is owned by GalleryDetailPage as a page-level FAB so it stays reachable outside this dense header.
 */
@ComponentV2
export struct GalleryHeaderCard {
  @Require @Param gallery: EhGallery;
  @Event onUploader: (name: string) => void = (_name: string) => {};
  @Event onTitleTap: () => void = () => {};
  @Param titleSheetShown: boolean = false;
  @BuilderParam titleSheetContent: () => void;
  @Event onTitleSheetDisappear: () => void = () => {};
  @Local titlePref: GalleryTitleState = connectGalleryTitle();

  private primaryTitle(): string {
    return this.gallery.displayTitle(this.titlePref.japaneseTitleInGalleryPage)
  }

  private secondaryTitle(): string {
    return this.gallery.secondaryTitle(this.titlePref.japaneseTitleInGalleryPage)
  }

  // Title line budget against the FIXED card height (COVER_H) so the JP title and uploader stay
  // inside the card — the title truncates first.
  // The layoutWeight+clip text group in build() is the structural backstop if real font metrics differ.
  private titleMaxLines(): number {
    const hasSecondary: boolean = this.secondaryTitle().length > 0
    const hasUploader: boolean = this.gallery.uploader.length > 0
    // Fixed cover height minus the JP (2 lines) + uploader (1 line) reserves; the remainder is title
    // lines at LINE_HEIGHT_TITLE.
    const textArea: number = COVER_H
    const secondaryReserve: number = hasSecondary
      ? 2 * ThemeConstants.LINE_HEIGHT_BODY + ThemeConstants.SPACE_XS
      : 0
    const uploaderReserve: number = hasUploader
      ? ThemeConstants.LINE_HEIGHT_BODY + ThemeConstants.SPACE_XS
      : 0
    const lines: number = Math.floor(
      (textArea - secondaryReserve - uploaderReserve) / ThemeConstants.LINE_HEIGHT_TITLE,
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
          radius: ThemeConstants.DETAIL_COVER_RADIUS,
          sourceWidth: this.gallery.imgWidth,
          sourceHeight: this.gallery.imgHeight,
          // Detail cover slot is fixed for the header layout, but the visible image itself keeps the real
          // EH cover proportion and owns the rounded clip. The slot must not become a grey letterbox box.
          containFit: true,
        })
        Column({ space: ThemeConstants.SPACE_XS }) {
          // Flexible text group: fills the cover-height column and clips, so a long title cannot
          // overflow the card. The title line count is budgeted by titleMaxLines() so the JP title +
          // uploader stay visible.
          Column({ space: ThemeConstants.SPACE_XS }) {
            Column({ space: ThemeConstants.SPACE_XS }) {
              Text(this.primaryTitle())
                .fontSize(ThemeConstants.FONT_SIZE_TITLE)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('sys.color.font_primary'))
                .lineHeight(ThemeConstants.LINE_HEIGHT_TITLE)
                // Budgeted line count (titleMaxLines): fills the space when alone, fewer when the JP title
                // / uploader are also shown — the title truncates before metadata overflows.
                .maxLines(this.titleMaxLines())
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
              if (this.secondaryTitle().length > 0) {
                Text(this.secondaryTitle())
                  .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
                  .fontColor($r('sys.color.font_secondary'))
                  .lineHeight(ThemeConstants.LINE_HEIGHT_BODY)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .onClick(() => {
              this.onTitleTap()
            })
            .bindSheet(this.titleSheetShown, this.titleSheetContent(), appSheetOptions({
              detents: [SheetSize.LARGE],
              showClose: false,
              keyboardAvoidMode: SheetKeyboardAvoidMode.TRANSLATE_AND_RESIZE,
              onDisappear: () => {
                this.onTitleSheetDisappear()
              },
            }))
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
