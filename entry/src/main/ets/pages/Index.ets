import {
  HdsNavigation,
  HdsTabs,
  HdsTabsController,
  HdsNavigationTitleMode,
  HdsAnimationMode,
  hdsMaterial,
  BottomBuilderShowType,
  HideMode,
  HdsNavDestination,
  HdsSnackBar,
  SnackBarIconOptions,
  SnackBarMessageOptions,
  SnackBarOperationOptions,
  SnackBarOperationType,
  SnackBarStyleOptions,
} from '@kit.UIDesignKit'
import { ComponentContent, curves } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import {
  connectNavStack,
  NavStackHolder,
  connectPendingEhUrl,
  ClipboardLinkCandidateState,
  connectClipboardLinkCandidate,
  ThemeConstants,
  DiagnosticLogger,
  PendingEhUrlState,
  EhConstants,
  EhUrlRouter,
  GalleryRef,
  ImagePageRef,
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
  DownloadQueueSignalState,
  DownloadViewState,
  DownloadViewType,
  connectSearchAction,
  SearchActionState,
  connectSiteMode,
  connectAuth,
  AuthState,
  FavSelectionBridge,
  HomeSourceBridge,
  connectHomeTabAutoHide,
  HomeTabAutoHideState,
  SearchPageParams,
  SELECTOR_BAR_HEIGHT,
  DOWNLOAD_SELECTOR_BAR_HEIGHT,
  connectDownloadQueue,
  connectDownloadQueueSignal,
  connectDownloadView,
  setDownloadQueuePageActive,
  immersiveTitleBarOpts,
  ImmersiveMaterialSettings,
  ImmersiveMaterialSettingsState,
  connectImmersiveMaterialSettings,
  InternalQaRoutes,
  RootRefreshRegistry,
  SafeModeGate,
  SafeModeState,
  connectSafeMode,
  SecuritySettings,
  SecuritySettingsState,
  connectSecuritySettings,
  ListMode,
  ReaderOverlayNavigationState,
  connectReaderOverlayNavigation,
  TabletLayoutSettings,
  TabletLayoutState,
  connectTabletLayout,
  LayoutSafeAreaState,
  connectLayoutSafeArea,
  GalleryDetailTransitionState,
  GalleryDetailTransitionPhase,
  connectGalleryDetailTransition,
  GalleryDetailTransitionCoordinator,
  ThemeDisplayState,
  connectThemeDisplay,
  EhSpriteThumbnail,
  EhImageKnifeImage,
  ReaderThumbnailTransitionState,
  connectReaderThumbnailTransition,
} from 'shared'
import { MainTabIcon } from '../components/MainTabIcon'
import { HomeSourceBarCCBuilder } from '../components/HomeSourceBar'
import { ToplistPeriodBarCCBuilder } from '../components/ToplistPeriodBar'
import { FavcatBarCCBuilder } from '../components/FavcatBar'
import { DownloadTitleBarCCBuilder } from '../components/DownloadTypeBar'
import { IndexRouteCoordinator } from '../model/IndexRouteCoordinator'
import type { IndexDestinationFamily } from '../model/IndexRouteCoordinator'
import { HomePage, ToplistPage, TabManagerPage, TabEditPage } from 'home'
import { GallerySearchPage } from 'search'
import { FavoriteSelectorPage, FavoritesPage, MyTagsPage, ViewedHistoryPage } from 'user'
import {
  SettingsPage,
  EhSettingsPage,
  EhProfileSettingsPage,
  AccountPage,
  AccountLoginPage,
  AccountCookiePage,
  LayoutSettingsPage,
  ColumnDensityPage,
  CacheSettingsPage,
  ReaderSettingsPage,
  ReaderSuperResolutionModelsPage,
  DownloadSettingsPage,
  SearchSettingsPage,
  LocalBlockSettingsPage,
  ImageBlockSettingsPage,
  TagTranslationSettingsPage,
  CommentTranslationSettingsPage,
  ComicTranslationSettingsPage,
  ToriiWholePageLiveEvaluationPage,
  MangaRenderingServiceSettingsPage,
  LlmSourceManagerPage,
  LlmSourceDetailPage,
  SyncSettingsPage,
  WebDavSyncSettingsPage,
  AdvancedSettingsPage,
  SecuritySettingsPage,
  AboutPage,
  SystemSymbolBrowserPage,
} from 'settings'
import {
  GalleryDetailPage,
  GalleryInfoPage,
  GalleryTorrentsPage,
  GalleryArchiverPage,
  GalleryAllThumbnailsPage,
  GalleryCommentsPage,
} from 'gallery'
import { ReaderPage } from 'reader'
import { DownloadQueuePage, DOWNLOAD_PINNED_TASK_GROUP_HEADER_HEIGHT } from 'download'
import { EhLoginWebPage } from './EhLoginWebPage'
import { EhCookieImportPage } from './EhCookieImportPage'
import { EhPasswordLoginPage } from './EhPasswordLoginPage'
import { CoverFallbackProbePage } from './CoverFallbackProbePage'
import { ReaderGestureProbePage } from './ReaderGestureProbePage'
import { ImagePageRouteErrorPage } from './ImagePageRouteErrorPage'
import { GalleryWebPage } from './GalleryWebPage'

const GALLERY_DETAIL_OPEN_CURVE: curves.ICurve = curves.cubicBezierCurve(0.2, 0, 0, 1)
const GALLERY_DETAIL_CLOSE_CURVE: curves.ICurve = curves.cubicBezierCurve(0.3, 0, 0.2, 1)
// Crossfade thresholds describe spatial window progress, not elapsed time. Curve changes therefore
// keep the card/detail handoff at the same visible window size.
const GALLERY_DETAIL_OPEN_CARD_EXIT_START_PROGRESS: number = 0
const GALLERY_DETAIL_OPEN_CARD_EXIT_END_PROGRESS: number = 0.55
const GALLERY_DETAIL_CLOSE_CARD_ENTRY_START_PROGRESS: number = 0.55
const GALLERY_DETAIL_CLOSE_CARD_ENTRY_END_PROGRESS: number = 0.9
// The captured source card hands off as one rounded surface. These are spatial progress thresholds:
// curve changes cannot move its fade to a different expanded-card size.
const GALLERY_DETAIL_COVER_OPEN_CARD_EXIT_START_PROGRESS: number = 0.15
const GALLERY_DETAIL_COVER_OPEN_CARD_EXIT_END_PROGRESS: number = 0.5
const GALLERY_DETAIL_COVER_CLOSE_CARD_ENTRY_START_PROGRESS: number = 0.5
const GALLERY_DETAIL_COVER_CLOSE_CARD_ENTRY_END_PROGRESS: number = 0.75
const GALLERY_DETAIL_CURVE_INVERSE_ITERATIONS: number = 16

function galleryDetailTimeAtProgress(curve: curves.ICurve, targetProgress: number): number {
  const boundedTarget: number = Math.max(0, Math.min(1, targetProgress))
  let lower: number = 0
  let upper: number = 1
  for (let index: number = 0; index < GALLERY_DETAIL_CURVE_INVERSE_ITERATIONS; index += 1) {
    const candidate: number = (lower + upper) / 2
    if (curve.interpolate(candidate) < boundedTarget) {
      lower = candidate
    } else {
      upper = candidate
    }
  }
  return (lower + upper) / 2
}

