import { HdsNavDestination } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import {
  ThemeConstants,
  EhGallery,
  ShareUtil,
  GalleryDetailParams,
  GalleryInfoParams,
  GalleryTorrentsParams,
  ReaderParams,
  GalleryCommentsParams,
  AllThumbnailsParams,
  connectNavStack,
  connectSearchAction,
  connectSiteMode,
  connectGalleryReadProgress,
  GalleryReadProgressState,
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
    if (this.vm.gallery.title().length > 0) {
      return this.vm.gallery.title()
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

  // Native HDS title-bar actions. Read remains the primary FAB; local favorite and share are secondary
  // top actions matching eros_fe's heart/share detail affordances.
  private detailMenu(): Record<string, Object> {
    const favoriteInner: Record<string, Object> = {
      'label': this.localFavoriteLabel(),
      'icon': this.isLocalFavorite() ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'),
      'isEnabled': true,
      'action': () => {
        this.toggleLocalFavorite()
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
    const items: Record<string, Object>[] = [{ 'content': favoriteInner }, { 'content': shareInner }]
    return { 'value': items, 'maxCount': 2 }
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
