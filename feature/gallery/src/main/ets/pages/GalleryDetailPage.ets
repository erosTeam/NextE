import { appMenuOptions } from 'shared'
import { HdsNavDestination, HdsTabsController } from '@kit.UIDesignKit'
import { ComponentContent, CustomContentDialog, FrameNode, SymbolGlyphModifier } from '@kit.ArkUI'
import { common, Want } from '@kit.AbilityKit'
import { pasteboard } from '@kit.BasicServicesKit'
import {
  ThemeConstants,
  ThemeDisplayState,
  connectThemeDisplay,
  EhGallery,
  EhGalleryVersion,
  EhGalleryComment,
  TagGroup,
  EhConstants,
  ShareUtil,
  GalleryDetailParams,
  GalleryInfoParams,
  GalleryTorrentsParams,
  GalleryArchiverParams,
  GalleryWebParams,
  ReaderParams,
  GalleryCommentsParams,
  AllThumbnailsParams,
  Favcat,
  GalleryFavoriteInfo,
  EhApiService,
  GalleryDetailResult,
  EhErrorText,
  connectNavStack,
  NavStackHolder,
  connectReaderOverlayNavigation,
  ReaderOverlayNavigationState,
  connectSearchAction,
  connectSiteMode,
  SiteModeState,
  AuthState,
  connectAuth,
  connectGalleryReadProgress,
  GalleryReadProgressState,
  GalleryTitleState,
  connectGalleryTitle,
  connectThumbnailMode,
  ThumbnailModeState,
  DownloadGalleryTask,
  DownloadArchiverTask,
  DownloadGalleryTaskStatus,
  ReaderLocalSourceService,
  DownloadQueueSettings,
  DownloadQueueState,
  DownloadQueueSignalState,
  connectDownloadQueue,
  connectDownloadQueueSignal,
  connectDownloadSettings,
  DownloadOriginalMode,
  EhGalleryImage,
  LocalFavSettings,
  LocalBlockService,
  LocalFavState,
  connectLocalFav,
  GalleryFavoriteMutationState,
  connectGalleryFavoriteMutation,
  GalleryRatingMutationState,
  connectGalleryRatingMutation,
  CommentVoteMutationState,
  connectCommentVoteMutation,
  GalleryDetailRefreshMutationState,
  connectGalleryDetailRefreshMutation,
  RemoteFavoriteSlotCacheState,
  connectRemoteFavoriteSlotCache,
  ViewedGallery,
  ViewedHistorySettings,
  PullRefreshListScaffold,
  PullRefreshController,
  GroupedListSection,
  ConciseListRow,
  PageErrorState,
  AppStrings,
  AppModalScaffold,
  RatingStars,
  GalleryRatingResult,
  FavcatListSettings,
  immersiveTitleBarOpts,
  connectTagTranslationSettings,
  TagTranslationSettingsState,
  ActionHandEdgeState,
  connectActionHandEdge,
  MotionHandStateService,
  ActionFollowTouchTracker,
  ActionFollowTouchState,
  ActionFollowTouchUpdate,
  HdsCapsuleBarButton,
  ReadButtonStyleSettings,
  ReadButtonStyleState,
  connectReadButtonStyle,
  appSheetOptions,
  AppPrompt,
  DiagnosticLogger,
  SafeModeState,
  connectSafeMode,
  GalleryDetailBackToTopState,
  connectGalleryDetailBackToTop,
  GalleryDetailTransitionState,
  connectGalleryDetailTransition,
  GALLERY_DETAIL_BACK_TO_TOP_METADATA,
  GALLERY_DETAIL_BACK_TO_TOP_THUMBNAILS,
  TabletLayoutSettings,
  TabletLayoutState,
  connectTabletLayout,
  LayoutSafeAreaBridge,
  LayoutSafeAreaState,
  connectLayoutSafeArea,
  ReaderSuperResolutionService,
  GalleryTitleTranslationService,
} from 'shared'
import { GalleryDetailViewModel } from '../viewmodel/GalleryDetailViewModel'
import { AllThumbnailsViewModel } from '../viewmodel/AllThumbnailsViewModel'
import { GalleryHeaderCard } from '../components/GalleryHeaderCard'
import { GalleryInfoBar } from '../components/GalleryInfoBar'
import { GalleryTagsCard } from '../components/GalleryTagsCard'
import { GalleryPreviewGrid } from '../components/GalleryPreviewGrid'
import { GalleryCommentsCard } from '../components/GalleryCommentsCard'
import { GalleryAddTagsSheet } from '../components/GalleryAddTagsSheet'
import { GalleryTorrentsContent } from './GalleryTorrentsPage'
import { GalleryArchiverContent } from './GalleryArchiverPage'
import { GalleryAllThumbnailsContent } from './GalleryAllThumbnailsPage'
import { GalleryDownloadTaskProjection } from '../model/GalleryDownloadTaskProjection'

class GalleryDetailSheetContentParams {
  content: () => void

  constructor(content: () => void) {
    this.content = content
  }
}

@ComponentV2
struct GalleryDetailSheetContentHost {
  @BuilderParam content: () => void;

  build() {
    this.content()
  }
}

@Builder
function galleryDetailSheetContentBuilder(params: GalleryDetailSheetContentParams) {
  GalleryDetailSheetContentHost({ content: params.content })
}

@ObservedV2
class GalleryTitleTranslationState {
  @Trace source: string = ''
  @Trace text: string = ''
  @Trace shown: boolean = false
  @Trace loading: boolean = false
  @Trace measuredHeight: number = 0
  @Trace animatedHeight: number = 0
  @Trace heightLocked: boolean = false
  @Trace contentOpacity: number = 1
  @Trace pendingMeasure: boolean = false
  @Trace pendingTargetShown: boolean = false
  @Trace animating: boolean = false
  private requestId: number = 0
  private animationId: number = 0

  private cancelPresentation(): void {
    this.animationId = this.animationId + 1
    this.shown = false
    this.measuredHeight = 0
    this.animatedHeight = 0
    this.heightLocked = false
    this.contentOpacity = 1
    this.pendingMeasure = false
    this.pendingTargetShown = false
    this.animating = false
  }

  reset(): void {
    this.requestId = this.requestId + 1
    this.cancelPresentation()
    this.source = ''
    this.text = ''
    this.loading = false
  }

  begin(source: string): number {
    this.requestId = this.requestId + 1
    this.cancelPresentation()
    this.source = source
    this.text = ''
    this.loading = true
    return this.requestId
  }

  isCurrent(requestId: number, source: string): boolean {
    return requestId === this.requestId && source === this.source
  }

  complete(translated: string): void {
    this.cancelPresentation()
    this.loading = false
    this.text = translated
  }

  fail(): void {
    this.cancelPresentation()
    this.loading = false
  }

  startAnimation(): number {
    this.animationId = this.animationId + 1
    this.animating = true
    return this.animationId
  }

  isAnimationCurrent(animationId: number): boolean {
    return animationId === this.animationId
  }

  finishAnimation(animationId: number): void {
    if (this.isAnimationCurrent(animationId)) {
      this.animating = false
    }
  }
}

const DETAIL_SHEET_REMOTE_FAVORITE: string = 'remoteFavorite'
const DETAIL_SHEET_FULL_TITLE: string = 'fullTitle'
const DETAIL_SHEET_TORRENTS: string = 'torrents'
const DETAIL_SHEET_ARCHIVER: string = 'archiver'
const DETAIL_SHEET_DOWNLOAD_UPGRADE: string = 'downloadUpgrade'
const DETAIL_SHEET_ADD_TAGS: string = 'addTags'
const TITLE_TRANSLATION_REGULAR: string = 'title'
const TITLE_TRANSLATION_JAPANESE: string = 'japaneseTitle'
const TITLE_TRANSLATION_ACTION_SIZE: number = 30
const TITLE_TRANSLATION_ICON_SIZE: number = 16
// followOperation touch heuristics: a drag counts as a scroll (→ report the operating side) only once its
// vertical movement clearly dominates, so a tap on content doesn't yank the floating Read button sideways.
const FOLLOW_OPERATION_VERTICAL_SCROLL_THRESHOLD: number = 12
const FOLLOW_OPERATION_VERTICAL_DOMINANCE_RATIO: number = 1.2

/**
 * Gallery detail (eros_fe page structure, native HDS rendering). Section order mirrors eros_fe:
 * header(cover+title+uploader) → info bar → relations → tags → COMMENTS peek (max 2) → PREVIEWS
 * peek (first page only). Comments sit BEFORE previews so they are reachable without scrolling past
 * thousands of thumbnails; "view all" / "more" link out to the separate Comments / AllThumbnails pages
 * instead of inflating this page. Read/resume is a page-level FAB, not a header-card capsule, so the
 * detail -> Reader primary flow stays reachable while scrolling. The nav-bar title is revealed only on
 * scroll (no duplicate with the header card title). Each block is a shared GroupedListSection card on
 * the SecondaryListScaffold.
 */
