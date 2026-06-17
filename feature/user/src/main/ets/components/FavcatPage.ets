import {
  ThemeConstants,
  EhGallery,
  GalleryCard,
  GalleryGridCard,
  GallerySimpleCard,
  GalleryDetailParams,
  PageErrorState,
  PageLoadingState,
  CardEmptyState,
  LoadingFooter,
  PullRefreshListScaffold,
  PullRefreshGridScaffold,
  PullRefreshController,
  connectNavStack,
  connectSiteMode,
  SiteModeState,
  connectListMode,
  ListModeState,
  ListMode,
  FavSelectionState,
  connectFavSelection,
  Favcat,
  SELECTOR_BAR_HEIGHT,
  ActiveKeyState,
} from 'shared'
import { FavoritesViewModel } from '../viewmodel/FavoritesViewModel'

/**
 * One retained FAVCAT page (V2Next FeedListPage pattern; mirrors GallerySourcePage). Each favcat ('a' =
 * all, '0'..'9') gets its OWN FavcatPage inside FavoritesPage's Swiper, owning its OWN FavoritesViewModel
 * + datasource + (Index-bound) scroller, kept alive by the Swiper — so switching favcat away and back
 * preserves that favcat's list AND scroll. FavSelectionState stays a pure selection bus.
 *
 * Lazy first-load on activate. The GLOBAL order (favorited/posted) lives on the shared bus
 * (FavSelectionState.orderByPosted); this page reloads when it toggles. The parsed favcat sidebar is
 * merged into the shared favList so the bar shows real names + counts (the 'a' page sees the full set).
 */
@ComponentV2
export struct FavcatPage {
  // 'a' = all, '0'..'9' = slots. Stable for this page's lifetime (the Swiper key).
  @Param favcatKey: string = 'a';
  // Shared active-key signal from the host; active when active.activeKey === favcatKey.
  @Param active: ActiveKeyState = new ActiveKeyState();
  @Param scroller: Scroller = new Scroller();
  @Local vm: FavoritesViewModel = new FavoritesViewModel();
  @Local siteMode: SiteModeState = connectSiteMode();
  @Local listMode: ListModeState = connectListMode();
  @Local favSel: FavSelectionState = connectFavSelection();
  @Local listContentWidth: number = 0;
  private stack: NavPathStack = connectNavStack().stack;
  private refreshController: PullRefreshController = new PullRefreshController();
  private loadedOnce: boolean = false;

  private isActive(): boolean {
    return this.active.activeKey === this.favcatKey
  }