const GALLERY_DETAIL_OPEN_CARD_EXIT_START_TIME: number = galleryDetailTimeAtProgress(
  GALLERY_DETAIL_OPEN_CURVE,
  GALLERY_DETAIL_OPEN_CARD_EXIT_START_PROGRESS,
)
const GALLERY_DETAIL_OPEN_CARD_EXIT_END_TIME: number = galleryDetailTimeAtProgress(
  GALLERY_DETAIL_OPEN_CURVE,
  GALLERY_DETAIL_OPEN_CARD_EXIT_END_PROGRESS,
)
const GALLERY_DETAIL_COVER_OPEN_CARD_EXIT_START_TIME: number = galleryDetailTimeAtProgress(
  GALLERY_DETAIL_OPEN_CURVE,
  GALLERY_DETAIL_COVER_OPEN_CARD_EXIT_START_PROGRESS,
)
const GALLERY_DETAIL_COVER_OPEN_CARD_EXIT_END_TIME: number = galleryDetailTimeAtProgress(
  GALLERY_DETAIL_OPEN_CURVE,
  GALLERY_DETAIL_COVER_OPEN_CARD_EXIT_END_PROGRESS,
)
const GALLERY_DETAIL_CLOSE_CARD_ENTRY_START_TIME: number = galleryDetailTimeAtProgress(
  GALLERY_DETAIL_CLOSE_CURVE,
  GALLERY_DETAIL_CLOSE_CARD_ENTRY_START_PROGRESS,
)
const GALLERY_DETAIL_COVER_CLOSE_CARD_ENTRY_START_TIME: number = galleryDetailTimeAtProgress(
  GALLERY_DETAIL_CLOSE_CURVE,
  GALLERY_DETAIL_COVER_CLOSE_CARD_ENTRY_START_PROGRESS,
)
const GALLERY_DETAIL_COVER_CLOSE_CARD_ENTRY_END_TIME: number = galleryDetailTimeAtProgress(
  GALLERY_DETAIL_CLOSE_CURVE,
  GALLERY_DETAIL_COVER_CLOSE_CARD_ENTRY_END_PROGRESS,
)
const GALLERY_DETAIL_CLOSE_CARD_ENTRY_END_TIME: number = galleryDetailTimeAtProgress(
  GALLERY_DETAIL_CLOSE_CURVE,
  GALLERY_DETAIL_CLOSE_CARD_ENTRY_END_PROGRESS,
)

@Builder
function IndexEmptyDestinationRoute() {
  Column() {}
}

@Builder
function IndexGalleryDetailRoute() {
  GalleryDetailPage()
}

@Builder
function IndexGalleryInfoRoute() {
  GalleryInfoPage()
}

@Builder
function IndexGalleryTorrentsRoute() {
  GalleryTorrentsPage()
}

@Builder
function IndexGalleryArchiverRoute() {
  GalleryArchiverPage()
}

@Builder
function IndexGalleryWebRoute() {
  GalleryWebPage()
}

@Builder
function IndexSearchRoute() {
  GallerySearchPage()
}

@Builder
function IndexReaderOverlayBackdropRoute() {
  HdsNavDestination() {
    Column() {}
      .id('reader-overlay-backdrop')
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)
  }
  .hideTitleBar(true)
  .backgroundColor(Color.Transparent)
}

@ComponentV2
struct IndexReaderThumbnailTransitionProxy {
  @Require @Param state: ReaderThumbnailTransitionState;

  build() {
    if (this.state.targetVisible()) {
      Stack({ alignContent: Alignment.Center }) {
        if (this.state.openingReverse() && this.state.openingReverseSnapshot !== undefined) {
          // Once the decoded Reader image has begun taking ownership, reverse from those exact
          // pixels instead of visibly dropping back to the click-time thumbnail at full size.
          Image(this.state.openingReverseSnapshot)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Fill)
            .syncLoad(true)
        } else if (this.state.sourceSnapshot !== undefined) {
          // Preserve the exact click-time pixels for the whole flight. The measured proxy bounds are
          // the contained image bounds, so this never stretches a fixed thumbnail slot or reloads a
          // second sprite while the real source is hidden.
          Image(this.state.sourceSnapshot)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Fill)
            .syncLoad(true)
        } else {
          EhSpriteThumbnail({
            url: this.state.image.thumbUrl,
            thumbWidth: this.state.image.thumbWidth,
            thumbHeight: this.state.image.thumbHeight,
            offsetX: this.state.image.thumbOffsetX,
            imageKey: this.state.image.imgkey,
            spriteWidth: this.state.image.spriteWidth,
            spriteHeight: this.state.image.spriteHeight,
            displayWidth: this.state.proxyWidth,
            radius: 0,
          })
        }
      }
      .width(this.state.proxyWidth)
      .height(this.state.proxyHeight)
      .position({
        x: this.state.proxyX,
        y: this.state.proxyY,
      })
      .borderRadius(this.state.proxyRadius)
      .clip(true)
      .opacity(this.state.openingProxyOpacity)
      .hitTestBehavior(HitTestMode.None)
    }
  }
}

@Builder
function IndexEhLoginRoute() {
  EhLoginWebPage()
}

@Builder
function IndexEhCookieImportRoute() {
  EhCookieImportPage()
}

@Builder
function IndexEhPasswordLoginRoute() {
  EhPasswordLoginPage()
}

@Builder
function IndexMyTagsRoute() {
  MyTagsPage()
}

@Builder
function IndexHistoryRoute() {
  ViewedHistoryPage()
}

@Builder
function IndexFavoriteSelectorRoute() {
  FavoriteSelectorPage()
}

@Builder
function IndexTabManagerRoute() {
  TabManagerPage()
}

@Builder
function IndexTabEditRoute() {
  TabEditPage()
}

@Builder
function IndexAllThumbnailsRoute() {
  GalleryAllThumbnailsPage()
}

@Builder
function IndexGalleryCommentsRoute() {
  GalleryCommentsPage()
}

@Builder
function IndexEhSettingsRoute() {
  EhSettingsPage()
}

@Builder
function IndexEhProfileSettingsRoute() {
  EhProfileSettingsPage()
}

@Builder
function IndexAccountRoute() {
  AccountPage()
}

@Builder
function IndexAccountLoginRoute() {
  AccountLoginPage()
}

@Builder
function IndexAccountCookieRoute() {
  AccountCookiePage()
}

@Builder
function IndexLayoutSettingsRoute() {
  LayoutSettingsPage()
}

@Builder
function IndexColumnDensityRoute() {
  ColumnDensityPage()
}

@Builder
function IndexThumbnailColumnDensityRoute() {
  ColumnDensityPage({ targetMode: ListMode.THUMBNAIL_GRID })
}

@Builder
function IndexCacheSettingsRoute() {
  CacheSettingsPage()
}

@Builder
function IndexReaderSettingsRoute() {
  ReaderSettingsPage()
}

@Builder
function IndexReaderSuperResolutionModelsRoute() {
  ReaderSuperResolutionModelsPage()
}

@Builder
function IndexDownloadSettingsRoute() {
  DownloadSettingsPage()
}

@Builder
function IndexSearchSettingsRoute() {
  SearchSettingsPage()
}

@Builder
function IndexLocalBlockSettingsRoute() {
  LocalBlockSettingsPage()
}

@Builder
function IndexImageBlockSettingsRoute() {
  ImageBlockSettingsPage()
}

@Builder
function IndexTagTranslationSettingsRoute() {
  TagTranslationSettingsPage()
}

