import {
  connectSiteMode,
  SiteModeState,
  connectAuth,
  AuthState,
  connectHomeSource,
  HomeSourceState,
  SELECTOR_BAR_HEIGHT,
} from 'shared'
import { GalleryListViewModel } from '../viewmodel/GalleryListViewModel'
import { GalleryListBody } from '../components/GalleryListBody'

/**
 * Gallery tab: the table-site gallery list (V2Next FeedListPage pattern). The source switcher
 * (默认/热门/订阅) is pinned in the HDS title bar as a `bottomBuilder` (HomeSourceBar in entry),
 * writing the shared HomeSourceState this page reacts to. Toplist is its own bottom tab now. The
 * list body (loading/grid/list/paging) is the shared GalleryListBody.
 */
@ComponentV2
export struct HomePage {
  @Local vm: GalleryListViewModel = new GalleryListViewModel();
  @Local siteMode: SiteModeState = connectSiteMode();
  @Local auth: AuthState = connectAuth();
  @Local homeSource: HomeSourceState = connectHomeSource();
  // Index-owned scroller for this tab, so the title bar can bindToScrollable it (scroll-up auto-hide).
  @Param scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    // Seed the VM from the holder before the first load (in case it changed before this remount);
    // the @Monitors below handle every later change.
    this.vm.syncSource(this.homeSource.source, this.homeSource.toplistTl)
    this.vm.loadData()
  }

  @Monitor('siteMode.isEx')
  onSiteChange(): void {
    this.vm.reload()
  }

  // Source switch from the pinned bar (默认/热门/订阅) → reload from the first page.
  @Monitor('homeSource.source')
  onSourceChange(): void {
    this.vm.setSource(this.homeSource.source)
  }

  // 订阅 (watched) is login-only; if the user logs out while on it, reset the holder to the front
  // page (the bar's highlight follows and the VM reloads via onSourceChange).
  @Monitor('auth.isLogin')
  onLoginChange(): void {
    if (!this.auth.isLogin && this.homeSource.source === 'watched') {
      this.homeSource.source = ''
    }
  }

  build() {
    GalleryListBody({ vm: this.vm, topPadding: SELECTOR_BAR_HEIGHT, scroller: this.scroller })
  }
}
