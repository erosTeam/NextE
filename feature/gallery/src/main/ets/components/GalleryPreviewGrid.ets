import { ThemeConstants, EhGalleryImage, EhSpriteThumbnail, GroupedListSection } from 'shared'

// Preview row height (eros_fe ThumbHorizontalList is a fixed-height row, height ~200 incl. labels). Each
// thumb keeps its true aspect at this height, so its width varies and there is no white border padding.
const PREVIEW_H: number = 150

/**
 * Detail-page preview PEEK (eros_fe ThumbHorizontalList): the first preview page is shown inline as a
 * HORIZONTAL scrolling row of fixed-height thumbnails (width follows each thumb's true aspect — portrait
 * and landscape previews sit side by side with no blank padding, unlike a fixed-tile grid). Tap emits
 * the 0-based page index so the parent opens the reader; "查看全部" → onMore opens the separate
 * all-thumbnails page. Shares the GroupedListSection chrome.
 */
@ComponentV2
export struct GalleryPreviewGrid {
  @Require @Param images: EhGalleryImage[];
  @Param total: number = 0;
  @Param hasMore: boolean = false;
  @Event onOpen: (pageZeroBased: number) => void = (_p: number) => {};
  @Event onMore: () => void = () => {};

  build() {
    GroupedListSection({ inset: ThemeConstants.SPACE_MD }) {
      Column({ space: ThemeConstants.SPACE_SM }) {
        Row({ space: ThemeConstants.SPACE_XS }) {
          Text($r('app.string.gallery_preview'))
            .fontSize(ThemeConstants.FONT_SIZE_TITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
          Text(`(${this.total > 0 ? this.total : this.images.length})`)
            .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
          Blank()
          if (this.hasMore) {
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
          if (this.hasMore) {
            this.onMore()
          }
        })
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
                    // Fixed row height; width follows the thumb's true aspect (no fixed-tile letterboxing).
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
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }
}
