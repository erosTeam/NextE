import {
  HdsNavigation,
  HdsTabs,
  HdsTabsController,
  HdsNavigationTitleMode,
  hdsMaterial,
  BottomBuilderShowType,
  HideMode,
} from '@kit.UIDesignKit'
import { ComponentContent } from '@kit.ArkUI'
import {
  connectNavStack,
  connectPendingEhUrl,
  ThemeConstants,
  DiagnosticLogger,
  PendingEhUrlState,
  EhUrlRouter,
  GalleryRef,
  GalleryDetailParams,
  ImagePageRouteErrorParams,
  ImagePageRouteService,
  ImagePageRouteTarget,
  ReaderParams,
  connectSearchAction,
  SearchActionState,
  connectAuth,
  AuthState,
  connectFavSelection,
  FavSelectionBridge,
  SearchPageParams,
  SELECTOR_BAR_HEIGHT,
  DOWNLOAD_SELECTOR_BAR_HEIGHT,
  immersiveTitleBarOpts,
  immersiveMaterialType,
  InternalQaRoutes,
} from 'shared'
import { MainTabIcon } from '../components/MainTabIcon'
import { HomeSourceBarCCBuilder } from '../components/HomeSourceBar'
import { ToplistPeriodBarCCBuilder } from '../components/ToplistPeriodBar'
import { FavcatBarCCBuilder } from '../components/FavcatBar'
import { DownloadTypeBarCCBuilder } from '../components/DownloadTypeBar'
import { HomePage, ToplistPage } from 'home'
import { GallerySearchPage } from 'search'
import { FavoriteSelectorPage, FavoritesPage, MyTagsPage, ViewedHistoryPage } from 'user'
import { SettingsPage, LayoutSettingsPage, ReaderSettingsPage, DownloadSettingsPage, SearchSettingsPage, AdvancedSettingsPage, AboutPage } from 'settings'
import { GalleryDetailPage, GalleryInfoPage, GalleryTorrentsPage, GalleryArchiverPage, GalleryAllThumbnailsPage, GalleryCommentsPage } from 'gallery'
import { ReaderPage } from 'reader'
import { DownloadQueuePage } from 'download'
import { EhLoginWebPage } from './EhLoginWebPage'
import { EhCookieImportPage } from './EhCookieImportPage'
import { CoverFallbackProbePage } from './CoverFallbackProbePage'
import { ImagePageRouteErrorPage } from './ImagePageRouteErrorPage'

/**
 * NextE navigation shell — native HDS (`HdsNavigation` + `HdsTabs` from `@kit.UIDesignKit`,
 * V2Next's pattern). Bottom tabs mirror eros_fe's CupertinoTabBar IA (tabhome_controller.dart:69-92):
 * 画廊 / 收藏 / 排行 / 下载 / 设置. Search is NOT a tab — it's a title-bar icon on 画廊 that pushes the
 * search page (eros_fe custom_tabbar_page.dart:219-229). The 画廊 source switcher and the 排行 period
 * switcher are pinned under the title as HDS `bottomBuilder`s (never scrolling list items). Routed
 * pages register through `routerMap`; content insets are owned by the shared list scaffolds.
 */
@Entry
@ComponentV2
struct Index {
  private stack: NavPathStack = connectNavStack().stack;
  private tabsController: HdsTabsController = new HdsTabsController();
  // One scroller per tab (画廊/收藏/排行/下载/设置); the title bar binds to the ACTIVE tab's scroller
  // for scroll-up auto-hide (V2Next homeTabScrollers/titleScroller). Index OWNS them + passes each down.
  private homeTabScrollers: Scroller[] = [
    new Scroller(),
    new Scroller(),
    new Scroller(),
    new Scroller(),
    new Scroller(),
  ];
  @Local titleScroller: Scroller = this.homeTabScrollers[0];
  // Pinned title-bar bottomBuilders, cached ONCE (recreating per titleBar re-issue would remount the
  // control ~per frame, as V2Next's pillBarContent comment warns).
  private sourceBarContent: ComponentContent<Object> | null = null;
  private periodBarContent: ComponentContent<Object> | null = null;
  private favcatBarContent: ComponentContent<Object> | null = null;
  private downloadTypeBarContent: ComponentContent<Object> | null = null;
  @Local pendingEhUrl: PendingEhUrlState = connectPendingEhUrl();
  @Local searchAction: SearchActionState = connectSearchAction();
  // Read so the 收藏 menu gates remote-only actions on login while the local favcat bar stays visible.
  // Mirrors HomeSourceBar gating 订阅 on isLogin.
  @Local auth: AuthState = connectAuth();
  @Local currentTab: number = 0;
  private lastHandledSignal: string = '';
  private lastHandledQuery: string = '';