@Builder
function IndexCommentTranslationSettingsRoute() {
  CommentTranslationSettingsPage()
}

@Builder
function IndexComicTranslationSettingsRoute() {
  ComicTranslationSettingsPage()
}

@Builder
function IndexToriiWholePageLiveEvaluationRoute() {
  ToriiWholePageLiveEvaluationPage()
}

@Builder
function IndexMangaRenderingServiceSettingsRoute() {
  MangaRenderingServiceSettingsPage()
}

@Builder
function IndexLlmSourceManagerRoute() {
  LlmSourceManagerPage()
}

@Builder
function IndexLlmSourceDetailRoute() {
  LlmSourceDetailPage()
}

@Builder
function IndexSyncSettingsRoute() {
  SyncSettingsPage()
}

@Builder
function IndexWebDavSyncSettingsRoute() {
  WebDavSyncSettingsPage()
}

@Builder
function IndexAdvancedSettingsRoute() {
  AdvancedSettingsPage()
}

@Builder
function IndexSecuritySettingsRoute() {
  SecuritySettingsPage()
}

@Builder
function IndexAboutRoute() {
  AboutPage()
}

@Builder
function IndexSystemSymbolBrowserRoute() {
  SystemSymbolBrowserPage()
}

@Builder
function IndexImagePageRouteErrorRoute() {
  ImagePageRouteErrorPage()
}

@Builder
function IndexCoverFallbackProbeRoute() {
  CoverFallbackProbePage()
}

@Builder
function IndexReaderGestureProbeRoute() {
  ReaderGestureProbePage()
}

@ComponentV2
struct IndexSplitPlaceholder {
  // HDS keeps splitPlaceholder as a cached ComponentContent. Reading this signal makes the cached
  // placeholder repaint when the app switches between light and dark mode.
  @Local themeDisplay: ThemeDisplayState = connectThemeDisplay();

  private themeTracked(color: ResourceColor): ResourceColor {
    return this.themeDisplay.effectiveDark ? color : color
  }

  build() {
    Column({ space: ThemeConstants.SPACE_MD }) {
      SymbolGlyph($r('sys.symbol.rectangle_split_1x2'))
        .fontSize(ThemeConstants.FONT_SIZE_H1)
        .fontColor([this.themeTracked($r('sys.color.font_tertiary'))])
      Text($r('app.string.tablet_select_detail'))
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor(this.themeTracked($r('sys.color.font_tertiary')))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.themeTracked($r('sys.color.ohos_id_color_sub_background')))
  }
}

