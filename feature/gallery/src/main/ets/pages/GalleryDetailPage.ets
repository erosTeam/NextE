import { HdsNavDestination, HdsTabsController } from '@kit.UIDesignKit'
import { SymbolGlyphModifier } from '@kit.ArkUI'
import { common, Want } from '@kit.AbilityKit'
import { pasteboard } from '@kit.BasicServicesKit'
import {
  ThemeConstants,
  EhGallery,
  EhGalleryComment,
  TagGroup,
  EhConstants,
  ShareUtil,
  GalleryDetailParams,
  GalleryInfoParams,
  GalleryTorrentsParams,
  GalleryArchiverParams,
  GalleryWebParams,
  GalleryEditTagsParams,
  ReaderParams,
  GalleryCommentsParams,
  AllThumbnailsParams,
  Favcat,
  GalleryFavoriteInfo,
  EhApiService,
  EhErrorText,
  connectNavStack,
  connectSearchAction,
  connectSiteMode,
  connectGalleryReadProgress,
  GalleryReadProgressState,
  GalleryTitleState,
  connectGalleryTitle,
  connectThumbnailMode,
  ThumbnailModeState,
  DownloadGalleryTask,
  DownloadQueueSettings,
  DownloadQueueState,
  connectDownloadQueue,
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
  RemoteFavoriteSlotCacheState,
  connectRemoteFavoriteSlotCache,
  ViewedGallery,
  ViewedHistorySettings,
  PullRefreshListScaffold,
  PullRefreshController,
  GroupedListSection,
  PageErrorState,
  AppStrings,
  AppModalScaffold,
  RatingStars,
  GalleryRatingResult,
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
} from 'shared'
import { GalleryDetailViewModel } from '../viewmodel/GalleryDetailViewModel'
import { GalleryHeaderCard } from '../components/GalleryHeaderCard'
import { GalleryInfoBar } from '../components/GalleryInfoBar'
import { GalleryTagsCard } from '../components/GalleryTagsCard'
import { GalleryPreviewGrid } from '../components/GalleryPreviewGrid'
import { GalleryCommentsCard } from '../components/GalleryCommentsCard'
import { GalleryTorrentsContent } from './GalleryTorrentsPage'

