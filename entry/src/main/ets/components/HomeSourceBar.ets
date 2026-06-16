import {
  HomeSourceState,
  connectHomeSource,
  AuthState,
  connectAuth,
  connectHomeSourceVisualIndex,
  TabVisualIndexState,
  SubTabBar,
  SubTabItem,
} from 'shared'

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

  // Must mirror HomePage.visibleSources() order so the visual index lines up with the right tab.
  private tabs(): SubTabItem[] {
    const items: SubTabItem[] = [
      new SubTabItem('', $r('app.string.home_source_default')),
      new SubTabItem('popular', $r('app.string.home_source_popular')),
    ]
    if (this.auth.isLogin) {
      items.push(new SubTabItem('watched', $r('app.string.home_source_watched')))
    }
    return items
  }

  build() {
    SubTabBar({
      tabs: this.tabs(),
      visualIndex: this.visual.value,
      onSelect: (index: number) => {
        const items: SubTabItem[] = this.tabs()
        if (index >= 0 && index < items.length) {
          this.home.source = items[index].key
        }
      },
    })
  }
}
@Builder
export function HomeSourceBarCCBuilder(_arg: Object) {
  HomeSourceBar()
}
