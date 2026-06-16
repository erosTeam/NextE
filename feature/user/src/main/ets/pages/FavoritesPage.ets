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
  connectAuth,
  AuthState,
  connectNavStack,
  connectSiteMode,
  SiteModeState,
  connectListMode,
  ListModeState,
  ListMode,
  FavSelectionState,
  connectFavSelection,
  SELECTOR_BAR_HEIGHT,
} from 'shared'
import { SymbolGlyphModifier } from '@kit.ArkUI'
import { FavoritesViewModel } from '../viewmodel/FavoritesViewModel'

/**
 * Favorites tab (M3). Logged out → an actionable login prompt (opens the in-app EH web login).
 * Logged in → the user's favorites on the shared PullRefreshListScaffold + GalleryCard (same as
 * Home), with a horizontal favcat selector bar (全部 + slots 0-9 with counts) as the first list
 * row. Rows + favcat bar both come from the real favorites.php parse (EhGalleryListParser +
 * EhFavcatListParser). Gated on AuthState.isLogin; loads on first appear when logged in.
 */
@ComponentV2
export struct FavoritesPage {
  @Local auth: AuthState = connectAuth();
  @Local vm: FavoritesViewModel = new FavoritesViewModel();
  @Local siteMode: SiteModeState = connectSiteMode();
  @Local listMode: ListModeState = connectListMode();
  private stack: NavPathStack = connectNavStack().stack;
  // Index-owned scroller for this tab (title-bar scroll-up auto-hide via bindToScrollable).
  @Param scroller: Scroller = new Scroller();
  private refreshController: PullRefreshController = new PullRefreshController();
  private started: boolean = false;
  // Pinned favcat bar state. FavcatBar lives in Index's title bar (outside this page's tree), so the
  // bar and this page talk ONLY through this shared holder: a favcat chip tap and the HDS title-bar
  // order action arrive as cmdSeq commands, and this page publishes the favList/favcat/order snapshot
  // back. Search is NOT here — it's a title-bar action that opens the shared adaptive search page.
  @Local favSel: FavSelectionState = connectFavSelection();
  // Native order-dropdown visibility. The title-bar order icon can't anchor a Menu (HDS menu icons
  // aren't owned nodes), so it publishes 'openOrderMenu' and this page opens an owned `bindMenu`
  // dropdown (V2Next TopicDetailComponents order/mode picker) anchored at the content's trailing edge.
  @Local orderMenuShown: boolean = false;

  aboutToAppear(): void {
    this.maybeLoad()
  }

  // Bar → page: a favcat chip tap selects the slot; the title-bar order icon opens the order dropdown
  // (the VM's own unchanged/isLoading guards make a stray re-fire harmless).
  @Monitor('favSel.cmdSeq')
  onFavCommand(): void {
    const kind: string = this.favSel.cmdKind
    if (kind === 'select') {
      this.vm.selectFavcat(this.favSel.cmdArg)
    } else if (kind === 'openOrderMenu') {
      this.orderMenuShown = true
    }
  }

  // Page → bar: mirror the VM's favcat snapshot into the holder so the pinned bar renders the right
  // chips / highlight / order label. Fires synchronously after each VM field change (selectFavcat sets
  // favcat before awaiting), so the chip highlight flips promptly rather than a network round-trip
  // later. The seeded placeholder slots stay until the first parse populates vm.favList — this only
  // fires on change, so the empty initial vm.favList never clobbers the seed.
  @Monitor('vm.favList', 'vm.favcat', 'vm.favOrder')
  syncBar(): void {
    this.favSel.favList = this.vm.favList
    this.favSel.selectedFavcat = this.vm.favcat
    this.favSel.orderByPosted = this.vm.isOrderByPosted()
  }

  @Monitor('auth.isLogin')
  onLogin(): void {
    this.maybeLoad()
  }

