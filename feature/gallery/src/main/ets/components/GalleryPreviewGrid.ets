import {
  ThemeConstants,
  EhGalleryImage,
  EhSpriteThumbnail,
  PreviewThumbTile,
  GroupedListSection,
} from 'shared'

// Horizontal-mode row thumb height (eros_fe ThumbHorizontalList ~200 incl. labels): each thumb keeps
// its true aspect at this height so its width varies with no white-border padding.
const PREVIEW_H: number = 150

/**
 * Detail-page preview section — eros_fe ThumbTile + GalleryBody dispatch, restored to its three modes
 * driven by the two thumbnail settings the parent passes in (both default false → GRID):
 *   - hidden=true     → NO inline previews; the tappable "查看全部 >" header AND a centered "more previews"
 *                       button both open all-thumbnails (eros_fe hidden-inline MorePreviewButton).
 *   - horizontal=true → a tappable "预览 (n) 查看全部 >" header that opens all-thumbnails, over a horizontal
 *                       scrolling row of fixed-height thumbs (eros_fe ThumbHorizontalList).
 *   - else (GRID)     → the SAME tappable "查看全部 >" header + an inline wrap-grid peek of the first preview
 *                       page + a centered "更多预览/没有更多预览" button below (eros_fe ThumbSliverGrid + MorePreviewButton).
 * The all-thumbnails page is reachable via the header in EVERY mode (and the button in grid/hidden);
 * onOpen(page0) opens the reader.
 */
@ComponentV2
export struct GalleryPreviewGrid {
  @Require @Param images: EhGalleryImage[];
  @Param total: number = 0;
  @Param hasMore: boolean = false;
  @Param horizontal: boolean = false;
  @Param hidden: boolean = false;
  @Event onOpen: (pageZeroBased: number) => void = (_p: number) => {};
  @Event onMore: (initialImagePage: number) => void = (_initialImagePage: number) => {};

  private lastImagePage(): number {
    if (this.images.length === 0) {
      return 0
    }
    return this.images[this.images.length - 1].page
  }

  // Centered tappable entry into the all-thumbnails page (eros_fe MorePreviewButton). The label reflects
  // whether more pages remain, but the row always navigates.
  @Builder
  moreButton(initialImagePage: number) {
    Row({ space: ThemeConstants.SPACE_XS }) {
      Text(
        this.hasMore
          ? $r('app.string.detail_more_previews')
          : $r('app.string.detail_no_more_previews'),
      )
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor($r('sys.color.font_emphasize'))
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontColor([$r('sys.color.font_tertiary')])
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: ThemeConstants.SPACE_MD, bottom: ThemeConstants.SPACE_SM })
    .onClick(() => {
      this.onMore(initialImagePage)
    })
  }

  // Section header. `entry` = this header IS an all-thumbnails entry: show the visible "查看全部 >"
  // affordance and make the whole row tappable (→ onMore). All three modes pass entry=true so the header
  // is always a real, affordanced entry (no invisible tap target); GRID/HIDDEN also keep the button below.
  @Builder
  sectionHeader(entry: boolean) {
    Row({ space: ThemeConstants.SPACE_XS }) {
      Text($r('app.string.gallery_preview'))
        .fontSize(ThemeConstants.FONT_SIZE_TITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
      Text(`(${this.total > 0 ? this.total : this.images.length})`)
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontColor($r('sys.color.font_tertiary'))
      Blank()
      if (entry) {
        Text($r('app.string.detail_view_all'))
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor($r('sys.color.font_emphasize'))
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor([$r('sys.color.font_tertiary')])
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      if (entry) {
        this.onMore(0)
      }
    })
  }

  // Horizontal scrolling row of fixed-height thumbs (each keeps true aspect).
  @Builder
  horizontalRow() {
    List({ space: ThemeConstants.SPACE_SM }) {
      ForEach(
        this.images,
        (img: EhGalleryImage) => {
          ListItem() {
            Column({ space: 2 }) {
              EhSpriteThumbnail({
                url: img.thumbUrl,
                thumbWidth: img.thumbWidth,
                thumbHeight: img.thumbHeight,
                offsetX: img.thumbOffsetX,
                imageKey: img.imgkey,
                spriteWidth: img.spriteWidth,
                spriteHeight: img.spriteHeight,
                fitHeight: true,
                displayHeight: PREVIEW_H,
                enableImageBlock: true,
              })
              Text(`${img.page}`)
                .fontSize(ThemeConstants.FONT_SIZE_TINY)
                .fontColor($r('sys.color.font_tertiary'))
            }
            .alignItems(HorizontalAlign.Center)
            .onClick(() => {
              this.onOpen(img.page - 1)
            })
          }
        },
        (img: EhGalleryImage) => `${img.page}`,
      )
    }
    .listDirection(Axis.Horizontal)
    .height(PREVIEW_H + 22)
    .width('100%')
    .scrollBar(BarState.Off)
  }

  // Inline grid peek of the first preview page. Responsive column count via columnsTemplate (a true Grid,
  // not a wrapping Flex) so tiles align in columns with uniform gap and the last row left-aligns naturally.
  private columnsTemplate(): string {
    return `repeat(auto-fit, ${ThemeConstants.PREVIEW_THUMB_MIN_W}vp)`
  }

  @Builder
  gridPeek() {
    Grid() {
      ForEach(
        this.images,
        (img: EhGalleryImage) => {
          GridItem() {
            PreviewThumbTile({
              image: img,
              onTap: () => {
                this.onOpen(img.page - 1)
              },
            })
          }
        },
        (img: EhGalleryImage) => `${img.page}`,
      )
    }
    .columnsTemplate(this.columnsTemplate())
    .columnsGap(ThemeConstants.SPACE_SM)
    .rowsGap(ThemeConstants.SPACE_SM)
    .width('100%')
  }

  build() {
    GroupedListSection({ inset: ThemeConstants.SPACE_MD }) {
      Column({ space: ThemeConstants.SPACE_SM }) {
        if (this.hidden) {
          // Hidden-inline: no previews — the tappable header AND the button below both open all-thumbnails
          // (eros_fe hideGalleryThumbnails still offers a MorePreviewButton).
          this.sectionHeader(true)
          this.moreButton(0)
        } else if (this.horizontal) {
          this.sectionHeader(true)
          this.horizontalRow()
        } else {
          // Default GRID: tappable header entry + inline first-page peek + the button below.
          this.sectionHeader(true)
          this.gridPeek()
          this.moreButton(this.lastImagePage())
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }
}