  aboutToAppear(): void {
    this.handlePendingEhUrl()
  }

  @Monitor('pendingEhUrl.signal')
  onPendingEhUrl(): void {
    this.handlePendingEhUrl()
  }

  /**
   * Cross-page "search for X" (e.g. detail tag / Similar / uploader). Index is the only consumer of
   * the global pending signal; it pushes a new Search route with the query as a route/session param.
   * Old Search pages may remain alive underneath detail pages, but they never consume or clear this
   * global signal, so a later tag cannot be stolen by an older Search instance.
   */
  @Monitor('searchAction.pendingQuery')
  onPendingQuery(): void {
    const pq: string = this.searchAction.pendingQuery
    if (pq.length === 0 || pq === this.lastHandledQuery) {
      return
    }
    this.lastHandledQuery = pq
    const sep: number = pq.indexOf(':')
    const token: string = sep >= 0 ? pq.substring(0, sep) : `${Date.now()}`
    const query: string = sep >= 0 ? pq.substring(sep + 1) : pq
    this.stack.pushPathByName('Search', new SearchPageParams('', 'a', query, false, token))
    this.searchAction.clearPending()
  }

  // Push the search page, unless a search page is already on top (then its own @Monitor re-searches).
  private openSearch(focusOnAppear: boolean = true): void {
    const names: string[] = this.stack.getAllPathName()
    if (names.length === 0 || names[names.length - 1] !== 'Search') {
      this.stack.pushPathByName('Search', new SearchPageParams('', 'a', '', focusOnAppear))
    }
  }

  // Push the ONE shared search page in FAVORITE scope (eros_fe goSearchPage(searchType: favorite),
  // navigator_util.dart:76-106). The scope + current favcat ride a route param; the search inherits the
  // last-shown favcat ('a' = all favorites → favorites.php omits favcat → searches all).
  private openFavoriteSearch(): void {
    const favcat: string = connectFavSelection().selectedFavcat
    const names: string[] = this.stack.getAllPathName()
    if (names.length === 0 || names[names.length - 1] !== 'Search') {
      this.stack.pushPathByName('Search', new SearchPageParams('favorite', favcat))
    }
  }

  private openFavoriteSelector(): void {
    this.stack.pushPathByName('FavoriteSelector', null)
  }

  private handlePendingEhUrl(): void {
    const signal: string = this.pendingEhUrl.signal
    if (signal.length === 0 || signal === this.lastHandledSignal) {
      return
    }
    this.lastHandledSignal = signal
    const sep: number = signal.indexOf(':')
    const uri: string = sep >= 0 ? signal.substring(sep + 1) : signal
    if (uri === InternalQaRoutes.COVER_FALLBACK_PROBE_URI) {
      DiagnosticLogger.info('nav', 'internal_qa_open', 'cover-fallback')
      this.stack.pushPathByName('CoverFallbackProbe', null)
      return
    }
    const ref: GalleryRef | null = EhUrlRouter.parseGallery(uri)
    if (ref !== null) {
      DiagnosticLogger.info('nav', 'deep_link_open', `/g/${ref.gid}/${ref.token}`)
      this.stack.pushPathByName('GalleryDetail', new GalleryDetailParams(ref.gid, ref.token))
      return
    }
    if (EhUrlRouter.parseImagePage(uri) !== null) {
      DiagnosticLogger.info('nav', 'deep_link_open', '/s/')
      this.openImagePageUrl(uri)
    }
  }

  private openImagePageUrl(uri: string): void {
    ImagePageRouteService.resolve(uri)
      .then((target: ImagePageRouteTarget) => {
        this.stack.pushPathByName(
          'Reader',
          new ReaderParams(target.gid, target.token, target.index, target.fileCount, '', [target.seedImage], 0, 0),
        )
      })
      .catch((err: Error) => {
        DiagnosticLogger.warn('nav', 'image_page_deep_link_failed', err.message)
        this.stack.pushPathByName('ImagePageRouteError', new ImagePageRouteErrorParams(uri))
      })
  }

