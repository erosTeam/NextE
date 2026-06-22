import {
  connectSiteMode,
  SiteModeState,
  SELECTOR_BAR_HEIGHT,
  ActiveKeyState,
} from 'shared'
import { GalleryListViewModel } from '../viewmodel/GalleryListViewModel'
import { GalleryListBody } from './GalleryListBody'
import { common } from '@kit.AbilityKit'

/**
 * One retained gallery-SOURCE page (V2Next FeedListPage pattern). Each source (默认/热门/订阅) gets its
 * OWN GallerySourcePage instance inside HomePage's Swiper, and each owns its OWN GalleryListViewModel +
 * datasource + (Index-bound) scroller. The Swiper keeps the instances alive (cachedCount), so switching
 * source away and back preserves that source's list AND scroll offset — no shared-list reload. This is
 * the retained-tab model the gate requires; HomeSourceState stays a pure selection bus (it holds no data).
 *
 * Lazy first-load: a source loads its first page only when it FIRST becomes the active tab, not eagerly
 * for every cached page — so opening Home does not fire every source's network at once. Activation is
 * driven by the host's SHARED ActiveKeyState (active.activeKey === sourceKey), NOT a per-render isActive
 * @Param — a cached page never receives an isActive update, so that signal missed the first load.
 */
@ComponentV2
export struct GallerySourcePage {
  // '' front page / 'popular' / 'watched'. Stable for this page's lifetime (the Swiper key).
  @Param sourceKey: string = '';
  // Shared active-key signal from the host; this page is active when active.activeKey === sourceKey.
  @Param active: ActiveKeyState = new ActiveKeyState();
  // Index-owned scroller for this source, so the title bar can bindToScrollable the ACTIVE source's list.
  @Param scroller: Scroller = new Scroller();
  @Event onDidScroll?: (offset: number, state: ScrollState) => void;
  @Local vm: GalleryListViewModel = new GalleryListViewModel();
  @Local siteMode: SiteModeState = connectSiteMode();
  // First-load guard: load once on first activation; later activations reuse the retained list.
  private loadedOnce: boolean = false;

  private isActive(): boolean {
    return this.active.activeKey === this.sourceKey
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  aboutToAppear(): void {
    // Seed the source before any load (toplist tl is irrelevant to home sources → 0). The VM is this
    // page's own; nothing else writes it.
    this.vm.syncSource(this.sourceKey, 0)
    this.vm.setContext(this.ctx())
    if (this.isActive()) {
      this.loadOnce()
    }
  }

  // Load the first page the first time this source becomes active; retained afterwards. The host's @Trace
  // activeKey reaches even cached pages, so this fires reliably on a bar tap or swipe to this source.
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

  // A 表/里 site switch invalidates this source's rows; reload only if it has already loaded (an
  // unvisited source reloads naturally on its first activation with the new site).
  @Monitor('siteMode.isEx')
  onSiteChange(): void {
    if (this.loadedOnce) {
      this.vm.reload()
    }
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
