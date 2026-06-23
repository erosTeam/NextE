import {
  HomeSourceState,
  connectHomeSource,
  AuthState,
  connectAuth,
  connectHomeSourceVisualIndex,
  TabVisualIndexState,
  SubTabBar,
  TabItem,
  SubtabSelectionSettings,
} from 'shared'
import { common } from '@kit.AbilityKit'

/**
 * Gallery-tab source switcher, PINNED in the HDS title bar via a `bottomBuilder` (V2Next FeedPills
 * pattern) — never a scrolling list item. 默认 (front page) + 热门 (popular) always show; 订阅 (watched)
 * only when logged in (its tab list must match HomePage.visibleSources()).
 *
 * The indicator is the shared SubTabBar's sliding underline, driven by the per-frame visual index that
 * HomePage's retained Swiper publishes — so the bar tracks the finger/page swipe instead of jumping on
 * settle. A tap publishes the source key (the bus); HomePage swipes the Swiper, which drives the indicator.
 */
@ComponentV2
export struct HomeSourceBar {
  @Local home: HomeSourceState = connectHomeSource();
  @Local auth: AuthState = connectAuth();
  @Local visual: TabVisualIndexState = connectHomeSourceVisualIndex();

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  // Must mirror HomePage.visibleSources() order so the visual index lines up with the right tab.
  private tabs(): TabItem[] {
    const items: TabItem[] = [
      new TabItem('', $r('app.string.home_source_default')),
      new TabItem('popular', $r('app.string.home_source_popular')),
    ]
    if (this.auth.isLogin) {
      items.push(new TabItem('watched', $r('app.string.home_source_watched')))
    }
    return items
  }

  private selectedIndex(): number {
    const items: TabItem[] = this.tabs()
    const index: number = items.findIndex((item: TabItem) => item.key === this.home.source)
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
          SubtabSelectionSettings.setHomeSource(this.ctx(), items[index].key, this.auth.isLogin)
        }
      },
    })
  }
}
@Builder
export function HomeSourceBarCCBuilder(_arg: Object) {
  HomeSourceBar()
}
