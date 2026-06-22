import { SELECTOR_BAR_HEIGHT, ActiveKeyState } from 'shared'
import { GalleryListViewModel } from '../viewmodel/GalleryListViewModel'
import { GalleryListBody } from './GalleryListBody'
import { common } from '@kit.AbilityKit'

/**
 * One retained toplist-PERIOD page (V2Next FeedListPage pattern; mirrors GallerySourcePage). NextE
 * presents the period control (全部/年榜/月榜/昨日 = tl 11/12/13/15) as a subtab, so each period owns its
 * OWN GalleryListViewModel + datasource + scroller, kept alive by ToplistPage's Swiper. Switching period
 * away and back preserves that period's list AND scroll — no shared-list reload. HomeSourceState.toplistTl
 * stays a pure selection bus (it holds no data).
 *
 * Lazy first-load: a period loads its first page only when it FIRST becomes the active tab. No site
 * @Monitor — toplist.php is e-hentai only and does not react to the 表/里 toggle.
 */
@ComponentV2
export struct ToplistPeriodPage {
  // Toplist period: tl 11 all-time / 12 year / 13 month / 15 yesterday. Stable (the Swiper key).
  @Param periodTl: number = 15;
  // Shared active-key signal from the host; active when active.activeKey === this period's key (`${tl}`).
  @Param active: ActiveKeyState = new ActiveKeyState();
  // Index-bound scroller for this period (title auto-hide follows the active period's list).
  @Param scroller: Scroller = new Scroller();
  @Event onDidScroll?: (offset: number, state: ScrollState) => void;
  @Local vm: GalleryListViewModel = new GalleryListViewModel();
  private loadedOnce: boolean = false;

  private isActive(): boolean {
    return this.active.activeKey === `${this.periodTl}`
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  aboutToAppear(): void {
    this.vm.syncSource('toplist', this.periodTl)
    this.vm.setContext(this.ctx())
    if (this.isActive()) {
      this.loadOnce()
    }
  }

  // Host's @Trace activeKey reaches cached pages, so first activation (tap or swipe) fires reliably.
  @Monitor('active.activeKey')
  onActiveChange(): void {
    if (this.isActive()) {
      this.loadOnce()
    }
  }

  private loadOnce(): void {
    if (this.loadedOnce) {
      return
    }
    this.loadedOnce = true
    this.vm.loadData()
  }

  build() {
    GalleryListBody({
      vm: this.vm,
      topPadding: SELECTOR_BAR_HEIGHT,
      scroller: this.scroller,
      onDidScroll: (offset: number, state: ScrollState) => {
        if (this.onDidScroll) {
          this.onDidScroll(offset, state)
        }
      },
    })
  }
}
