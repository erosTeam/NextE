import {
  connectHomeSource,
  HomeSourceState,
  connectToplistVisualIndex,
  TabVisualIndexState,
  RetainedSubtabHost,
  ActiveKeyState,
  SubtabSelectionSettings,
} from 'shared'
import { common } from '@kit.AbilityKit'
import { ToplistPeriodPage } from '../components/ToplistPeriodPage'

// Toplist period keys in the bar's order (ToplistPeriodBar): 全部(11) · 年榜(12) · 月榜(13) · 昨日(15).
// The host works on string keys; this surface maps key <-> the numeric tl on the selection bus.
const TOPLIST_KEYS: string[] = ['11', '12', '13', '15']

// Global @Builder (no `this`) for RetainedSubtabHost's @BuilderParam. Renders one retained period page,
// handed the shared active-key signal.
@Builder
function toplistPeriodPageBuilder(key: string, active: ActiveKeyState, scroller: Scroller) {
  ToplistPeriodPage({ periodTl: Number(key), active: active, scroller: scroller })
}

/**
 * Toplist (排行) tab: retained per-PERIOD sub-tabs on the shared RetainedSubtabHost framework (same as
 * Home). The period selector (全部/年榜/月榜/昨日, ToplistPeriodBar) writes HomeSourceState.toplistTl (the
 * selection BUS); the host swipes to the retained ToplistPeriodPage for that period (each owns its own VM
 * + scroller). NextE presents the period as a subtab, so it gets subtab retention — NOT a shared-list
 * reload. Toplist always hits the e-hentai host, so it does not react to the 表/里 toggle.
 */
@ComponentV2
export struct ToplistPage {
  @Local homeSource: HomeSourceState = connectHomeSource();
  @Local visual: TabVisualIndexState = connectToplistVisualIndex();
  @Event onScrollerReady?: (scroller: Scroller) => void;

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  build() {
    RetainedSubtabHost({
      keys: TOPLIST_KEYS,
      selectedKey: `${this.homeSource.toplistTl}`,
      pageBuilder: toplistPeriodPageBuilder,
      onSelectKey: (key: string) => {
        SubtabSelectionSettings.setToplistTl(this.ctx(), Number(key))
      },
      onVisualIndex: (value: number) => {
        this.visual.value = value
      },
      onScrollerReady: (scroller: Scroller) => {
        if (this.onScrollerReady) {
          this.onScrollerReady(scroller)
        }
      },
    })
  }
}