  aboutToAppear(): void {
    // Fix this page to its favcat + the current global order before any load.
    this.vm.configure(this.favcatKey, this.favSel.orderByPosted)
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

  private async loadOnce(): Promise<void> {
    if (this.loadedOnce) {
      return
    }
    this.loadedOnce = true
    await this.vm.load()
    // Publish the parsed favcat sidebar AFTER the load resolves (deterministic) so the shared favList — and
    // thus the bar's real names/counts — are populated; the bar's keyed-by-label/count ForEach then rebuilds.
    this.publishFavList()
  }

  // Global order toggle from the shared bus → reload this favcat with the new order (if already loaded;
  // an unvisited favcat picks up the order on its first activation).
  @Monitor('favSel.orderByPosted')
  async onOrderChange(): Promise<void> {
    if (this.loadedOnce) {
      await this.vm.applyOrder(this.favSel.orderByPosted)
      this.publishFavList()
    }
  }

  @Monitor('siteMode.isEx')
  async onSiteChange(): Promise<void> {
    if (this.loadedOnce) {
      await this.vm.load()
      this.publishFavList()
    }
  }

  // Publish this favcat's parsed sidebar into the shared favList so the bar shows names + counts. The 'a'
  // page sees the complete set (EH omits only the active favcat, and 'a' is not a slot). Incoming wins.
  private publishFavList(): void {
    if (this.vm.favList.length === 0) {
      return
    }
    const byId: Map<string, Favcat> = new Map<string, Favcat>()
    this.favSel.favList.forEach((f: Favcat) => byId.set(f.favId, f))
    this.vm.favList.forEach((f: Favcat) => byId.set(f.favId, f))
    const merged: Favcat[] = []
    byId.forEach((f: Favcat) => merged.push(f))
    this.favSel.favList = merged
  }

  private openDetail(g: EhGallery): void {
    this.stack.pushPathByName(
      'GalleryDetail',
      new GalleryDetailParams(g.gid, g.token, g.thumbUrl, g.title(), g.fileCount),
    )
  }

  build() {
    Column() {
      if (
        this.vm.itemCount === 0 &&
        this.vm.errorMessage.length === 0 &&
        (this.vm.isLoading || !this.loadedOnce)
      ) {
        // Never-loaded OR loading (nothing yet) → content-area loading. Gating on `!loadedOnce` (not just
        // the transient isLoading) closes the frame where a freshly-switched favcat is mounted but its load
        // hasn't flipped isLoading true yet — which otherwise flashes an empty body before the spinner.
        PageLoadingState()
      } else if (this.vm.itemCount === 0 && this.vm.errorMessage.length > 0) {
        PageErrorState({
          message: this.vm.errorMessage,
          retryAction: () => {
            this.vm.load()
          },
        })
      } else if (this.vm.itemCount === 0 && this.loadedOnce && !this.vm.isLoading) {
        CardEmptyState({ message: $r('app.string.common_no_content') })
      } else if (this.listMode.mode === ListMode.GRID) {
        PullRefreshGridScaffold({
          scroller: this.scroller,
          topPadding: SELECTOR_BAR_HEIGHT,
          bottomPadding: ThemeConstants.FLOAT_BAR_HEIGHT + ThemeConstants.SPACE_LG,
          controller: this.refreshController,
          onRefresh: async () => {
            await this.vm.refresh()
          },
          onBottomRefresh: async () => {
            await this.vm.loadMore()
          },
          canStartBottomRefresh: () => this.vm.canLoadMore(),
          onReachEnd: () => {
            this.vm.loadMore()
          },
        }) {
          LazyForEach(
            this.vm.dataSource,
            (g: EhGallery) => {
              GridItem() {
                GalleryGridCard({ gallery: g })
              }
              .onClick(() => {
                this.openDetail(g)
              })
            },
            (g: EhGallery) => g.gid,
          )
        }
      } else {
        PullRefreshListScaffold({
          scroller: this.scroller,
          listSpace: this.listMode.mode === ListMode.SIMPLE_LIST ? 0 : ThemeConstants.SPACE_SM,
          topPadding: SELECTOR_BAR_HEIGHT,
          bottomPadding: ThemeConstants.FLOAT_BAR_HEIGHT + ThemeConstants.SPACE_LG,
          controller: this.refreshController,
          onRefresh: async () => {
            await this.vm.refresh()
          },
          onBottomRefresh: async () => {
            await this.vm.loadMore()
          },
          canStartBottomRefresh: () => this.vm.canLoadMore(),
          onReachEnd: () => {
            this.vm.loadMore()
          },
          onContentWidth: (contentWidth: number) => {
            this.listContentWidth = contentWidth
          },
        }) {
          LazyForEach(
            this.vm.dataSource,
            (g: EhGallery) => {
              ListItem() {
                if (this.listMode.mode === ListMode.SIMPLE_LIST) {
                  GallerySimpleCard({ gallery: g })
                } else {
                  GalleryCard({ gallery: g, listContentWidth: this.listContentWidth })
                }
              }
              .onClick(() => {
                this.openDetail(g)
              })
            },
            (g: EhGallery) => g.gid,
          )
          ListItem() {
            LoadingFooter({
              // Page-level isLoading too, so a favcat reload never strands a "没有更多了" terminal flash.
              isLoading: this.vm.isLoadingMore || this.vm.isLoading,
              hasMore: this.vm.hasMore,
              isError: this.vm.errorMessage.length > 0 && this.vm.hasMore,
              onRetry: () => {
                this.vm.loadMore()
              },
            })
          }
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
