import {
  Favcat,
  FavSelectionState,
  connectFavSelection,
  connectFavcatVisualIndex,
  TabVisualIndexState,
  SubTabBar,
  TabItem,
} from 'shared'

/**
 * Favorites favcat switcher, PINNED in the HDS title bar via a `bottomBuilder`. CHIPS-ONLY (search +
 * order are HDS title-bar actions). '全部' (all) is a synthetic favId 'a'; slots 0-9 come from `favList`
 * (name + count). It uses the shared SubTabBar's V2Next sliding indicator, driven by the per-frame favcat
 * visual index that FavoritesPage's retained Swiper publishes — so the bar tracks the finger/page swipe.
 * Many favcats overflow, so the bar scrolls horizontally and auto-centres the active favcat. A chip tap
 * writes the selected favcat (the bus); FavoritesPage swipes the Swiper to that retained page.
 */
@ComponentV2
export struct FavcatBar {
  @Local fav: FavSelectionState = connectFavSelection();
  @Local visual: TabVisualIndexState = connectFavcatVisualIndex();

  // Must mirror FavoritesPage.favcatKeys() order: synthetic 'a' (all) + the favcat slots. NAMES ONLY —
  // no count suffix in this bar (product decision). The parsed counts stay in favList state (fc.totNum)
  // for other uses; they are simply not passed to TabItem here, so SubTabBar (count defaults -1) hides
  // them. The favTitle still joins the SubTabBar key, so the bar still rebuilds on the seed→real rename.
  private tabs(): TabItem[] {
    const items: TabItem[] = [new TabItem('a', $r('app.string.favorites_all'))]
    this.fav.favList.forEach((fc: Favcat) => items.push(new TabItem(fc.favId, fc.favTitle)))
    return items
  }

  build() {
    SubTabBar({
      tabs: this.tabs(),
      visualIndex: this.visual.value,
      scrollable: true,
      onSelect: (index: number) => {
        const items: TabItem[] = this.tabs()
        if (index >= 0 && index < items.length) {
          this.fav.selectedFavcat = items[index].key
        }
      },
    })
  }
}
@Builder
export function FavcatBarCCBuilder(_arg: Object) {
  FavcatBar()
}