  private tabTitle(): ResourceStr {
    if (this.currentTab === 1) {
      return $r('app.string.tab_favorites')
    }
    if (this.currentTab === 2) {
      return $r('app.string.tab_toplist')
    }
    if (this.currentTab === 3) {
      return $r('app.string.tab_download')
    }
    if (this.currentTab === 4) {
      return $r('app.string.tab_settings')
    }
    return 'E-Hentai'
  }

  private scrollActiveTabToTop(): void {
    this.titleScroller.scrollToIndex(0)
  }

  // 画廊 title-bar utility actions (HDS menu shape: value[]+maxCount). eros_fe exposes search plus
  // list navigation helpers in the trailing cluster; NextE keeps the same title-action semantics while
  // limiting this slice to the reliable active-scroller "back to top" action.
  private searchMenu(): Record<string, Object> {
    const searchInner: Record<string, Object> = {
      'label': $r('app.string.tab_search'),
      'icon': $r('sys.symbol.magnifyingglass'),
      'isEnabled': true,
      'action': () => {
        this.openSearch()
      },
    }
    const topInner: Record<string, Object> = {
      'label': $r('app.string.common_back_to_top'),
      'icon': $r('sys.symbol.arrow_up'),
      'isEnabled': true,
      'action': () => {
        this.scrollActiveTabToTop()
      },
    }
    const items: Record<string, Object>[] = [
      { 'content': searchInner },
      { 'content': topInner },
    ]
    return { 'value': items, 'maxCount': 2 }
  }

  // Empty menu — HDS keeps the last-set title-bar menu across tab switches, so non-gallery tabs must
  // explicitly clear the 画廊 search icon (else it lingers on 排行/下载/设置).
  private emptyMenu(): Record<string, Object> {
    const empty: Record<string, Object>[] = []
    return { 'value': empty, 'maxCount': 0 }
  }

  // 收藏 title-bar trailing actions (eros_fe favorites nav bar: search icon + sort_down,
  // favorite_tabbar_page.dart:190-273). Two native HDS menu items (V2Next multi-item menu shape:
  // value[]+maxCount; maxCount:2 → both render inline). Search pushes the ONE shared adaptive search
  // page in favorite scope; order opens a native action menu (the HarmonyOS equivalent of eros_fe's
  // CupertinoActionSheet showFavOrder). NOT hand-rolled into the favcat bar.
  private favoritesMenu(): Record<string, Object> {
    const searchInner: Record<string, Object> = {
      'label': $r('app.string.tab_search'),
      'icon': $r('sys.symbol.magnifyingglass'),
      'isEnabled': true,
      'action': () => {
        this.openFavoriteSearch()
      },
    }
    const orderInner: Record<string, Object> = {
      'label': $r('app.string.fav_order_title'),
      'icon': $r('sys.symbol.sort'),
      'isEnabled': true,
      'action': () => {
        FavSelectionBridge.publishOpenOrderMenu()
      },
    }
    const selectorInner: Record<string, Object> = {
      'label': $r('app.string.favorites_selector_title'),
      'icon': $r('sys.symbol.list_bullet_square_fill'),
      'isEnabled': true,
      'action': () => {
        this.openFavoriteSelector()
      },
    }
    const items: Record<string, Object>[] = [
      { 'content': searchInner },
      { 'content': orderInner },
      { 'content': selectorInner },
    ]
    return { 'value': items, 'maxCount': 3 }
  }

  private localFavoritesMenu(): Record<string, Object> {
    const selectorInner: Record<string, Object> = {
      'label': $r('app.string.favorites_selector_title'),
      'icon': $r('sys.symbol.list_bullet_square_fill'),
      'isEnabled': true,
      'action': () => {
        this.openFavoriteSelector()
      },
    }
    const items: Record<string, Object>[] = [{ 'content': selectorInner }]
    return { 'value': items, 'maxCount': 1 }
  }

  private bottomBuilder(content: ComponentContent<Object>, height: number = SELECTOR_BAR_HEIGHT): Record<string, Object> {
    return {
      'builderComponent': content,
      'height': height,
      'showType': BottomBuilderShowType.DIRECTLY_SHOW,
    }
  }

