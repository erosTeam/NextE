import {
  ThemeConstants,
  EhGallery,
  GalleryCard,
  GalleryGridCard,
  GalleryWaterfallCard,
  galleryWaterfallReuseId,
  requestGalleryCoverRetry,
  GalleryCoverWallCard,
  GallerySimpleCard,
  GalleryDetailParams,
  PageErrorState,
  PageLoadingState,
  CardEmptyState,
  LoadingFooter,
  PullRefreshListScaffold,
  PullRefreshGridScaffold,
  PullRefreshWaterFlowScaffold,
  PullRefreshController,
  connectNavStack,
  NavStackHolder,
  selectGalleryDetailFromPeerList,
  connectSiteMode,
  SiteModeState,
  connectListMode,
  ListModeState,
  ListMode,
  FavSelectionState,
  connectFavSelection,
  FavcatListSettings,
  Favcat,
  SELECTOR_BAR_HEIGHT,
  ActiveKeyState,
  connectLocalFav,
  LocalFavState,
  GalleryFavoriteMutationState,
  connectGalleryFavoriteMutation,
  GalleryRatingMutationState,
  connectGalleryRatingMutation,
  connectTagTranslationSettings,
  TagTranslationSettingsState,
  RootRefreshRegistry,
  LocalBlockState,
  connectLocalBlock,
  AppStrings,
  DiagnosticLogger,
  LayoutSafeAreaState,
  connectLayoutSafeArea,
  AuthState,
  connectAuth,
  GalleryDetailBackToTopState,
  connectGalleryDetailBackToTop,
} from 'shared'
import { common } from '@kit.AbilityKit'
import { CustomContentDialog } from '@kit.ArkUI'
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
  @Event onDidScroll?: (offset: number, state: ScrollState) => void;
  @Local vm: FavoritesViewModel = new FavoritesViewModel();
  @Local auth: AuthState = connectAuth();
  @Local siteMode: SiteModeState = connectSiteMode();
  @Local listMode: ListModeState = connectListMode();
  @Local favSel: FavSelectionState = connectFavSelection();
  @Local localFav: LocalFavState = connectLocalFav();
  @Local favoriteMutation: GalleryFavoriteMutationState = connectGalleryFavoriteMutation();
  @Local ratingMutation: GalleryRatingMutationState = connectGalleryRatingMutation();
  @Local tagTranslation: TagTranslationSettingsState = connectTagTranslationSettings();
  @Local localBlock: LocalBlockState = connectLocalBlock();
  @Local navStackHolder: NavStackHolder = connectNavStack();
  @Local listContentWidth: number = 0;
  @Local jumpPageText: string = '';
  @Local jumpError: string = '';
  @Local galleryDetailBackToTop: GalleryDetailBackToTopState = connectGalleryDetailBackToTop();
  private layout: LayoutSafeAreaState = connectLayoutSafeArea();
  private stack: NavPathStack = connectNavStack().stack;
  private refreshController: PullRefreshController = new PullRefreshController();
  private loadedOnce: boolean = false;
  private jumpSubmitting: boolean = false;
  private selectedJumpDate: Date = new Date();
  private jumpDialogController: CustomDialogController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: $r('app.string.favorites_jump_page'),
      contentBuilder: () => {
        this.FavoriteJumpDialogContent()
      },
      buttons: [
        {
          value: $r('app.string.common_cancel'),
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: () => {
            this.closeJumpDialog()
          },
        },
        {
          value: $r('app.string.favorites_jump_page'),
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: () => {
            this.confirmFavoriteJump()
          },
        },
      ],
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    customStyle: false,
  });

  private isActive(): boolean {
    return this.active.activeKey === this.favcatKey
  }

  private primaryBackToTopEnabled(): boolean {
    return this.isActive() && this.galleryDetailBackToTop.primaryEnabled()
  }

  private reportPrimaryUserScroll(): void {
    if (this.isActive()) {
      this.galleryDetailBackToTop.selectPrimary()
    }
  }

  aboutToAppear(): void {
    // Fix this page to its favcat + the current global order before any load.
    this.vm.configure(this.favcatKey, this.favSel.orderByPosted)
    this.vm.setContext(this.ctx())
    this.vm.seedFavList(this.favSel.favList)
    if (this.isActive()) {
      this.loadOnce()
    }
    // Re-tapping the active Favorites tab refreshes this favcat's list (nav shell looks up by Scroller).
    RootRefreshRegistry.register(this.scroller, () => {
      this.refreshController.triggerTopRefresh()
    })
  }

  aboutToDisappear(): void {
    RootRefreshRegistry.unregister(this.scroller)
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
    const committed: boolean = await this.vm.load()
    // Publish the parsed favcat sidebar AFTER the load resolves (deterministic) so the shared favList — and
    // thus the bar's real names/counts — are populated. A superseded account/site/order load must not
    // publish its old metadata into the newly active account.
    if (committed) {
      this.publishFavList()
    }
  }

  // Global order toggle from the shared bus → reload this favcat with the new order (if already loaded;
  // an unvisited favcat picks up the order on its first activation).
  @Monitor('favSel.orderByPosted')
  async onOrderChange(): Promise<void> {
    if (this.loadedOnce) {
      const committed: boolean = await this.vm.applyOrder(this.favSel.orderByPosted)
      if (committed) {
        this.publishFavList()
      }
    }
  }

  @Monitor('favSel.cmdSeq')
  onFavoriteCommand(): void {
    if (!this.isActive()) {
      return
    }
    if (this.favSel.cmdKind === 'openJumpDialog') {
      this.openJumpAction()
    } else if (this.favSel.cmdKind === 'jumpFirstPage') {
      this.jumpToFirstPage()
    }
  }

  @Monitor('siteMode.isEx')
  async onSiteChange(): Promise<void> {
    if (this.loadedOnce) {
      const committed: boolean = await this.vm.load(true)
      if (committed) {
        this.publishFavList()
      }
    }
  }

  @Monitor('auth.memberId')
  async onAccountChange(): Promise<void> {
    this.loadedOnce = false
    this.vm.resetForAccount(this.favcatKey, this.favSel.orderByPosted, this.favSel.favList)
    if (this.isActive()) {
      await this.loadOnce()
    }
  }

  @Monitor('localFav.items')
  async onLocalFavChange(): Promise<void> {
    if (this.loadedOnce && this.favcatKey === 'l') {
      await this.vm.load()
    }
  }

  @Monitor('favSel.favList')
  onFavListChange(): void {
    if (this.loadedOnce) {
      this.vm.resolveVisibleFavoriteSlotsFrom(this.favSel.favList)
    }
  }

  @Monitor('favoriteMutation.version')
  onFavoriteMutation(): void {
    if (this.loadedOnce) {
      this.vm.applyFavoriteMutation(
        this.favoriteMutation.gid,
        this.favoriteMutation.favcat,
        this.favoriteMutation.favTitle,
      )
    }
  }

  @Monitor('ratingMutation.version')
  onRatingMutation(): void {
    this.vm.applyRatingMutation(
      this.ratingMutation.gid,
      this.ratingMutation.userRating,
      this.ratingMutation.averageRating,
      this.ratingMutation.ratingCount,
      this.ratingMutation.colorRating,
    )
  }

  @Monitor('tagTranslation.enabled')
  onTagTranslationChange(): void {
    if (this.loadedOnce) {
      this.vm.reapplyTagTranslation()
    }
  }

  @Monitor('localBlock.version')
  async onLocalBlockChange(): Promise<void> {
    if (this.loadedOnce) {
      await this.vm.applyLocalBlockChange()
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
    this.vm.favList.forEach((f: Favcat) => {
      const current: Favcat | undefined = byId.get(f.favId)
      byId.set(f.favId, this.mergeFavcatMetadata(current, f))
    })
    const merged: Favcat[] = []
    byId.forEach((f: Favcat) => merged.push(f))
    this.favSel.favList = merged
    FavcatListSettings.persist(this.ctx(), merged)
    this.vm.resolveVisibleFavoriteSlotsFrom(merged)
  }

  private mergeFavcatMetadata(current: Favcat | undefined, incoming: Favcat): Favcat {
    if (current === undefined) {
      return incoming
    }
    const currentPlaceholder: boolean = FavSelectionState.isPlaceholderFavcat(current)
    const incomingPlaceholder: boolean = FavSelectionState.isPlaceholderFavcat(incoming)
    if (incomingPlaceholder && !currentPlaceholder) {
      return current
    }
    if (!incomingPlaceholder && currentPlaceholder) {
      return incoming
    }
    if (!incomingPlaceholder) {
      const next: Favcat = new Favcat(incoming.favId, incoming.favTitle, incoming.totNum)
      if (incoming.totNum === 0 && current.totNum > 0 && incoming.favTitle === current.favTitle) {
        next.totNum = current.totNum
      }
      return next
    }
    return current
  }

  private static pad2(value: number): string {
    return value < 10 ? `0${value}` : `${value}`
  }

  private static formatDate(value: Date): string {
    const month: number = value.getMonth() + 1
    const day: number = value.getDate()
    return `${value.getFullYear()}-${FavcatPage.pad2(month)}-${FavcatPage.pad2(day)}`
  }

  private openJumpAction(): void {
    if (!this.vm.canJumpRemote()) {
      DiagnosticLogger.info('favorites', 'jump_action_blocked', `favcat=${this.favcatKey}`)
      return
    }
    if (this.vm.canJumpToPageNumber()) {
      this.openJumpDialog()
      return
    }
    this.openDateJumpAfterDialog()
  }

  private openJumpDialog(): void {
    this.jumpPageText = `${this.vm.currentPageNumber()}`
    this.jumpError = ''
    this.jumpDialogController.open()
  }

  private closeJumpDialog(): void {
    try {
      this.jumpDialogController.close()
    } catch (_error) {
    }
  }

  private normalizeJumpInput(value: string): string {
    return (value || '').replace(/[^0-9]/g, '')
  }

  private jumpHelpText(): string {
    const pageCount: number = this.vm.pageCount()
    if (pageCount <= 0) {
      return AppStrings.get('favorites_jump_help')
    }
    return `${AppStrings.get('favorites_jump_help')} 1 - ${pageCount}`
  }

  private confirmFavoriteJump(): void {
    if (this.jumpSubmitting) {
      return
    }
    const page: number = Number.parseInt(this.jumpPageText, 10)
    const pageCount: number = this.vm.pageCount()
    if (Number.isNaN(page) || page <= 0 || (pageCount > 0 && page > pageCount)) {
      this.jumpError = AppStrings.get('favorites_jump_invalid')
      return
    }
    this.jumpSubmitting = true
    this.vm.jumpToPage(page)
      .then((ok: boolean) => {
        this.jumpSubmitting = false
        if (!ok) {
          this.jumpError = AppStrings.get('common_load_failed')
          return
        }
        this.closeJumpDialog()
        this.publishFavList()
        this.scrollToTopSoon()
      })
      .catch((_error: Error) => {
        this.jumpSubmitting = false
        this.jumpError = AppStrings.get('common_load_failed')
      })
  }

  private openDateJumpAfterDialog(): void {
    this.getUIContext().showDatePickerDialog({
      start: new Date(2007, 2, 20),
      end: new Date(),
      selected: this.selectedJumpDate,
      onDateAccept: (value: Date) => {
        this.selectedJumpDate = value
        const seek: string = FavcatPage.formatDate(value)
        this.jumpSubmitting = true
        this.vm.jumpToDateAfter(seek)
          .then((ok: boolean) => {
            this.jumpSubmitting = false
            if (ok) {
              this.publishFavList()
              this.scrollToTopSoon()
            }
          })
          .catch((_error: Error) => {
            this.jumpSubmitting = false
          })
      },
    })
  }

  private jumpToFirstPage(): void {
    if (!this.vm.shouldJumpFirstPage()) {
      this.scrollToTopSoon()
      return
    }
    if (this.jumpSubmitting) {
      return
    }
    this.jumpSubmitting = true
    this.vm.jumpFirstPage()
      .then((ok: boolean) => {
        this.jumpSubmitting = false
        if (ok) {
          this.publishFavList()
          this.scrollToTopSoon()
        }
      })
      .catch((_error: Error) => {
        this.jumpSubmitting = false
      })
  }

  private scrollToTopSoon(): void {
    setTimeout(() => {
      try {
        this.scroller.scrollToIndex(0)
      } catch (_error) {
      }
    }, 50)
  }

  private refreshCurrentList(): Promise<void> {
    return this.vm.refresh((prependedCount: number) => {
      this.restoreAfterPrepend(prependedCount)
    })
  }

  private restoreAfterPrepend(prependedCount: number): void {
    if (prependedCount <= 0) {
      return
    }
    const targetIndex: number = prependedCount + 1
    const firstDelay: number = ThemeConstants.ANIM_DONE_DELAY_MS + ThemeConstants.ANIM_DURATION + 40
    const finalDelay: number = firstDelay + ThemeConstants.ANIM_STATE_RESET_MS + 40
    DiagnosticLogger.info(
      'favorites',
      'restore_prepend_schedule',
      `favcat=${this.favcatKey} prepended=${prependedCount} target=${targetIndex} firstDelay=${firstDelay} finalDelay=${finalDelay}`,
    )
    this.schedulePrependRestore(targetIndex, firstDelay)
    this.schedulePrependRestore(targetIndex, finalDelay)
  }

  private schedulePrependRestore(targetIndex: number, delayMs: number): void {
    setTimeout(() => {
      this.restorePrependTarget(targetIndex, delayMs)
    }, delayMs)
  }

  private restorePrependTarget(targetIndex: number, delayMs: number): void {
    try {
      const before: number = this.safeYOffset()
      this.scroller.scrollToIndex(targetIndex, false, ScrollAlign.START)
      const alignedOffset: number = this.safeYOffset()
      const adjustedOffset: number = this.adjustPrependOffset(alignedOffset)
      DiagnosticLogger.info(
        'favorites',
        'restore_prepend_attempt',
        `favcat=${this.favcatKey} target=${targetIndex} delay=${delayMs} before=${before} aligned=${alignedOffset} adjusted=${adjustedOffset} after=${this.safeYOffset()}`,
      )
    } catch (_error) {
    }
  }

  private adjustPrependOffset(alignedOffset: number): number {
    if (alignedOffset <= 0) {
      return alignedOffset
    }
    const topReserve: number = this.layout.topAvoidHeight + ThemeConstants.TITLE_BAR_HEIGHT + SELECTOR_BAR_HEIGHT
    const adjustedOffset: number = Math.max(0, alignedOffset - topReserve)
    this.scroller.scrollTo({
      xOffset: 0,
      yOffset: adjustedOffset,
    })
    return adjustedOffset
  }

  private safeYOffset(): number {
    try {
      return this.scroller.currentOffset().yOffset
    } catch (_error) {
      return -1
    }
  }

  @Builder
  FavoriteJumpDialogContent() {
    Column({ space: ThemeConstants.SPACE_SM }) {
      Text(this.jumpHelpText())
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      TextInput({
        text: this.jumpPageText,
        placeholder: $r('app.string.favorites_jump_placeholder'),
      })
        .type(InputType.Number)
        .inputFilter('^[0-9]*$')
        .defaultFocus(true)
        .width('100%')
        .onChange((value: string) => {
          this.jumpPageText = this.normalizeJumpInput(value)
          this.jumpError = ''
        })
      if (this.jumpError.length > 0) {
        Text(this.jumpError)
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor($r('sys.color.ohos_id_color_warning'))
          .width('100%')
      }
    }
    .width('100%')
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private openDetail(g: EhGallery): void {
    const params: GalleryDetailParams = new GalleryDetailParams(
      g.gid,
      g.token,
      g.thumbUrl,
      g.title(),
      g.fileCount,
      g.imgWidth,
      g.imgHeight,
    )
    selectGalleryDetailFromPeerList(this.stack, params)
  }

  private isGallerySelected(gallery: EhGallery): boolean {
    return this.navStackHolder.isPrimaryPaneGallerySelected(gallery.gid, gallery.token)
  }

  private loadMoreIfTailAppeared(index: number): void {
    if (index < this.vm.itemCount - 1) {
      return
    }
    if (this.vm.canLoadMore()) {
      this.vm.loadMore()
    }
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
          backToTop: this.primaryBackToTopEnabled(),
          minColumnWidth: ThemeConstants.GALLERY_GRID_MIN_W,
          pinchModeKey: ListMode.GRID,
          gap: ThemeConstants.GALLERY_GRID_GAP,
          horizontalPadding: ThemeConstants.GALLERY_GRID_GAP,
          topPadding: SELECTOR_BAR_HEIGHT,
          bottomPadding: ThemeConstants.FLOAT_BAR_HEIGHT + ThemeConstants.SPACE_LG,
          itemCount: this.vm.itemCount,
          nearEndThreshold: 4,
          controller: this.refreshController,
          onRefresh: async () => {
            requestGalleryCoverRetry()
            await this.refreshCurrentList()
          },
          onBottomRefresh: async () => {
            await this.vm.loadMore()
          },
          canStartBottomRefresh: () => this.vm.canLoadMore(),
          onReachEnd: () => {
            if (this.vm.canLoadMore()) {
              this.vm.loadMore()
            }
          },
          onNearEnd: () => {
            if (this.vm.canLoadMore()) {
              this.vm.loadMore()
            }
          },
          onDidScroll: (offset: number, state: ScrollState) => {
            if (this.onDidScroll) {
              this.onDidScroll(offset, state)
            }
          },
          onUserScroll: () => {
            this.reportPrimaryUserScroll()
          },
          showFooter: true,
          footerIsLoading: this.vm.isLoadingMore || this.vm.isLoading,
          footerHasMore: this.vm.hasMore,
          footerIsError: this.vm.errorMessage.length > 0 && this.vm.hasMore,
          onFooterRetry: () => {
            this.vm.loadMore()
          },
        }) {
          LazyForEach(
            this.vm.dataSource,
            (g: EhGallery, index: number) => {
              GridItem() {
                GalleryGridCard({ gallery: g, selected: this.isGallerySelected(g) })
              }
              .onAppear(() => {
                this.loadMoreIfTailAppeared(index)
              })
              .onClick(() => {
                this.openDetail(g)
              })
            },
            (g: EhGallery) => g.renderKey(),
          )
        }
      } else if (this.listMode.mode === ListMode.WATERFALL) {
        PullRefreshWaterFlowScaffold({
          scroller: this.scroller,
          backToTop: this.primaryBackToTopEnabled(),
          minColumnWidth: ThemeConstants.GALLERY_WATERFALL_MIN_W,
          pinchModeKey: ListMode.WATERFALL,
          itemCount: this.vm.itemCount,
          nearEndThreshold: 4,
          gap: ThemeConstants.GALLERY_GRID_GAP,
          horizontalPadding: ThemeConstants.GALLERY_GRID_GAP,
          topPadding: SELECTOR_BAR_HEIGHT,
          bottomPadding: ThemeConstants.FLOAT_BAR_HEIGHT + ThemeConstants.SPACE_LG,
          controller: this.refreshController,
          onRefresh: async () => {
            requestGalleryCoverRetry()
            await this.refreshCurrentList()
          },
          onBottomRefresh: async () => {
            await this.vm.loadMore()
          },
          canStartBottomRefresh: () => this.vm.canLoadMore(),
          onReachEnd: () => {
            if (this.vm.canLoadMore()) {
              this.vm.loadMore()
            }
          },
          onNearEnd: () => {
            if (this.vm.canLoadMore()) {
              this.vm.loadMore()
            }
          },
          onDidScroll: (offset: number, state: ScrollState) => {
            if (this.onDidScroll) {
              this.onDidScroll(offset, state)
            }
          },
          onUserScroll: () => {
            this.reportPrimaryUserScroll()
          },
          showFooter: true,
          footerIsLoading: this.vm.isLoadingMore || this.vm.isLoading,
          footerHasMore: this.vm.hasMore,
          footerIsError: this.vm.errorMessage.length > 0 && this.vm.hasMore,
          onFooterRetry: () => {
            this.vm.loadMore()
          },
        }) {
          LazyForEach(
            this.vm.dataSource,
            (g: EhGallery, index: number) => {
              FlowItem() {
                GalleryWaterfallCard({ gallery: g, selected: this.isGallerySelected(g) })
                  .reuse({ reuseId: () => galleryWaterfallReuseId(g) })
              }
              .width('100%')
              .onAppear(() => {
                this.loadMoreIfTailAppeared(index)
              })
              .onClick(() => {
                this.openDetail(g)
              })
            },
            (g: EhGallery) => g.renderKey(),
          )
        }
      } else if (this.listMode.mode === ListMode.COVER_WALL) {
        PullRefreshWaterFlowScaffold({
          scroller: this.scroller,
          backToTop: this.primaryBackToTopEnabled(),
          minColumnWidth: ThemeConstants.GALLERY_COVER_WALL_MIN_W,
          pinchModeKey: ListMode.COVER_WALL,
          itemCount: this.vm.itemCount,
          nearEndThreshold: 4,
          gap: ThemeConstants.GALLERY_GRID_GAP,
          horizontalPadding: ThemeConstants.GALLERY_GRID_GAP,
          topPadding: SELECTOR_BAR_HEIGHT,
          bottomPadding: ThemeConstants.FLOAT_BAR_HEIGHT + ThemeConstants.SPACE_LG,
          controller: this.refreshController,
          onRefresh: async () => {
            requestGalleryCoverRetry()
            await this.refreshCurrentList()
          },
          onBottomRefresh: async () => {
            await this.vm.loadMore()
          },
          canStartBottomRefresh: () => this.vm.canLoadMore(),
          onReachEnd: () => {
            if (this.vm.canLoadMore()) {
              this.vm.loadMore()
            }
          },
          onNearEnd: () => {
            if (this.vm.canLoadMore()) {
              this.vm.loadMore()
            }
          },
          onDidScroll: (offset: number, state: ScrollState) => {
            if (this.onDidScroll) {
              this.onDidScroll(offset, state)
            }
          },
          onUserScroll: () => {
            this.reportPrimaryUserScroll()
          },
          showFooter: true,
          footerIsLoading: this.vm.isLoadingMore || this.vm.isLoading,
          footerHasMore: this.vm.hasMore,
          footerIsError: this.vm.errorMessage.length > 0 && this.vm.hasMore,
          onFooterRetry: () => {
            this.vm.loadMore()
          },
        }) {
          LazyForEach(
            this.vm.dataSource,
            (g: EhGallery, index: number) => {
              FlowItem() {
                GalleryCoverWallCard({ gallery: g, selected: this.isGallerySelected(g) })
              }
              .width('100%')
              .onAppear(() => {
                this.loadMoreIfTailAppeared(index)
              })
              .onClick(() => {
                this.openDetail(g)
              })
            },
            (g: EhGallery) => g.renderKey(),
          )
        }
      } else {
        PullRefreshListScaffold({
          scroller: this.scroller,
          backToTop: this.primaryBackToTopEnabled(),
          listSpace: this.listMode.mode === ListMode.SIMPLE_LIST ? 0 : ThemeConstants.SPACE_SM,
          topPadding: SELECTOR_BAR_HEIGHT,
          bottomPadding: ThemeConstants.FLOAT_BAR_HEIGHT + ThemeConstants.SPACE_LG,
          controller: this.refreshController,
          onRefresh: async () => {
            requestGalleryCoverRetry()
            await this.refreshCurrentList()
          },
          onBottomRefresh: async () => {
            await this.vm.loadMore()
          },
          canStartBottomRefresh: () => this.vm.canLoadMore(),
          onReachEnd: () => {
            if (this.vm.canLoadMore()) {
              this.vm.loadMore()
            }
          },
          onContentWidth: (contentWidth: number) => {
            this.listContentWidth = contentWidth
          },
          onDidScroll: (offset: number, state: ScrollState) => {
            if (this.onDidScroll) {
              this.onDidScroll(offset, state)
            }
          },
          onUserScroll: () => {
            this.reportPrimaryUserScroll()
          },
        }) {
          LazyForEach(
            this.vm.dataSource,
            (g: EhGallery, index: number) => {
              ListItem() {
                if (this.listMode.mode === ListMode.SIMPLE_LIST) {
                  GallerySimpleCard({ gallery: g, selected: this.isGallerySelected(g) })
                } else {
                  GalleryCard({
                    gallery: g,
                    selected: this.isGallerySelected(g),
                    listContentWidth: this.listContentWidth,
                  })
                }
              }
              .onAppear(() => {
                this.loadMoreIfTailAppeared(index)
              })
              .onClick(() => {
                this.openDetail(g)
              })
            },
            (g: EhGallery) => g.renderKey(),
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
