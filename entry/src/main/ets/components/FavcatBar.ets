import {
  Favcat,
  FavSelectionState,
  connectFavSelection,
  connectFavcatVisualIndex,
  TabVisualIndexState,
  SubTabBar,
  TabItem,
  connectAuth,
  AuthState,
  connectLocalFav,
  LocalFavState,
  SubtabSelectionSettings,
  EhConstants,
} from 'shared'
import { common } from '@kit.AbilityKit'

/**
 * Favorites favcat switcher, PINNED in the HDS title bar via a `bottomBuilder`. CHIPS-ONLY (search +
 * order are HDS title-bar actions). '全部' (all) is a synthetic favId 'a' whose count is the remote 0-9
 * aggregate; slots 0-9 come from `favList` (name + count). It uses the shared SubTabBar's V2Next
 * sliding indicator, driven by the per-frame favcat visual index that FavoritesPage's retained Swiper
 * publishes — so the bar tracks the finger/page swipe.
 * Many favcats overflow, so the bar scrolls horizontally and auto-centres the active favcat. A chip tap
 * writes the selected favcat (the bus); FavoritesPage swipes the Swiper to that retained page.
 */
@ComponentV2
export struct FavcatBar {
  @Local fav: FavSelectionState = connectFavSelection();
  @Local visual: TabVisualIndexState = connectFavcatVisualIndex();
  @Local auth: AuthState = connectAuth();
  @Local localFav: LocalFavState = connectLocalFav();

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  // Must mirror FavoritesPage.favcatKeys() order: synthetic 'a' (all) + the favcat slots. Only the
  // synthetic all chip shows a count: eros_fe sums the remote 0-9 slots for "all"; per-slot counts stay
  // in the full-screen selector so the horizontal bar remains compact.
  private tabs(): TabItem[] {
    if (!this.auth.isLogin) {
      return [new TabItem('l', $r('app.string.favorites_local'), this.localFav.count(), EhConstants.favCatColor('l'))]
    }
    const items: TabItem[] = [
      new TabItem('a', $r('app.string.favorites_all'), this.fav.remoteTotalCount(), EhConstants.favCatColor('a')),
    ]
    this.fav.favList.forEach((fc: Favcat) => {
      items.push(new TabItem(fc.favId, fc.favTitle, -1, EhConstants.favCatColor(fc.favId)))
    })
    items.push(new TabItem('l', $r('app.string.favorites_local'), this.localFav.count(), EhConstants.favCatColor('l')))
    return items
  }

  private selectedIndex(): number {
    const items: TabItem[] = this.tabs()
    const selected: string = !this.auth.isLogin
      ? 'l'
      : (this.fav.selectedFavcat.length > 0 ? this.fav.selectedFavcat : 'a')
    const index: number = items.findIndex((item: TabItem) => item.key === selected)
    return index < 0 ? 0 : index
  }

  build() {
    SubTabBar({
      tabs: this.tabs(),
      visualIndex: this.visual.value,
      selectedIndex: this.selectedIndex(),
      onSelect: (index: number) => {
        const items: TabItem[] = this.tabs()
        if (index >= 0 && index < items.length) {
          SubtabSelectionSettings.setFavoritesFavcat(this.ctx(), items[index].key, this.auth.isLogin)
        }
      },
    })
  }
}
@Builder
export function FavcatBarCCBuilder(_arg: Object) {
  FavcatBar()
}