@ComponentV2
export struct GalleryDetailPage {
  @Local vm: GalleryDetailViewModel = new GalleryDetailViewModel();
  @Local fullPreviewVm: AllThumbnailsViewModel = new AllThumbnailsViewModel();
  @Local tabletLayout: TabletLayoutState = connectTabletLayout();
  @Local layoutSafeArea: LayoutSafeAreaState = connectLayoutSafeArea();
  @Local params: GalleryDetailParams = new GalleryDetailParams();
  @Local auth: AuthState = connectAuth();
  @Local siteMode: SiteModeState = connectSiteMode();
  // The nav-bar title appears only after the header card scrolls away (eros_fe scroll-driven title).
  @Local showNavTitle: boolean = false;
  @Local detailRefreshInFlight: boolean = false;
  @Local titlePref: GalleryTitleState = connectGalleryTitle();
  // Per-gallery reading progress: the READ button resumes at + labels itself with the saved page.
  // Persistence stays live in Reader; the button uses a frozen snapshot until Reader starts closing.
  @Local readProgress: GalleryReadProgressState = connectGalleryReadProgress();
  @Local readerOverlay: ReaderOverlayNavigationState = connectReaderOverlayNavigation();
  @Local displayedResumeIndex: number = 0;
  // Detail-preview display mode (eros_fe hideGalleryThumbnails / horizontalThumbnails). Reactive so a
  // settings toggle re-renders this page's preview section live (grid ↔ horizontal ↔ hidden-inline).
  @Local thumbMode: ThumbnailModeState = connectThumbnailMode();
  // Local gallery download queue state: mirrors eros_fe GalleryTask uniqueness and updates live while
  // the gallery image executor resolves prepared seeds into sandbox files.
  @Local downloadQueue: DownloadQueueState = connectDownloadQueue();
  @Local downloadQueueSignalState: DownloadQueueSignalState = connectDownloadQueueSignal();
  @Local downloadQueueTick: number = 0;
  @Local downloadChipHasTask: boolean = false;
  @Local downloadChipStatus: string = DownloadGalleryTaskStatus.QUEUED;
  @Local archiverChipHasTask: boolean = false;
  @Local archiverChipStatus: string = DownloadGalleryTaskStatus.QUEUED;
  @Local downloadMenuShown: boolean = false;
  @Local localFav: LocalFavState = connectLocalFav();
  @Local favoriteMutation: GalleryFavoriteMutationState = connectGalleryFavoriteMutation();
  @Local ratingMutation: GalleryRatingMutationState = connectGalleryRatingMutation();
  @Local commentVoteMutation: CommentVoteMutationState = connectCommentVoteMutation();
  @Local detailRefreshMutation: GalleryDetailRefreshMutationState = connectGalleryDetailRefreshMutation();
  @Local safeMode: SafeModeState = connectSafeMode();
  @Local torrentSheetParams: GalleryTorrentsParams = new GalleryTorrentsParams();
  @Local archiverSheetParams: GalleryArchiverParams = new GalleryArchiverParams();
  @Local tagTranslation: TagTranslationSettingsState = connectTagTranslationSettings();
  @Local favoriteSlotCache: RemoteFavoriteSlotCacheState = connectRemoteFavoriteSlotCache();
  // Resolved Read-FAB hand edge (smart-grip / follow-operation / fixed). visualActionEdge mirrors it and
  // drives a smooth .translate() slide; root/button widths convert the discrete edge into a continuous X.
  @Local actionEdge: ActionHandEdgeState = connectActionHandEdge();
  // Seed from the CURRENT resolved edge (the service resolves it at startup, before this page mounts), so a
  // page opened while the edge is already 'left' starts left — @Monitor only fires on later changes.
  @Local visualActionEdge: string = connectActionHandEdge().edge;
  @Local detailRootWidth: number = connectLayoutSafeArea().rememberedGalleryDetailContentWidth(
    connectNavStack().isSplitMode,
  );
  @Local detailMetadataWidth: number = 0;
  @Local compactPreviewReloadToken: number = 0;
  @Local readFabWidth: number = 0;
  @Local readFabLayoutReady: boolean = false;
  @Local readFabShouldAnimate: boolean = false;
  @Local actionStripViewportWidth: number = 0;
  @Local actionStripContentWidth: number = 0;
  @Local actionStripLayoutReady: boolean = false;
  @Local actionStripShouldAnimate: boolean = false;
  @Local readButtonStyle: ReadButtonStyleState = connectReadButtonStyle();
  @Local themeDisplay: ThemeDisplayState = connectThemeDisplay();
  private followTouchState: ActionFollowTouchState = ActionFollowTouchTracker.initialState();
  @Local detailSheetShown: boolean = false;
  @Local detailSheetKind: string = '';
  @Local titleTranslation: GalleryTitleTranslationState = new GalleryTitleTranslationState();
  @Local japaneseTitleTranslation: GalleryTitleTranslationState = new GalleryTitleTranslationState();
  @Local fullPreviewJumpPageText: string = '';
  @Local fullPreviewJumpError: string = '';
  @Local remoteFavoriteSelectedCat: string = '';
  @Local remoteFavoriteNote: string = '';
  @Local remoteFavoriteSlots: Favcat[] = [];
  @Local remoteFavoriteSubmitting: boolean = false;
  @Local remoteFavoriteLoadingFavcats: boolean = false;
  @Local remoteFavoriteError: string = '';
  @Local ratingSelected: number = 0;
  @Local ratingSubmitting: boolean = false;
  @Local ratingError: string = '';
  @Local downloadUpgradeBusyGid: string = '';
  @Local navStackHolder: NavStackHolder = connectNavStack();
  @Local galleryDetailBackToTop: GalleryDetailBackToTopState = connectGalleryDetailBackToTop();
  @Local galleryDetailTransition: GalleryDetailTransitionState = connectGalleryDetailTransition();
  @Local isFirstSecondaryDetail: boolean = false;
  private stack: NavPathStack = connectNavStack().stack;
  private navigationDestinationId: string = '';
  private readFabMaterialController: HdsTabsController = new HdsTabsController();
  private actionStripScroller: Scroller = new Scroller();
  private fullPreviewScroller: Scroller = new Scroller();
  private fullPreviewRefreshController: PullRefreshController = new PullRefreshController();
  private remoteFavoriteSheetContent: ComponentContent<GalleryDetailSheetContentParams> | null = null;
  private fullPreviewJumpSubmitting: boolean = false;
  private fullPreviewJumpDialogController: CustomDialogController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: $r('app.string.gallery_preview_jump'),
      contentBuilder: () => {
        this.FullPreviewJumpDialogContent()
      },
      buttons: [
        {
          value: $r('app.string.common_cancel'),
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: () => {
            this.closeFullPreviewJumpDialog()
          },
        },
        {
          value: $r('app.string.gallery_preview_jump'),
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: () => {
            this.confirmFullPreviewJump()
          },
        },
      ],
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    customStyle: false,
  });
  private ratingDialogController: CustomDialogController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: $r('app.string.detail_rate'),
      contentBuilder: () => {
        this.RatingDialogContent()
      },
      buttons: [
        {
          value: $r('app.string.common_cancel'),
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: () => {
            this.closeRatingDialog()
          },
        },
        {
          value: $r('app.string.detail_rate_submit'),
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: () => {
            this.submitRating()
          },
        },
      ],
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    customStyle: false,
  });
  // Account/site changes replace preview URLs and permissions. Until a real replacement detail result
  // arrives, keep the full-preview VM empty and make the next seed a complete fresh session.
  private fullPreviewMustReset: boolean = false;

  // Smooth-slide the Read FAB when the resolved edge changes. FlexAlign can't tween, so the button carries
  // .animation() on its translate and we only flip the target edge here (mirrors V2Next's edge @Monitor).
  @Monitor('actionEdge.edge')
  private onActionEdgeChanged(): void {
    this.readFabShouldAnimate = this.readFabLayoutReady
    this.actionStripShouldAnimate = this.actionStripLayoutReady
    this.visualActionEdge = this.actionEdge.edge
    this.scrollActionStripToEdge()
  }

  @Monitor('readButtonStyle.style')
  private onReadButtonStyleChanged(): void {
    this.readFabWidth = 0
    this.readFabLayoutReady = false
    this.readFabShouldAnimate = false
  }

  @Monitor('commentVoteMutation.version')
  private onCommentVoteMutation(): void {
    if (this.commentVoteMutation.gid !== this.params.gid) {
      return
    }
    this.vm.applyCommentVote(
      this.commentVoteMutation.commentId,
      this.commentVoteMutation.score,
      this.commentVoteMutation.vote,
      this.commentVoteMutation.scoreDetails,
    )
  }

  @Monitor('detailRefreshMutation.version')
  private onExternalDetailRefresh(): void {
    if (
      this.detailRefreshMutation.gid !== this.params.gid ||
      this.detailRefreshMutation.token !== this.params.token ||
      this.detailRefreshMutation.isEx !== this.siteMode.isEx
    ) {
      return
    }
    this.vm.applyExternalRefreshResult(this.detailRefreshMutation.snapshot())
  }

  @Monitor('downloadQueueSignalState.version')
  private onDownloadQueueChanged(): void {
    this.downloadQueueTick = this.downloadQueueTick + 1
    this.syncDownloadChipState('signal')
  }

  private markDownloadQueueDirty(): void {
    this.downloadQueueTick = this.downloadQueueTick + 1
    this.syncDownloadChipState('local')
  }

  // Continuous X for the Read FAB inside the padded full-width rail: left edge = 0 (Start), right edge =
  // inner width − button width. Interpolated by the button's .animation().
  private readFabVisualX(): number {
    if (this.visualActionEdge === 'left') {
      return 0
    }
    const inner: number = this.readFabAvailableWidth() - this.readFabRailSideInset() * 2
    return Math.max(0, inner - this.readFabWidth)
  }

  private readFabAvailableWidth(): number {
    return this.usesSplitDetailLayout() ? this.detailRootWidth : this.detailMetadataWidth
  }

  private readFabUsesHdsMaterial(): boolean {
    return this.readButtonStyle.style === ReadButtonStyleSettings.STYLE_HDS
  }

  private readFabRailSideInset(): number {
    return this.readFabUsesHdsMaterial() ? 0 : ThemeConstants.SPACE_LG
  }

  private readFabRailBottomInset(): number {
    return this.readFabUsesHdsMaterial() ? 0 : ThemeConstants.SPACE_LG
  }

  private readFabOuterHeight(): number {
    return this.readFabUsesHdsMaterial()
      ? ThemeConstants.BUTTON_HEIGHT + ThemeConstants.SPACE_LG * 2
      : ThemeConstants.BUTTON_HEIGHT
  }

  private usesSplitDetailLayout(): boolean {
    return TabletLayoutSettings.allowsSplit(
      this.tabletLayout.mode,
      this.layoutSafeArea.mainWindowWidthPx,
      this.layoutSafeArea.mainWindowHeightPx,
    ) && this.detailRootWidth >= ThemeConstants.GALLERY_DETAIL_SPLIT_MIN_WIDTH
  }

  private usesWideSplitWorkspace(): boolean {
    return this.navStackHolder.isSplitMode && this.usesSplitDetailLayout()
  }

  private syncGalleryDetailBackToTopWorkspace(): void {
    if (this.navigationDestinationId.length === 0) {
      return
    }
    if (this.usesWideSplitWorkspace()) {
      this.galleryDetailBackToTop.begin(this.navigationDestinationId)
      return
    }
    this.galleryDetailBackToTop.end(this.navigationDestinationId)
  }

  private releaseGalleryDetailBackToTopWorkspace(): void {
    this.galleryDetailBackToTop.end(this.navigationDestinationId)
  }

  @Monitor('navStackHolder.isSplitMode')
  private onNavigationModeChanged(): void {
    this.syncGalleryDetailBackToTopWorkspace()
  }

  @Monitor('themeDisplay.effectiveDark')
  private onThemeDisplayChanged(): void {
    const content: ComponentContent<GalleryDetailSheetContentParams> | null = this.remoteFavoriteSheetContent
    if (content === null) {
      return
    }
    // ComponentContent owns the sheet body, while openBindSheet owns the native HDS host surface.
    // Refresh both boundaries when the resolved theme changes so the API-26 material cannot retain
    // the color mode from the time the sheet was opened.
    content.updateConfiguration()
    this.getUIContext()
      .updateBindSheet(content, { systemMaterial: AppPrompt.modalSystemMaterial() }, true)
      .catch((error: Error) => {
        DiagnosticLogger.warn('gallery', 'favorite_sheet_theme_refresh_failed', error.message)
      })
  }

  private readFabMaterialBarWidth(): number {
    const index: number = this.resumeIndex()
    if (index <= 0) {
      return 86
    }
    return Math.min(172, 104 + (index + 1).toString().length * 8)
  }

  private readFabAnimationDuration(): number {
    return this.readFabShouldAnimate ? ThemeConstants.ANIM_DURATION : 0
  }

  private actionStripVisualX(): number {
    if (this.visualActionEdge === 'left' || this.actionStripContentWidth >= this.actionStripViewportWidth) {
      return 0
    }
    return Math.max(0, this.actionStripViewportWidth - this.actionStripContentWidth)
  }

  private actionStripRailMinWidth(): Length {
    if (this.actionStripViewportWidth <= 0) {
      return '100%'
    }
    return this.actionStripViewportWidth
  }

  private actionStripAnimationDuration(): number {
    return this.actionStripShouldAnimate ? ThemeConstants.ANIM_DURATION : 0
  }

  private updateReadFabLayoutReady(): void {
    if (this.readFabAvailableWidth() > 0 && this.readFabWidth > 0) {
      this.readFabLayoutReady = true
    }
  }

  private updateActionStripLayoutReady(): void {
    if (this.actionStripViewportWidth > 0 && this.actionStripContentWidth > 0) {
      this.actionStripLayoutReady = true
    }
  }

  private scrollActionStripToEdge(): void {
    try {
      this.actionStripScroller.scrollEdge(this.visualActionEdge === 'left' ? Edge.Start : Edge.End)
    } catch (_error) {
    }
  }

  // followOperation mode: a scroll-like drag reports its start X so the button hops to the operating side.
  private handleFollowTouch(event: TouchEvent): void {
    if (event.touches.length === 0) {
      return
    }
    const touch: TouchObject = event.touches[0]
    const update: ActionFollowTouchUpdate = ActionFollowTouchTracker.update(
      this.followTouchState,
      event.type,
      touch.x,
      touch.y,
      FOLLOW_OPERATION_VERTICAL_SCROLL_THRESHOLD,
      FOLLOW_OPERATION_VERTICAL_DOMINANCE_RATIO,
    )
    this.followTouchState = update.state
    if (update.shouldReport) {
      MotionHandStateService.reportFollowOperationX(update.reportX, this.readFabAvailableWidth())
    }
  }
  private scroller: Scroller = new Scroller();
  private refreshController: PullRefreshController = new PullRefreshController();
  // Pending 5s viewed-history timer (eros_fe delays addHistory 5s after open so a quick bounce isn't
  // recorded). Cancelled if the user leaves before it fires. -1 = none.
  private historyTimer: number = -1;
  private superResolutionPrepareTimer: number = -1;

  // eros_fe resumes reading at the saved lastIndex when the READ button is tapped (thumbnail taps
  // still open their own page). 0 when there is no saved progress.
  private resumeIndex(): number {
    return this.displayedResumeIndex
  }

  private syncDisplayedReadProgress(): void {
    this.displayedResumeIndex = this.readProgress.getIndex(this.params.gid)
  }

  @Monitor('readProgress.revision')
  private onReadProgressChanged(): void {
    if (!this.readerOverlay.visible) {
      this.syncDisplayedReadProgress()
    }
  }

  @Monitor('readerOverlay.closing')
  private onReaderOverlayClosingChanged(): void {
    if (this.readerOverlay.closing) {
      this.syncDisplayedReadProgress()
    }
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  @Monitor('tagTranslation.enabled')
  onTagTranslationChange(): void {
    this.vm.reapplyTagTranslation()
  }

  // Detail HTML contains account-scoped favorite/rating/API data. Keep the current body visible while
  // the replacement arrives, but never let an in-flight old account/site response repaint or cache it.
  @Monitor('auth.memberId')
  onDetailAccountChange(): void {
    this.reloadFullPreviewForContext()
  }

  @Monitor('siteMode.isEx')
  onDetailSiteChange(): void {
    this.reloadFullPreviewForContext()
  }

  @Monitor('vm.previewRevision')
  onDetailPreviewSeedChanged(): void {
    this.syncFullPreviewFromDetail()
  }

  private reloadFullPreviewForContext(): void {
    this.fullPreviewMustReset = true
    this.fullPreviewVm.invalidate()
    this.vm.reloadForContext()
  }

  private retryDetailLoad(): void {
    // A context replacement keeps the previous detail VM marked loaded. Retrying it through load()
    // would therefore be a silent no-op; restart the replacement run and its fresh preview session.
    if (this.fullPreviewMustReset) {
      this.reloadFullPreviewForContext()
      return
    }
    this.vm.load(this.params.gid, this.params.token)
  }

  private syncFullPreviewFromDetail(): void {
    if (this.params.gid.length === 0 || this.vm.images.length === 0) {
      return
    }
    this.fullPreviewVm.syncDetailFirstPage(
      this.allThumbnailsParams(0, false),
      !this.fullPreviewMustReset,
    )
    this.fullPreviewMustReset = false
  }

  // Record this gallery in viewed-history 5s after open (eros_fe's debounce). By then the detail fetch
  // has usually landed, so the entry carries the full title/thumb; if not, the list seed still has gid/
  // token/title/thumb — enough for a history row.
  private scheduleHistoryAdd(): void {
    if (this.historyTimer >= 0) {
      clearTimeout(this.historyTimer)
    }
    this.historyTimer = setTimeout(() => {
      this.historyTimer = -1
      if (this.vm.gallery.gid.length > 0) {
        ViewedHistorySettings.add(
          this.ctx(),
          ViewedGallery.fromGallery(this.vm.gallery, Date.now()),
        )
      }
    }, 5000)
  }

  private scheduleSuperResolutionPreparation(): void {
    if (this.superResolutionPrepareTimer >= 0) {
      clearTimeout(this.superResolutionPrepareTimer)
    }
    // Let the detail transition and first layout settle before model IO and Vulkan pipeline creation.
    // The work itself stays on the native background QoS and is reused by the Reader process.
    this.superResolutionPrepareTimer = setTimeout(() => {
      this.superResolutionPrepareTimer = -1
      ReaderSuperResolutionService.prepareSelectedModel(this.ctx())
    }, 600)
  }

  aboutToAppear(): void {
    this.syncDownloadChipState('appear')
    this.scheduleSuperResolutionPreparation()
  }

  aboutToDisappear(): void {
    // Left before the 5s debounce fired → this open was transient; don't record it.
    if (this.historyTimer >= 0) {
      clearTimeout(this.historyTimer)
      this.historyTimer = -1
    }
    if (this.superResolutionPrepareTimer >= 0) {
      clearTimeout(this.superResolutionPrepareTimer)
      this.superResolutionPrepareTimer = -1
    }
  }

  private navTitle(): string {
    const title: string = this.vm.gallery.displayTitle(this.titlePref.japaneseTitleInGalleryPage)
    if (title.length > 0) {
      return title
    }
    return this.params.title.length > 0 ? this.params.title : AppStrings.get('nav_gallery')
  }

  private primaryDetailTitle(): string {
    const title: string = this.vm.gallery.displayTitle(this.titlePref.japaneseTitleInGalleryPage)
    return title.length > 0 ? title : this.params.title
  }

  private secondaryDetailTitle(): string {
    return this.vm.gallery.secondaryTitle(this.titlePref.japaneseTitleInGalleryPage)
  }

  private englishDetailTitle(): string {
    if (this.vm.gallery.englishTitle.length > 0) {
      return this.vm.gallery.englishTitle
    }
    return this.params.title
  }

  private japaneseDetailTitle(): string {
    return this.vm.gallery.japaneseTitle
  }

  private titleTranslationStateFor(kind: string): GalleryTitleTranslationState {
    return kind === TITLE_TRANSLATION_JAPANESE
      ? this.japaneseTitleTranslation
      : this.titleTranslation
  }

  private titleTranslationTextFor(kind: string): string {
    return this.titleTranslationStateFor(kind).text
  }

  private titleTranslationShownFor(kind: string): boolean {
    const source: string = this.titleSourceFor(kind)
    const state: GalleryTitleTranslationState = this.titleTranslationStateFor(kind)
    return source.length > 0 && state.source === source && state.shown
  }

  private titleTranslationLoadingFor(kind: string): boolean {
    const source: string = this.titleSourceFor(kind)
    const state: GalleryTitleTranslationState = this.titleTranslationStateFor(kind)
    return source.length > 0 && state.source === source && state.loading
  }

  private titleTranslationBusyFor(kind: string): boolean {
    return this.titleTranslationLoadingFor(kind) || this.titleTranslationStateFor(kind).animating
  }

  private titleSourceFor(kind: string): string {
    return kind === TITLE_TRANSLATION_JAPANESE
      ? this.japaneseDetailTitle().trim()
      : this.englishDetailTitle().trim()
  }

  private resetTitleTranslations(): void {
    this.titleTranslation.reset()
    this.japaneseTitleTranslation.reset()
  }

  private isTitleTranslationRequestCurrent(
    kind: string,
    requestId: number,
    gid: string,
    token: string,
    source: string,
  ): boolean {
    return this.titleTranslationStateFor(kind).isCurrent(requestId, source) &&
      gid === this.params.gid &&
      token === this.params.token &&
      source === this.titleSourceFor(kind)
  }

  private failTitleTranslation(kind: string): void {
    this.titleTranslationStateFor(kind).fail()
    this.getUIContext()
      .getPromptAction()
      .openToast({ message: $r('app.string.detail_title_translation_failed') })
      .catch((_error: Error) => {})
  }

  private requestTitleTranslationVisibility(kind: string, targetShown: boolean): void {
    const state: GalleryTitleTranslationState = this.titleTranslationStateFor(kind)
    if (state.text.length === 0 || state.animating) {
      return
    }
    state.pendingTargetShown = targetShown
    state.pendingMeasure = true
    state.animating = true
  }

  private updateTitleTranslationMeasuredHeight(kind: string, area: Area): void {
    const height: number = area.height as number
    if (height > 0) {
      this.titleTranslationStateFor(kind).measuredHeight = height
    }
  }

  private handlePendingTitleTranslationArea(kind: string, area: Area): void {
    const state: GalleryTitleTranslationState = this.titleTranslationStateFor(kind)
    if (!state.pendingMeasure) {
      return
    }
    const targetHeight: number = area.height as number
    if (targetHeight <= 0) {
      return
    }
    const targetShown: boolean = state.pendingTargetShown
    const animationId: number = state.startAnimation()
    state.pendingMeasure = false
    state.measuredHeight = targetHeight
    state.animatedHeight = targetShown ? 0 : targetHeight
    state.heightLocked = true
    state.contentOpacity = targetShown ? 0 : 1
    if (targetShown) {
      state.shown = true
    }
    setTimeout((): void => {
      if (!state.isAnimationCurrent(animationId)) {
        return
      }
      this.getUIContext().animateTo(
        { duration: ThemeConstants.ANIM_DURATION, curve: Curve.EaseOut },
        () => {
          state.animatedHeight = targetShown ? targetHeight : 0
          state.contentOpacity = targetShown ? 1 : 0
        },
      )
      setTimeout((): void => {
        if (!state.isAnimationCurrent(animationId)) {
          return
        }
        state.shown = targetShown
        state.animatedHeight = 0
        state.heightLocked = false
        state.contentOpacity = 1
        state.measuredHeight = targetHeight
        state.finishAnimation(animationId)
      }, ThemeConstants.ANIM_DURATION + ThemeConstants.ANIM_DONE_DELAY_MS)
    }, 0)
  }

  private translateTitle(kind: string, source: string): void {
    const state: GalleryTitleTranslationState = this.titleTranslationStateFor(kind)
    const requestId: number = state.begin(source)
    const gid: string = this.params.gid
    const token: string = this.params.token
    GalleryTitleTranslationService.translate(this.ctx(), source)
      .then((translated: string) => {
        if (!this.isTitleTranslationRequestCurrent(kind, requestId, gid, token, source)) {
          return
        }
        const result: string = translated.trim()
        if (result.length === 0) {
          state.complete(result)
          this.failTitleTranslation(kind)
          return
        }
        state.complete(result)
        this.requestTitleTranslationVisibility(kind, true)
      })
      .catch((error: Error) => {
        if (!this.isTitleTranslationRequestCurrent(kind, requestId, gid, token, source)) {
          return
        }
        DiagnosticLogger.warn('gallery', 'title_translation_failed', `kind=${kind} ${error.message}`)
        this.failTitleTranslation(kind)
      })
  }

  private toggleOrTranslateTitle(kind: string): void {
    const source: string = this.titleSourceFor(kind)
    if (source.length === 0 || this.titleTranslationBusyFor(kind)) {
      return
    }
    if (
      this.titleTranslationStateFor(kind).source === source &&
      this.titleTranslationTextFor(kind).length > 0
    ) {
      const nextShown: boolean = !this.titleTranslationShownFor(kind)
      this.requestTitleTranslationVisibility(kind, nextShown)
      return
    }
    this.translateTitle(kind, source)
  }

  private fileCountNum(): number {
    return this.vm.gallery.fileCountNumber()
  }

  private openReader(index: number): void {
    const contentLanguage: string = this.vm.gallery.contentLanguage()
    const params: ReaderParams = new ReaderParams(
      this.params.gid,
      this.params.token,
      index,
      this.fileCountNum(),
      this.navTitle(),
      this.vm.images,
      this.vm.images.length > 0 ? 1 : 0,
      this.vm.images.length,
    )
    params.sourceLanguage = contentLanguage.length > 0
      ? contentLanguage
      : 'auto'
    connectReaderOverlayNavigation().open(params)
  }

  private openFullPreviewReader(img: EhGalleryImage): void {
    if (this.fullPreviewMustReset) {
      return
    }
    this.ensureFullPreviewSeeded()
    const pageZeroBased: number = img.page > 0 ? img.page - 1 : 0
    const contentLanguage: string = this.vm.gallery.contentLanguage()
    const params: ReaderParams = new ReaderParams(
      this.params.gid,
      this.params.token,
      pageZeroBased,
      this.fileCountNum(),
      this.navTitle(),
      this.fullPreviewVm.loadedImages(),
      this.fullPreviewVm.loadedPreviewPages(),
      this.fullPreviewVm.seedPerPage(),
      this.fullPreviewVm.loadedPreviewPageNumbers(),
      img.sUrl,
    )
    params.sourceLanguage = contentLanguage.length > 0
      ? contentLanguage
      : 'auto'
    connectReaderOverlayNavigation().open(params)
  }

  private readFabLabel(): ResourceStr {
    const index: number = this.resumeIndex()
    if (index > 0) {
      return $r('app.string.detail_read_resume', (index + 1).toString())
    }
    return $r('app.string.detail_read')
  }

  private openComments(): void {
    this.stack.pushPathByName(
      'GalleryComments',
      new GalleryCommentsParams(
        this.params.gid,
        this.params.token,
        this.vm.comments,
        this.navTitle(),
        this.vm.gallery.apikey,
        this.vm.gallery.apiuid,
      ),
    )
  }

  private openGalleryInfo(): void {
    this.stack.pushPathByName(
      'GalleryInfo',
      new GalleryInfoParams(this.vm.gallery.copy(), connectSiteMode().isEx, this.navTitle()),
    )
  }

  private openTorrents(): void {
    this.torrentSheetParams = new GalleryTorrentsParams(
      this.params.gid,
      this.params.token,
      connectSiteMode().isEx,
      this.navTitle(),
      this.vm.gallery.torrentCount,
    )
    this.openDetailSheet(DETAIL_SHEET_TORRENTS)
  }

  private openParentGallery(): void {
    if (this.vm.gallery.parentGid.length === 0 || this.vm.gallery.parentGid === this.params.gid) {
      return
    }
    this.stack.pushPathByName(
      'GalleryDetail',
      new GalleryDetailParams(
        this.vm.gallery.parentGid,
        this.vm.gallery.parentToken,
        '',
        '',
      ),
    )
  }

  private openArchiver(): void {
    const thumbUrl: string = this.vm.gallery.thumbUrl.length > 0
      ? this.vm.gallery.thumbUrl
      : (this.vm.gallery.thumbUrlL.length > 0 ? this.vm.gallery.thumbUrlL : this.params.thumbUrl)
    DiagnosticLogger.info(
      'gallery',
      'detail_archiver_open',
      `gid=${this.params.gid} hasArchiverLink=${this.vm.gallery.archiverLink.length > 0}`,
    )
    this.archiverSheetParams = new GalleryArchiverParams(
      this.params.gid,
      this.params.token,
      this.vm.gallery.archiverLink,
      connectSiteMode().isEx,
      this.navTitle(),
      thumbUrl,
      this.vm.gallery.imgWidth,
      this.vm.gallery.imgHeight,
    )
    this.openDetailSheet(DETAIL_SHEET_ARCHIVER)
  }

  private torrentTitle(count: string): string {
    return AppStrings.get('detail_torrents').replace('%s', count)
  }

  private currentDownloadGid(): string {
    return this.vm.gallery.gid.length > 0 ? this.vm.gallery.gid : this.params.gid
  }

  private currentDownloadToken(): string {
    return this.vm.gallery.token.length > 0 ? this.vm.gallery.token : this.params.token
  }

  private downloadVariantTask(preferOriginal: boolean): DownloadGalleryTask | null {
    if (this.downloadQueueSignalState.version < 0) {
      return null
    }
    if (this.downloadQueueTick < 0) {
      return null
    }
    return GalleryDownloadTaskProjection.galleryTask(
      this.downloadQueue.galleryTasks,
      this.currentDownloadGid(),
      this.currentDownloadToken(),
      preferOriginal,
    )
  }

  private downloadTasks(): DownloadGalleryTask[] {
    return GalleryDownloadTaskProjection.galleryTasks(
      this.downloadQueue.galleryTasks,
      this.currentDownloadGid(),
      this.currentDownloadToken(),
    )
  }

  private archiverTasks(): DownloadArchiverTask[] {
    return GalleryDownloadTaskProjection.archiverTasks(
      this.downloadQueue.archiverTasks,
      this.currentDownloadGid(),
    )
  }

  private isDownloadTaskComplete(task: DownloadGalleryTask): boolean {
    return GalleryDownloadTaskProjection.effectiveGalleryStatus(task) === DownloadGalleryTaskStatus.COMPLETE
  }

  private completeDownloadTask(): DownloadGalleryTask | null {
    const tasks: DownloadGalleryTask[] = this.downloadTasks()
    for (let i: number = 0; i < tasks.length; i++) {
      if (this.isDownloadTaskComplete(tasks[i])) {
        return tasks[i]
      }
    }
    return null
  }

  private syncDownloadChipState(reason: string): void {
    const galleryTasks: DownloadGalleryTask[] = this.downloadTasks()
    const archiverTasks: DownloadArchiverTask[] = this.archiverTasks()
    const oldHasTask: boolean = this.downloadChipHasTask
    const oldStatus: string = this.downloadChipStatus
    const oldArchiverHasTask: boolean = this.archiverChipHasTask
    const oldArchiverStatus: string = this.archiverChipStatus
    this.downloadChipHasTask = galleryTasks.length > 0
    this.downloadChipStatus = GalleryDownloadTaskProjection.aggregateGalleryStatus(galleryTasks)
    this.archiverChipHasTask = archiverTasks.length > 0
    this.archiverChipStatus = GalleryDownloadTaskProjection.aggregateArchiverStatus(archiverTasks)
    if (
      oldHasTask !== this.downloadChipHasTask ||
      oldStatus !== this.downloadChipStatus ||
      oldArchiverHasTask !== this.archiverChipHasTask ||
      oldArchiverStatus !== this.archiverChipStatus
    ) {
      DiagnosticLogger.info(
        'download',
        'detail_download_chip_sync',
        `reason=${reason} gid=${this.params.gid} galleryTasks=${galleryTasks.length} galleryStatus=${this.downloadChipStatus} archiverTasks=${archiverTasks.length} archiverStatus=${this.archiverChipStatus}`,
      )
    }
  }

  private statusTitle(status: string): string {
    if (status === DownloadGalleryTaskStatus.COMPLETE) {
      return AppStrings.get('download_status_complete')
    }
    if (status === DownloadGalleryTaskStatus.DOWNLOADING) {
      return AppStrings.get('download_status_downloading')
    }
    if (status === DownloadGalleryTaskStatus.PAUSED) {
      return AppStrings.get('download_status_paused')
    }
    if (status === DownloadGalleryTaskStatus.PARTIAL) {
      return AppStrings.get('download_status_partial')
    }
    if (status === DownloadGalleryTaskStatus.ERROR) {
      return AppStrings.get('download_status_error')
    }
    if (status === DownloadGalleryTaskStatus.PREPARING) {
      return AppStrings.get('download_status_preparing')
    }
    if (status === DownloadGalleryTaskStatus.READY) {
      return AppStrings.get('download_status_ready')
    }
    return AppStrings.get('download_status_queued')
  }

  private downloadTitle(): string {
    return this.downloadChipHasTask
      ? this.statusTitle(this.downloadChipStatus)
      : AppStrings.get('detail_download')
  }

  private archiverTitle(): string {
    return this.archiverChipHasTask
      ? this.statusTitle(this.archiverChipStatus)
      : AppStrings.get('download_archiver')
  }

  private openDownloadedTaskFromDetail(task: DownloadGalleryTask): void {
    const params: ReaderParams | null = ReaderLocalSourceService.galleryTaskParams(task, this.resumeIndex())
    if (params === null) {
      return
    }
    DiagnosticLogger.info(
      'download',
      'detail_open_local_reader',
      `gid=${task.gid} images=${params.fileCount} index=${params.index} sourceHash=${DiagnosticLogger.ownerHash(params.source.sourceKey)}`,
    )
    connectReaderOverlayNavigation().open(params)
  }

  private onDownloadChipTap(): void {
    if (this.downloadTasks().length > 0) {
      this.downloadMenuShown = true
      return
    }
    this.enqueueGalleryDownloadWithPolicy()
  }

  private downloadVariantLabel(preferOriginal: boolean): ResourceStr {
    return preferOriginal
      ? $r('app.string.download_original_images')
      : $r('app.string.download_use_regular_short')
  }

  private downloadVariantStatus(task: DownloadGalleryTask | null): string {
    if (task === null) {
      return AppStrings.get('detail_download')
    }
    const status: string = GalleryDownloadTaskProjection.effectiveGalleryStatus(task)
    const progress: string = task.downloadProgressText()
    if (progress.length > 0 &&
      (status === DownloadGalleryTaskStatus.DOWNLOADING || status === DownloadGalleryTaskStatus.PARTIAL)) {
      return `${this.statusTitle(status)} · ${progress}`
    }
    return this.statusTitle(status)
  }

  private downloadVariantIcon(task: DownloadGalleryTask | null): SymbolGlyphModifier {
    if (task === null) {
      return new SymbolGlyphModifier($r('sys.symbol.arrow_down_to_line'))
    }
    const status: string = GalleryDownloadTaskProjection.effectiveGalleryStatus(task)
    if (status === DownloadGalleryTaskStatus.COMPLETE) {
      return new SymbolGlyphModifier($r('sys.symbol.checkmark'))
    }
    if (status === DownloadGalleryTaskStatus.ERROR || status === DownloadGalleryTaskStatus.PARTIAL) {
      return new SymbolGlyphModifier($r('sys.symbol.exclamationmark_circle'))
    }
    if (status === DownloadGalleryTaskStatus.PAUSED) {
      return new SymbolGlyphModifier($r('sys.symbol.play'))
    }
    return new SymbolGlyphModifier($r('sys.symbol.clock'))
  }

  private canUseDownloadVariant(task: DownloadGalleryTask | null): boolean {
    if (task === null) {
      return true
    }
    const status: string = GalleryDownloadTaskProjection.effectiveGalleryStatus(task)
    return status !== DownloadGalleryTaskStatus.PREPARING && status !== DownloadGalleryTaskStatus.DOWNLOADING
  }

  private useDownloadVariant(preferOriginal: boolean): void {
    const task: DownloadGalleryTask | null = this.downloadVariantTask(preferOriginal)
    this.downloadMenuShown = false
    if (task === null) {
      this.enqueueGalleryDownload(preferOriginal)
      return
    }
    if (this.isDownloadTaskComplete(task)) {
      this.openDownloadedTaskFromDetail(task)
      return
    }
    if (!this.canUseDownloadVariant(task)) {
      return
    }
    DownloadQueueSettings.downloadGalleryImages(
      this.ctx(),
      task.gid,
      task.token,
      task.preferOriginal,
    ).catch((error: Error) => {
      DiagnosticLogger.warn(
        'download',
        'detail_download_variant_resume_failed',
        `gid=${task.gid} quality=${task.preferOriginal ? 'original' : 'resample'} error=${error.message}`,
      )
    })
  }

  private currentGalleryForLocalFav(): EhGallery {
    const g: EhGallery =
      this.vm.gallery.gid.length > 0
        ? this.vm.gallery.copy()
        : new EhGallery(this.params.gid, this.params.token)
    if (g.thumbUrl.length === 0) {
      g.thumbUrl = this.params.thumbUrl
    }
    if (g.imgWidth === 0) {
      g.imgWidth = this.params.imgWidth
    }
    if (g.imgHeight === 0) {
      g.imgHeight = this.params.imgHeight
    }
    if (g.englishTitle.length === 0) {
      g.englishTitle = this.params.title
    }
    if (g.fileCount.length === 0) {
      g.fileCount = this.params.fileCount
    }
    return g
  }

  private isLocalFavorite(): boolean {
    const gid: string = this.vm.gallery.gid.length > 0 ? this.vm.gallery.gid : this.params.gid
    return this.localFav.items.some((item: EhGallery) => item.gid === gid)
  }

  private localFavoriteLabel(): Resource {
    return $r('app.string.favorites_local')
  }

  private localFavoriteActionLabel(): Resource {
    return this.isLocalFavorite()
      ? $r('app.string.detail_remove_local_favorite')
      : $r('app.string.detail_add_local_favorite')
  }

  private async toggleLocalFavorite(): Promise<void> {
    const gid: string = this.vm.gallery.gid.length > 0 ? this.vm.gallery.gid : this.params.gid
    let message: Resource
    if (LocalFavSettings.contains(gid)) {
      await LocalFavSettings.removeByGid(this.ctx(), gid)
      message = $r('app.string.detail_local_favorite_removed')
    } else {
      await LocalFavSettings.add(this.ctx(), this.currentGalleryForLocalFav())
      message = $r('app.string.detail_local_favorite_added')
    }
    this.getUIContext()
      .getPromptAction()
      .openToast({ message: message })
      .catch((_error: Error) => {
        // Persistence already completed; toast failure should not roll back local favorite state.
      })
  }

  private confirmRemoveLocalFavorite(): void {
    this.getUIContext().showAlertDialog({
      message: $r('app.string.detail_remove_local_favorite_confirm'),
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {},
      },
      secondaryButton: {
        value: $r('app.string.detail_remove_local_favorite'),
        fontColor: Color.Red,
        action: () => {
          this.toggleLocalFavorite()
        },
      },
    })
  }

  private toggleLocalFavoriteWithSafety(): void {
    if (this.isLocalFavorite()) {
      this.confirmRemoveLocalFavorite()
      return
    }
    this.toggleLocalFavorite()
  }

  private currentPersonalRating(): number {
    return this.vm.gallery.isRated && this.vm.gallery.ratingFallBack > 0
      ? this.vm.gallery.ratingFallBack
      : 0
  }

  private openDetailSheet(kind: string): void {
    this.detailSheetKind = kind
    this.detailSheetShown = true
  }

  private closeDetailSheet(): void {
    if (
      this.detailSheetKind === DETAIL_SHEET_REMOTE_FAVORITE &&
      this.remoteFavoriteSheetContent !== null
    ) {
      this.getUIContext()
        .closeBindSheet(this.remoteFavoriteSheetContent)
        .catch((error: Error) => {
          DiagnosticLogger.warn('gallery', 'favorite_sheet_close_failed', error.message)
        })
      return
    }
    this.detailSheetShown = false
  }

  private detailSheetDetentsFor(kind: string): [
    string | number | Resource,
    (string | number | Resource)?,
    (string | number | Resource)?,
  ] {
    if (kind === DETAIL_SHEET_ARCHIVER) {
      return [SheetSize.MEDIUM, SheetSize.LARGE]
    }
    if (kind === DETAIL_SHEET_DOWNLOAD_UPGRADE) {
      return [SheetSize.MEDIUM, SheetSize.LARGE]
    }
    if (kind === DETAIL_SHEET_TORRENTS) {
      return [SheetSize.MEDIUM, SheetSize.LARGE]
    }
    if (kind === DETAIL_SHEET_ADD_TAGS) {
      return [SheetSize.LARGE]
    }
    return [SheetSize.LARGE]
  }

  private isDetailSheetActive(kind: string): boolean {
    return this.detailSheetShown && this.detailSheetKind === kind
  }

  private usesPageDetailSheetHost(): boolean {
    if (!this.detailSheetShown) {
      return false
    }
    // Only title actions without a componentId-backed host stay on the destination root. Favorite is
    // opened through openBindSheet against its actual HDS icon node below.
    return this.detailSheetKind === DETAIL_SHEET_ADD_TAGS ||
      this.detailSheetKind === DETAIL_SHEET_DOWNLOAD_UPGRADE
  }

  private favoriteSheetTargetId(): string {
    return `gallery_detail_favorite_${this.getUniqueId()}`
  }

  private resetRemoteFavoriteSheet(content: ComponentContent<GalleryDetailSheetContentParams>): void {
    if (this.remoteFavoriteSheetContent !== content) {
      return
    }
    this.remoteFavoriteSheetContent = null
    content.dispose()
    if (this.detailSheetKind === DETAIL_SHEET_REMOTE_FAVORITE) {
      this.detailSheetShown = false
      this.detailSheetKind = ''
    }
  }

  private openRemoteFavoriteSheetOnTitleButton(): void {
    const uiContext: UIContext = this.getUIContext()
    const target: FrameNode | null = uiContext.getFrameNodeById(this.favoriteSheetTargetId())
    if (target === null) {
      this.detailSheetShown = false
      this.detailSheetKind = ''
      DiagnosticLogger.warn('gallery', 'favorite_sheet_target_missing', this.favoriteSheetTargetId())
      return
    }
    const params: GalleryDetailSheetContentParams = new GalleryDetailSheetContentParams(() => {
      this.RemoteFavoriteSheet()
    })
    const content: ComponentContent<GalleryDetailSheetContentParams> =
      new ComponentContent<GalleryDetailSheetContentParams>(
        uiContext,
        wrapBuilder<[GalleryDetailSheetContentParams]>(galleryDetailSheetContentBuilder),
        params,
        { nestingBuilderSupported: true },
      )
    this.remoteFavoriteSheetContent = content
    uiContext
      .openBindSheet(
        content,
        appSheetOptions({
          detents: this.detailSheetDetentsFor(DETAIL_SHEET_REMOTE_FAVORITE),
          showClose: false,
          keyboardAvoidMode: SheetKeyboardAvoidMode.TRANSLATE_AND_RESIZE,
          onDisappear: () => {
            this.resetRemoteFavoriteSheet(content)
          },
        }),
        target.getUniqueId(),
      )
      .catch((error: Error) => {
        DiagnosticLogger.warn('gallery', 'favorite_sheet_open_failed', error.message)
        this.resetRemoteFavoriteSheet(content)
      })
  }

  private detailSheetOptions(kind: string): SheetOptions {
    return appSheetOptions({
      detents: this.detailSheetDetentsFor(kind),
      showClose: false,
      keyboardAvoidMode: SheetKeyboardAvoidMode.TRANSLATE_AND_RESIZE,
      onDisappear: () => {
        if (this.detailSheetKind === kind) {
          this.closeDetailSheet()
        }
      },
    })
  }

  private openRatingDialog(): void {
    this.ratingSelected = this.currentPersonalRating()
    this.ratingError = ''
    this.ratingDialogController.open()
  }

  private closeRatingDialog(): void {
    try {
      this.ratingDialogController.close()
    } catch (_error) {
      // Dialog may already be dismissed by tapping outside.
    }
  }

  private ratingLabel(value: number): string {
    return `${value.toFixed(1)} / 5`
  }

  private ratingHint(): string {
    if (this.vm.gallery.apikey.length === 0 || this.vm.gallery.apiuid.length === 0) {
      return AppStrings.get('detail_rate_missing_key')
    }
    if (this.currentPersonalRating() > 0) {
      return `${AppStrings.get('detail_rate_current')}${this.ratingLabel(this.currentPersonalRating())}`
    }
    return AppStrings.get('detail_rate_write_notice')
  }

  private async submitRating(): Promise<void> {
    if (this.ratingSubmitting) {
      return
    }
    if (this.vm.gallery.apikey.length === 0 || this.vm.gallery.apiuid.length === 0) {
      this.ratingError = AppStrings.get('detail_rate_missing_key')
      return
    }
    if (this.ratingSelected <= 0) {
      return
    }
    this.ratingSubmitting = true
    this.ratingError = ''
    try {
      const result: GalleryRatingResult = await this.vm.rateGallery(this.ratingSelected)
      this.ratingMutation.publish(
        this.vm.gallery.gid,
        result.userRating,
        result.averageRating,
        result.ratingCount,
        result.colorRating,
      )
      this.closeRatingDialog()
      this.getUIContext()
        .getPromptAction()
        .openToast({ message: $r('app.string.detail_rate_success') })
        .catch((_error: Error) => {})
    } catch (err) {
      this.ratingError = EhErrorText.forUser(err)
      this.getUIContext()
        .getPromptAction()
        .openToast({ message: $r('app.string.detail_rate_failed') })
        .catch((_error: Error) => {})
    } finally {
      this.ratingSubmitting = false
    }
  }

  private async enqueueGalleryDownload(preferOriginal: boolean = false): Promise<void> {
    const task: DownloadGalleryTask = DownloadGalleryTask.fromGallery(
      this.vm.gallery,
      this.params.gid,
      this.params.token,
    )
    task.preferOriginal = preferOriginal
    DiagnosticLogger.info(
      'download',
      'detail_enqueue_request',
      `gid=${task.gid} tokenHash=${DiagnosticLogger.ownerHash(task.token)} preferOriginal=${preferOriginal} images=${this.vm.images.length}`,
    )
    if (!await DownloadQueueSettings.ensureDownloadStorageReady(this.ctx())) {
      this.getUIContext()
        .getPromptAction()
        .openToast({ message: $r('app.string.common_load_failed') })
        .catch((_error: Error) => {})
      return
    }
    const inserted: boolean = await DownloadQueueSettings.enqueueGallery(this.ctx(), task)
    this.markDownloadQueueDirty()
    DownloadQueueSettings.prepareGallerySeeds(
      this.ctx(),
      task.gid,
      task.token,
      connectSiteMode().isEx,
      this.vm.images,
      this.vm.previewPageCount,
      task.preferOriginal,
    ).catch((error: Error) => {
      DiagnosticLogger.warn(
        'download',
        'detail_prepare_failed',
        `gid=${task.gid} tokenHash=${DiagnosticLogger.ownerHash(task.token)} error=${error.message}`,
      )
    })
    this.getUIContext()
      .getPromptAction()
      .openToast({
        message: inserted
          ? $r('app.string.download_gallery_added')
          : $r('app.string.download_gallery_already_queued'),
      })
      .catch((_error: Error) => {
        // The queue state has already been written; toast failure should not undo the user action.
      })
  }

  private enqueueGalleryDownloadWithPolicy(): void {
    const originalMode: string = connectDownloadSettings().originalMode
    const gid: string = this.vm.gallery.gid.length > 0 ? this.vm.gallery.gid : this.params.gid
    const token: string = this.vm.gallery.token.length > 0 ? this.vm.gallery.token : this.params.token
    DiagnosticLogger.info(
      'download',
      'detail_download_tap',
      `gid=${gid} tokenHash=${DiagnosticLogger.ownerHash(token)} originalMode=${originalMode}`,
    )
    if (originalMode === DownloadOriginalMode.ALWAYS) {
      this.enqueueGalleryDownload(true)
      return
    }
    if (originalMode !== DownloadOriginalMode.ASK) {
      this.enqueueGalleryDownload(false)
      return
    }
    this.getUIContext().showAlertDialog({
      title: $r('app.string.download_original_images'),
      message: $r('app.string.download_original_prompt'),
      primaryButton: {
        value: $r('app.string.download_use_regular_image'),
        action: () => {
          this.enqueueGalleryDownload(false)
        },
      },
      secondaryButton: {
        value: $r('app.string.download_use_original_image'),
        action: () => {
          this.enqueueGalleryDownload(true)
        },
      },
    })
  }

  private canShowDownloadUpgrade(): boolean {
    return this.completeDownloadTask() !== null && this.vm.gallery.newerVersions.length > 0
  }

  private openDownloadUpgradeSheet(): void {
    if (!this.canShowDownloadUpgrade()) {
      return
    }
    this.downloadUpgradeBusyGid = ''
    this.openDetailSheet(DETAIL_SHEET_DOWNLOAD_UPGRADE)
  }

  private enqueueDownloadUpgradeWithPolicy(version: EhGalleryVersion): void {
    const originalMode: string = connectDownloadSettings().originalMode
    DiagnosticLogger.info(
      'download',
      'detail_download_upgrade_tap',
      `from=${this.params.gid} to=${version.gid} originalMode=${originalMode}`,
    )
    if (originalMode === DownloadOriginalMode.ALWAYS) {
      this.enqueueDownloadUpgrade(version, true)
      return
    }
    if (originalMode !== DownloadOriginalMode.ASK) {
      this.enqueueDownloadUpgrade(version, false)
      return
    }
    this.getUIContext().showAlertDialog({
      title: $r('app.string.download_original_images'),
      message: $r('app.string.download_original_prompt'),
      primaryButton: {
        value: $r('app.string.download_use_regular_image'),
        action: () => {
          this.enqueueDownloadUpgrade(version, false)
        },
      },
      secondaryButton: {
        value: $r('app.string.download_use_original_image'),
        action: () => {
          this.enqueueDownloadUpgrade(version, true)
        },
      },
    })
  }

  private async enqueueDownloadUpgrade(version: EhGalleryVersion, preferOriginal: boolean): Promise<void> {
    if (this.downloadUpgradeBusyGid.length > 0) {
      return
    }
    this.downloadUpgradeBusyGid = version.gid
    try {
      DiagnosticLogger.info(
        'download',
        'detail_download_upgrade_start',
        `from=${this.params.gid} to=${version.gid} tokenHash=${DiagnosticLogger.ownerHash(version.token)} preferOriginal=${preferOriginal}`,
      )
      const detail: GalleryDetailResult = await EhApiService.getInstance().getGalleryDetail(
        version.gid,
        version.token,
        connectSiteMode().isEx,
      )
      const task: DownloadGalleryTask = DownloadGalleryTask.fromGallery(
        detail.gallery,
        version.gid,
        version.token,
      )
      task.upgradeFromGid = this.params.gid
      task.preferOriginal = preferOriginal
      const inserted: boolean = await DownloadQueueSettings.enqueueGallery(this.ctx(), task)
      this.markDownloadQueueDirty()
      await DownloadQueueSettings.prepareGallerySeeds(
        this.ctx(),
        task.gid,
        task.token,
        connectSiteMode().isEx,
        detail.images,
        detail.previewPageCount,
        task.preferOriginal,
      )
      DiagnosticLogger.info(
        'download',
        'detail_download_upgrade_enqueued',
        `from=${this.params.gid} to=${task.gid} inserted=${inserted}`,
      )
      this.getUIContext()
        .getPromptAction()
        .openToast({
          message: inserted
            ? $r('app.string.download_gallery_added')
            : $r('app.string.download_gallery_already_queued'),
        })
        .catch((_error: Error) => {})
      this.closeDetailSheet()
    } catch (error) {
      DiagnosticLogger.warn(
        'download',
        'detail_download_upgrade_failed',
        `from=${this.params.gid} to=${version.gid} error=${(error as Error).message}`,
      )
      this.getUIContext()
        .getPromptAction()
        .openToast({ message: EhErrorText.forUser(error) })
        .catch((_toastError: Error) => {})
    } finally {
      this.downloadUpgradeBusyGid = ''
    }
  }

  private allThumbnailsParams(initialImagePage: number, includeSession: boolean): AllThumbnailsParams {
    let seedImages: EhGalleryImage[] = []
    let seedPreviewPages: number[] = []
    let seedPerPage: number = 0
    let seedCurrentPreviewPage: number = 0
    if (includeSession && this.fullPreviewVm.hasSeeded()) {
      seedImages = this.fullPreviewVm.loadedImages()
      seedPreviewPages = this.fullPreviewVm.loadedPreviewPageNumbers()
      seedPerPage = this.fullPreviewVm.seedPerPage()
      seedCurrentPreviewPage = this.fullPreviewVm.currentPreviewPageNumber()
    }
    return new AllThumbnailsParams(
      this.params.gid,
      this.params.token,
      connectSiteMode().isEx,
      this.fileCountNum(),
      this.vm.previewPageCount,
      this.navTitle(),
      this.vm.images,
      initialImagePage,
      seedImages,
      seedPreviewPages,
      seedPerPage,
      seedCurrentPreviewPage,
      this.vm.gallery.contentLanguage(),
    )
  }

  private ensureFullPreviewSeeded(): void {
    if (this.fullPreviewMustReset || this.params.gid.length === 0 || this.vm.images.length === 0) {
      return
    }
    this.fullPreviewVm.syncDetailFirstPage(this.allThumbnailsParams(0, false), true)
  }

  private openThumbnails(initialImagePage: number = 0): void {
    if (this.fullPreviewMustReset) {
      return
    }
    this.ensureFullPreviewSeeded()
    this.stack.pushPathByName(
      'AllThumbnails',
      this.allThumbnailsParams(initialImagePage, true),
    )
  }

  private scrollFullPreviewToImagePage(pageOneBased: number): void {
    const targetIndex: number = this.fullPreviewVm.visibleIndexForImagePage(pageOneBased)
    if (targetIndex < 0) {
      return
    }
    setTimeout(() => {
      this.fullPreviewScroller.scrollToIndex(targetIndex)
    }, 50)
  }

  private async backFullPreviewToFirstPage(): Promise<void> {
    const loaded: boolean = await this.fullPreviewVm.loadImagePage(1)
    if (loaded) {
      this.scrollFullPreviewToImagePage(1)
    }
  }

  private fullPreviewMaxImagePage(): number {
    const fileCount: number = this.fileCountNum()
    return fileCount > 0 ? fileCount : this.fullPreviewVm.itemCount
  }

  private fullPreviewDefaultJumpPage(): number {
    const maxPage: number = this.fullPreviewMaxImagePage()
    if (maxPage <= 0) {
      return 1
    }
    return Math.min(maxPage, this.fullPreviewVm.itemCount + 1)
  }

  private openFullPreviewJumpDialog(): void {
    this.fullPreviewJumpPageText = `${this.fullPreviewDefaultJumpPage()}`
    this.fullPreviewJumpError = ''
    this.fullPreviewJumpDialogController.open()
  }

  private closeFullPreviewJumpDialog(): void {
    try {
      this.fullPreviewJumpDialogController.close()
    } catch (_error) {
      // Dialog may already be dismissed by tapping outside.
    }
  }

  private normalizeFullPreviewJumpInput(value: string): string {
    return (value || '').replace(/[^0-9]/g, '')
  }

  private fullPreviewJumpHelpText(): string {
    const maxPage: number = this.fullPreviewMaxImagePage()
    if (maxPage <= 0) {
      return AppStrings.get('gallery_preview_jump_help')
    }
    return `${AppStrings.get('gallery_preview_jump_help')} 1 - ${maxPage}`
  }

  private confirmFullPreviewJump(): void {
    if (this.fullPreviewJumpSubmitting) {
      return
    }
    const page: number = Number.parseInt(this.fullPreviewJumpPageText, 10)
    const maxPage: number = this.fullPreviewMaxImagePage()
    if (Number.isNaN(page) || page <= 0 || (maxPage > 0 && page > maxPage)) {
      this.fullPreviewJumpError = AppStrings.get('gallery_preview_jump_invalid')
      return
    }
    this.fullPreviewJumpSubmitting = true
    this.fullPreviewVm.loadImagePage(page)
      .then((loaded: boolean) => {
        this.fullPreviewJumpSubmitting = false
        if (!loaded) {
          this.fullPreviewJumpError = AppStrings.get('common_load_failed')
          return
        }
        this.closeFullPreviewJumpDialog()
        this.scrollFullPreviewToImagePage(page)
      })
      .catch((_error: Error) => {
        this.fullPreviewJumpSubmitting = false
        this.fullPreviewJumpError = AppStrings.get('common_load_failed')
      })
  }

  private detailBottomPreviewInitialPage(): number {
    if (this.thumbMode.hideGalleryThumbnails || this.thumbMode.horizontalThumbnails) {
      return 0
    }
    if (this.vm.images.length === 0) {
      return 0
    }
    return this.vm.images[this.vm.images.length - 1].page
  }

  // Scroll-revealed title (empty until the header card scrolls past) over the app's immersive
  // GRADIENT_BLUR title-bar backdrop, same as every other page.
  private detailTitleBar(): Record<string, Object> {
    const title: Record<string, Object> = {
      'mainTitle': this.showNavTitle ? this.navTitle() : '',
    }
    const content: Record<string, Object> = { 'title': title, 'menu': this.detailMenu() }
    return immersiveTitleBarOpts(content)
  }

  // Native HDS title-bar actions. Read remains the primary FAB; secondary tools stay in the title-bar
  // menu so detail content does not gain ad-hoc action rows.
  private detailMenu(): Record<string, Object> {
    const favoriteInner: Record<string, Object> = {
      'label': $r('app.string.detail_favorite'),
      'icon': this.favoriteTitleBarIcon(),
      'componentId': this.favoriteSheetTargetId(),
      'isEnabled': true,
      'action': () => {
        this.openRemoteFavorite()
      },
    }
    const shareInner: Record<string, Object> = {
      'label': $r('app.string.detail_share'),
      'icon': $r('sys.symbol.share'),
      'isEnabled': true,
      'action': () => {
        this.shareGallery()
      },
    }
    const commentsInner: Record<string, Object> = {
      'label': $r('app.string.gallery_comments'),
      'icon': $r('sys.symbol.doc_plaintext'),
      'isEnabled': true,
      'action': () => {
        this.openComments()
      },
    }
    const previewFirstInner: Record<string, Object> = {
      'label': $r('app.string.gallery_preview_first_page'),
      'icon': $r('sys.symbol.arrow_up_circle'),
      'isEnabled': !this.fullPreviewVm.loading,
      'action': () => {
        this.backFullPreviewToFirstPage()
      },
    }
    const previewJumpInner: Record<string, Object> = {
      'label': $r('app.string.gallery_preview_jump'),
      'icon': $r('sys.symbol.arrow_right'),
      'isEnabled': !this.fullPreviewVm.loading,
      'action': () => {
        this.openFullPreviewJumpDialog()
      },
    }
    const parentInner: Record<string, Object> = {
      'label': $r('app.string.detail_parent'),
      'icon': $r('sys.symbol.link'),
      'isEnabled': true,
      'action': () => {
        this.openParentGallery()
      },
    }
    const refreshInner: Record<string, Object> = {
      'label': $r('app.string.common_refresh'),
      'icon': $r('sys.symbol.arrow_clockwise'),
      'isEnabled': !this.detailRefreshInFlight,
      'action': () => {
        this.refreshFromTitle()
      },
    }
    const downloadUpgradeInner: Record<string, Object> = {
      'label': $r('app.string.download_upgrade_newer'),
      'icon': $r('sys.symbol.arrow_down_to_line'),
      'isEnabled': this.canShowDownloadUpgrade(),
      'action': () => {
        this.openDownloadUpgradeSheet()
      },
    }
    const addTagsInner: Record<string, Object> = {
      'label': $r('app.string.detail_add_tags'),
      'icon': $r('sys.symbol.plus'),
      'isEnabled': !this.safeMode.restricted(),
      'action': () => {
        this.openAddTags()
      },
    }
    const copyLinkInner: Record<string, Object> = {
      'label': $r('app.string.detail_copy_link'),
      'icon': $r('sys.symbol.doc_text_on_doc_text'),
      'isEnabled': true,
      'action': () => {
        this.copyGalleryLink()
      },
    }
    const copyTitleInner: Record<string, Object> = {
      'label': $r('app.string.detail_copy_title'),
      'icon': $r('sys.symbol.doc_text_on_doc_text'),
      'isEnabled': true,
      'action': () => {
        this.copyGalleryTitle()
      },
    }
    const openBrowserInner: Record<string, Object> = {
      'label': $r('app.string.detail_open_browser'),
      'icon': $r('sys.symbol.arrow_right'),
      'isEnabled': true,
      'action': () => {
        this.openExternalBrowser()
      },
    }
    const openWebInner: Record<string, Object> = {
      'label': $r('app.string.detail_open_internal_web'),
      'icon': $r('sys.symbol.house_fill'),
      'isEnabled': true,
      'action': () => {
        this.openInternalWeb()
      },
    }
    const items: Record<string, Object>[] = [
      { 'content': favoriteInner },
      { 'content': shareInner },
      { 'content': commentsInner },
      { 'content': refreshInner },
      { 'content': addTagsInner },
      { 'content': copyLinkInner },
      { 'content': copyTitleInner },
      { 'content': openBrowserInner },
      { 'content': openWebInner },
    ]
    if (this.usesSplitDetailLayout() && this.fullPreviewVm.itemCount > 0) {
      items.splice(3, 0, { 'content': previewFirstInner })
      items.splice(4, 0, { 'content': previewJumpInner })
    }
    if (this.vm.gallery.parentGid.length > 0 && this.vm.gallery.parentGid !== this.params.gid) {
      items.splice(3, 0, { 'content': parentInner })
    }
    if (this.canShowDownloadUpgrade()) {
      items.splice(4, 0, { 'content': downloadUpgradeInner })
    }
    return { 'value': items, 'maxCount': 3 }
  }

  private favoriteTitleBarIcon(): Resource | SymbolGlyphModifier {
    if (this.vm.gallery.favcat.length > 0) {
      return new SymbolGlyphModifier($r('sys.symbol.heart_fill')).fontColor([
        EhConstants.favCatColor(this.vm.gallery.favcat),
      ])
    }
    if (this.isLocalFavorite()) {
      return new SymbolGlyphModifier($r('sys.symbol.heart_fill')).fontColor([
        EhConstants.favCatColor('l'),
      ])
    }
    return $r('sys.symbol.heart')
  }

  private galleryUrl(): string {
    return `${EhConstants.baseUrl(connectSiteMode().isEx)}/g/${this.params.gid}/${this.params.token}/`
  }

  private async refreshFromTitle(): Promise<void> {
    if (this.detailRefreshInFlight) {
      return
    }
    this.detailRefreshInFlight = true
    try {
      await this.vm.refresh()
    } catch (_error) {
      this.getUIContext()
        .getPromptAction()
        .openToast({
          message: $r('app.string.common_refresh_failed'),
        })
        .catch((_toastError: Error) => {})
    } finally {
      this.detailRefreshInFlight = false
    }
  }

  // Share the gallery's public /g/<gid>/<token>/ URL via the system share sheet (eros_fe shareText).
  private shareGallery(): void {
    ShareUtil.shareGallery(
      this.getUIContext().getHostContext() as common.UIAbilityContext,
      this.params.gid,
      this.params.token,
      connectSiteMode().isEx,
      this.vm.gallery.title(),
    )
  }

  private copyText(text: string, message: ResourceStr): void {
    const content: string = text.trim()
    if (content.length === 0) {
      return
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, content)
      pasteboard.getSystemPasteboard().setDataSync(data)
      this.getUIContext()
        .getPromptAction()
        .openToast({ message: message })
        .catch((_error: Error) => {})
    } catch (_error) {
      this.getUIContext()
        .getPromptAction()
        .openToast({
          message: $r('app.string.error_http'),
        })
        .catch((_toastError: Error) => {})
    }
  }

  private copyGalleryLink(): void {
    this.copyText(this.galleryUrl(), $r('app.string.detail_link_copied'))
  }

  private copyGalleryTitle(): void {
    this.copyText(this.primaryDetailTitle(), $r('app.string.detail_title_copied'))
  }

  private visiblePreviewComments(): EhGalleryComment[] {
    return LocalBlockService.filterComments(this.vm.comments)
  }

  private openFullTitleSheet(): void {
    if (this.englishDetailTitle().length === 0 && this.japaneseDetailTitle().length === 0) {
      return
    }
    this.openDetailSheet(DETAIL_SHEET_FULL_TITLE)
  }

  private openExternalBrowser(): void {
    const want: Want = { action: 'ohos.want.action.viewData', uri: this.galleryUrl() }
    this.ctx()
      .startAbility(want)
      .catch((_error: Error) => {
        this.getUIContext()
          .getPromptAction()
          .openToast({
            message: $r('app.string.error_http'),
          })
          .catch((_toastError: Error) => {})
      })
  }

  private openInternalWeb(): void {
    this.stack.pushPathByName(
      'GalleryWeb',
      new GalleryWebParams(this.galleryUrl(), this.navTitle()),
    )
  }

  private openAddTags(): void {
    if (this.safeMode.restricted()) {
      return
    }
    this.openDetailSheet(DETAIL_SHEET_ADD_TAGS)
  }

  private async refreshTagsAfterAdd(): Promise<void> {
    this.closeDetailSheet()
    try {
      await this.vm.refresh()
      this.getUIContext()
        .getPromptAction()
        .openToast({ message: $r('app.string.detail_add_tags_success') })
        .catch((_error: Error) => {})
    } catch (err) {
      DiagnosticLogger.warn('gallery', 'tag_add_refresh_failed', (err as Error).message)
      this.getUIContext()
        .getPromptAction()
        .openToast({ message: $r('app.string.common_refresh_failed') })
        .catch((_error: Error) => {})
    }
  }

  private openRemoteFavorite(): void {
    if (this.remoteFavoriteSheetContent !== null) {
      return
    }
    this.remoteFavoriteSelectedCat = this.vm.gallery.favcat.length > 0 ? this.vm.gallery.favcat : ''
    this.remoteFavoriteNote = this.vm.gallery.favNote
    this.remoteFavoriteError = ''
    if (this.remoteFavoriteSlots.length === 0 && this.favoriteSlotCache.favcats.length > 0) {
      this.remoteFavoriteSlots = this.copyFavcats(this.favoriteSlotCache.favcats)
    }
    this.detailSheetKind = DETAIL_SHEET_REMOTE_FAVORITE
    this.detailSheetShown = true
    this.openRemoteFavoriteSheetOnTitleButton()
    this.refreshRemoteFavcats()
  }

  private copyFavcats(favcats: Favcat[]): Favcat[] {
    const out: Favcat[] = []
    favcats.forEach((fav: Favcat) => {
      out.push(new Favcat(fav.favId, fav.favTitle, fav.totNum))
    })
    return out
  }

  private async refreshRemoteFavcats(): Promise<void> {
    if (this.remoteFavoriteLoadingFavcats) {
      return
    }
    this.remoteFavoriteLoadingFavcats = true
    this.remoteFavoriteError = ''
    try {
      const info: GalleryFavoriteInfo = await EhApiService.getInstance().getGalleryFavoriteInfo(
        connectSiteMode().isEx,
        this.params.gid,
        this.params.token,
      )
      this.remoteFavoriteSlots = info.favcats
      if (info.favcats.length > 0) {
        this.favoriteSlotCache.update(info.favcats)
        await FavcatListSettings.persist(this.ctx(), info.favcats)
      }
      const selectedStillExists: boolean =
        info.favcats.findIndex((fav: Favcat) => fav.favId === this.remoteFavoriteSelectedCat) >= 0
      const currentStillExists: boolean =
        this.vm.gallery.favcat.length > 0 &&
        info.favcats.findIndex((fav: Favcat) => fav.favId === this.vm.gallery.favcat) >= 0
      if (this.vm.gallery.favcat.length > 0 && info.selectFavcat.length > 0) {
        this.remoteFavoriteSelectedCat = info.selectFavcat
      } else if (currentStillExists) {
        this.remoteFavoriteSelectedCat = this.vm.gallery.favcat
      } else if (!selectedStillExists || this.remoteFavoriteSelectedCat === 'favdel') {
        this.remoteFavoriteSelectedCat = ''
      }
      this.remoteFavoriteNote = info.favNote
      if (info.favcats.length === 0) {
        this.remoteFavoriteError = AppStrings.get('detail_remote_favorite_no_slots')
      }
    } catch (e) {
      this.remoteFavoriteError = EhErrorText.forUser(e)
    } finally {
      this.remoteFavoriteLoadingFavcats = false
    }
  }

  private async submitRemoteFavorite(): Promise<void> {
    if (this.remoteFavoriteSubmitting) {
      return
    }
    this.remoteFavoriteSubmitting = true
    this.remoteFavoriteError = ''
    const favcat: string =
      this.remoteFavoriteSelectedCat.length > 0 ? this.remoteFavoriteSelectedCat : 'favdel'
    const nextFavcat: string = favcat === 'favdel' ? '' : favcat
    const nextFavTitle: string =
      nextFavcat.length > 0 ? this.remoteFavoriteTitleFor(nextFavcat) : ''
    const nextFavNote: string = nextFavcat.length > 0 ? this.remoteFavoriteNote.trim() : ''
    const previousFavcat: string = this.vm.gallery.favcat
    const previousFavTitle: string = this.vm.gallery.favTitle
    const previousFavNote: string = this.vm.gallery.favNote
    this.vm.applyRemoteFavoriteState(nextFavcat, nextFavTitle, nextFavNote)
    this.favoriteMutation.publish(this.params.gid, nextFavcat, nextFavTitle, nextFavNote)
    this.remoteFavoriteSelectedCat = nextFavcat
    this.remoteFavoriteNote = nextFavNote
    this.closeDetailSheet()
    try {
      await EhApiService.getInstance().updateGalleryFavorite({
        isEx: connectSiteMode().isEx,
        gid: this.params.gid,
        token: this.params.token,
        favcat: favcat,
        favnote: nextFavNote,
      })
      await this.vm.refresh()
      this.vm.applyRemoteFavoriteState(nextFavcat, nextFavTitle, nextFavNote)
      this.favoriteMutation.publish(this.params.gid, nextFavcat, nextFavTitle, nextFavNote)
      this.getUIContext()
        .getPromptAction()
        .openToast({
          message: $r('app.string.detail_remote_favorite_saved'),
        })
        .catch((_toastError: Error) => {})
    } catch (e) {
      this.remoteFavoriteError = EhErrorText.forUser(e)
      this.vm.applyRemoteFavoriteState(previousFavcat, previousFavTitle, previousFavNote)
      this.favoriteMutation.publish(
        this.params.gid,
        previousFavcat,
        previousFavTitle,
        previousFavNote,
      )
      this.remoteFavoriteSelectedCat = previousFavcat
      this.remoteFavoriteNote = previousFavNote
      this.getUIContext()
        .getPromptAction()
        .openToast({
          message: this.remoteFavoriteError,
        })
        .catch((_toastError: Error) => {})
    } finally {
      this.remoteFavoriteSubmitting = false
    }
  }

  private isRemoteFavoriteSlotSelected(favcat: string): boolean {
    return this.remoteFavoriteSelectedCat === favcat
  }

  private isCurrentRemoteFavoriteSlot(favcat: string): boolean {
    return this.vm.gallery.favcat.length > 0 && this.vm.gallery.favcat === favcat
  }

  private remoteFavoriteSelectedTitle(): string {
    const index: number = this.remoteFavoriteSlots.findIndex(
      (fav: Favcat) => fav.favId === this.remoteFavoriteSelectedCat,
    )
    return index >= 0 ? this.remoteFavoriteSlots[index].favTitle : ''
  }

  private remoteFavoriteTitleFor(favcat: string): string {
    const index: number = this.remoteFavoriteSlots.findIndex((fav: Favcat) => fav.favId === favcat)
    return index >= 0 ? this.remoteFavoriteSlots[index].favTitle : ''
  }

  private remoteFavoriteStatusText(): ResourceStr {
    if (this.remoteFavoriteSelectedCat === 'favdel') {
      return $r('app.string.detail_remote_favorite_will_remove')
    }
    if (this.remoteFavoriteSelectedCat.length === 0) {
      return $r('app.string.detail_remote_favorite_none')
    }
    if (this.vm.gallery.favcat.length === 0) {
      return $r('app.string.detail_remote_favorite_will_add', this.remoteFavoriteSelectedTitle())
    }
    if (this.remoteFavoriteSelectedCat === this.vm.gallery.favcat) {
      return $r('app.string.detail_remote_favorite_current_slot', this.vm.gallery.favTitle)
    }
    return $r('app.string.detail_remote_favorite_will_move', this.remoteFavoriteSelectedTitle())
  }

  private remoteFavoriteStatusColor(): ResourceColor {
    if (this.remoteFavoriteSelectedCat === 'favdel') {
      return Color.Red
    }
    if (
      this.remoteFavoriteSelectedCat.length > 0 &&
      (this.vm.gallery.favcat.length === 0 ||
        this.remoteFavoriteSelectedCat !== this.vm.gallery.favcat)
    ) {
      return $r('sys.color.font_primary')
    }
    return $r('sys.color.font_secondary')
  }

  private canSubmitRemoteFavorite(): boolean {
    if (this.remoteFavoriteSlots.length === 0) {
      return false
    }
    return this.remoteFavoriteSelectedCat.length > 0 || this.vm.gallery.favcat.length > 0
  }

  @Builder
  private FullTitleSheet() {
    AppModalScaffold({
      title: $r('app.string.detail_full_title'),
      showConfirmAction: false,
      closeAction: () => {
        this.closeDetailSheet()
      },
    }) {
      ListItem() {
        GroupedListSection({ inset: 0 }) {
          Column({ space: ThemeConstants.SPACE_MD }) {
            if (this.englishDetailTitle().length > 0) {
              this.TitleReadBlock(
                $r('app.string.detail_info_title'),
                this.englishDetailTitle(),
                $r('app.string.detail_title_translation'),
                TITLE_TRANSLATION_REGULAR,
              )
            }
            if (this.japaneseDetailTitle().length > 0) {
              this.TitleReadBlock(
                $r('app.string.detail_info_jpn_title'),
                this.japaneseDetailTitle(),
                $r('app.string.detail_japanese_title_translation'),
                TITLE_TRANSLATION_JAPANESE,
              )
            }
          }
          .width('100%')
          .padding(ThemeConstants.SPACE_MD)
        }
      }
    }
  }

  @Builder
  private TitleReadBlock(
    label: ResourceStr,
    value: string,
    translationLabel: Resource,
    kind: string,
  ) {
    Column() {
      Row({ space: ThemeConstants.SPACE_SM }) {
        Text(label)
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_secondary'))
          .layoutWeight(1)
        this.TitleTranslationAction(kind, translationLabel)
      }
      .alignItems(VerticalAlign.Center)
      .width('100%')
      Text(value)
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor($r('sys.color.font_primary'))
        .lineHeight(ThemeConstants.LINE_HEIGHT_BODY)
        .copyOption(CopyOptions.LocalDevice)
        .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
        .width('100%')
        .margin({ top: ThemeConstants.SPACE_XS })
      this.TitleTranslationArea(translationLabel, kind)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private TitleTranslationTextContent(translationLabel: Resource, kind: string) {
    Text(translationLabel)
      .fontSize(ThemeConstants.FONT_SIZE_BODY)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('sys.color.font_secondary'))
      .width('100%')
    Text(this.titleTranslationTextFor(kind))
      .fontSize(ThemeConstants.FONT_SIZE_BODY)
      .fontColor($r('sys.color.font_primary'))
      .lineHeight(ThemeConstants.LINE_HEIGHT_BODY)
      .copyOption(CopyOptions.LocalDevice)
      .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
      .width('100%')
  }

  @Builder
  private TitleTranslationLayers(translationLabel: Resource, kind: string) {
    if (
      this.titleTranslationShownFor(kind) &&
      this.titleTranslationTextFor(kind).length > 0
    ) {
      Column({ space: ThemeConstants.SPACE_XS }) {
        this.TitleTranslationTextContent(translationLabel, kind)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ top: ThemeConstants.SPACE_XS * 2 })
      .onAreaChange((_oldArea: Area, area: Area) => {
        this.updateTitleTranslationMeasuredHeight(kind, area)
      })
    }
    if (
      this.titleTranslationStateFor(kind).pendingMeasure &&
      this.titleTranslationTextFor(kind).length > 0
    ) {
      Column({ space: ThemeConstants.SPACE_XS }) {
        this.TitleTranslationTextContent(translationLabel, kind)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ top: ThemeConstants.SPACE_XS * 2 })
      .opacity(0)
      .hitTestBehavior(HitTestMode.None)
      .position({ x: 0, y: 0 })
      .onAreaChange((_oldArea: Area, area: Area) => {
        this.handlePendingTitleTranslationArea(kind, area)
      })
    }
  }

  @Builder
  private TitleTranslationArea(translationLabel: Resource, kind: string) {
    if (this.titleTranslationStateFor(kind).heightLocked) {
      Stack({ alignContent: Alignment.TopStart }) {
        this.TitleTranslationLayers(translationLabel, kind)
      }
      .width('100%')
      .height(this.titleTranslationStateFor(kind).animatedHeight)
      .clip(true)
      .opacity(this.titleTranslationStateFor(kind).contentOpacity)
    } else {
      Stack({ alignContent: Alignment.TopStart }) {
        this.TitleTranslationLayers(translationLabel, kind)
      }
      .width('100%')
    }
  }

  @Builder
  private TitleTranslationAction(kind: string, label: Resource) {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      if (this.titleTranslationLoadingFor(kind)) {
        LoadingProgress()
          .width(TITLE_TRANSLATION_ICON_SIZE)
          .height(TITLE_TRANSLATION_ICON_SIZE)
      } else {
        SymbolGlyph($r('sys.symbol.translate'))
          .fontSize(TITLE_TRANSLATION_ICON_SIZE)
          .fontColor([
            this.titleTranslationShownFor(kind) && this.titleTranslationTextFor(kind).length > 0
              ? ThemeConstants.BRAND_PRIMARY
              : $r('sys.color.font_tertiary'),
          ])
      }
    }
    .buttonStyle(ButtonStyleMode.NORMAL)
    .backgroundColor(Color.Transparent)
    .width(TITLE_TRANSLATION_ACTION_SIZE)
    .height(TITLE_TRANSLATION_ACTION_SIZE)
    .enabled(!this.titleTranslationBusyFor(kind))
    .opacity(1)
    .accessibilityText(label)
    .onClick(() => {
      this.toggleOrTranslateTitle(kind)
    })
  }

  private downloadUpgradeTitle(version: EhGalleryVersion): string {
    if (version.title.length > 0) {
      return version.title
    }
    return AppStrings.get('download_upgrade_untitled')
  }

  private downloadUpgradeSubtitle(version: EhGalleryVersion): string {
    if (version.posted.length > 0) {
      return `${version.posted} · ${version.gid}`
    }
    return version.gid
  }

  private downloadUpgradeTrailing(version: EhGalleryVersion): string {
    if (this.downloadUpgradeBusyGid === version.gid) {
      return AppStrings.get('common_loading')
    }
    return ''
  }

  @Builder
  private DownloadUpgradeSheet() {
    AppModalScaffold({
      title: $r('app.string.download_upgrade_choose'),
      showConfirmAction: false,
      closeAction: () => {
        this.closeDetailSheet()
      },
    }) {
      ListItem() {
        GroupedListSection({ inset: 0 }) {
          ForEach(
            this.vm.gallery.newerVersions,
            (version: EhGalleryVersion) => {
              ConciseListRow({
                title: this.downloadUpgradeTitle(version),
                subtitle: this.downloadUpgradeSubtitle(version),
                trailingText: this.downloadUpgradeTrailing(version),
                showChevron: this.downloadUpgradeBusyGid.length === 0,
                isEnabled: this.downloadUpgradeBusyGid.length === 0,
                action: () => {
                  this.enqueueDownloadUpgradeWithPolicy(version)
                },
              })
            },
            (version: EhGalleryVersion) => `${version.gid}:${version.token}`,
          )
        }
      }
    }
  }

  @Builder
  private RatingDialogContent() {
    Column({ space: ThemeConstants.SPACE_MD }) {
      Text(this.ratingHint())
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      // A rating is one bounded decision, so keep it in the same centered Dialog pattern as page jumps.
      Column({ space: ThemeConstants.SPACE_SM }) {
        RatingStars({
          rating: this.ratingSelected,
          color: EhConstants.ratingStarColor(''),
          starSize: 40,
          interactive: true,
          onRate: (value: number) => {
            this.ratingSelected = value
            this.ratingError = ''
          },
        })
        Text(this.ratingSelected > 0 ? this.ratingLabel(this.ratingSelected) : '—')
          .fontSize(ThemeConstants.FONT_SIZE_HEADING)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .enabled(!this.ratingSubmitting)
      if (this.ratingError.length > 0) {
        Text(this.ratingError)
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontColor($r('sys.color.ohos_id_color_warning'))
          .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private RemoteFavoriteSlot(fav: Favcat) {
    Row({ space: ThemeConstants.SPACE_MD }) {
      SymbolGlyph($r('sys.symbol.heart_fill'))
        .fontSize(24)
        .fontColor([EhConstants.favCatColor(fav.favId)])
      Text(fav.favTitle)
        .fontSize(ThemeConstants.FONT_SIZE_HEADING)
        .fontWeight(
          this.isRemoteFavoriteSlotSelected(fav.favId) ||
            this.isCurrentRemoteFavoriteSlot(fav.favId)
            ? FontWeight.Medium
            : FontWeight.Regular,
        )
        .fontColor($r('sys.color.font_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (this.isCurrentRemoteFavoriteSlot(fav.favId)) {
        Text($r('app.string.detail_remote_favorite_current_badge'))
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontColor($r('sys.color.font_secondary'))
      }
      if (fav.totNum > 0) {
        Text(`${fav.totNum}`)
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontColor($r('sys.color.font_secondary'))
      }
      if (this.isRemoteFavoriteSlotSelected(fav.favId)) {
        SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
          .fontSize(ThemeConstants.FONT_SIZE_TITLE)
          .fontColor([ThemeConstants.BRAND_PRIMARY])
      }
    }
    .width('100%')
    .padding({
      left: ThemeConstants.SPACE_MD,
      right: ThemeConstants.SPACE_MD,
      top: ThemeConstants.SPACE_MD,
      bottom: ThemeConstants.SPACE_MD,
    })
    .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
    .backgroundColor(
      this.isRemoteFavoriteSlotSelected(fav.favId)
        ? $r('sys.color.ohos_id_color_click_effect')
        : Color.Transparent,
    )
    .enabled(!this.remoteFavoriteSubmitting)
    .onClick(() => {
      if (
        this.isRemoteFavoriteSlotSelected(fav.favId) &&
        this.isCurrentRemoteFavoriteSlot(fav.favId)
      ) {
        this.remoteFavoriteSelectedCat = 'favdel'
      } else {
        this.remoteFavoriteSelectedCat = fav.favId
      }
    })
  }

  @Builder
  private LocalFavoriteRow() {
    Row({ space: ThemeConstants.SPACE_MD }) {
      SymbolGlyph(this.isLocalFavorite() ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
        .fontSize(24)
        .fontColor([
          this.isLocalFavorite() ? EhConstants.favCatColor('l') : $r('sys.color.font_secondary'),
        ])
      Text(this.localFavoriteLabel())
        .fontSize(ThemeConstants.FONT_SIZE_HEADING)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .layoutWeight(1)
      Text(this.localFavoriteActionLabel())
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor(this.isLocalFavorite() ? Color.Red : $r('sys.color.font_secondary'))
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor([$r('sys.color.font_secondary')])
    }
    .width('100%')
    .padding({
      left: ThemeConstants.SPACE_MD,
      right: ThemeConstants.SPACE_MD,
      top: ThemeConstants.SPACE_MD,
      bottom: ThemeConstants.SPACE_MD,
    })
    .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .enabled(!this.remoteFavoriteSubmitting)
    .onClick(() => {
      this.toggleLocalFavoriteWithSafety()
    })
  }

  @Builder
  private RemoteFavoriteSheet() {
    AppModalScaffold({
      title: $r('app.string.detail_remote_favorite'),
      contentBackgroundColor: $r('sys.color.ohos_id_color_sub_background'),
      confirmText: $r('app.string.detail_remote_favorite_save'),
      confirmEnabled: this.canSubmitRemoteFavorite(),
      confirmLoading: this.remoteFavoriteSubmitting,
      closeAction: () => {
        this.closeDetailSheet()
      },
      confirmAction: () => {
        this.submitRemoteFavorite()
      },
    }) {
      ListItem() {
        Column({ space: ThemeConstants.SPACE_MD }) {
          Text(this.remoteFavoriteStatusText())
            .fontSize(ThemeConstants.FONT_SIZE_BODY)
            .fontColor(this.remoteFavoriteStatusColor())
            .width('100%')
          TextArea({
            text: this.remoteFavoriteNote,
            placeholder: $r('app.string.detail_remote_favorite_note_placeholder'),
          })
            .height(96)
            .fontSize(ThemeConstants.FONT_SIZE_BODY)
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
            .enabled(!this.remoteFavoriteSubmitting && this.remoteFavoriteSelectedCat !== 'favdel')
            .onChange((value: string) => {
              this.remoteFavoriteNote = value
            })
          Column({ space: ThemeConstants.SPACE_XS }) {
            ForEach(
              this.remoteFavoriteSlots,
              (fav: Favcat) => {
                this.RemoteFavoriteSlot(fav)
              },
              (fav: Favcat) => fav.favId,
            )
          }.width('100%')
          this.LocalFavoriteRow()
          if (this.remoteFavoriteError.length > 0) {
            Text(this.remoteFavoriteError)
              .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
              .fontColor(Color.Red)
              .width('100%')
          }
        }.width('100%')
      }
    }
  }

  @Builder
  private DetailSheet() {
    if (this.detailSheetKind === DETAIL_SHEET_REMOTE_FAVORITE) {
      this.RemoteFavoriteSheet()
    } else if (this.detailSheetKind === DETAIL_SHEET_FULL_TITLE) {
      this.FullTitleSheet()
    } else if (this.detailSheetKind === DETAIL_SHEET_DOWNLOAD_UPGRADE) {
      this.DownloadUpgradeSheet()
    } else if (this.detailSheetKind === DETAIL_SHEET_ADD_TAGS) {
      GalleryAddTagsSheet({
        gid: this.params.gid,
        token: this.params.token,
        isEx: connectSiteMode().isEx,
        allowSubmit: !this.safeMode.restricted(),
        closeAction: () => {
          this.closeDetailSheet()
        },
        submittedAction: () => {
          this.refreshTagsAfterAdd().then(() => {})
        },
      })
    } else if (this.detailSheetKind === DETAIL_SHEET_TORRENTS) {
      GalleryTorrentsContent({
        params: this.torrentSheetParams,
        modal: true,
        closeAction: () => {
          this.closeDetailSheet()
        },
      })
    } else if (this.detailSheetKind === DETAIL_SHEET_ARCHIVER) {
      GalleryArchiverContent({
        params: this.archiverSheetParams,
        modal: true,
        closeAction: () => {
          this.closeDetailSheet()
        },
      })
    }
  }

  @Builder
  private FullPreviewJumpDialogContent() {
    Column({ space: ThemeConstants.SPACE_SM }) {
      Text(this.fullPreviewJumpHelpText())
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      TextInput({
        text: this.fullPreviewJumpPageText,
        placeholder: $r('app.string.gallery_preview_jump_placeholder'),
      })
        .type(InputType.Number)
        .inputFilter('^[0-9]*$')
        .defaultFocus(true)
        .width('100%')
        .onChange((value: string) => {
          this.fullPreviewJumpPageText = this.normalizeFullPreviewJumpInput(value)
          this.fullPreviewJumpError = ''
        })
      if (this.fullPreviewJumpError.length > 0) {
        Text(this.fullPreviewJumpError)
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor($r('sys.color.ohos_id_color_warning'))
          .width('100%')
      }
    }
    .width('100%')
  }

  @Builder
  private ReadFabFilledButton() {
    Button({ type: ButtonType.Capsule }) {
      Row({ space: ThemeConstants.SPACE_SM }) {
        SymbolGlyph($r('sys.symbol.doc_plaintext'))
          .fontSize(ThemeConstants.FONT_SIZE_HEADING)
          .fontColor([ThemeConstants.TEXT_ON_BRAND])
        Text(this.readFabLabel())
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeConstants.TEXT_ON_BRAND)
      }
      .padding({ left: ThemeConstants.SPACE_LG, right: ThemeConstants.SPACE_LG })
      .height(ThemeConstants.BUTTON_HEIGHT)
      .alignItems(VerticalAlign.Center)
    }
    .height(ThemeConstants.BUTTON_HEIGHT)
    // Capsule buttons default to the SYSTEM brand color; set the theme accent explicitly so the Read
    // FAB follows the user's theme color instead of staying system-blue.
    .backgroundColor(ThemeConstants.BRAND_PRIMARY)
    .shadow(ShadowStyle.OUTER_DEFAULT_MD)
    .onClick(() => {
      this.openReader(this.resumeIndex())
    })
  }

  @Builder
  private ReadFabHdsButton() {
    HdsCapsuleBarButton({
      controller: this.readFabMaterialController,
      barWidth: this.readFabMaterialBarWidth(),
      barHeight: ThemeConstants.BUTTON_HEIGHT,
      activityPadding: ThemeConstants.SPACE_LG,
      barBottomMargin: ThemeConstants.SPACE_LG,
      onButtonClick: () => {
        this.openReader(this.resumeIndex())
      },
    }) {
      Row({ space: ThemeConstants.SPACE_SM }) {
        SymbolGlyph($r('sys.symbol.doc_plaintext_fill'))
          .fontSize(ThemeConstants.FONT_SIZE_HEADING)
          .fontColor([ThemeConstants.BRAND_PRIMARY])
        Text(this.readFabLabel())
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeConstants.BRAND_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .height(ThemeConstants.BUTTON_HEIGHT)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .translate({ y: -ThemeConstants.SPACE_XS })
    }
  }

  @Builder
  private ReadFabButton() {
    if (this.readFabUsesHdsMaterial()) {
      this.ReadFabHdsButton()
    } else {
      this.ReadFabFilledButton()
    }
  }

  @Builder
  private ReadFabRail() {
    Row() {
      Row() {
        this.ReadFabButton()
      }
      .height(this.readFabOuterHeight())
      .translate({ x: this.readFabVisualX() })
      .opacity(this.readFabLayoutReady ? 1 : 0)
      .animation({ duration: this.readFabAnimationDuration(), curve: Curve.EaseOut })
      .onAreaChange((_oldArea: Area, area: Area) => {
        this.readFabWidth = area.width as number
        this.updateReadFabLayoutReady()
      })
    }
    // Full-width bottom rail; the button is Start-anchored and slid horizontally by translate so the
    // Read FAB aligns to the holding-hand side (smart-grip / follow / fixed). HDS material style uses
    // its internal activity padding for edge clearance, so the rail padding is style-dependent.
    .width('100%')
    .padding({ left: this.readFabRailSideInset(), right: this.readFabRailSideInset() })
    .justifyContent(FlexAlign.Start)
    .hitTestBehavior(HitTestMode.Transparent)
    .position({ left: 0, bottom: this.readFabRailBottomInset() })
  }

  @Builder
  private DetailMetadataPane(showCompactPreview: boolean) {
    Stack() {
      PullRefreshListScaffold({
        scroller: this.scroller,
        backToTop: this.galleryDetailBackToTop.detailEnabled(
          this.navigationDestinationId,
          GALLERY_DETAIL_BACK_TO_TOP_METADATA,
        ),
        listSpace: ThemeConstants.SPACE_MD,
        bottomPadding: ThemeConstants.SPACE_XXL + ThemeConstants.BUTTON_HEIGHT,
        controller: this.refreshController,
        onRefresh: async () => {
          this.compactPreviewReloadToken += 1
          await this.vm.refresh()
        },
        onUserScroll: () => {
          this.galleryDetailBackToTop.selectDetailOwner(
            this.navigationDestinationId,
            GALLERY_DETAIL_BACK_TO_TOP_METADATA,
          )
        },
        onBottomRefresh: async () => {
          if (showCompactPreview) {
            this.openThumbnails(this.detailBottomPreviewInitialPage())
          }
        },
        canStartBottomRefresh: () => showCompactPreview && this.vm.images.length > 0,
        onDidScroll: (offset: number) => {
          const past: boolean = offset > 160
          if (past !== this.showNavTitle) {
            this.showNavTitle = past
          }
        },
      }) {
        ListItem() {
          GalleryHeaderCard({
            gallery: this.vm.gallery,
            onTitleTap: () => {
              this.openFullTitleSheet()
            },
            titleSheetShown: this.isDetailSheetActive(DETAIL_SHEET_FULL_TITLE),
            titleSheetContent: () => {
              this.DetailSheet()
            },
            onTitleSheetDisappear: () => {
              if (this.detailSheetKind === DETAIL_SHEET_FULL_TITLE) {
                this.closeDetailSheet()
              }
            },
            onUploader: (name: string) => {
              this.searchUploader(name)
            },
          })
        }
        ListItem() {
          GalleryInfoBar({
            gallery: this.vm.gallery,
            onOpenInfo: () => {
              this.openGalleryInfo()
            },
          })
        }
        ListItem() {
          this.relationsRow()
        }

        if (this.vm.gallery.tagGroups.length > 0) {
          ListItem() {
            GalleryTagsCard({
              gallery: this.vm.gallery,
              onTagVoteChanged: (namespace: string, tagText: string, vote: number) => {
                this.vm.applyTagVote(namespace, tagText, vote)
              },
            })
          }
        }

        // Comments remain in the metadata pane, before the compact first-page preview.
        if (this.visiblePreviewComments().length > 0) {
          ListItem() {
            GalleryCommentsCard({
              comments: this.visiblePreviewComments(),
              referenceComments: this.vm.comments,
              max: 2,
              onMore: () => {
                this.openComments()
              },
              onAuthor: (name: string) => {
                this.searchUploader(name)
              },
            })
          }
        }

        if (showCompactPreview) {
          // The established compact path remains the first-page peek plus standalone all-thumbnails route.
          if (this.vm.images.length > 0) {
            ListItem() {
              GalleryPreviewGrid({
                images: this.vm.images,
                total: this.fileCountNum(),
                hasMore: this.vm.hasMorePreviews(),
                horizontal: this.thumbMode.horizontalThumbnails,
                hidden: this.thumbMode.hideGalleryThumbnails,
                thumbnailReloadToken: this.compactPreviewReloadToken,
                loadDeferred: !this.vm.postTransitionReady,
                onOpen: (page0: number) => {
                  this.openReader(page0)
                },
                onMore: (initialImagePage: number) => {
                  this.openThumbnails(initialImagePage)
                },
              })
            }
          } else if (this.vm.loading && !this.vm.cachedDetailApplied) {
            ListItem() {
              Row() {
                LoadingProgress()
                  .width(ThemeConstants.LOADING_SIZE)
                  .height(ThemeConstants.LOADING_SIZE)
                  .color(ThemeConstants.BRAND_PRIMARY)
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
              .padding(ThemeConstants.SPACE_MD)
            }
          } else if (this.vm.error.length > 0) {
            ListItem() {
              PageErrorState({
                message: this.vm.error,
                expand: false,
                retryAction: () => {
                  this.retryDetailLoad()
                },
              })
            }
          }
        }
      }
      if (showCompactPreview) {
        this.ReadFabRail()
      }
    }
    .width('100%')
    .height('100%')
    .id('gallery-detail-pane')
  }

  @Builder
  private FullPreviewPane() {
    Stack() {
      if (this.fullPreviewVm.itemCount > 0) {
        GalleryAllThumbnailsContent({
          vm: this.fullPreviewVm,
          scroller: this.fullPreviewScroller,
          controller: this.fullPreviewRefreshController,
          backToTop: this.galleryDetailBackToTop.detailEnabled(
            this.navigationDestinationId,
            GALLERY_DETAIL_BACK_TO_TOP_THUMBNAILS,
          ),
          onUserScroll: () => {
            this.galleryDetailBackToTop.selectDetailOwner(
              this.navigationDestinationId,
              GALLERY_DETAIL_BACK_TO_TOP_THUMBNAILS,
            )
          },
          onOpen: (img: EhGalleryImage) => {
            this.openFullPreviewReader(img)
          },
        })
      } else if (this.vm.loading && !this.vm.cachedDetailApplied) {
        Column() {
          LoadingProgress()
            .width(ThemeConstants.LOADING_SIZE)
            .height(ThemeConstants.LOADING_SIZE)
            .color(ThemeConstants.BRAND_PRIMARY)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.vm.error.length > 0) {
        Column() {
          PageErrorState({
            message: this.vm.error,
            retryAction: () => {
              this.retryDetailLoad()
            },
          })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
  }

  private refreshFirstSecondaryDetail(pathStack: NavPathStack): void {
    const pathNames: string[] = pathStack.getAllPathName()
    this.isFirstSecondaryDetail = pathNames.length === 1 && pathNames[0] === 'GalleryDetail'
  }

  build() {
    HdsNavDestination() {
      Stack() {
        Column() {}
          .width('100%')
          .height('100%')
          .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
        if (this.galleryDetailTransition.cardSnapshot !== undefined) {
          Image(this.galleryDetailTransition.cardSnapshot)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Fill)
            .syncLoad(true)
            .opacity(this.galleryDetailTransition.cardOpacity)
            .hitTestBehavior(HitTestMode.None)
        }
        Stack() {
          if (this.usesSplitDetailLayout()) {
          Row() {
            Column() {
              this.DetailMetadataPane(false)
            }
            .layoutWeight(1)
            .height('100%')
            .onAreaChange((_oldArea: Area, area: Area) => {
              this.detailMetadataWidth = area.width as number
              this.updateReadFabLayoutReady()
            })

            Column() {
              this.FullPreviewPane()
            }
            .layoutWeight(1)
            .height('100%')
            .id('gallery-full-preview-pane')
          }
          .width('100%')
          .height('100%')
          .alignItems(VerticalAlign.Top)
          .onTouch((event: TouchEvent) => {
            this.handleFollowTouch(event)
          })
          // The wide detail is one workspace. Its primary Read action may follow either hand all the
          // way to the outer edge instead of being trapped at the metadata/preview seam.
          this.ReadFabRail()
          } else {
          Column() {
            this.DetailMetadataPane(true)
          }
          .width('100%')
          .height('100%')
          .onAreaChange((_oldArea: Area, area: Area) => {
            this.detailMetadataWidth = area.width as number
            this.updateReadFabLayoutReady()
          })
          .onTouch((event: TouchEvent) => {
            this.handleFollowTouch(event)
          })
          }
        }
        .width('100%')
        .height('100%')
        .onAreaChange((_oldArea: Area, area: Area) => {
          const width: number = area.width as number
          if (this.detailRootWidth !== width) {
            this.detailRootWidth = width
          }
          LayoutSafeAreaBridge.publishGalleryDetailContentWidth(width, this.navStackHolder.isSplitMode)
          this.syncGalleryDetailBackToTopWorkspace()
        })
        .bindSheet(
          this.usesPageDetailSheetHost(),
          this.DetailSheet(),
          this.detailSheetOptions(this.detailSheetKind),
        )
        .opacity(this.galleryDetailTransition.contentOpacity)
      }
      .width('100%')
      .height('100%')
    }
    .titleBar(this.detailTitleBar())
    .hideTitleBar(this.galleryDetailTransition.eligible && !this.galleryDetailTransition.chromeVisible, false)
    .hideBackButton(this.navStackHolder.isSplitMode && this.isFirstSecondaryDetail)
    .backgroundColor(
      this.galleryDetailTransition.eligible
        ? '#00000000'
        : $r('sys.color.ohos_id_color_sub_background'),
    )
    .scale({
      x: this.galleryDetailTransition.scaleX,
      y: this.galleryDetailTransition.scaleY,
      centerX: '50%',
      centerY: '50%',
    })
    .translate({
      x: this.galleryDetailTransition.translateX,
      y: this.galleryDetailTransition.translateY,
    })
    .borderRadius(this.galleryDetailTransition.radius)
    .clip(this.galleryDetailTransition.eligible)
    .onDisAppear(() => {
      this.releaseGalleryDetailBackToTopWorkspace()
    })
    .onReady((context: NavDestinationContext) => {
      this.refreshFirstSecondaryDetail(context.pathStack)
      if (context.navDestinationId !== undefined) {
        this.navigationDestinationId = context.navDestinationId
      }
      this.syncGalleryDetailBackToTopWorkspace()
      const p = context.pathInfo.param as GalleryDetailParams
      if (p !== undefined && p.gid.length > 0) {
        this.params = p
        this.syncDisplayedReadProgress()
        this.resetTitleTranslations()
        this.vm.setContext(this.ctx())
        const seed: EhGallery = new EhGallery(p.gid, p.token)
        seed.thumbUrl = p.thumbUrl
        seed.imgWidth = p.imgWidth
        seed.imgHeight = p.imgHeight
        seed.englishTitle = p.title
        // Carry fileCount into the seed so the VM's gdata enrich is skipped for list-row opens (which
        // pass it) and fires only for sparse opens (deep link / URL paste, where it's '').
        seed.fileCount = p.fileCount
        this.vm.seed(seed)
        this.syncDownloadChipState('ready')
        this.vm.load(p.gid, p.token)
        this.scheduleHistoryAdd()
      }
    })
    .onWillShow(() => {
      this.refreshFirstSecondaryDetail(this.stack)
      this.syncGalleryDetailBackToTopWorkspace()
      if (!this.readerOverlay.visible) {
        this.syncDisplayedReadProgress()
      }
    })
    .onWillHide(() => {
      this.releaseGalleryDetailBackToTopWorkspace()
    })
  }

  // "Similar" runs a title search for this gallery on the Search tab (eros_fe p_Similar). Publishes
  // on the shared search bus; Index closes this page, switches tabs, and runs the search.
  private openSimilar(): void {
    const short: string = this.vm.gallery.shortTitle()
    if (short.length === 0) {
      return
    }
    connectSearchAction().publishQuery(`title:"${short}"`)
  }

  // Tap an uploader / comment author → search their uploads. eros_fe QUOTES namespaced searches
  // (goSearchPageWithParam → `uploader:"name"`), so a multi-word username matches exactly instead of
  // tokenizing into separate terms. Same bus; consistent with openSimilar's quoted title.
  private searchUploader(name: string): void {
    const n: string = name.trim()
    if (n.length === 0) {
      return
    }
    connectSearchAction().publishQuery(`uploader:"${n}"`)
  }

  @Builder
  private DetailActionChip(icon: Resource, label: ResourceStr, enabled: boolean, action: () => void) {
    Button({ type: ButtonType.Capsule }) {
      Row({ space: ThemeConstants.DETAIL_ACTION_CHIP_GAP }) {
        SymbolGlyph(icon)
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor([enabled ? ThemeConstants.BRAND_PRIMARY : $r('sys.color.font_secondary')])
        Text(label)
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(enabled ? ThemeConstants.BRAND_PRIMARY : $r('sys.color.font_secondary'))
          .maxLines(1)
      }
      .height(ThemeConstants.DETAIL_ACTION_CHIP_HEIGHT)
      .padding({ left: ThemeConstants.SPACE_SM, right: ThemeConstants.SPACE_MD })
      .alignItems(VerticalAlign.Center)
    }
    .height(ThemeConstants.DETAIL_ACTION_CHIP_HEIGHT)
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .enabled(enabled)
    .onClick(action)
  }

  @Builder
  private DetailSheetActionChip(
    icon: Resource,
    label: ResourceStr,
    enabled: boolean,
    kind: string,
    action: () => void,
  ) {
    Button({ type: ButtonType.Capsule }) {
      Row({ space: ThemeConstants.DETAIL_ACTION_CHIP_GAP }) {
        SymbolGlyph(icon)
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor([enabled ? ThemeConstants.BRAND_PRIMARY : $r('sys.color.font_secondary')])
        Text(label)
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(enabled ? ThemeConstants.BRAND_PRIMARY : $r('sys.color.font_secondary'))
          .maxLines(1)
      }
      .height(ThemeConstants.DETAIL_ACTION_CHIP_HEIGHT)
      .padding({ left: ThemeConstants.SPACE_SM, right: ThemeConstants.SPACE_MD })
      .alignItems(VerticalAlign.Center)
    }
    .height(ThemeConstants.DETAIL_ACTION_CHIP_HEIGHT)
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .enabled(enabled)
    .onClick(action)
    .bindSheet(this.isDetailSheetActive(kind), this.DetailSheet(), this.detailSheetOptions(kind))
  }

  @Builder
  private DownloadVariantMenuItem(preferOriginal: boolean) {
    MenuItem({
      content: this.downloadVariantLabel(preferOriginal),
      labelInfo: this.downloadVariantStatus(this.downloadVariantTask(preferOriginal)),
      symbolEndIcon: this.downloadVariantIcon(this.downloadVariantTask(preferOriginal)),
    })
      .enabled(this.canUseDownloadVariant(this.downloadVariantTask(preferOriginal)))
      .onClick(() => {
        this.useDownloadVariant(preferOriginal)
      })
  }

  @Builder
  private DownloadVariantMenu() {
    Menu() {
      this.DownloadVariantMenuItem(false)
      this.DownloadVariantMenuItem(true)
    }
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  private DownloadActionChip() {
    Button({ type: ButtonType.Capsule }) {
      Row({ space: ThemeConstants.DETAIL_ACTION_CHIP_GAP }) {
        SymbolGlyph($r('sys.symbol.arrow_down_to_line'))
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor([ThemeConstants.BRAND_PRIMARY])
        Text(this.downloadTitle())
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeConstants.BRAND_PRIMARY)
          .maxLines(1)
      }
      .height(ThemeConstants.DETAIL_ACTION_CHIP_HEIGHT)
      .padding({ left: ThemeConstants.SPACE_SM, right: ThemeConstants.SPACE_MD })
      .alignItems(VerticalAlign.Center)
    }
    .height(ThemeConstants.DETAIL_ACTION_CHIP_HEIGHT)
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .onClick(() => {
      this.onDownloadChipTap()
    })
    .bindMenu(this.downloadMenuShown, this.DownloadVariantMenu, appMenuOptions({
      placement: Placement.BottomRight,
      onDisappear: () => {
        this.downloadMenuShown = false
      },
    }))
  }

  @Builder
  relationsRow() {
    GroupedListSection({ inset: ThemeConstants.SPACE_MD }) {
      // Keep this strip coupled to the smart-grip/follow-operation edge exactly like the Read FAB.
      // Do not simplify this to a plain horizontal Scroll: the rail width + translate animation is what
      // preserves smooth left/right edge alignment when the action side changes.
      Scroll(this.actionStripScroller) {
        Row() {
          Row({ space: ThemeConstants.SPACE_XS }) {
            this.DetailActionChip($r('sys.symbol.magnifyingglass'), $r('app.string.detail_similar'), true, () => {
              this.openSimilar()
            })
            if (
              Number.parseInt(
                this.vm.gallery.torrentCount.length > 0 ? this.vm.gallery.torrentCount : '0',
                10,
              ) > 0
            ) {
              this.DetailSheetActionChip($r('sys.symbol.doc_plaintext'), this.torrentTitle(this.vm.gallery.torrentCount),
                true, DETAIL_SHEET_TORRENTS, () => {
                  this.openTorrents()
                })
            }
            this.DetailSheetActionChip($r('sys.symbol.doc_zipper'), this.archiverTitle(), true,
              DETAIL_SHEET_ARCHIVER, () => {
                this.openArchiver()
              })
            this.DetailActionChip($r('sys.symbol.star'), $r('app.string.detail_rate'), true, () => {
              this.openRatingDialog()
            })
            this.DownloadActionChip()
          }
          .alignItems(VerticalAlign.Center)
          .translate({ x: this.actionStripVisualX() })
          .animation({ duration: this.actionStripAnimationDuration(), curve: Curve.EaseOut })
          .onAreaChange((_oldArea: Area, area: Area) => {
            this.actionStripContentWidth = area.width as number
            this.updateActionStripLayoutReady()
          })
        }
        // A minimum keeps short strips aligned to the selected hand edge while leaving the horizontal
        // maximum unconstrained. An exact viewport-sized width would shrink the measured child Row,
        // hide real capsule overflow, and leave Scroll with no draggable range.
        .constraintSize({ minWidth: this.actionStripRailMinWidth() })
        .justifyContent(FlexAlign.Start)
      }
      .scrollable(ScrollDirection.Horizontal)
      .nestedScroll({
        scrollForward: NestedScrollMode.SELF_ONLY,
        scrollBackward: NestedScrollMode.SELF_ONLY,
      })
      .scrollBar(BarState.Off)
      .width('100%')
      .onAreaChange((_oldArea: Area, area: Area) => {
        this.actionStripViewportWidth = area.width as number
        this.updateActionStripLayoutReady()
      })
      .onAppear(() => {
        this.scrollActionStripToEdge()
      })
    }
  }
}
