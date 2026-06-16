import {
  ThemeConstants,
  Favcat,
  FavSelectionState,
  connectFavSelection,
  FavSelectionBridge,
  SELECTOR_BAR_HEIGHT,
} from 'shared'

/**
 * Favorites favcat switcher, PINNED in the HDS title bar via a `bottomBuilder` (V2Next FeedPills
 * pattern) — never a scrolling list item, matching the gallery source bar and eros_fe's pinned favcat
 * LinkScrollBar (favorite_tabbar_page.dart:280). This bar is CHIPS-ONLY: search + order are HDS
 * title-bar actions (eros_fe favorites nav bar: search icon + sort_down — favorite_tabbar_page.dart:190-273),
 * NOT hand-rolled here. A chip tap goes through the single-writer FavSelectionBridge (the page's
 * FavoritesViewModel is page-@Local and unreachable from here). '全部' (all) is a synthetic favId 'a'
 * chip; slots 0-9 come from `favList`. Chip style is the text-tab + brand underline shared with
 * HomeSourceBar (eros_fe's favcat bar is likewise a LinkScrollBar of underlined text tabs, not capsules).
 */
@ComponentV2
export struct FavcatBar {
  @Local fav: FavSelectionState = connectFavSelection();

  build() {
    Row() {
      Scroll() {
        Row({ space: ThemeConstants.SPACE_XS }) {
          this.Chip('a', $r('app.string.favorites_all'), -1)
          ForEach(
            this.fav.favList,
            (fc: Favcat) => {
              this.Chip(fc.favId, fc.favTitle, fc.totNum)
            },
            // Key MUST include name + count: the seeded slots and the parsed favcats share favIds 0-9, so
            // keying on favId alone made ForEach reuse the seed chips (label/count are @Builder params,
            // frozen at create time) and the bar stayed "Favorites N / 0" after the real data arrived.
            (fc: Favcat) => `${fc.favId}:${fc.favTitle}:${fc.totNum}`,
          )
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .layoutWeight(1)
    }
    .width('100%')
    .height(SELECTOR_BAR_HEIGHT)
    .padding({ left: ThemeConstants.SPACE_SM, right: ThemeConstants.SPACE_SM })
    .alignItems(VerticalAlign.Center)
  }

  // Text-tab + brand underline (V2Next FeedPills / HomeSourceBar) — selected = brand + Medium, else
  // secondary + Regular. The per-slot count stays as a small trailing number (eros_fe shows it only on
  // the hamburger selector page; NextE keeps it inline so the bar still surfaces totals). The 'a' all
  // chip passes count -1 to hide the number.
  @Builder
  Chip(id: string, label: ResourceStr, count: number) {
    Column({ space: 1 }) {
      Row({ space: 3 }) {
        Text(label)
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontColor(
            this.fav.selectedFavcat === id
              ? ThemeConstants.BRAND_PRIMARY
              : $r('sys.color.font_secondary'),
          )
          .fontWeight(this.fav.selectedFavcat === id ? FontWeight.Medium : FontWeight.Regular)
          .maxLines(1)
        if (count >= 0) {
          Text(`${count}`)
            .fontSize(ThemeConstants.FONT_SIZE_TINY)
            .fontColor(
              this.fav.selectedFavcat === id
                ? ThemeConstants.BRAND_PRIMARY
                : $r('sys.color.font_tertiary'),
            )
        }
      }
      .padding({
        left: ThemeConstants.SPACE_MD,
        right: ThemeConstants.SPACE_MD,
        top: ThemeConstants.SPACE_XS,
      })
      Row()
        .height(3)
        .width(18)
        .borderRadius(1.5)
        .backgroundColor(
          this.fav.selectedFavcat === id ? ThemeConstants.BRAND_PRIMARY : Color.Transparent,
        )
    }
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      FavSelectionBridge.publishSelect(id)
    })
  }
}
@Builder
export function FavcatBarCCBuilder(_arg: Object) {
  FavcatBar()
}