@Builder
function IndexSplitPlaceholderCCBuilder(_state: Object) {
  IndexSplitPlaceholder()
}

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
  @Local navStackHolder: NavStackHolder = connectNavStack();
  @Local galleryDetailTransition: GalleryDetailTransitionState = connectGalleryDetailTransition();
  @Local tabletLayout: TabletLayoutState = connectTabletLayout();
  @Local layoutSafeArea: LayoutSafeAreaState = connectLayoutSafeArea();
  private galleryDetailTransitionSerial: number = 0;
  private stack: NavPathStack = connectNavStack().stack;
  private tabsController: HdsTabsController = new HdsTabsController();
  private emptyDestinationBuilder: WrappedBuilder<[]> = wrapBuilder<[]>(IndexEmptyDestinationRoute);
  private mappedDestinationBuilders: Record<string, WrappedBuilder<[]>> = {
    'galleryDetail': wrapBuilder<[]>(IndexGalleryDetailRoute),
    'galleryInfo': wrapBuilder<[]>(IndexGalleryInfoRoute),
    'galleryTorrents': wrapBuilder<[]>(IndexGalleryTorrentsRoute),
    'galleryArchiver': wrapBuilder<[]>(IndexGalleryArchiverRoute),
    'galleryWeb': wrapBuilder<[]>(IndexGalleryWebRoute),
    'search': wrapBuilder<[]>(IndexSearchRoute),
    'ehLogin': wrapBuilder<[]>(IndexEhLoginRoute),
    'ehCookieImport': wrapBuilder<[]>(IndexEhCookieImportRoute),
    'ehPasswordLogin': wrapBuilder<[]>(IndexEhPasswordLoginRoute),
    'myTags': wrapBuilder<[]>(IndexMyTagsRoute),
    'history': wrapBuilder<[]>(IndexHistoryRoute),
    'favoriteSelector': wrapBuilder<[]>(IndexFavoriteSelectorRoute),
    'tabManager': wrapBuilder<[]>(IndexTabManagerRoute),
    'tabEdit': wrapBuilder<[]>(IndexTabEditRoute),
    'allThumbnails': wrapBuilder<[]>(IndexAllThumbnailsRoute),
    'galleryComments': wrapBuilder<[]>(IndexGalleryCommentsRoute),
    'ehSettings': wrapBuilder<[]>(IndexEhSettingsRoute),
    'ehProfileSettings': wrapBuilder<[]>(IndexEhProfileSettingsRoute),
    'account': wrapBuilder<[]>(IndexAccountRoute),
    'accountLogin': wrapBuilder<[]>(IndexAccountLoginRoute),
    'accountCookie': wrapBuilder<[]>(IndexAccountCookieRoute),
    'layoutSettings': wrapBuilder<[]>(IndexLayoutSettingsRoute),
    'columnDensity': wrapBuilder<[]>(IndexColumnDensityRoute),
    'thumbnailColumnDensity': wrapBuilder<[]>(IndexThumbnailColumnDensityRoute),
    'cacheSettings': wrapBuilder<[]>(IndexCacheSettingsRoute),
    'readerSettings': wrapBuilder<[]>(IndexReaderSettingsRoute),
    'readerSuperResolutionModels': wrapBuilder<[]>(IndexReaderSuperResolutionModelsRoute),
    'downloadSettings': wrapBuilder<[]>(IndexDownloadSettingsRoute),
    'searchSettings': wrapBuilder<[]>(IndexSearchSettingsRoute),
    'localBlockSettings': wrapBuilder<[]>(IndexLocalBlockSettingsRoute),
    'imageBlockSettings': wrapBuilder<[]>(IndexImageBlockSettingsRoute),
    'tagTranslationSettings': wrapBuilder<[]>(IndexTagTranslationSettingsRoute),
    'commentTranslationSettings': wrapBuilder<[]>(IndexCommentTranslationSettingsRoute),
    'comicTranslationSettings': wrapBuilder<[]>(IndexComicTranslationSettingsRoute),
    'toriiWholePageLiveEvaluation': wrapBuilder<[]>(IndexToriiWholePageLiveEvaluationRoute),
    'mangaRenderingServiceSettings': wrapBuilder<[]>(IndexMangaRenderingServiceSettingsRoute),
    'llmSourceManager': wrapBuilder<[]>(IndexLlmSourceManagerRoute),
    'llmSourceDetail': wrapBuilder<[]>(IndexLlmSourceDetailRoute),
    'syncSettings': wrapBuilder<[]>(IndexSyncSettingsRoute),
    'webDavSyncSettings': wrapBuilder<[]>(IndexWebDavSyncSettingsRoute),
    'advancedSettings': wrapBuilder<[]>(IndexAdvancedSettingsRoute),
    'securitySettings': wrapBuilder<[]>(IndexSecuritySettingsRoute),
    'about': wrapBuilder<[]>(IndexAboutRoute),
    'systemSymbolBrowser': wrapBuilder<[]>(IndexSystemSymbolBrowserRoute),
    'imagePageRouteError': wrapBuilder<[]>(IndexImagePageRouteErrorRoute),
    'coverFallbackProbe': wrapBuilder<[]>(IndexCoverFallbackProbeRoute),
    'readerGestureProbe': wrapBuilder<[]>(IndexReaderGestureProbeRoute),
  };
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
  private downloadTitleBarContent: ComponentContent<Object> | null = null;
  private splitPlaceholderContent: ComponentContent<Object> | null = null;
  @Local pendingEhUrl: PendingEhUrlState = connectPendingEhUrl();
  @Local clipboardCandidate: ClipboardLinkCandidateState = connectClipboardLinkCandidate();
  @Local searchAction: SearchActionState = connectSearchAction();
  // Read so the 收藏 menu gates remote-only actions on login while the local favcat bar stays visible.
  // Mirrors HomeSourceBar gating 订阅 on isLogin.
  @Local auth: AuthState = connectAuth();
  @Local safeMode: SafeModeState = connectSafeMode();
  @Local securitySettings: SecuritySettingsState = connectSecuritySettings();
  @Local homeTab: HomeTabAutoHideState = connectHomeTabAutoHide();
  @Local immersiveMaterial: ImmersiveMaterialSettingsState = connectImmersiveMaterialSettings();
  @Local downloadView: DownloadViewState = connectDownloadView();
  @Local downloadQueueSignal: DownloadQueueSignalState = connectDownloadQueueSignal();
  @Local currentTab: number = 0;
  @Local readerOverlay: ReaderOverlayNavigationState = connectReaderOverlayNavigation();
  @Local readerThumbnailTransition: ReaderThumbnailTransitionState = connectReaderThumbnailTransition();
  private lastHandledSignal: string = '';
  private lastHandledClipboardCandidateSignal: string = '';
  private clipboardSnackBar: HdsSnackBar = new HdsSnackBar(this.getUIContext());
  private lastHandledQuery: string = '';
  private readonly IMAGE_BLOCK_QA_GID: string = '3049882';
  private readonly IMAGE_BLOCK_QA_TOKEN: string = 'd7e740a39e';
  private readonly IMAGE_BLOCK_QA_FILE_COUNT: number = 6;
  private readonly IMAGE_BLOCK_QA_TITLE: string = '[pulpawoelbo] D.VA advertisement (Overwatch)';

  aboutToAppear(): void {
    this.readerOverlay.reset()
    this.handlePendingEhUrl()
    this.handleClipboardLinkCandidate()
    this.syncDownloadQueuePageActive()
  }

  aboutToDisappear(): void {
    setDownloadQueuePageActive(false)
    this.clearHomeTabAnimationGuardTimer()
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private mappedDestinationBuilder(family: IndexDestinationFamily): WrappedBuilder<[]> {
    return this.mappedDestinationBuilders[family] || this.emptyDestinationBuilder
  }

  @Monitor('pendingEhUrl.signal')
  onPendingEhUrl(): void {
    this.handlePendingEhUrl()
  }

  @Monitor('clipboardCandidate.signal')
  onClipboardLinkCandidate(): void {
    this.handleClipboardLinkCandidate()
  }

  @Monitor('securitySettings.locked', 'readerOverlay.visible')
  onClipboardPromptGateChanged(): void {
    this.handleClipboardLinkCandidate()
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
  onSafeModeChanged(): void {
    let target: number = this.currentTab
    if (this.safeMode.restricted()) {
      if (this.currentTab === 3) {
        target = 1
      } else if (this.currentTab === 4) {
        target = 2
      } else if (this.currentTab === 1 || this.currentTab === 2) {
        target = 0
      }
    } else if (this.currentTab === 1 || this.currentTab === 2) {
      target = this.currentTab === 1 ? 3 : 4
    }
    if (target !== this.currentTab) {
      this.currentTab = target
      this.titleScroller = this.homeTabScrollers[target]
      this.syncDownloadQueuePageActive()
      setTimeout((): void => {
        this.tabsController.changeIndex(target)
      }, 0)
    }
    this.handleClipboardLinkCandidate()
  }

  private handleClipboardLinkCandidate(): void {
    const signal: string = this.clipboardCandidate.signal
    if (
      signal.length === 0 ||
      signal === this.lastHandledClipboardCandidateSignal ||
      this.safeMode.restricted() ||
      this.securitySettings.locked ||
      this.readerOverlay.visible
    ) {
      return
    }
    const sep: number = signal.indexOf(':')
    const uri: string = sep >= 0 ? signal.substring(sep + 1) : signal
    if (!EhUrlRouter.canHandle(uri)) {
      this.lastHandledClipboardCandidateSignal = signal
      return
    }
    this.lastHandledClipboardCandidateSignal = signal
    const galleryRef: GalleryRef | null = EhUrlRouter.parseGallery(uri)
    const imageRef: ImagePageRef | null = EhUrlRouter.parseImagePage(uri)
    const imagePageNumber: number = imageRef === null ? 1 : imageRef.page + 1
    const content: ResourceStr = galleryRef !== null
      ? $r('app.string.clipboard_link_snackbar_gallery', galleryRef.gid)
      : $r('app.string.clipboard_link_snackbar_image', imagePageNumber.toString())
    const icon: SnackBarIconOptions = {
      icon: $r('sys.symbol.link'),
    }
    const message: SnackBarMessageOptions = {
      title: $r('app.string.clipboard_link_snackbar_title'),
      content: content,
    }
    const operation: SnackBarOperationOptions = {
      operationType: SnackBarOperationType.TEXT_WITH_CLOSE,
      content: $r('app.string.clipboard_link_open'),
      contentAccessibilityText: $r('app.string.clipboard_link_open_accessibility'),
      closeButtonAccessibilityText: $r('app.string.clipboard_link_close_accessibility'),
      onContentClick: () => {
        this.clipboardSnackBar.dismiss()
        this.openEhUrl(uri)
      },
      onCloseButtonClick: () => {
        this.clipboardSnackBar.dismiss()
      },
    }
    const style: SnackBarStyleOptions = {
      duration: 0,
    }
    this.clipboardSnackBar.dismiss()
    this.clipboardSnackBar.show(icon, message, operation, style)
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
  // navigator_util.dart:76-106). Search defaults to all remote favorites; an explicit folder is chosen
  // inside the Search filter sheet rather than inherited invisibly from the Favorites tab.
  private openFavoriteSearch(): void {
    if (this.safeMode.restricted()) {
      return
    }
    const names: string[] = this.stack.getAllPathName()
    if (names.length === 0 || names[names.length - 1] !== 'Search') {
      this.stack.pushPathByName('Search', new SearchPageParams('favorite', 'a'))
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
    this.openEhUrl(uri)
  }

  private openEhUrl(uri: string): void {
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
      this.readerOverlay.openGestureProbe()
      return
    }
    if (uri === InternalQaRoutes.IMAGE_BLOCK_READER_OPEN_URI) {
      DiagnosticLogger.info('nav', 'internal_qa_open', 'image-block-reader-open')
      this.openImageBlockReaderOpenQa()
      return
    }
    if (uri === InternalQaRoutes.IMAGE_BLOCK_SETTINGS_OPEN_URI) {
      DiagnosticLogger.info('nav', 'internal_qa_open', 'image-block-settings-open')
      this.stack.pushPathByName('ImageBlockSettings', null)
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

  private openImageBlockReaderOpenQa(): void {
    this.readerOverlay.open(
      new ReaderParams(
        this.IMAGE_BLOCK_QA_GID,
        this.IMAGE_BLOCK_QA_TOKEN,
        0,
        this.IMAGE_BLOCK_QA_FILE_COUNT,
        this.IMAGE_BLOCK_QA_TITLE,
      ),
    )
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
          this.readerOverlay.open(
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

  private downloadTabIndex(): number {
    return this.safeMode.restricted() ? 1 : 3
  }

  private syncDownloadQueuePageActive(): void {
    const active: boolean = this.currentTab === this.downloadTabIndex()
    setDownloadQueuePageActive(active)
    if (active) {
      DownloadQueueSettings.syncActiveGalleryProgressToQueue()
    }
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

  private galleryBackToTopMenuItem(): Record<string, Object> {
    const topInner: Record<string, Object> = {
      'label': $r('app.string.common_back_to_top'),
      'icon': $r('sys.symbol.arrow_up'),
      'isEnabled': true,
      'action': () => {
        HomeSourceBridge.publishJumpGalleryFirstPage()
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
    const dateJumpInner: Record<string, Object> = {
      'label': $r('app.string.gallery_jump_date_after'),
      'icon': $r('sys.symbol.clock'),
      'isEnabled': true,
      'action': () => {
        HomeSourceBridge.publishOpenDateJumpAfterDialog()
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
      { 'content': dateJumpInner },
      { 'content': layoutInner },
      this.galleryBackToTopMenuItem(),
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
      this.galleryBackToTopMenuItem(),
    ]
    return { 'value': items, 'maxCount': 2 }
  }

  private topOnlyMenu(): Record<string, Object> {
    const jumpInner: Record<string, Object> = {
      'label': $r('app.string.toplist_jump_page'),
      'icon': $r('sys.symbol.chevron_right_circle'),
      'isEnabled': true,
      'action': () => {
        HomeSourceBridge.publishOpenToplistJumpDialog()
      },
    }
    const firstPageInner: Record<string, Object> = {
      'label': $r('app.string.toplist_first_page'),
      'icon': $r('sys.symbol.arrow_up_circle'),
      'isEnabled': true,
      'action': () => {
        HomeSourceBridge.publishJumpToplistFirstPage()
      },
    }
    const items: Record<string, Object>[] = [
      { 'content': jumpInner },
      { 'content': firstPageInner },
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
    const jumpInner: Record<string, Object> = {
      'label': $r('app.string.favorites_jump_page'),
      'icon': $r('sys.symbol.chevron_right_circle'),
      'isEnabled': true,
      'action': () => {
        FavSelectionBridge.publishOpenJumpDialog()
      },
    }
    const firstPageInner: Record<string, Object> = {
      'label': $r('app.string.favorites_first_page'),
      'icon': $r('sys.symbol.arrow_up_circle'),
      'isEnabled': true,
      'action': () => {
        FavSelectionBridge.publishJumpFirstPage()
      },
    }
    const items: Record<string, Object>[] = [
      { 'content': searchInner },
      { 'content': orderInner },
      { 'content': jumpInner },
      { 'content': selectorInner },
      { 'content': firstPageInner },
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
    const signalVersion: number = this.downloadQueueSignal.version
    const items: Record<string, Object>[] = []
    const searchInner: Record<string, Object> = {
      'label': this.downloadView.searchActive ? $r('app.string.download_search_close') : $r('app.string.tab_search'),
      'icon': this.downloadView.searchActive ? $r('sys.symbol.xmark') : $r('sys.symbol.magnifyingglass'),
      'isEnabled': true,
      'action': () => {
        this.toggleDownloadSearch()
      },
    }
    items.push({ 'content': searchInner })
    items.push(this.downloadSortMenuItem())
    const resumeInner: Record<string, Object> = {
      'label': $r('app.string.download_resume_all'),
      'icon': $r('sys.symbol.play_fill'),
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
    return { 'value': items, 'maxCount': signalVersion >= 0 ? 3 : 3 }
  }

  private downloadSortMenuItem(): Record<string, Object> {
    const sortInner: Record<string, Object> = {
      'label': $r('app.string.fav_order_title'),
      'icon': $r('sys.symbol.sort'),
      'isEnabled': true,
      'action': () => {
        this.openDownloadSortMenu()
      },
    }
    return { 'content': sortInner }
  }

  private openDownloadSortMenu(): void {
    this.downloadView.cmdKind = 'openSortMenu'
    this.downloadView.cmdSeq = this.downloadView.cmdSeq + 1
  }

  private toggleDownloadSearch(): void {
    const active: boolean = !this.downloadView.searchActive
    this.downloadView.searchActive = active
    if (!active) {
      this.downloadView.searchText = ''
    }
    DiagnosticLogger.info('download', active ? 'download_search_open' : 'download_search_close', `type=${this.downloadView.viewType}`)
  }

  private downloadHasResumable(): boolean {
    const queue = connectDownloadQueue()
    if (this.downloadView.viewType === DownloadViewType.ARCHIVER) {
      return queue.archiverTasks.some((task: DownloadArchiverTask) => {
        return task.status === DownloadGalleryTaskStatus.QUEUED ||
          task.status === DownloadGalleryTaskStatus.ERROR
      })
    }
    return queue.galleryTasks.some((task: DownloadGalleryTask) => {
      return task.status === DownloadGalleryTaskStatus.QUEUED ||
        task.status === DownloadGalleryTaskStatus.READY ||
        task.status === DownloadGalleryTaskStatus.PAUSED ||
        task.status === DownloadGalleryTaskStatus.PARTIAL ||
        task.status === DownloadGalleryTaskStatus.ERROR
    })
  }

  private downloadHasPausable(): boolean {
    const queue = connectDownloadQueue()
    if (this.downloadView.viewType === DownloadViewType.ARCHIVER) {
      return false
    }
    return queue.galleryTasks.some((task: DownloadGalleryTask) => {
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
        if (this.downloadTitleBarContent === null) {
          this.downloadTitleBarContent = new ComponentContent<Object>(
            this.getUIContext(),
            wrapBuilder<[Object]>(DownloadTitleBarCCBuilder),
            new Object(),
          )
        }
        content['bottomBuilder'] = this.bottomBuilder(
          this.downloadTitleBarContent,
          DOWNLOAD_SELECTOR_BAR_HEIGHT + (this.downloadView.pinnedGroupVisible
            ? DOWNLOAD_PINNED_TASK_GROUP_HEADER_HEIGHT
            : 0),
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

  private splitPlaceholder(): ComponentContent<Object> {
    if (this.splitPlaceholderContent === null) {
      this.splitPlaceholderContent = new ComponentContent<Object>(
        this.getUIContext(),
        wrapBuilder<[Object]>(IndexSplitPlaceholderCCBuilder),
        new Object(),
      )
    }
    return this.splitPlaceholderContent
  }

  private rootNavigationMode(): NavigationMode {
    return TabletLayoutSettings.allowsSplit(
      this.tabletLayout.mode,
      this.layoutSafeArea.mainWindowWidthPx,
      this.layoutSafeArea.mainWindowHeightPx,
    )
      ? NavigationMode.Auto
      : NavigationMode.Stack
  }

  @Builder
  routerMap(name: string) {
    if (!SafeModeGate.routeAllowed(name)) {
      Column() {}
    } else {
      this.destinationContent(IndexRouteCoordinator.family(name))
    }
  }

  @Builder
  readerOverlayRouterMap(name: string) {
    if (!SafeModeGate.routeAllowed(name)) {
      Column() {}
    } else if (name === 'ReaderOverlayBackdrop') {
      IndexReaderOverlayBackdropRoute()
    } else if (name === 'Reader') {
      ReaderPage({
        settingsSheetContent: (dismiss: () => void) => {
          this.ReaderSettingsSheet(dismiss)
        },
      })
    } else if (name === 'ReaderSettings') {
      ReaderSettingsPage()
    } else if (name === 'ReaderSuperResolutionModels') {
      ReaderSuperResolutionModelsPage()
    } else if (name === 'ReaderGestureProbe') {
      ReaderGestureProbePage()
    } else {
      Column() {}
    }
  }

  @Builder
  private ReaderSettingsSheet(dismiss: () => void) {
    ReaderSettingsPage({
      sheetPresentation: true,
      closeSheet: () => {
        dismiss()
      },
    })
  }

  @Builder
  private destinationContent(family: IndexDestinationFamily | null) {
    if (family === null) {
      Column() {}
    } else {
      this.mappedDestinationBuilder(family).builder()
    }
  }

  private syncGalleryDetailCoverTarget(): boolean {
    return GalleryDetailTransitionCoordinator.syncDetailCoverTarget(this.getUIContext())
  }

  private coverExpandSurfaceActive(): boolean {
    return this.galleryDetailTransition.eligible && this.galleryDetailTransition.isCoverExpand()
  }

  private sourceCoverLeftInCard(): number {
    return Math.max(0, Math.min(
      this.galleryDetailTransition.handoffWidth,
      this.galleryDetailTransition.sourceCoverX - this.galleryDetailTransition.handoffX,
    ))
  }

  private sourceCoverTopInCard(): number {
    return Math.max(0, Math.min(
      this.galleryDetailTransition.handoffHeight,
      this.galleryDetailTransition.sourceCoverY - this.galleryDetailTransition.handoffY,
    ))
  }

  private sourceCoverRightInCard(): number {
    return Math.max(this.sourceCoverLeftInCard(), Math.min(
      this.galleryDetailTransition.handoffWidth,
      this.galleryDetailTransition.sourceCoverX + this.galleryDetailTransition.sourceCoverWidth -
        this.galleryDetailTransition.handoffX,
    ))
  }

  private sourceCoverBottomInCard(): number {
    return Math.max(this.sourceCoverTopInCard(), Math.min(
      this.galleryDetailTransition.handoffHeight,
      this.galleryDetailTransition.sourceCoverY + this.galleryDetailTransition.sourceCoverHeight -
        this.galleryDetailTransition.handoffY,
    ))
  }

  @Builder
  private GalleryDetailCardSnapshotSlice(
    sliceX: number,
    sliceY: number,
    sliceWidth: number,
    sliceHeight: number,
  ) {
    if (
      this.galleryDetailTransition.cardSnapshot !== undefined &&
      sliceWidth > 0 &&
      sliceHeight > 0
    ) {
      Stack({ alignContent: Alignment.TopStart }) {
        Image(this.galleryDetailTransition.cardSnapshot)
          .width(this.galleryDetailTransition.handoffWidth)
          .height(this.galleryDetailTransition.handoffHeight)
          .objectFit(ImageFit.Fill)
          .syncLoad(true)
          .position({
            x: -sliceX,
            y: -sliceY,
          })
          .hitTestBehavior(HitTestMode.None)
      }
      .width(sliceWidth)
      .height(sliceHeight)
      .position({
        x: sliceX,
        y: sliceY,
      })
      .clip(true)
      .hitTestBehavior(HitTestMode.None)
    }
  }

  @Builder
  private GalleryDetailSourceCardRemainder() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.GalleryDetailCardSnapshotSlice(
        0,
        0,
        this.galleryDetailTransition.handoffWidth,
        this.sourceCoverTopInCard(),
      )
      this.GalleryDetailCardSnapshotSlice(
        0,
        this.sourceCoverTopInCard(),
        this.sourceCoverLeftInCard(),
        this.sourceCoverBottomInCard() - this.sourceCoverTopInCard(),
      )
      this.GalleryDetailCardSnapshotSlice(
        this.sourceCoverRightInCard(),
        this.sourceCoverTopInCard(),
        this.galleryDetailTransition.handoffWidth - this.sourceCoverRightInCard(),
        this.sourceCoverBottomInCard() - this.sourceCoverTopInCard(),
      )
      this.GalleryDetailCardSnapshotSlice(
        0,
        this.sourceCoverBottomInCard(),
        this.galleryDetailTransition.handoffWidth,
        this.galleryDetailTransition.handoffHeight - this.sourceCoverBottomInCard(),
      )
    }
    .width(this.galleryDetailTransition.handoffWidth)
    .height(this.galleryDetailTransition.handoffHeight)
    .position({
      x: this.galleryDetailTransition.handoffX,
      y: this.galleryDetailTransition.handoffY,
    })
    .borderRadius(ThemeConstants.RADIUS_CARD)
    .clip(true)
    .opacity(this.galleryDetailTransition.cardOpacity)
    .hitTestBehavior(HitTestMode.None)
  }

  private galleryDetailNavTransition(
    from: NavContentInfo,
    to: NavContentInfo,
    operation: NavigationOperation,
  ): NavigationAnimatedTransition | undefined {
    if (this.navStackHolder.isSplitMode || !this.galleryDetailTransition.eligible) {
      return undefined
    }
    const isPush: boolean = operation === NavigationOperation.PUSH && to.name === 'GalleryDetail'
    const isPop: boolean = operation === NavigationOperation.POP && from.name === 'GalleryDetail'
    if (!isPush && !isPop) {
      return undefined
    }
    this.galleryDetailTransitionSerial += 1
    const transitionSerial: number = this.galleryDetailTransitionSerial
    return {
      timeout: ThemeConstants.ANIM_DURATION * 12,
      transition: (proxy: NavigationTransitionProxy): void => {
        if (isPush) {
          if (
            this.galleryDetailTransition.isCoverExpand() &&
            !this.syncGalleryDetailCoverTarget()
          ) {
            DiagnosticLogger.info(
              'gallery-detail-transition',
              'cover_target_fallback',
              `gid=${this.galleryDetailTransition.galleryId}`,
            )
            this.galleryDetailTransition.useSeamlessFallback()
          }
          const coverExpand: boolean = this.galleryDetailTransition.isCoverExpand()
          this.getUIContext().animateTo({
            duration: ThemeConstants.ANIM_DURATION,
            curve: GALLERY_DETAIL_OPEN_CURVE,
            onFinish: (): void => {
              if (transitionSerial === this.galleryDetailTransitionSerial) {
                proxy.finishTransition()
              }
            },
          }, (): void => {
            this.galleryDetailTransition.expandWindow()
          })
          if (!coverExpand) {
            this.getUIContext().animateTo({
              delay: ThemeConstants.ANIM_DURATION * GALLERY_DETAIL_OPEN_CARD_EXIT_START_TIME,
              duration: ThemeConstants.ANIM_DURATION * (
                GALLERY_DETAIL_OPEN_CARD_EXIT_END_TIME - GALLERY_DETAIL_OPEN_CARD_EXIT_START_TIME
              ),
              curve: Curve.Linear,
            }, (): void => {
              this.galleryDetailTransition.crossfadeToDetail()
            })
          } else {
            this.getUIContext().animateTo({
              delay: ThemeConstants.ANIM_DURATION * GALLERY_DETAIL_COVER_OPEN_CARD_EXIT_START_TIME,
              duration: ThemeConstants.ANIM_DURATION * (
                GALLERY_DETAIL_COVER_OPEN_CARD_EXIT_END_TIME -
                  GALLERY_DETAIL_COVER_OPEN_CARD_EXIT_START_TIME
              ),
              curve: Curve.Linear,
            }, (): void => {
              this.galleryDetailTransition.hideSourceCard()
            })
          }
          return
        }
        if (
          this.galleryDetailTransition.isCoverExpand() &&
          !this.syncGalleryDetailCoverTarget()
        ) {
          DiagnosticLogger.info(
            'gallery-detail-transition',
            'cover_pop_fallback',
            `gallery=${this.galleryDetailTransition.galleryId} reason=target_not_visible`,
          )
          // The detail cover may have scrolled out of the viewport. Keep the whole detail surface
          // collapsing into the source card, suppress the stale cover flight, and fade the separately
          // captured source cover in near landing. The hidden source snapshot contains an empty card
          // slot, so the four-slice card remainder cannot restore the cover by itself.
          this.galleryDetailTransition.useCoverFadePopFallback()
        }
        const coverExpand: boolean = this.galleryDetailTransition.isCoverExpand()
        this.galleryDetailTransition.beginPop()
        this.getUIContext().animateTo({
          duration: ThemeConstants.ANIM_DURATION,
          curve: GALLERY_DETAIL_CLOSE_CURVE,
          onFinish: (): void => {
            if (transitionSerial === this.galleryDetailTransitionSerial) {
              proxy.finishTransition()
            }
          },
        }, (): void => {
          this.galleryDetailTransition.collapseWindow(ThemeConstants.RADIUS_CARD)
        })
        if (!coverExpand) {
          this.getUIContext().animateTo({
            delay: ThemeConstants.ANIM_DURATION * GALLERY_DETAIL_CLOSE_CARD_ENTRY_START_TIME,
            duration: ThemeConstants.ANIM_DURATION * (
              GALLERY_DETAIL_CLOSE_CARD_ENTRY_END_TIME - GALLERY_DETAIL_CLOSE_CARD_ENTRY_START_TIME
            ),
            curve: Curve.Linear,
          }, (): void => {
            this.galleryDetailTransition.crossfadeToCard()
          })
        } else {
          this.getUIContext().animateTo({
            delay: ThemeConstants.ANIM_DURATION * GALLERY_DETAIL_COVER_CLOSE_CARD_ENTRY_START_TIME,
            duration: ThemeConstants.ANIM_DURATION * (
              GALLERY_DETAIL_COVER_CLOSE_CARD_ENTRY_END_TIME -
                GALLERY_DETAIL_COVER_CLOSE_CARD_ENTRY_START_TIME
            ),
            curve: Curve.Linear,
          }, (): void => {
            this.galleryDetailTransition.revealSourceCard()
          })
        }
      },
      onTransitionEnd: (success: boolean): void => {
        if (transitionSerial !== this.galleryDetailTransitionSerial) {
          return
        }
        if (isPush) {
          this.galleryDetailTransition.markPushSettled(success)
        } else {
          this.galleryDetailTransition.markPopSettled(success)
        }
      },
    }
  }

  build() {
    Stack() {
      if (
        this.galleryDetailTransition.eligible &&
        this.galleryDetailTransition.sourceSnapshot !== undefined
      ) {
        Image(this.galleryDetailTransition.sourceSnapshot)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Fill)
          .syncLoad(true)
          .hitTestBehavior(HitTestMode.None)
      }
      Stack() {
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
                onScrollerReady: (scroller: Scroller) => {
                  this.setHomeActiveScroller(1, scroller)
                },
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
                onScrollerReady: (scroller: Scroller) => {
                  this.setHomeActiveScroller(3, scroller)
                },
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
          const changed: boolean = index !== this.currentTab
          if (changed && this.stack.getAllPathName().length > 0) {
            this.galleryDetailTransition.reset()
            this.stack.clear(false)
            this.navStackHolder.clearSecondaryEntry()
          }
          this.currentTab = index
          this.syncDownloadQueuePageActive()
          // Rebind the title bar to the newly-active tab's scroller so it auto-hides off that list.
          this.titleScroller = this.homeTabScrollers[index]
          if (this.homeTab.autoHide) {
            this.restoreHomeTabIfHidden()
          }
        })
      }
      .navDestination(this.routerMap)
      .customNavContentTransition((
        from: NavContentInfo,
        to: NavContentInfo,
        operation: NavigationOperation,
      ): NavigationAnimatedTransition | undefined => {
        return this.galleryDetailNavTransition(from, to, operation)
      })
      // The root shell owns the adaptive split. Its geometry depends only on available width; changing
      // a peer root tab clears the old tab's secondary stack and leaves this primary pane in place.
      .mode(this.rootNavigationMode())
      .onNavigationModeChange((mode: NavigationMode) => {
        this.navStackHolder.setSplitMode(mode === NavigationMode.Split)
      })
      .splitPlaceholder(this.splitPlaceholder())
      .navBarWidth(ThemeConstants.TABLET_PRIMARY_PANE_WIDTH)
      // HDS resolves the percentage range against the current navigation width, then clamps its upper
      // edge by minContentWidth. This preserves a 320vp detail surface while allowing the user to reach
      // a balanced two-pane layout instead of pinning the list at one fixed width.
      .navBarWidthRange({
        minWidth: ThemeConstants.TABLET_PRIMARY_PANE_MIN_WIDTH,
        maxWidth: '100%',
      })
      .minContentWidth(ThemeConstants.TABLET_DETAIL_MIN_WIDTH)
      .enableDragBar(true)
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
      // The navigation keeps its final full-screen layout while the outer surface changes size. Its
      // inverse offset keeps every detail element at its settled screen coordinate, so expanding the
      // surface reveals content without reflowing or scaling it.
      .width(
        this.coverExpandSurfaceActive()
          ? Math.max(1, this.galleryDetailTransition.rootWidth)
          : '100%',
      )
      .height(
        this.coverExpandSurfaceActive()
          ? Math.max(1, this.galleryDetailTransition.rootHeight)
          : '100%',
      )
      .position({
        x: this.coverExpandSurfaceActive() ? -this.galleryDetailTransition.clipX : 0,
        y: this.coverExpandSurfaceActive() ? -this.galleryDetailTransition.clipY : 0,
      })
      .backgroundColor(
        this.galleryDetailTransition.eligible
          ? Color.Transparent
          : $r('sys.color.ohos_id_color_sub_background'),
      )
      .id('nexte-root-navigation')
      }
      .width(
        this.coverExpandSurfaceActive()
          ? Math.max(1, this.galleryDetailTransition.clipWidth)
          : '100%',
      )
      .height(
        this.coverExpandSurfaceActive()
          ? Math.max(1, this.galleryDetailTransition.clipHeight)
          : '100%',
      )
      .position({
        x: this.coverExpandSurfaceActive() ? this.galleryDetailTransition.clipX : 0,
        y: this.coverExpandSurfaceActive() ? this.galleryDetailTransition.clipY : 0,
      })
      .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
      .shadow(ShadowStyle.OUTER_DEFAULT_MD)
      .borderRadius(this.coverExpandSurfaceActive() ? this.galleryDetailTransition.radius : 0)
      .clip(this.coverExpandSurfaceActive())
      if (
        this.galleryDetailTransition.phase === GalleryDetailTransitionPhase.PREPARING &&
        this.galleryDetailTransition.cardSnapshot !== undefined
      ) {
        Image(this.galleryDetailTransition.cardSnapshot)
          .width(this.galleryDetailTransition.handoffWidth)
          .height(this.galleryDetailTransition.handoffHeight)
          .objectFit(ImageFit.Fill)
          .syncLoad(true)
          .position({
            x: this.galleryDetailTransition.handoffX,
            y: this.galleryDetailTransition.handoffY,
          })
          .hitTestBehavior(HitTestMode.None)
      }
      if (
        this.galleryDetailTransition.eligible &&
        this.galleryDetailTransition.isCoverExpand() &&
        this.galleryDetailTransition.cardSnapshot !== undefined
      ) {
        if (this.galleryDetailTransition.preserveSourceCoverBackground) {
          // The card snapshot was captured after only the foreground image became transparent. Its real
          // blur/gradient layer therefore remains complete and needs no synthetic mask or background patch.
          Image(this.galleryDetailTransition.cardSnapshot)
            .width(this.galleryDetailTransition.handoffWidth)
            .height(this.galleryDetailTransition.handoffHeight)
            .objectFit(ImageFit.Fill)
            .syncLoad(true)
            .position({
              x: this.galleryDetailTransition.handoffX,
              y: this.galleryDetailTransition.handoffY,
            })
            .borderRadius(ThemeConstants.RADIUS_CARD)
            .clip(true)
            .opacity(this.galleryDetailTransition.cardOpacity)
            .hitTestBehavior(HitTestMode.None)
        } else {
          // Covers without a separate backdrop keep the existing four-slice path so the expanding detail
          // surface is revealed instead of exposing the thumbnail's generic loading placeholder.
          this.GalleryDetailSourceCardRemainder()
        }
      }
      if (
        this.galleryDetailTransition.coverFlightVisible() &&
        this.galleryDetailTransition.coverSnapshot !== undefined
      ) {
        // The cover belongs to the expanding card surface. Give it a second clip with exactly the
        // surface bounds/radius so it can never protrude past a rounded container corner while flying.
        Stack({ alignContent: Alignment.TopStart }) {
          Stack() {
            if (this.galleryDetailTransition.coverUrl.length > 0) {
              EhImageKnifeImage({
                src: EhConstants.cdnThumb(this.galleryDetailTransition.coverUrl),
                widthValue: '100%',
                heightValue: '100%',
                objectFit: ImageFit.Cover,
                radius: this.galleryDetailTransition.flightCoverRadius,
                onComplete: () => {
                  this.galleryDetailTransition.markCoverResourceReady()
                },
              })
            }
            if (!this.galleryDetailTransition.coverResourceReady) {
              // The click-time pixels guarantee that the first transition frame cannot be blank.
              // Once the already-cached thumbnail resource paints, it takes over at the identical
              // Cover crop and can reveal the full image continuously as the flight rect changes.
              Image(this.galleryDetailTransition.coverSnapshot)
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Cover)
                .syncLoad(true)
            }
          }
            .width(this.galleryDetailTransition.flightCoverWidth)
            .height(this.galleryDetailTransition.flightCoverHeight)
            .position({
              x: this.galleryDetailTransition.flightCoverX - this.galleryDetailTransition.clipX,
              y: this.galleryDetailTransition.flightCoverY - this.galleryDetailTransition.clipY,
            })
            .borderRadius(this.galleryDetailTransition.flightCoverRadius)
            .clip(true)
            .renderGroup(true)
            .hitTestBehavior(HitTestMode.None)
        }
        .width(Math.max(1, this.galleryDetailTransition.clipWidth))
        .height(Math.max(1, this.galleryDetailTransition.clipHeight))
        .position({
          x: this.galleryDetailTransition.clipX,
          y: this.galleryDetailTransition.clipY,
        })
        .borderRadius(this.galleryDetailTransition.radius)
        .clip(true)
        .zIndex(2)
        .hitTestBehavior(HitTestMode.None)
      }
      if (
        this.galleryDetailTransition.fallbackCoverVisible() &&
        this.galleryDetailTransition.coverSnapshot !== undefined
      ) {
        // When the detail cover is off-screen there is no valid flight origin. Fade the click-time
        // source pixels in at their exact landing rect while the detail surface finishes collapsing;
        // this avoids exposing the intentionally hidden source card as an empty cover slot.
        Image(this.galleryDetailTransition.coverSnapshot)
          .width(this.galleryDetailTransition.sourceCoverWidth)
          .height(this.galleryDetailTransition.sourceCoverHeight)
          .objectFit(ImageFit.Fill)
          .syncLoad(true)
          .position({
            x: this.galleryDetailTransition.sourceCoverX,
            y: this.galleryDetailTransition.sourceCoverY,
          })
          .borderRadius(this.galleryDetailTransition.sourceCoverRadius)
          .clip(true)
          .opacity(this.galleryDetailTransition.fallbackCoverOpacity)
          .zIndex(2)
          .hitTestBehavior(HitTestMode.None)
      }
      if (this.readerOverlay.visible) {
        HdsNavigation(this.readerOverlay.stack) {
          Column() {}
        }
        .navDestination(this.readerOverlayRouterMap)
        .hideNavBar(true)
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .opacity(this.readerThumbnailTransition.overlayOpacity)
        .onAppear(() => {
          this.readerOverlay.presentPendingReader()
        })
        .id('reader-overlay-navigation')
      }
      IndexReaderThumbnailTransitionProxy({ state: this.readerThumbnailTransition })
      if (this.securitySettings.locked) {
        SecurityLockOverlay({
          authenticating: this.securitySettings.authenticating,
          authError: this.securitySettings.authError,
          onUnlock: () => {
            SecuritySettings.unlockNow(this.ctx(), 'overlay')
          },
        })
      }
    }
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

@ComponentV2
struct SecurityLockOverlay {
  @Param authenticating: boolean = false;
  @Param authError: string = '';
  @Param onUnlock: () => void = () => {};

  build() {
    Column({ space: ThemeConstants.SPACE_MD }) {
      Text($r('app.string.security_locked_title'))
        .fontSize(ThemeConstants.FONT_SIZE_TITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
      if (this.authenticating) {
        LoadingProgress()
          .width(ThemeConstants.LOADING_SIZE)
          .height(ThemeConstants.LOADING_SIZE)
      } else {
        Button($r('app.string.security_unlock_button'))
          .type(ButtonType.Capsule)
          .fontColor(ThemeConstants.TEXT_ON_BRAND)
          .backgroundColor(ThemeConstants.BRAND_PRIMARY)
          .onClick(() => {
            this.onUnlock()
          })
      }
      if (this.authError.length > 0) {
        Text(this.authError)
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor($r('sys.color.font_secondary'))
      }
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width('100%')
    .height('100%')
    .backdropBlur(ThemeConstants.LOCK_OVERLAY_BLUR_RADIUS)
    .backgroundColor(ThemeConstants.LOCK_OVERLAY_TINT)
    .onClick(() => {})
  }
}