  @Monitor('siteMode.isEx')
  onSiteChange(): void {
    if (this.auth.isLogin) {
      this.vm.load()
    }
  }

  private maybeLoad(): void {
    if (this.auth.isLogin && !this.started) {
      this.started = true
      this.vm.load()
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column() {
        if (!this.auth.isLogin) {
          PageErrorState({
            message: $r('app.string.favorites_login_hint'),
            retryLabel: $r('app.string.settings_login'),
            retryAction: () => {
              this.stack.pushPathByName('EhLogin', null)
            },
          })
        } else if (this.vm.isLoading && this.vm.itemCount === 0) {
          // First load (or a reload after error) — show a spinner instead of a blank page.
          PageLoadingState()
        } else if (this.vm.itemCount === 0 && this.vm.errorMessage.length > 0) {
          // Load failed (e.g. ExHentai favorites need igneous, or a transient network error): surface
          // it with a retry instead of rendering nothing (the former blank-page bug).
          PageErrorState({
            message: this.vm.errorMessage,
            retryAction: () => {
              this.vm.load()
            },
          })
        } else if (this.vm.itemCount === 0 && this.vm.favList.length === 0) {
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
                  this.stack.pushPathByName(
                    'GalleryDetail',
                    new GalleryDetailParams(g.gid, g.token, g.thumbUrl, g.title(), g.fileCount),
                  )
                })
              },
              (g: EhGallery) => g.gid,
            )
          }
        } else {
          // LIST (cards) and SIMPLE_LIST (compact divider rows) share one scaffold.
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
          }) {
            LazyForEach(
              this.vm.dataSource,
              (g: EhGallery) => {
                ListItem() {
                  if (this.listMode.mode === ListMode.SIMPLE_LIST) {
                    GallerySimpleCard({ gallery: g })
                  } else {
                    GalleryCard({ gallery: g })
                  }
                }
                .onClick(() => {
                  this.stack.pushPathByName(
                    'GalleryDetail',
                    new GalleryDetailParams(g.gid, g.token, g.thumbUrl, g.title(), g.fileCount),
                  )
                })
              },
              (g: EhGallery) => g.gid,
            )
            ListItem() {
              LoadingFooter({
                isLoading: this.vm.isLoadingMore,
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
      // Invisible anchor for the native order dropdown at the content's trailing edge (under the favcat
      // bar, near the title-bar order icon). bindMenu can't attach to the HDS title-bar icon (not an
      // owned node), so the order action opens this owned Menu via the command bus.
      Row()
        .width(1)
        .height(1)
        .hitTestBehavior(HitTestMode.None)
        .bindMenu(this.orderMenuShown, this.OrderMenu, {
          placement: Placement.BottomRight,
          onDisappear: () => {
            this.orderMenuShown = false
          },
        })
    }
    .width('100%')
    .height('100%')
  }

  // Native order dropdown (eros_fe showFavOrder — but a native HDS Menu, not a dialog). Opened from the
  // title-bar order icon via the command bus; FavoritesPage owns the VM, so the items toggle it
  // directly. The active order carries a checkmark (V2Next TopicDetailComponents.ets:192-227).
  @Builder
  OrderMenu() {
    Menu() {
      MenuItem({
        content: $r('app.string.fav_order_fav'),
        symbolEndIcon: this.vm.isOrderByPosted()
          ? undefined
          : new SymbolGlyphModifier($r('sys.symbol.checkmark')),
      })
        .onClick(() => {
          if (this.vm.isOrderByPosted()) {
            this.vm.toggleOrder()
          }
          this.orderMenuShown = false
        })
      MenuItem({
        content: $r('app.string.fav_order_posted'),
        symbolEndIcon: this.vm.isOrderByPosted()
          ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
          : undefined,
      })
        .onClick(() => {
          if (!this.vm.isOrderByPosted()) {
            this.vm.toggleOrder()
          }
          this.orderMenuShown = false
        })
    }
  }
}
