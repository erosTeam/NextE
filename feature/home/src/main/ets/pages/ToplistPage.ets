import { connectHomeSource, HomeSourceState, SELECTOR_BAR_HEIGHT } from 'shared'
import { GalleryListViewModel } from '../viewmodel/GalleryListViewModel'
import { GalleryListBody } from '../components/GalleryListBody'

/**
 * Toplist (排行) tab — eros_fe's ToplistTab is a top-level bottom-tab destination, NOT a gallery
 * source (tabhome_controller.dart:28). The period selector (全部/年榜/月榜/昨日) is pinned in the
 * HDS title bar as a `bottomBuilder` (ToplistPeriodBar in entry), writing HomeSourceState.toplistTl
 * which this page reacts to. The list body is the shared GalleryListBody. Toplist always hits the
 * e-hentai host (toplist.php 404s on exhentai), so it does not react to the 表/里 site toggle.
 */
@ComponentV2
export struct ToplistPage {
  @Local vm: GalleryListViewModel = new GalleryListViewModel();
  @Local homeSource: HomeSourceState = connectHomeSource();
  // Index-owned scroller for this tab, so the title bar can bindToScrollable it (scroll-up auto-hide).
  @Param scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.vm.syncSource('toplist', this.homeSource.toplistTl)
    this.vm.loadData()
  }

  // Period switch from the pinned bar (tl 11/12/13/15) → reload from page 0.
  @Monitor('homeSource.toplistTl')
  onPeriodChange(): void {
    this.vm.setToplistPeriod(this.homeSource.toplistTl)
  }

  build() {
    GalleryListBody({ vm: this.vm, topPadding: SELECTOR_BAR_HEIGHT, scroller: this.scroller })
  }
}
