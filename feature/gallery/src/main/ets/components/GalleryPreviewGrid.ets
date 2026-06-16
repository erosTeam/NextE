import {
  ThemeConstants,
  EhGalleryImage,
  EhSpriteThumbnail,
  PreviewThumbTile,
  GroupedListSection,
  ResponsiveGrid,
} from 'shared'

// Horizontal-mode row thumb height (eros_fe ThumbHorizontalList ~200 incl. labels): each thumb keeps
// its true aspect at this height so its width varies with no white-border padding.
const PREVIEW_H: number = 150

/**
 * Detail-page preview section — eros_fe ThumbTile + GalleryBody dispatch, restored to its three modes
 * driven by the two thumbnail settings the parent passes in (both default false → GRID):
 *   - hidden=true     → NO inline previews; a single centered "more previews" entry into all-thumbnails
 *                       (eros_fe hidden-inline MorePreviewButton).
 *   - horizontal=true → a tappable "缩略图 (n) 查看全部 >" header that ALWAYS opens all-thumbnails, over a
 *                       horizontal scrolling row of fixed-height thumbs (eros_fe ThumbHorizontalList).
 *   - else (GRID)     → plain title header + an inline wrap-grid peek of the first preview page + a
 *                       centered "更多预览/没有更多预览" entry below (eros_fe ThumbSliverGrid + MorePreviewButton).
 * The separate all-thumbnails page is reachable via onMore in EVERY mode; onOpen(page0) opens the reader.
 */
@ComponentV2
export struct GalleryPreviewGrid {
  @Require @Param images: EhGalleryImage[];
  @Param total: number = 0;
  @Param hasMore: boolean = false;
  @Param horizontal: boolean = false;
  @Param hidden: boolean = false;
  @Event onOpen: (pageZeroBased: number) => void = (_p: number) => {};
  @Event onMore: () => void = () => {};
  // Measured grid width (vp); the GRID column count + tile width are derived from it (responsive).
  @Local gridWidth: number = 0;

  // Responsive column count for the inline GRID peek: derived from the measured pane width and a min
  // comfortable thumb width (a phone lands ~3 columns, wider screens scale up) — never hardcoded.
  private gridColumns(): number {
    return ResponsiveGrid.columns(
      this.gridWidth,
      ThemeConstants.PREVIEW_THUMB_MIN_W,
      ThemeConstants.SPACE_SM,
    )
  }

  // One tile's width: the column width once gridColumns() share the pane minus gaps. Falls back to the
  // min width before the first layout pass measures the pane.
  private gridTileWidth(): number {
    if (this.gridWidth <= 0) {
      return ThemeConstants.PREVIEW_THUMB_MIN_W
    }
    return ResponsiveGrid.columnWidth(this.gridWidth, this.gridColumns(), ThemeConstants.SPACE_SM)
  }

  // Centered tappable entry into the all-thumbnails page (eros_fe MorePreviewButton). The label reflects
  // whether more pages remain, but the row always navigates.
  @Builder
  moreButton() {
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
      this.onMore()
    })
  }

  // Section header. `entry` = this header IS the all-thumbnails entry (horizontal mode): show the
  // "查看全部 >" affordance and make the whole row tappable. Grid mode passes entry=false (the entry is
  // the button below), so it stays a plain title.
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
        this.onMore()
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
                spriteWidth: img.spriteWidth,
                spriteHeight: img.spriteHeight,
                fitHeight: true,
                displayHeight: PREVIEW_H,
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

  // Inline wrap-grid peek of the first preview page. Responsive column count (gridColumns) + a shared
  // PreviewThumbTile per item: each tile is a FIXED-size frame with the thumb contained+centered and the
  // page number at a constant position, so a flat/wide or misdetected thumb never drags the baseline.
  @Builder
  gridPeek() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
      ForEach(
        this.images,
        (img: EhGalleryImage) => {
          PreviewThumbTile({
            image: img,
            tileWidth: this.gridTileWidth(),
            onTap: () => {
              this.onOpen(img.page - 1)
            },
          }).margin({ bottom: ThemeConstants.SPACE_SM })
        },
        (img: EhGalleryImage) => `${img.page}`,
      )
    }
    .width('100%')
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.gridWidth = newValue.width as number
    })
  }

  build() {
    GroupedListSection({ inset: ThemeConstants.SPACE_MD }) {
      Column({ space: ThemeConstants.SPACE_SM }) {
        if (this.hidden) {
          // Hidden-inline: only the entry button, no previews (eros_fe hideGalleryThumbnails).
          this.sectionHeader(false)
          this.moreButton()
        } else if (this.horizontal) {
          this.sectionHeader(true)
          this.horizontalRow()
        } else {
          this.sectionHeader(false)
          this.gridPeek()
          this.moreButton()
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }
}
