import {
  HdsNavigation,
  HdsTabs,
  HdsTabsController,
  HdsNavigationTitleMode,
  HdsAnimationMode,
  hdsMaterial,
  BottomBuilderShowType,
  HideMode,
} from '@kit.UIDesignKit'
import { ComponentContent } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import {
  connectNavStack,
  connectPendingEhUrl,
  ThemeConstants,
  DiagnosticLogger,
  PendingEhUrlState,
  EhConstants,
  EhUrlRouter,
  GalleryRef,
  GalleryDetailParams,
  GalleryCommentsParams,
  GalleryWebParams,
  ImagePageRouteErrorParams,
  ImagePageRouteService,
  ImagePageRouteTarget,
  ReaderParams,
  DownloadArchiverTask,
  DownloadGalleryTask,
  DownloadGalleryTaskStatus,
  DownloadQueueSettings,
  DownloadQueueState,
  DownloadViewState,
  DownloadViewType,
  connectSearchAction,
  SearchActionState,
  connectSiteMode,
  connectAuth,
  AuthState,
  connectFavSelection,
  FavSelectionBridge,
  HomeSourceBridge,
  connectHomeTabAutoHide,
  HomeTabAutoHideState,
  SearchPageParams,
  SELECTOR_BAR_HEIGHT,
  DOWNLOAD_SELECTOR_BAR_HEIGHT,
  connectDownloadQueue,
  connectDownloadView,
  immersiveTitleBarOpts,
  ImmersiveMaterialSettings,
  ImmersiveMaterialSettingsState,
  connectImmersiveMaterialSettings,
  InternalQaRoutes,
  RootRefreshRegistry,
  SafeModeGate,
  SafeModeState,
  connectSafeMode,
} from 'shared'
import { MainTabIcon } from '../components/MainTabIcon'
import { HomeSourceBarCCBuilder } from '../components/HomeSourceBar'
import { ToplistPeriodBarCCBuilder } from '../components/ToplistPeriodBar'
import { FavcatBarCCBuilder } from '../components/FavcatBar'
import { DownloadTypeBarCCBuilder } from '../components/DownloadTypeBar'
import { HomePage, ToplistPage, TabManagerPage, TabEditPage } from 'home'
import { GallerySearchPage } from 'search'
import { FavoriteSelectorPage, FavoritesPage, MyTagsPage, ViewedHistoryPage } from 'user'
import {
  SettingsPage,
  EhSettingsPage,
  EhProfileSettingsPage,
  AccountPage,
  AccountLoginPage,
  LayoutSettingsPage,
  ColumnDensityPage,
  CacheSettingsPage,
  ReaderSettingsPage,
  DownloadSettingsPage,
  SearchSettingsPage,
  LocalBlockSettingsPage,
  TagTranslationSettingsPage,
  TranslationSettingsPage,
  SyncSettingsPage,
  WebDavSyncSettingsPage,
  AdvancedSettingsPage,
  SecuritySettingsPage,
  AboutPage,
} from 'settings'
import {
  GalleryDetailPage,
  GalleryInfoPage,
  GalleryTorrentsPage,
  GalleryArchiverPage,
  GalleryAllThumbnailsPage,
  GalleryCommentsPage,
  GalleryEditTagsPage,
} from 'gallery'
import { ReaderPage } from 'reader'
import { DownloadQueuePage } from 'download'
import { EhLoginWebPage } from './EhLoginWebPage'
import { EhCookieImportPage } from './EhCookieImportPage'
import { EhPasswordLoginPage } from './EhPasswordLoginPage'
import { CoverFallbackProbePage } from './CoverFallbackProbePage'
import { ReaderGestureProbePage } from './ReaderGestureProbePage'
import { ImagePageRouteErrorPage } from './ImagePageRouteErrorPage'
import { GalleryWebPage } from './GalleryWebPage'

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
  private readonly HOME_TAB_SCROLL_DELTA_PX: number = 6;
  private readonly HOME_TAB_ANIMATION_GUARD_MS: number = 180;
  private homeTabLastScrollOffsets: number[] = [0, 0, 0, 0, 0];
  private homeTabAnimationGuardTimerId: number = -1;
  private homeTabVisibleByScroll: boolean = true;
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
  @Local safeMode: SafeModeState = connectSafeMode();
  @Local homeTab: HomeTabAutoHideState = connectHomeTabAutoHide();
  @Local immersiveMaterial: ImmersiveMaterialSettingsState = connectImmersiveMaterialSettings();
  @Local downloadView: DownloadViewState = connectDownloadView();
  @Local downloadQueue: DownloadQueueState = connectDownloadQueue();
  @Local currentTab: number = 0;
  private lastHandledSignal: string = '';
  private lastHandledQuery: string = '';

  aboutToAppear(): void {
    this.handlePendingEhUrl()
  }

  aboutToDisappear(): void {
    this.clearHomeTabAnimationGuardTimer()
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
    if (this.safeMode.restricted()) {
      this.searchAction.clearPending()
      return
    }
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

  @Monitor('homeTab.autoHide')
  onHomeTabAutoHideChanged(): void {
    this.applyHomeTabAutoHide()
  }

  @Monitor('safeMode.unlocked')
  onSafeModeUnlocked(): void {
    if (!this.safeMode.restricted() && (this.currentTab === 1 || this.currentTab === 2)) {
      const target: number = this.currentTab === 1 ? 3 : 4
      this.currentTab = target
      this.titleScroller = this.homeTabScrollers[target]
      setTimeout((): void => {
        this.tabsController.changeIndex(target)
      }, 0)
    }
  }

  // Push the search page, unless a search page is already on top (then its own @Monitor re-searches).
  private openSearch(focusOnAppear: boolean = true): void {
    if (this.safeMode.restricted()) {
      return
    }
    const names: string[] = this.stack.getAllPathName()
    if (names.length === 0 || names[names.length - 1] !== 'Search') {
      this.stack.pushPathByName('Search', new SearchPageParams('', 'a', '', focusOnAppear))
    }
  }

  // Push the ONE shared search page in FAVORITE scope (eros_fe goSearchPage(searchType: favorite),
  // navigator_util.dart:76-106). The scope + current favcat ride a route param; the search inherits the
  // last-shown favcat ('a' = all favorites → favorites.php omits favcat → searches all).
  private openFavoriteSearch(): void {
    if (this.safeMode.restricted()) {
      return
    }
    const favcat: string = connectFavSelection().selectedFavcat
    const names: string[] = this.stack.getAllPathName()
    if (names.length === 0 || names[names.length - 1] !== 'Search') {
      this.stack.pushPathByName('Search', new SearchPageParams('favorite', favcat))
    }
  }

  private openFavoriteSelector(): void {
    if (this.safeMode.restricted()) {
      return
    }
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
    if (this.safeMode.restricted()) {
      DiagnosticLogger.info('nav', 'safe_mode_deep_link_blocked', uri)
      return
    }
    const currentUri: string = EhUrlRouter.toCurrentHost(uri, EhConstants.baseUrl(connectSiteMode().isEx))
    if (uri === InternalQaRoutes.COVER_FALLBACK_PROBE_URI) {
      DiagnosticLogger.info('nav', 'internal_qa_open', 'cover-fallback')
      this.stack.pushPathByName('CoverFallbackProbe', null)
      return
    }
    if (uri === InternalQaRoutes.READER_GESTURE_PROBE_URI) {
      DiagnosticLogger.info('nav', 'internal_qa_open', 'reader-gesture')
      this.stack.pushPathByName('ReaderGestureProbe', null)
      return
    }
    const ref: GalleryRef | null = EhUrlRouter.parseGallery(currentUri)
    if (ref !== null) {
      DiagnosticLogger.info('nav', 'deep_link_open', `/g/${ref.gid}/${ref.token}`)
      if (EhUrlRouter.wantsComments(currentUri)) {
        this.stack.pushPathByName('GalleryComments', new GalleryCommentsParams(ref.gid, ref.token))
        return
      }
      this.stack.pushPathByName('GalleryDetail', new GalleryDetailParams(ref.gid, ref.token))
      return
    }
    if (EhUrlRouter.parseImagePage(currentUri) !== null) {
      DiagnosticLogger.info('nav', 'deep_link_open', '/s/')
      this.openImagePageUrl(currentUri)
    }
  }

  private openImagePageUrl(uri: string): void {
    ImagePageRouteService.resolve(uri)
      .then((target: ImagePageRouteTarget) => {
        this.stack.pushPathByName('GalleryDetail', new GalleryDetailParams(target.gid, target.token))
        this.confirmOpenImagePage(target)
      })
      .catch((err: Error) => {
        DiagnosticLogger.warn('nav', 'image_page_deep_link_failed', err.message)
        this.stack.pushPathByName('ImagePageRouteError', new ImagePageRouteErrorParams(uri))
      })
  }

  private confirmOpenImagePage(target: ImagePageRouteTarget): void {
    this.getUIContext().showAlertDialog({
      message: $r('app.string.image_page_jump_confirm', (target.index + 1).toString()),
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {},
      },
      secondaryButton: {
        value: $r('app.string.detail_read'),
        action: () => {
          this.stack.pushPathByName(
            'Reader',
            new ReaderParams(
              target.gid,
              target.token,
              target.index,
              target.fileCount,
              '',
              [target.seedImage],
              0,
              0,
            ),
          )
        },
      },
    })
  }

  private tabTitle(): ResourceStr {
    const tab: number = this.logicalCurrentTab()
    if (tab === 1) {
      return $r('app.string.tab_favorites')
    }
    if (tab === 2) {
      return $r('app.string.tab_toplist')
    }
    if (tab === 3) {
      return $r('app.string.tab_download')
    }
    if (tab === 4) {
      return $r('app.string.tab_settings')
    }
    return $r('app.string.tab_gallery')
  }

  private logicalCurrentTab(): number {
    if (this.safeMode.restricted() && this.currentTab === 1) {
      return 3
    }
    if (this.safeMode.restricted() && this.currentTab === 2) {
      return 4
    }
    return this.currentTab
  }

  private scrollActiveTabToTop(): void {
    this.titleScroller.scrollToIndex(0)
  }

  private setHomeActiveScroller(index: number, scroller: Scroller): void {
    const oldScroller: Scroller = this.homeTabScrollers[index]
    if (oldScroller === scroller) {
      if (this.homeTab.autoHide) {
        this.tabsController.bindScroller(index, scroller)
      }
      return
    }
    this.tabsController.unbindScroller(oldScroller)
    this.homeTabScrollers[index] = scroller
    if (this.currentTab === index) {
      this.titleScroller = scroller
    }
    if (this.homeTab.autoHide) {
      this.tabsController.bindScroller(index, scroller)
      this.restoreHomeTabIfHidden()
    }
  }

  // Re-tap of the already-active bottom tab: refresh that tab's ACTIVE sub-tab list (scroll-to-top +
  // pull-refresh) via the registry, keyed by the active sub-tab's Scroller we already track per tab.
  // No-op for tabs without a pull-refresh list (downloads/settings).
  private triggerRootRefresh(index: number): void {
    if (index < 0 || index >= this.homeTabScrollers.length) {
      return
    }
    RootRefreshRegistry.trigger(this.homeTabScrollers[index])
  }

  private applyHomeTabAutoHide(): void {
    if (this.homeTab.autoHide) {
      for (let index = 0; index < this.homeTabScrollers.length; index++) {
        this.tabsController.bindScroller(index, this.homeTabScrollers[index])
      }
      this.restoreHomeTabIfHidden()
      return
    }
    for (let index = 0; index < this.homeTabScrollers.length; index++) {
      this.tabsController.unbindScroller(this.homeTabScrollers[index])
    }
    this.restoreHomeTabIfHidden()
  }

  private restoreHomeTabIfHidden(): void {
    if (this.homeTabVisibleByScroll) {
      return
    }
    this.homeTabVisibleByScroll = true
    this.tabsController.applyShowAnimation(HdsAnimationMode.SCROLL_ANIMATION)
  }

  private clearHomeTabAnimationGuardTimer(): void {
    if (this.homeTabAnimationGuardTimerId === -1) {
      return
    }
    clearTimeout(this.homeTabAnimationGuardTimerId)
    this.homeTabAnimationGuardTimerId = -1
  }

  private startHomeTabAnimationGuardTimer(): void {
    this.clearHomeTabAnimationGuardTimer()
    this.homeTabAnimationGuardTimerId = setTimeout((): void => {
      this.homeTabAnimationGuardTimerId = -1
    }, this.HOME_TAB_ANIMATION_GUARD_MS)
  }

  private applyHomeTabScrollAnimation(visible: boolean): void {
    if (
      !this.homeTab.autoHide ||
      this.homeTabAnimationGuardTimerId !== -1 ||
      this.homeTabVisibleByScroll === visible
    ) {
      return
    }
    this.homeTabVisibleByScroll = visible
    if (visible) {
      this.tabsController.applyShowAnimation(HdsAnimationMode.SCROLL_ANIMATION)
    } else {
      this.tabsController.applyHideAnimation(HdsAnimationMode.SCROLL_ANIMATION)
    }
    this.startHomeTabAnimationGuardTimer()
  }

  private onHomeTabDidScroll(index: number, offset: number, state: ScrollState): void {
    if (index !== this.currentTab || !this.homeTab.autoHide) {
      this.homeTabLastScrollOffsets[index] = offset
      return
    }
    if (offset <= this.HOME_TAB_SCROLL_DELTA_PX) {
      this.homeTabLastScrollOffsets[index] = offset
      this.restoreHomeTabIfHidden()
      return
    }
    if (state === ScrollState.Idle) {
      this.homeTabLastScrollOffsets[index] = offset
      return
    }
    const lastOffset: number = this.homeTabLastScrollOffsets[index]
    this.homeTabLastScrollOffsets[index] = offset
    const delta: number = offset - lastOffset
    if (delta < -this.HOME_TAB_SCROLL_DELTA_PX) {
      this.applyHomeTabScrollAnimation(true)
      return
    }
    if (delta > this.HOME_TAB_SCROLL_DELTA_PX) {
      this.applyHomeTabScrollAnimation(false)
    }
  }

  private backToTopMenuItem(): Record<string, Object> {
    const topInner: Record<string, Object> = {
      'label': $r('app.string.common_back_to_top'),
      'icon': $r('sys.symbol.arrow_up'),
      'isEnabled': true,
      'action': () => {
        this.scrollActiveTabToTop()
      },
    }
    return { 'content': topInner }
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
    // Quick list-layout switcher (mirrors the 收藏 order action): the icon can't anchor a Menu, so it
    // asks HomePage (which owns an anchor node) to open the native layout dropdown via the command bus.
    const layoutInner: Record<string, Object> = {
      'label': $r('app.string.settings_view'),
      'icon': $r('sys.symbol.square_grid_2x2'),
      'isEnabled': true,
      'action': () => {
        HomeSourceBridge.publishOpenLayoutMenu()
      },
    }
    const items: Record<string, Object>[] = [
      { 'content': searchInner },
      { 'content': layoutInner },
      this.backToTopMenuItem(),
    ]
    return { 'value': items, 'maxCount': 3 }
  }

  private safeGalleryMenu(): Record<string, Object> {
    const layoutInner: Record<string, Object> = {
      'label': $r('app.string.settings_view'),
      'icon': $r('sys.symbol.square_grid_2x2'),
      'isEnabled': true,
      'action': () => {
        HomeSourceBridge.publishOpenLayoutMenu()
      },
    }
    const items: Record<string, Object>[] = [
      { 'content': layoutInner },
      this.backToTopMenuItem(),
    ]
    return { 'value': items, 'maxCount': 2 }
  }

  private topOnlyMenu(): Record<string, Object> {
    const items: Record<string, Object>[] = [this.backToTopMenuItem()]
    return { 'value': items, 'maxCount': 1 }
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
      this.backToTopMenuItem(),
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
    const items: Record<string, Object>[] = [{ 'content': selectorInner }, this.backToTopMenuItem()]
    return { 'value': items, 'maxCount': 2 }
  }

  private downloadMenu(): Record<string, Object> {
    const items: Record<string, Object>[] = []
    const resumeInner: Record<string, Object> = {
      'label': $r('app.string.download_resume_all'),
      'icon': $r('sys.symbol.arrow_clockwise'),
      'isEnabled': true,
      'action': () => {
        this.resumeVisibleDownloads()
      },
    }
    const pauseInner: Record<string, Object> = {
      'label': $r('app.string.download_pause_all'),
      'icon': $r('sys.symbol.pause'),
      'isEnabled': true,
      'action': () => {
        this.pauseVisibleDownloads()
      },
    }
    if (this.downloadHasResumable()) {
      items.push({ 'content': resumeInner })
    }
    if (this.downloadHasPausable()) {
      items.push({ 'content': pauseInner })
    }
    items.push(this.backToTopMenuItem())
    return { 'value': items, 'maxCount': items.length }
  }

  private downloadHasResumable(): boolean {
    if (this.downloadView.viewType === DownloadViewType.ARCHIVER) {
      return this.downloadQueue.archiverTasks.some((task: DownloadArchiverTask) => {
        return task.status === DownloadGalleryTaskStatus.QUEUED ||
          task.status === DownloadGalleryTaskStatus.PAUSED ||
          task.status === DownloadGalleryTaskStatus.ERROR
      })
    }
    return this.downloadQueue.galleryTasks.some((task: DownloadGalleryTask) => {
      return task.status === DownloadGalleryTaskStatus.QUEUED ||
        task.status === DownloadGalleryTaskStatus.READY ||
        task.status === DownloadGalleryTaskStatus.PAUSED ||
        task.status === DownloadGalleryTaskStatus.PARTIAL ||
        task.status === DownloadGalleryTaskStatus.ERROR
    })
  }

  private downloadHasPausable(): boolean {
    if (this.downloadView.viewType === DownloadViewType.ARCHIVER) {
      return this.downloadQueue.archiverTasks.some((task: DownloadArchiverTask) => {
        return task.status === DownloadGalleryTaskStatus.DOWNLOADING
      })
    }
    return this.downloadQueue.galleryTasks.some((task: DownloadGalleryTask) => {
      return task.status === DownloadGalleryTaskStatus.DOWNLOADING
    })
  }

  private resumeVisibleDownloads(): void {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext
    const task: Promise<void> = this.downloadView.viewType === DownloadViewType.ARCHIVER
      ? DownloadQueueSettings.resumeAllArchiverDownloads(context)
      : DownloadQueueSettings.resumeAllGalleryDownloads(context)
    task.catch((error: Error) => {
      DiagnosticLogger.warn('download', 'resume_all_visible_failed', error.message)
    })
  }

  private pauseVisibleDownloads(): void {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext
    const task: Promise<void> = this.downloadView.viewType === DownloadViewType.ARCHIVER
      ? DownloadQueueSettings.pauseAllArchiverDownloads(context)
      : DownloadQueueSettings.pauseAllGalleryDownloads(context)
    task.catch((error: Error) => {
      DiagnosticLogger.warn('download', 'pause_all_visible_failed', error.message)
    })
  }

  private bottomBuilder(
    content: ComponentContent<Object>,
    height: number = SELECTOR_BAR_HEIGHT,
  ): Record<string, Object> {
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
    const tab: number = this.logicalCurrentTab()
    if (tab === 0) {
      if (this.sourceBarContent === null) {
        this.sourceBarContent = new ComponentContent<Object>(
          this.getUIContext(),
          wrapBuilder<[Object]>(HomeSourceBarCCBuilder),
          new Object(),
        )
      }
      content['bottomBuilder'] = this.bottomBuilder(this.sourceBarContent)
      content['menu'] = this.safeMode.restricted() ? this.safeGalleryMenu() : this.searchMenu()
    } else if (tab === 1) {
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
      if (tab === 2) {
        if (this.periodBarContent === null) {
          this.periodBarContent = new ComponentContent<Object>(
            this.getUIContext(),
            wrapBuilder<[Object]>(ToplistPeriodBarCCBuilder),
            new Object(),
          )
        }
        content['bottomBuilder'] = this.bottomBuilder(this.periodBarContent)
        content['menu'] = this.topOnlyMenu()
      }
      if (tab === 3) {
        if (this.downloadTypeBarContent === null) {
          this.downloadTypeBarContent = new ComponentContent<Object>(
            this.getUIContext(),
            wrapBuilder<[Object]>(DownloadTypeBarCCBuilder),
            new Object(),
          )
        }
        content['bottomBuilder'] = this.bottomBuilder(
          this.downloadTypeBarContent,
          DOWNLOAD_SELECTOR_BAR_HEIGHT,
        )
        content['menu'] = this.downloadMenu()
      }
      if (tab !== 2 && tab !== 3) {
        content['menu'] = this.emptyMenu()
      }
    }
    // Wrap with V2Next's immersive title-bar style (GRADIENT_BLUR scroll effect + immersive material)
    // so content scrolling under the status bar / title bar is progressively blurred, not shown sharp.
    return immersiveTitleBarOpts(content)
  }

  @Builder
  routerMap(name: string) {
    if (!SafeModeGate.routeAllowed(name)) {
      Column() {}
    } else if (name === 'GalleryDetail') {
      GalleryDetailPage()
    } else if (name === 'GalleryInfo') {
      GalleryInfoPage()
    } else if (name === 'GalleryTorrents') {
      GalleryTorrentsPage()
    } else if (name === 'GalleryArchiver') {
      GalleryArchiverPage()
    } else if (name === 'GalleryWeb') {
      GalleryWebPage()
    } else if (name === 'GalleryEditTags') {
      GalleryEditTagsPage()
    } else if (name === 'Search') {
      GallerySearchPage()
    } else if (name === 'Reader') {
      ReaderPage()
    } else if (name === 'EhLogin') {
      EhLoginWebPage()
    } else if (name === 'EhCookieImport') {
      EhCookieImportPage()
    } else if (name === 'EhPasswordLogin') {
      EhPasswordLoginPage()
    } else if (name === 'MyTags') {
      MyTagsPage()
    } else if (name === 'History') {
      ViewedHistoryPage()
    } else if (name === 'FavoriteSelector') {
      FavoriteSelectorPage()
    } else if (name === 'TabManager') {
      TabManagerPage()
    } else if (name === 'TabEdit') {
      TabEditPage()
    } else if (name === 'AllThumbnails') {
      GalleryAllThumbnailsPage()
    } else if (name === 'GalleryComments') {
      GalleryCommentsPage()
    } else if (name === 'EhSettings') {
      EhSettingsPage()
    } else if (name === 'EhProfileSettings') {
      EhProfileSettingsPage()
    } else if (name === 'Account') {
      AccountPage()
    } else if (name === 'AccountLogin') {
      AccountLoginPage()
    } else if (name === 'LayoutSettings') {
      LayoutSettingsPage()
    } else if (name === 'ColumnDensity') {
      ColumnDensityPage()
    } else if (name === 'CacheSettings') {
      CacheSettingsPage()
    } else if (name === 'ReaderSettings') {
      ReaderSettingsPage()
    } else if (name === 'DownloadSettings') {
      DownloadSettingsPage()
    } else if (name === 'SearchSettings') {
      SearchSettingsPage()
    } else if (name === 'LocalBlockSettings') {
      LocalBlockSettingsPage()
    } else if (name === 'TagTranslationSettings') {
      TagTranslationSettingsPage()
    } else if (name === 'TranslationSettings') {
      TranslationSettingsPage()
    } else if (name === 'SyncSettings') {
      SyncSettingsPage()
    } else if (name === 'WebDavSyncSettings') {
      WebDavSyncSettingsPage()
    } else if (name === 'AdvancedSettings') {
      AdvancedSettingsPage()
    } else if (name === 'SecuritySettings') {
      SecuritySettingsPage()
    } else if (name === 'About') {
      AboutPage()
    } else if (name === 'ImagePageRouteError') {
      ImagePageRouteErrorPage()
    } else if (name === 'CoverFallbackProbe') {
      CoverFallbackProbePage()
    } else if (name === 'ReaderGestureProbe') {
      ReaderGestureProbePage()
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
            onDidScroll: (offset: number, state: ScrollState) => {
              this.onHomeTabDidScroll(0, offset, state)
            },
          })
        }.tabBar(this.tabIcon($r('app.string.tab_gallery'), 0))
        if (this.safeMode.restricted()) {
          TabContent() {
            DownloadQueuePage({
              scroller: this.homeTabScrollers[1],
              onDidScroll: (offset: number, state: ScrollState) => {
                this.onHomeTabDidScroll(1, offset, state)
              },
            })
          }.tabBar(this.tabIcon($r('app.string.tab_download'), 1))
          TabContent() {
            SettingsPage({
              scroller: this.homeTabScrollers[2],
              onDidScroll: (offset: number, state: ScrollState) => {
                this.onHomeTabDidScroll(2, offset, state)
              },
            })
          }.tabBar(this.tabIcon($r('app.string.tab_settings'), 2))
        } else {
          TabContent() {
            // Retained per-favcat sub-tabs own their own scrollers; FavoritesPage reports the ACTIVE favcat's
            // scroller up so the title auto-hide binds the right list (V2Next onScrollerReady chain).
            FavoritesPage({
              onScrollerReady: (scroller: Scroller) => {
                this.setHomeActiveScroller(1, scroller)
              },
              onDidScroll: (offset: number, state: ScrollState) => {
                this.onHomeTabDidScroll(1, offset, state)
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
              onDidScroll: (offset: number, state: ScrollState) => {
                this.onHomeTabDidScroll(2, offset, state)
              },
            })
          }.tabBar(this.tabIcon($r('app.string.tab_toplist'), 2))
          TabContent() {
            DownloadQueuePage({
              scroller: this.homeTabScrollers[3],
              onDidScroll: (offset: number, state: ScrollState) => {
                this.onHomeTabDidScroll(3, offset, state)
              },
            })
          }.tabBar(this.tabIcon($r('app.string.tab_download'), 3))
          TabContent() {
            SettingsPage({
              scroller: this.homeTabScrollers[4],
              onDidScroll: (offset: number, state: ScrollState) => {
                this.onHomeTabDidScroll(4, offset, state)
              },
            })
          }.tabBar(this.tabIcon($r('app.string.tab_settings'), 4))
        }
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
          materialType: ImmersiveMaterialSettings.effect(this.immersiveMaterial.level).materialType,
          materialLevel: ImmersiveMaterialSettings.effect(this.immersiveMaterial.level)
            .materialLevel,
        },
      })
      .onAppear(() => {
        this.applyHomeTabAutoHide()
      })
      .onChange((index: number) => {
        this.currentTab = index
        // Rebind the title bar to the newly-active tab's scroller so it auto-hides off that list.
        this.titleScroller = this.homeTabScrollers[index]
        if (this.homeTab.autoHide) {
          this.restoreHomeTabIfHidden()
        }
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
    MainTabIcon({
      title: title,
      idx: idx,
      iconIdx: this.safeMode.restricted() && idx === 1 ? 3 : (this.safeMode.restricted() && idx === 2 ? 4 : idx),
      currentIndex: this.currentTab,
      onSelectedClick: (i: number) => {
        this.triggerRootRefresh(i)
      },
    })
  }
}
