import { ThemeConstants, EhGalleryImage, EhSpriteThumbnail, GroupedListSection } from 'shared'

// Horizontal-mode row thumb height (eros_fe ThumbHorizontalList ~200 incl. labels): each thumb keeps
// its true aspect at this height so its width varies with no white-border padding.
const PREVIEW_H: number = 150
// Grid/hidden-mode tile thumb width (matches the separate all-thumbnails page tile, displayWidth 82).
const GRID_THUMB_W: number = 82

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

  // Inline wrap-grid peek of the first preview page (fixed-width tiles, true aspect — no letterboxing).
  // Sized to content so the outer detail List scrolls it; mirrors the all-thumbnails tile treatment.
  @Builder
  gridPeek() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
      ForEach(
        this.images,
        (img: EhGalleryImage) => {
          Column({ space: 2 }) {
            EhSpriteThumbnail({
              url: img.thumbUrl,
              thumbWidth: img.thumbWidth,
              thumbHeight: img.thumbHeight,
              offsetX: img.thumbOffsetX,
              spriteWidth: img.spriteWidth,
              spriteHeight: img.spriteHeight,
              displayWidth: GRID_THUMB_W,
            })
            Text(`${img.page}`)
              .fontSize(ThemeConstants.FONT_SIZE_TINY)
              .fontColor($r('sys.color.font_tertiary'))
          }
          .width(GRID_THUMB_W)
          .margin({ bottom: ThemeConstants.SPACE_SM })
          .onClick(() => {
            this.onOpen(img.page - 1)
          })
        },
        (img: EhGalleryImage) => `${img.page}`,
      )
    }.width('100%')
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
