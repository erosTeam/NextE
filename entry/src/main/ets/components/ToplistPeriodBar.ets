import {
  HomeSourceState,
  connectHomeSource,
  connectToplistVisualIndex,
  TabVisualIndexState,
  SubTabBar,
  TabItem,
  SubtabSelectionSettings,
} from 'shared'
import { common } from '@kit.AbilityKit'

// Periods in the same order as ToplistPage's Swiper (TOPLIST_PERIODS): 全部(11) · 年榜(12) · 月榜(13) · 昨日(15).
const PERIOD_TLS: number[] = [11, 12, 13, 15]

/**
 * Toplist-tab period switcher, PINNED in the HDS title bar via a `bottomBuilder`. The period (全部/年榜/
 * 月榜/昨日 = tl 11/12/13/15) is presented as a subtab, so the indicator is the shared SubTabBar's sliding
 * underline driven by the per-frame visual index that ToplistPage's retained Swiper publishes — the bar
 * tracks the finger/page swipe. A tap publishes the period (the bus); ToplistPage swipes to that page.
 */
@ComponentV2
export struct ToplistPeriodBar {
  @Local home: HomeSourceState = connectHomeSource();
  @Local visual: TabVisualIndexState = connectToplistVisualIndex();

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private tabs(): TabItem[] {
    return [
      new TabItem('11', $r('app.string.toplist_all')),
      new TabItem('12', $r('app.string.toplist_year')),
      new TabItem('13', $r('app.string.toplist_month')),
      new TabItem('15', $r('app.string.toplist_yesterday')),
    ]
  }

  private selectedIndex(): number {
    const selected: string = `${this.home.toplistTl}`
    const items: TabItem[] = this.tabs()
    const index: number = items.findIndex((item: TabItem) => item.key === selected)
    return index < 0 ? 0 : index
  }

  build() {
    SubTabBar({
      tabs: this.tabs(),
      visualIndex: this.visual.value,
      selectedIndex: this.selectedIndex(),
      onSelect: (index: number) => {
        if (index >= 0 && index < PERIOD_TLS.length) {
          SubtabSelectionSettings.setToplistTl(this.ctx(), PERIOD_TLS[index])
        }
      },
    })
  }
}
@Builder
export function ToplistPeriodBarCCBuilder(_arg: Object) {
  ToplistPeriodBar()
}