  /**
   * HDS title-bar options per tab. 画廊 pins the source switcher (bottomBuilder) + a search icon;
   * 排行 pins the period switcher; 下载 pins the gallery/archive segmented switcher. Record<string,Object> (not a typed
   * literal) because bottomBuilder/menu aren't in the strict options interface.
   */
  private titleBarOpts(): Record<string, Object> {
    const title: Record<string, Object> = { 'mainTitle': this.tabTitle() }
    const content: Record<string, Object> = { 'title': title }
    if (this.currentTab === 0) {
      if (this.sourceBarContent === null) {
        this.sourceBarContent = new ComponentContent<Object>(
          this.getUIContext(),
          wrapBuilder<[Object]>(HomeSourceBarCCBuilder),
          new Object(),
        )
      }
      content['bottomBuilder'] = this.bottomBuilder(this.sourceBarContent)
      content['menu'] = this.searchMenu()
    } else if (this.currentTab === 1) {
      // 收藏: the favcat switcher is always pinned so logged-out users can reach the local `l` slot.
      // Search/order/selector remain remote-account actions and are only shown when logged in.
      if (this.favcatBarContent === null) {
        this.favcatBarContent = new ComponentContent<Object>(
          this.getUIContext(),
          wrapBuilder<[Object]>(FavcatBarCCBuilder),
          new Object(),
        )
      }
      content['bottomBuilder'] = this.bottomBuilder(this.favcatBarContent)
      if (this.auth.isLogin) {
        content['menu'] = this.favoritesMenu()
      } else {
        content['menu'] = this.localFavoritesMenu()
      }
    } else {
      if (this.currentTab === 2) {
        if (this.periodBarContent === null) {
          this.periodBarContent = new ComponentContent<Object>(
            this.getUIContext(),
            wrapBuilder<[Object]>(ToplistPeriodBarCCBuilder),
            new Object(),
          )
        }
        content['bottomBuilder'] = this.bottomBuilder(this.periodBarContent)
      }
      if (this.currentTab === 3) {
        if (this.downloadTypeBarContent === null) {
          this.downloadTypeBarContent = new ComponentContent<Object>(
            this.getUIContext(),
            wrapBuilder<[Object]>(DownloadTypeBarCCBuilder),
            new Object(),
          )
        }
        content['bottomBuilder'] = this.bottomBuilder(this.downloadTypeBarContent, DOWNLOAD_SELECTOR_BAR_HEIGHT)
      }
      content['menu'] = this.emptyMenu()
    }
    // Wrap with V2Next's immersive title-bar style (GRADIENT_BLUR scroll effect + immersive material)
    // so content scrolling under the status bar / title bar is progressively blurred, not shown sharp.
    return immersiveTitleBarOpts(content)
  }

  @Builder
  routerMap(name: string) {
    if (name === 'GalleryDetail') {
      GalleryDetailPage()
    } else if (name === 'GalleryInfo') {
      GalleryInfoPage()
    } else if (name === 'GalleryTorrents') {
      GalleryTorrentsPage()
    } else if (name === 'GalleryArchiver') {
      GalleryArchiverPage()
    } else if (name === 'Search') {
      GallerySearchPage()
    } else if (name === 'Reader') {
      ReaderPage()
    } else if (name === 'EhLogin') {
      EhLoginWebPage()
    } else if (name === 'EhCookieImport') {
      EhCookieImportPage()
    } else if (name === 'MyTags') {
      MyTagsPage()
    } else if (name === 'History') {
      ViewedHistoryPage()
    } else if (name === 'FavoriteSelector') {
      FavoriteSelectorPage()
    } else if (name === 'AllThumbnails') {
      GalleryAllThumbnailsPage()
    } else if (name === 'GalleryComments') {
      GalleryCommentsPage()
    } else if (name === 'LayoutSettings') {
      LayoutSettingsPage()
    } else if (name === 'ReaderSettings') {
      ReaderSettingsPage()
    } else if (name === 'DownloadSettings') {
      DownloadSettingsPage()
    } else if (name === 'SearchSettings') {
      SearchSettingsPage()
    } else if (name === 'AdvancedSettings') {
      AdvancedSettingsPage()
    } else if (name === 'About') {
      AboutPage()
    } else if (name === 'ImagePageRouteError') {
      ImagePageRouteErrorPage()
    } else if (name === 'CoverFallbackProbe') {
      CoverFallbackProbePage()
    }
  }

