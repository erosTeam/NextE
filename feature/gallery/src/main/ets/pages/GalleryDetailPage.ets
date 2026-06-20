import { HdsNavDestination } from '@kit.UIDesignKit'
import { SymbolGlyphModifier } from '@kit.ArkUI'
import { common, Want } from '@kit.AbilityKit'
import { pasteboard } from '@kit.BasicServicesKit'
import {
  ThemeConstants,
  EhGallery,
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
  LocalFavState,
  connectLocalFav,
  ViewedGallery,
  ViewedHistorySettings,
  PullRefreshListScaffold,
  PullRefreshController,
  GroupedListSection,
  PageErrorState,
  AppStrings,
  AppModalScaffold,
  immersiveTitleBarOpts,
} from 'shared'
import { GalleryDetailViewModel } from '../viewmodel/GalleryDetailViewModel'
import { GalleryHeaderCard } from '../components/GalleryHeaderCard'
import { GalleryInfoBar } from '../components/GalleryInfoBar'
import { GalleryTagsCard } from '../components/GalleryTagsCard'
import { GalleryPreviewGrid } from '../components/GalleryPreviewGrid'
import { GalleryCommentsCard } from '../components/GalleryCommentsCard'

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
  @Local remoteFavoriteSheetShown: boolean = false;
  @Local remoteFavoriteSelectedCat: string = '';
  @Local remoteFavoriteNote: string = '';
  @Local remoteFavoriteSlots: Favcat[] = [];
  @Local remoteFavoriteSubmitting: boolean = false;
  @Local remoteFavoriteLoadingFavcats: boolean = false;
  @Local remoteFavoriteError: string = '';
  private stack: NavPathStack = connectNavStack().stack;
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
      new GalleryCommentsParams(this.params.gid, this.params.token, this.vm.comments, this.navTitle()),
    )
  }

  private openGalleryInfo(): void {
    this.stack.pushPathByName(
      'GalleryInfo',
      new GalleryInfoParams(this.vm.gallery.copy(), connectSiteMode().isEx, this.navTitle()),
    )
  }

  private openTorrents(): void {
    this.stack.pushPathByName(
      'GalleryTorrents',
      new GalleryTorrentsParams(
        this.params.gid,
        this.params.token,
        connectSiteMode().isEx,
        this.navTitle(),
        this.vm.gallery.torrentCount,
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
    const token: string = this.vm.gallery.token.length > 0 ? this.vm.gallery.token : this.params.token
    return this.downloadQueue.galleryTasks.some((task: DownloadGalleryTask) => {
      return task.gid === gid && task.token === token
    })
  }

  private downloadTitle(): Resource {
    return this.isGalleryQueued() ? $r('app.string.download_status_queued') : $r('app.string.detail_download')
  }

  private currentGalleryForLocalFav(): EhGallery {
    const g: EhGallery = this.vm.gallery.gid.length > 0 ? this.vm.gallery.copy() : new EhGallery(this.params.gid, this.params.token)
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
    return this.isLocalFavorite() ? $r('app.string.detail_remove_local_favorite') : $r('app.string.detail_add_local_favorite')
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
    this.getUIContext().getPromptAction().openToast({ message: message }).catch((_error: Error) => {
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

  private openRatingSafety(): void {
    this.getUIContext().showAlertDialog({
      message: $r('app.string.detail_rate_readonly_confirm'),
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {},
      },
      secondaryButton: {
        value: $r('app.string.detail_open_internal_web'),
        action: () => {
          this.openInternalWeb()
        },
      },
    })
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
    this.getUIContext().getPromptAction().openToast({
      message: inserted
        ? $r('app.string.download_gallery_added')
        : $r('app.string.download_gallery_already_queued'),
    }).catch((_error: Error) => {
      // The queue state has already been written; toast failure should not undo the user action.
    })
  }

  private openThumbnails(): void {
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

  // Native HDS title-bar actions. Read remains the primary FAB. With >3 items and maxCount=3, HDS keeps
  // the first two actions inline and turns the third slot into overflow, so refresh and power-user tools
  // stay discoverable without crowding the title bar.
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
      { 'content': refreshInner },
      { 'content': editTagsInner },
      { 'content': copyLinkInner },
      { 'content': copyTitleInner },
      { 'content': openBrowserInner },
      { 'content': openWebInner },
    ]
    return { 'value': items, 'maxCount': 3 }
  }

  private favoriteTitleBarIcon(): Resource | SymbolGlyphModifier {
    if (this.vm.gallery.favcat.length > 0) {
      return new SymbolGlyphModifier($r('sys.symbol.heart_fill'))
        .fontColor([EhConstants.favCatColor(this.vm.gallery.favcat)])
    }
    if (this.isLocalFavorite()) {
      return new SymbolGlyphModifier($r('sys.symbol.heart_fill'))
        .fontColor([ThemeConstants.BRAND_PRIMARY])
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
      this.getUIContext().getPromptAction().openToast({
        message: $r('app.string.common_refresh_failed'),
      }).catch((_toastError: Error) => {
      })
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
      this.getUIContext().getPromptAction().openToast({ message: message }).catch((_error: Error) => {
      })
    } catch (_error) {
      this.getUIContext().getPromptAction().openToast({
        message: $r('app.string.error_http'),
      }).catch((_toastError: Error) => {
      })
    }
  }

  private copyGalleryLink(): void {
    this.copyText(this.galleryUrl(), $r('app.string.detail_link_copied'))
  }

  private copyGalleryTitle(): void {
    this.copyText(this.vm.gallery.title(), $r('app.string.detail_title_copied'))
  }

  private openExternalBrowser(): void {
    const want: Want = { action: 'ohos.want.action.viewData', uri: this.galleryUrl() }
    this.ctx().startAbility(want).catch((_error: Error) => {
      this.getUIContext().getPromptAction().openToast({
        message: $r('app.string.error_http'),
      }).catch((_toastError: Error) => {
      })
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
      new GalleryEditTagsParams(this.params.gid, this.params.token, connectSiteMode().isEx, this.navTitle()),
    )
  }

  private openRemoteFavorite(): void {
    this.remoteFavoriteSelectedCat = this.vm.gallery.favcat.length > 0 ? this.vm.gallery.favcat : ''
    this.remoteFavoriteNote = this.vm.gallery.favNote
    this.remoteFavoriteSlots = []
    this.remoteFavoriteError = ''
    this.remoteFavoriteSheetShown = true
    this.refreshRemoteFavcats()
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
      if (info.selectFavcat.length > 0) {
        this.remoteFavoriteSelectedCat = info.selectFavcat
      } else if (info.favcats.findIndex((fav: Favcat) => fav.favId === this.remoteFavoriteSelectedCat) < 0) {
        this.remoteFavoriteSelectedCat = info.favcats.length > 0 ? info.favcats[0].favId : ''
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
    try {
      await EhApiService.getInstance().updateGalleryFavorite({
        isEx: connectSiteMode().isEx,
        gid: this.params.gid,
        token: this.params.token,
        favcat: favcat,
        favnote: favcat === 'favdel' ? '' : this.remoteFavoriteNote.trim(),
      })
      await this.vm.refresh()
      this.remoteFavoriteSheetShown = false
      this.getUIContext().getPromptAction().openToast({
        message: $r('app.string.detail_remote_favorite_saved'),
      }).catch((_toastError: Error) => {
      })
    } catch (e) {
      this.remoteFavoriteError = EhErrorText.forUser(e)
    } finally {
      this.remoteFavoriteSubmitting = false
    }
  }

  private isRemoteFavoriteSlotSelected(favcat: string): boolean {
    return this.remoteFavoriteSelectedCat === favcat
  }

  @Builder
  private RemoteFavoriteSlot(fav: Favcat) {
    Row({ space: ThemeConstants.SPACE_MD }) {
      SymbolGlyph($r('sys.symbol.heart_fill'))
        .fontSize(24)
        .fontColor([EhConstants.favCatColor(fav.favId)])
      Text(fav.favTitle)
        .fontSize(ThemeConstants.FONT_SIZE_HEADING)
        .fontWeight(this.isRemoteFavoriteSlotSelected(fav.favId) ? FontWeight.Medium : FontWeight.Regular)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
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
    .backgroundColor(this.isRemoteFavoriteSlotSelected(fav.favId) ? $r('sys.color.ohos_id_color_click_effect') : Color.Transparent)
    .enabled(!this.remoteFavoriteSubmitting)
    .onClick(() => {
      this.remoteFavoriteSelectedCat = fav.favId
    })
  }

  @Builder
  private LocalFavoriteRow() {
    Row({ space: ThemeConstants.SPACE_MD }) {
      SymbolGlyph(this.isLocalFavorite() ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
        .fontSize(24)
        .fontColor([this.isLocalFavorite() ? ThemeConstants.BRAND_PRIMARY : $r('sys.color.font_secondary')])
      Text(this.localFavoriteLabel())
        .fontSize(ThemeConstants.FONT_SIZE_HEADING)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.isLocalFavorite() })
        .enabled(!this.remoteFavoriteSubmitting)
        .onChange((_checked: boolean) => {
          this.toggleLocalFavoriteWithSafety()
        })
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
  }

  @Builder
  private RemoteFavoriteSheet() {
    AppModalScaffold({
      title: $r('app.string.detail_remote_favorite'),
      includeKeyboardPadding: true,
      contentBackgroundColor: $r('sys.color.ohos_id_color_sub_background'),
      confirmText: $r('app.string.detail_remote_favorite_save'),
      confirmEnabled: this.remoteFavoriteSlots.length > 0,
      confirmLoading: this.remoteFavoriteSubmitting,
      closeAction: () => {
        this.remoteFavoriteSheetShown = false
      },
      confirmAction: () => {
        this.submitRemoteFavorite()
      },
    }) {
      ListItem() {
        Column({ space: ThemeConstants.SPACE_MD }) {
          if (this.remoteFavoriteLoadingFavcats) {
            Row({ space: ThemeConstants.SPACE_SM }) {
              LoadingProgress()
                .width(ThemeConstants.LOADING_SIZE_SMALL)
                .height(ThemeConstants.LOADING_SIZE_SMALL)
              Text($r('app.string.detail_remote_favorite_loading_slots'))
                .fontSize(ThemeConstants.FONT_SIZE_BODY)
                .fontColor($r('sys.color.font_secondary'))
            }
            .width('100%')
          }
          Text(this.vm.gallery.favcat.length > 0 ?
            $r('app.string.detail_remote_favorite_current_slot', this.vm.gallery.favTitle) :
            $r('app.string.detail_remote_favorite_none'))
            .fontSize(ThemeConstants.FONT_SIZE_BODY)
            .fontColor($r('sys.color.font_secondary'))
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
            if (this.vm.gallery.favcat.length > 0) {
              Row({ space: ThemeConstants.SPACE_MD }) {
                SymbolGlyph($r('sys.symbol.heart_slash'))
                  .fontSize(ThemeConstants.FONT_SIZE_TITLE)
                  .fontColor([Color.Red])
                Text($r('app.string.detail_remote_favorite_remove'))
                  .fontSize(ThemeConstants.FONT_SIZE_BODY)
                  .fontColor(Color.Red)
                  .layoutWeight(1)
                if (this.remoteFavoriteSelectedCat === 'favdel') {
                  SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                    .fontSize(ThemeConstants.FONT_SIZE_TITLE)
                    .fontColor([Color.Red])
                }
              }
              .width('100%')
              .padding({
                left: ThemeConstants.SPACE_MD,
                right: ThemeConstants.SPACE_MD,
                top: ThemeConstants.SPACE_SM,
                bottom: ThemeConstants.SPACE_SM,
              })
              .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
              .backgroundColor(this.remoteFavoriteSelectedCat === 'favdel' ?
                $r('sys.color.ohos_id_color_click_effect') : Color.Transparent)
              .enabled(!this.remoteFavoriteSubmitting)
              .onClick(() => {
                this.remoteFavoriteSelectedCat = 'favdel'
              })
            }
          }
          .width('100%')
          this.LocalFavoriteRow()
          if (this.remoteFavoriteError.length > 0) {
            Text(this.remoteFavoriteError)
              .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
              .fontColor(Color.Red)
              .width('100%')
          }
        }
        .width('100%')
      }
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
              GalleryTagsCard({ gallery: this.vm.gallery })
            }
          }

          // Comments PEEK — before previews so it is reachable without scrolling the thumbnails.
          if (this.vm.comments.length > 0) {
            ListItem() {
              GalleryCommentsCard({
                comments: this.vm.comments,
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
                onMore: () => {
                  this.openThumbnails()
                },
              })
            }
          } else if (this.vm.loading) {
            ListItem() {
              Row() {
                LoadingProgress()
                  .width(ThemeConstants.LOADING_SIZE)
                  .height(ThemeConstants.LOADING_SIZE)
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
        .shadow(ShadowStyle.OUTER_DEFAULT_MD)
        .position({ right: ThemeConstants.SPACE_LG, bottom: ThemeConstants.SPACE_LG })
        .onClick(() => {
          this.openReader(this.resumeIndex())
        })
      }
      .bindSheet($$this.remoteFavoriteSheetShown, this.RemoteFavoriteSheet(), {
        detents: [SheetSize.LARGE],
        showClose: false,
      })
    }
    .titleBar(this.detailTitleBar())
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .onReady((context: NavDestinationContext) => {
      const p = context.pathInfo.param as GalleryDetailParams
      if (p !== undefined && p.gid.length > 0) {
        this.params = p
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
  relationsRow() {
    GroupedListSection({ inset: ThemeConstants.SPACE_MD }) {
      Row({ space: ThemeConstants.SPACE_MD }) {
        Text($r('app.string.detail_similar'))
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor($r('sys.color.font_emphasize'))
          .onClick(() => {
            this.openSimilar()
          })
        if (this.vm.gallery.parentGid.length > 0 && this.vm.gallery.parentGid !== this.params.gid) {
          Text($r('app.string.detail_parent'))
            .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
            .fontColor($r('sys.color.font_emphasize'))
            .onClick(() => {
              this.stack.pushPathByName(
                'GalleryDetail',
                new GalleryDetailParams(
                  this.vm.gallery.parentGid,
                  this.vm.gallery.parentToken,
                  '',
                  '',
                ),
              )
            })
        }
        if (Number.parseInt(this.vm.gallery.torrentCount.length > 0 ? this.vm.gallery.torrentCount : '0', 10) > 0) {
          Text(this.torrentTitle(this.vm.gallery.torrentCount))
            .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
            .fontColor($r('sys.color.font_emphasize'))
            .onClick(() => {
              this.openTorrents()
            })
        }
        if (this.vm.gallery.archiverLink.length > 0) {
          Text($r('app.string.download_archiver'))
            .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
            .fontColor($r('sys.color.font_emphasize'))
            .onClick(() => {
              this.openArchiver()
            })
        }
        Text($r('app.string.detail_rate'))
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor($r('sys.color.font_emphasize'))
          .onClick(() => {
            this.openRatingSafety()
          })
        Text(this.downloadTitle())
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor(this.isGalleryQueued() ? $r('sys.color.font_secondary') : $r('sys.color.font_emphasize'))
          .onClick(() => {
            this.enqueueGalleryDownload()
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
  }
}