const DETAIL_SHEET_REMOTE_FAVORITE: string = 'remoteFavorite'
const DETAIL_SHEET_RATING: string = 'rating'
const DETAIL_SHEET_FULL_TITLE: string = 'fullTitle'
const DETAIL_SHEET_TORRENTS: string = 'torrents'
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
  @Local params: GalleryDetailParams = new GalleryDetailParams();
  // The nav-bar title appears only after the header card scrolls away (eros_fe scroll-driven title).
  @Local showNavTitle: boolean = false;
  @Local detailRefreshInFlight: boolean = false;
  @Local titlePref: GalleryTitleState = connectGalleryTitle();
  // Per-gallery reading progress: the READ button resumes at + labels itself with the saved page.
  // Reactive (revision-backed) so returning from the reader refreshes the button live.
  @Local readProgress: GalleryReadProgressState = connectGalleryReadProgress();
  // Detail-preview display mode (eros_fe hideGalleryThumbnails / horizontalThumbnails). Reactive so a
  // settings toggle re-renders this page's preview section live (grid ↔ horizontal ↔ hidden-inline).
  @Local thumbMode: ThumbnailModeState = connectThumbnailMode();
  // Local gallery download queue state: mirrors eros_fe GalleryTask uniqueness, but this lane only
  // enqueues/records a task. It does not start the background image downloader.
  @Local downloadQueue: DownloadQueueState = connectDownloadQueue();
  @Local localFav: LocalFavState = connectLocalFav();
  @Local favoriteMutation: GalleryFavoriteMutationState = connectGalleryFavoriteMutation();
  @Local ratingMutation: GalleryRatingMutationState = connectGalleryRatingMutation();
  @Local commentVoteMutation: CommentVoteMutationState = connectCommentVoteMutation();
  @Local torrentSheetParams: GalleryTorrentsParams = new GalleryTorrentsParams();
  @Local tagTranslation: TagTranslationSettingsState = connectTagTranslationSettings();
  @Local favoriteSlotCache: RemoteFavoriteSlotCacheState = connectRemoteFavoriteSlotCache();
  // Resolved Read-FAB hand edge (smart-grip / follow-operation / fixed). visualActionEdge mirrors it and
  // drives a smooth .translate() slide; root/button widths convert the discrete edge into a continuous X.
  @Local actionEdge: ActionHandEdgeState = connectActionHandEdge();
  // Seed from the CURRENT resolved edge (the service resolves it at startup, before this page mounts), so a
  // page opened while the edge is already 'left' starts left — @Monitor only fires on later changes.
  @Local visualActionEdge: string = connectActionHandEdge().edge;
  @Local detailRootWidth: number = 0;
  @Local readFabWidth: number = 0;
  @Local readFabLayoutReady: boolean = false;
  @Local readFabShouldAnimate: boolean = false;
  @Local actionStripViewportWidth: number = 0;
  @Local actionStripContentWidth: number = 0;
  @Local actionStripLayoutReady: boolean = false;
  @Local actionStripShouldAnimate: boolean = false;
  @Local readButtonStyle: ReadButtonStyleState = connectReadButtonStyle();
  private followTouchState: ActionFollowTouchState = ActionFollowTouchTracker.initialState();
  @Local detailSheetShown: boolean = false;
  @Local detailSheetKind: string = '';
  @Local remoteFavoriteSelectedCat: string = '';
  @Local remoteFavoriteNote: string = '';
  @Local remoteFavoriteSlots: Favcat[] = [];
  @Local remoteFavoriteSubmitting: boolean = false;
  @Local remoteFavoriteLoadingFavcats: boolean = false;
  @Local remoteFavoriteError: string = '';
  @Local ratingSelected: number = 0;
  @Local ratingSubmitting: boolean = false;
  @Local ratingError: string = '';
  private stack: NavPathStack = connectNavStack().stack;
  private readFabMaterialController: HdsTabsController = new HdsTabsController();
  private actionStripScroller: Scroller = new Scroller();

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
    )
  }

  // Continuous X for the Read FAB inside the padded full-width rail: left edge = 0 (Start), right edge =
  // inner width − button width. Interpolated by the button's .animation().
  private readFabVisualX(): number {
    if (this.visualActionEdge === 'left') {
      return 0
    }
    const inner: number = this.detailRootWidth - this.readFabRailSideInset() * 2
    return Math.max(0, inner - this.readFabWidth)
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

  private actionStripRailWidth(): Length {
    if (this.actionStripViewportWidth <= 0) {
      return '100%'
    }
    return Math.max(this.actionStripViewportWidth, this.actionStripContentWidth)
  }

  private actionStripAnimationDuration(): number {
    return this.actionStripShouldAnimate ? ThemeConstants.ANIM_DURATION : 0
  }

  private updateReadFabLayoutReady(): void {
    if (this.detailRootWidth > 0 && this.readFabWidth > 0) {
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
      MotionHandStateService.reportFollowOperationX(update.reportX, this.detailRootWidth)
    }
  }
  private scroller: Scroller = new Scroller();
  private refreshController: PullRefreshController = new PullRefreshController();
  // Pending 5s viewed-history timer (eros_fe delays addHistory 5s after open so a quick bounce isn't
  // recorded). Cancelled if the user leaves before it fires. -1 = none.
  private historyTimer: number = -1;

  // eros_fe resumes reading at the saved lastIndex when the READ button is tapped (thumbnail taps
  // still open their own page). 0 when there is no saved progress.
  private resumeIndex(): number {
    return this.readProgress.getIndex(this.params.gid)
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  @Monitor('tagTranslation.enabled')
  onTagTranslationChange(): void {
    this.vm.reapplyTagTranslation()
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

  aboutToDisappear(): void {
    // Left before the 5s debounce fired → this open was transient; don't record it.
    if (this.historyTimer >= 0) {
      clearTimeout(this.historyTimer)
      this.historyTimer = -1
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

  private fileCountNum(): number {
    return Number.parseInt(
      this.vm.gallery.fileCount.length > 0 ? this.vm.gallery.fileCount : '0',
      10,
    )
  }

  private openReader(index: number): void {
    this.stack.pushPathByName(
      'Reader',
      new ReaderParams(
        this.params.gid,
        this.params.token,
        index,
        this.fileCountNum(),
        this.navTitle(),
      ),
    )
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
    if (this.vm.gallery.archiverLink.length === 0) {
      return
    }
    this.stack.pushPathByName(
      'GalleryArchiver',
      new GalleryArchiverParams(
        this.params.gid,
        this.params.token,
        this.vm.gallery.archiverLink,
        connectSiteMode().isEx,
        this.navTitle(),
      ),
    )
  }

  private torrentTitle(count: string): string {
    return AppStrings.get('detail_torrents').replace('%s', count)
  }

  private isGalleryQueued(): boolean {
    const gid: string = this.vm.gallery.gid.length > 0 ? this.vm.gallery.gid : this.params.gid
    const token: string =
      this.vm.gallery.token.length > 0 ? this.vm.gallery.token : this.params.token
    return this.downloadQueue.galleryTasks.some((task: DownloadGalleryTask) => {
      return task.gid === gid && task.token === token
    })
  }

  private downloadTitle(): Resource {
    return this.isGalleryQueued()
      ? $r('app.string.download_status_queued')
      : $r('app.string.detail_download')
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
    this.detailSheetShown = false
  }

  private detailSheetDetents(): [string | number | Resource] {
    if (this.detailSheetKind === DETAIL_SHEET_RATING) {
      return [SheetSize.MEDIUM]
    }
    return [SheetSize.LARGE]
  }

  private openRatingSheet(): void {
    this.ratingSelected = this.currentPersonalRating()
    this.ratingError = ''
    this.openDetailSheet(DETAIL_SHEET_RATING)
  }

  private canSubmitRating(): boolean {
    return (
      !this.ratingSubmitting &&
      this.ratingSelected > 0 &&
      this.vm.gallery.apikey.length > 0 &&
      this.vm.gallery.apiuid.length > 0
    )
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
    if (!this.canSubmitRating()) {
      this.ratingError = AppStrings.get('detail_rate_missing_key')
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
      this.closeDetailSheet()
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

  private async enqueueGalleryDownload(): Promise<void> {
    const task: DownloadGalleryTask = DownloadGalleryTask.fromGallery(
      this.vm.gallery,
      this.params.gid,
      this.params.token,
    )
    const inserted: boolean = await DownloadQueueSettings.enqueueGallery(this.ctx(), task)
    DownloadQueueSettings.prepareGallerySeeds(
      this.ctx(),
      task.gid,
      task.token,
      connectSiteMode().isEx,
      this.vm.images,
      this.vm.previewPageCount,
    )
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

  private openThumbnails(initialImagePage: number = 0): void {
    this.stack.pushPathByName(
      'AllThumbnails',
      new AllThumbnailsParams(
        this.params.gid,
        this.params.token,
        connectSiteMode().isEx,
        this.fileCountNum(),
        this.vm.previewPageCount,
        this.navTitle(),
        this.vm.images,
        initialImagePage,
      ),
    )
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
    const editTagsInner: Record<string, Object> = {
      'label': $r('app.string.detail_edit_tags'),
      'icon': $r('sys.symbol.bookmark'),
      'isEnabled': true,
      'action': () => {
        this.openEditTags()
      },
    }
    const copyLinkInner: Record<string, Object> = {
      'label': $r('app.string.detail_copy_link'),
      'icon': $r('sys.symbol.link'),
      'isEnabled': true,
      'action': () => {
        this.copyGalleryLink()
      },
    }
    const copyTitleInner: Record<string, Object> = {
      'label': $r('app.string.detail_copy_title'),
      'icon': $r('sys.symbol.doc_plaintext'),
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
      { 'content': editTagsInner },
      { 'content': copyLinkInner },
      { 'content': copyTitleInner },
      { 'content': openBrowserInner },
      { 'content': openWebInner },
    ]
    if (this.vm.gallery.parentGid.length > 0 && this.vm.gallery.parentGid !== this.params.gid) {
      items.splice(3, 0, { 'content': parentInner })
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
    this.copyText(this.vm.gallery.title(), $r('app.string.detail_title_copied'))
  }

  private visiblePreviewComments(): EhGalleryComment[] {
    return LocalBlockService.filterComments(this.vm.comments)
  }

  private openFullTitleSheet(): void {
    if (this.primaryDetailTitle().length === 0 && this.secondaryDetailTitle().length === 0) {
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

  private openEditTags(): void {
    this.stack.pushPathByName(
      'GalleryEditTags',
      new GalleryEditTagsParams(
        this.params.gid,
        this.params.token,
        connectSiteMode().isEx,
        this.navTitle(),
      ),
    )
  }

  private openRemoteFavorite(): void {
    this.remoteFavoriteSelectedCat = this.vm.gallery.favcat.length > 0 ? this.vm.gallery.favcat : ''
    this.remoteFavoriteNote = this.vm.gallery.favNote
    this.remoteFavoriteError = ''
    if (this.remoteFavoriteSlots.length === 0 && this.favoriteSlotCache.favcats.length > 0) {
      this.remoteFavoriteSlots = this.copyFavcats(this.favoriteSlotCache.favcats)
    }
    this.openDetailSheet(DETAIL_SHEET_REMOTE_FAVORITE)
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
            this.TitleReadBlock($r('app.string.detail_display_title'), this.primaryDetailTitle())
            if (this.secondaryDetailTitle().length > 0) {
              this.TitleReadBlock(
                $r('app.string.detail_alternate_title'),
                this.secondaryDetailTitle(),
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
  private TitleReadBlock(label: ResourceStr, value: string) {
    Column({ space: ThemeConstants.SPACE_XS }) {
      Text(label)
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      Text(value)
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor($r('sys.color.font_primary'))
        .lineHeight(ThemeConstants.LINE_HEIGHT_BODY)
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private RatingSheet() {
    AppModalScaffold({
      title: $r('app.string.detail_rate'),
      contentBackgroundColor: $r('sys.color.ohos_id_color_sub_background'),
      confirmText: $r('app.string.detail_rate_submit'),
      confirmEnabled: this.canSubmitRating(),
      confirmLoading: this.ratingSubmitting,
      closeAction: () => {
        this.closeDetailSheet()
      },
      confirmAction: () => {
        this.submitRating()
      },
    }) {
      ListItem() {
        Column({ space: ThemeConstants.SPACE_MD }) {
          Text(this.ratingHint())
            .fontSize(ThemeConstants.FONT_SIZE_BODY)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
          // Slide or tap across the stars to rate (eros_fe rate dialog; 0.5 steps); value updates live below.
          Column({ space: ThemeConstants.SPACE_SM }) {
            RatingStars({
              rating: this.ratingSelected,
              color: EhConstants.ratingStarColor(''),
              starSize: 40,
              interactive: true,
              onRate: (value: number) => {
                this.ratingSelected = value
              },
            })
            Text(this.ratingSelected > 0 ? this.ratingLabel(this.ratingSelected) : '—')
              .fontSize(ThemeConstants.FONT_SIZE_HEADING)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary'))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ top: ThemeConstants.SPACE_MD, bottom: ThemeConstants.SPACE_MD })
          .enabled(!this.ratingSubmitting)
          if (this.ratingError.length > 0) {
            Text(this.ratingError)
              .fontSize(ThemeConstants.FONT_SIZE_BODY)
              .fontColor(Color.Red)
              .width('100%')
          }
        }.width('100%')
      }
    }
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
    } else if (this.detailSheetKind === DETAIL_SHEET_RATING) {
      this.RatingSheet()
    } else if (this.detailSheetKind === DETAIL_SHEET_FULL_TITLE) {
      this.FullTitleSheet()
    } else if (this.detailSheetKind === DETAIL_SHEET_TORRENTS) {
      GalleryTorrentsContent({
        params: this.torrentSheetParams,
        modal: true,
        closeAction: () => {
          this.closeDetailSheet()
        },
      })
    }
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

  build() {
    HdsNavDestination() {
      Stack() {
        PullRefreshListScaffold({
          scroller: this.scroller,
          listSpace: ThemeConstants.SPACE_MD,
          bottomPadding: ThemeConstants.SPACE_XXL + ThemeConstants.BUTTON_HEIGHT,
          controller: this.refreshController,
          onRefresh: async () => {
            await this.vm.refresh()
          },
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

          // Comments PEEK — before previews so it is reachable without scrolling the thumbnails.
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

          // Previews PEEK (first page only) — last; eros_fe ThumbTile modes (grid default / horizontal /
          // hidden-inline) per the thumbnail settings. The all-thumbnails entry is reachable in every mode.
          if (this.vm.images.length > 0) {
            ListItem() {
              GalleryPreviewGrid({
                images: this.vm.images,
                total: this.fileCountNum(),
                hasMore: this.vm.hasMorePreviews(),
                horizontal: this.thumbMode.horizontalThumbnails,
                hidden: this.thumbMode.hideGalleryThumbnails,
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
                  this.vm.load(this.params.gid, this.params.token)
                },
              })
            }
          }
        }
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
      .onAreaChange((_oldArea: Area, area: Area) => {
        this.detailRootWidth = area.width as number
        this.updateReadFabLayoutReady()
      })
      .onTouch((event: TouchEvent) => {
        this.handleFollowTouch(event)
      })
      .bindSheet($$this.detailSheetShown, this.DetailSheet(), appSheetOptions({
        detents: this.detailSheetDetents(),
        showClose: false,
        keyboardAvoidMode: SheetKeyboardAvoidMode.TRANSLATE_AND_RESIZE,
      }))
    }
    .titleBar(this.detailTitleBar())
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .onReady((context: NavDestinationContext) => {
      const p = context.pathInfo.param as GalleryDetailParams
      if (p !== undefined && p.gid.length > 0) {
        this.params = p
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
        this.vm.load(p.gid, p.token)
        this.scheduleHistoryAdd()
      }
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
  private DetailActionChip(icon: Resource, label: ResourceStr, emphasized: boolean, action: () => void) {
    Button({ type: ButtonType.Capsule }) {
      Row({ space: ThemeConstants.DETAIL_ACTION_CHIP_GAP }) {
        SymbolGlyph(icon)
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor([emphasized ? ThemeConstants.BRAND_PRIMARY : $r('sys.color.font_secondary')])
        Text(label)
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(emphasized ? ThemeConstants.BRAND_PRIMARY : $r('sys.color.font_secondary'))
          .maxLines(1)
      }
      .height(ThemeConstants.DETAIL_ACTION_CHIP_HEIGHT)
      .padding({ left: ThemeConstants.SPACE_SM, right: ThemeConstants.SPACE_MD })
      .alignItems(VerticalAlign.Center)
    }
    .height(ThemeConstants.DETAIL_ACTION_CHIP_HEIGHT)
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .onClick(action)
  }

  @Builder
  relationsRow() {
    GroupedListSection({ inset: ThemeConstants.SPACE_MD }) {
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
              this.DetailActionChip($r('sys.symbol.doc_plaintext'), this.torrentTitle(this.vm.gallery.torrentCount),
                true, () => {
                  this.openTorrents()
                })
            }
            if (this.vm.gallery.archiverLink.length > 0) {
              this.DetailActionChip($r('sys.symbol.externaldrive'), $r('app.string.download_archiver'), true, () => {
                this.openArchiver()
              })
            }
            this.DetailActionChip($r('sys.symbol.star'), $r('app.string.detail_rate'), true, () => {
              this.openRatingSheet()
            })
            this.DetailActionChip($r('sys.symbol.arrow_down_to_line'), this.downloadTitle(), !this.isGalleryQueued(),
              () => {
                this.enqueueGalleryDownload()
              })
          }
          .alignItems(VerticalAlign.Center)
          .translate({ x: this.actionStripVisualX() })
          .animation({ duration: this.actionStripAnimationDuration(), curve: Curve.EaseOut })
          .onAreaChange((_oldArea: Area, area: Area) => {
            this.actionStripContentWidth = area.width as number
            this.updateActionStripLayoutReady()
          })
        }
        .width(this.actionStripRailWidth())
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