  // A retained sub-tab page (e.g. HomePage's active source) reports its scroller; store it as that main
  // tab's scroller and, if that main tab is active, repoint the title binding so auto-hide follows the
  // active sub-tab's list (V2Next setHomeTabScroller). Other main tabs still pass homeTabScrollers down.
  private setHomeActiveScroller(index: number, scroller: Scroller): void {
    this.homeTabScrollers[index] = scroller
    if (this.currentTab === index) {
      this.titleScroller = scroller
    }
  }

  build() {
    HdsNavigation(this.stack) {
      HdsTabs({ controller: this.tabsController }) {
        TabContent() {
          // Retained per-source sub-tabs own their own scrollers; HomePage reports the ACTIVE source's
          // scroller up so the title auto-hide binds the right list (V2Next onScrollerReady chain).
          HomePage({
            onScrollerReady: (scroller: Scroller) => {
              this.setHomeActiveScroller(0, scroller)
            },
          })
        }.tabBar(this.tabIcon($r('app.string.tab_gallery'), 0))
        TabContent() {
          // Retained per-favcat sub-tabs own their own scrollers; FavoritesPage reports the ACTIVE favcat's
          // scroller up so the title auto-hide binds the right list (V2Next onScrollerReady chain).
          FavoritesPage({
            onScrollerReady: (scroller: Scroller) => {
              this.setHomeActiveScroller(1, scroller)
            },
          })
        }.tabBar(this.tabIcon($r('app.string.tab_favorites'), 1))
        TabContent() {
          // Retained per-period sub-tabs own their own scrollers; ToplistPage reports the ACTIVE period's
          // scroller up so the title auto-hide binds the right list (V2Next onScrollerReady chain).
          ToplistPage({
            onScrollerReady: (scroller: Scroller) => {
              this.setHomeActiveScroller(2, scroller)
            },
          })
        }.tabBar(this.tabIcon($r('app.string.tab_toplist'), 2))
        TabContent() {
          DownloadQueuePage({ scroller: this.homeTabScrollers[3] })
        }.tabBar(this.tabIcon($r('app.string.tab_download'), 3))
        TabContent() {
          SettingsPage({ scroller: this.homeTabScrollers[4] })
        }.tabBar(this.tabIcon($r('app.string.tab_settings'), 4))
      }
      .barOverlap(true)
      .barPosition(BarPosition.End)
      .barMode(BarMode.Fixed)
      .scrollable(false)
      .animationDuration(0)
      .barFloatingStyle({
        barBottomMargin: ThemeConstants.SPACE_XL,
        adaptToHandedness: true,
        systemMaterialEffect: {
          materialType: immersiveMaterialType(),
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE,
        },
      })
      .onChange((index: number) => {
        this.currentTab = index
        // Rebind the title bar to the newly-active tab's scroller so it auto-hides off that list.
        this.titleScroller = this.homeTabScrollers[index]
      })
    }
    .navDestination(this.routerMap)
    // Pin Stack mode (V2Next Index.ets:668): default Auto flips to two-column Split past ~600vp, so on
    // the unfolded foldable the name-pushed routes would render split instead of full-width pushes.
    .mode(NavigationMode.Stack)
    .titleBar(this.titleBarOpts())
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(true)
    // Scroll-up auto-hide of the title area (V2Next Index.ets:650-661). The bottomBuilder (源/周期条)
    // stays pinned (hideBottomBuilder:false), matching V2Next keeping its feed pills reachable while
    // scrolled. Bound to the active tab's scroller (rebound in onChange).
    .dynamicHideTitleBar({
      hideTitleArea: true,
      hideBottomBuilder: false,
      hideStatusBar: false,
      mode: HideMode.SCROLL_UP,
    })
    .bindToScrollable([this.titleScroller])
    .width('100%')
    .height('100%')
  }

  @Builder
  tabIcon(title: ResourceStr, idx: number) {
    MainTabIcon({ title: title, idx: idx, currentIndex: this.currentTab })
  }
}
