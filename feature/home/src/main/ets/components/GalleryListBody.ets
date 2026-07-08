import {
  ThemeConstants,
  EhGallery,
  GalleryCard,
  GalleryGridCard,
  GalleryWaterfallCard,
  GalleryCoverWallCard,
  GallerySimpleCard,
  GalleryDetailParams,
  LoadingFooter,
  PullRefreshListScaffold,
  PullRefreshGridScaffold,
  PullRefreshWaterFlowScaffold,
  PullRefreshController,
  PageLoadingState,
  PageErrorState,
  CardEmptyState,
  connectNavStack,
  connectListMode,
  ListModeState,
  ListMode,
  GalleryFavoriteMutationState,
  connectGalleryFavoriteMutation,
  GalleryRatingMutationState,
  connectGalleryRatingMutation,
  FavSelectionState,
  connectFavSelection,
  RootRefreshRegistry,
  LayoutSafeAreaState,
  connectLayoutSafeArea,
  DiagnosticLogger,
} from 'shared'
import { GalleryListViewModel } from '../viewmodel/GalleryListViewModel'

/**
 * The shared gallery-list body (loading / error / empty / grid / list / simple branches + paging),
 * used by both HomePage (Gallery tab) and ToplistPage (Toplist tab) so they can't drift. The page
 * owns the ViewModel + its source/period monitors + the pinned title-bar selector bar; this renders
 * the list and insets the first row below that pinned bar via `topPadding`.
 */
@ComponentV2
export struct GalleryListBody {
  @Require @Param vm: GalleryListViewModel;
  // Height of the page's pinned selector bar (source bar / period bar) so the first row clears it.
  @Param topPadding: number = 0;
  // Index owns one Scroller per tab and passes it down so the HdsNavigation title can bindToScrollable
  // the ACTIVE tab's list (scroll-up title auto-hide). Default for standalone use.
  @Param scroller: Scroller = new Scroller();
  // Per-tab display-mode override ('global' = follow the shared ListModeState). Changing it just
  // re-renders this tab with a different renderer; it does NOT refetch (handled by GallerySourcePage).
  @Param overrideMode: string = 'global';
  @Event onDidScroll?: (offset: number, state: ScrollState) => void;
  @Local listMode: ListModeState = connectListMode();
  @Local favoriteMutation: GalleryFavoriteMutationState = connectGalleryFavoriteMutation();
  @Local ratingMutation: GalleryRatingMutationState = connectGalleryRatingMutation();
  @Local favSel: FavSelectionState = connectFavSelection();
  @Local listContentWidth: number = 0;
  private layout: LayoutSafeAreaState = connectLayoutSafeArea();
  private stack: NavPathStack = connectNavStack().stack;
  private refreshController: PullRefreshController = new PullRefreshController();

  // Re-tapping the active bottom tab refreshes this list: the nav shell looks the action up by this list's
  // Scroller (it tracks each tab's active sub-tab Scroller) and fires it. Used by Gallery + Toplist tabs.
  aboutToAppear(): void {
    RootRefreshRegistry.register(this.scroller, () => {
      this.refreshController.triggerTopRefresh()
    })
  }

  aboutToDisappear(): void {
    RootRefreshRegistry.unregister(this.scroller)
  }

  @Monitor('favoriteMutation.version')
  onFavoriteMutation(): void {
    this.vm.applyFavoriteMutation(
      this.favoriteMutation.gid,
      this.favoriteMutation.favcat,
      this.favoriteMutation.favTitle,
    )
  }

  @Monitor('favSel.favList')
  onFavListChange(): void {
    this.vm.resolveVisibleFavoriteSlotsFrom(this.favSel.favList)
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

  // Renderer to use: the per-tab override when set, else the shared/global mode.
  private effectiveMode(): string {
    return this.overrideMode !== 'global' && this.overrideMode.length > 0
      ? this.overrideMode
      : this.listMode.mode
  }

  private openDetail(g: EhGallery): void {
    this.stack.pushPathByName(
      'GalleryDetail',
      new GalleryDetailParams(
        g.gid,
        g.token,
        g.thumbUrl,
        g.title(),
        g.fileCount,
        g.imgWidth,
        g.imgHeight,
      ),
    )
  }

  private restoreAfterPrepend(prependedCount: number): void {
    if (prependedCount <= 0) {
      return
    }
    const targetIndex: number = prependedCount + 1
    const firstDelay: number = ThemeConstants.ANIM_DONE_DELAY_MS + ThemeConstants.ANIM_DURATION + 40
    const finalDelay: number = firstDelay + ThemeConstants.ANIM_STATE_RESET_MS + 40
    DiagnosticLogger.info(
      'home-list-anchor',
      'restore_prepend_schedule',
      `prepended=${prependedCount} target=${targetIndex} offset=${this.safeYOffset()} firstDelay=${firstDelay} finalDelay=${finalDelay}`,
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
      try {
        DiagnosticLogger.info(
          'home-list-anchor',
          'restore_prepend_attempt',
          `target=${targetIndex} delay=${delayMs} before=${before} aligned=${alignedOffset} adjusted=${adjustedOffset} after=${this.safeYOffset()}`,
        )
      } catch (_logError) {}
    } catch (_error) {}
  }

  private adjustPrependOffset(alignedOffset: number): number {
    if (alignedOffset <= 0) {
      return alignedOffset
    }
    const topReserve: number = this.layout.topAvoidHeight + ThemeConstants.TITLE_BAR_HEIGHT + this.topPadding
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
        (this.vm.isLoading || !this.vm.loaded)
      ) {
        // Never-loaded OR loading (with nothing yet) → content-area loading. Gating on `!loaded` (not just
        // the transient isLoading) closes the frame where a freshly-switched sub-tab key is mounted but its
        // load hasn't flipped isLoading true yet — which used to flash CardEmptyState/no-more terminal copy.
        PageLoadingState()
      } else if (this.vm.itemCount === 0 && this.vm.errorMessage.length > 0) {
        PageErrorState({
          message: this.vm.errorMessage,
          retryAction: () => {
            this.vm.loadData()
          },
        })
      } else if (this.vm.itemCount === 0 && this.vm.source === '') {
        // Only the front page takes over the screen when empty; other sources fall through to the
        // scaffold so the pinned bar stays the only chrome (an empty list isn't a dead-end).
        CardEmptyState({ message: $r('app.string.common_no_content') })
      } else if (this.effectiveMode() === ListMode.GRID) {
        PullRefreshGridScaffold({
          scroller: this.scroller,
          minColumnWidth: ThemeConstants.GALLERY_GRID_MIN_W,
          pinchModeKey: ListMode.GRID,
          gap: ThemeConstants.GALLERY_GRID_GAP,
          horizontalPadding: ThemeConstants.GALLERY_GRID_GAP,
          topPadding: this.topPadding,
          bottomPadding: ThemeConstants.FLOAT_BAR_HEIGHT + ThemeConstants.SPACE_LG,
          itemCount: this.vm.itemCount,
          nearEndThreshold: 4,
          controller: this.refreshController,
          onRefresh: async () => {
            await this.vm.refresh((prependedCount: number) => {
              this.restoreAfterPrepend(prependedCount)
            })
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
                GalleryGridCard({ gallery: g })
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
      } else if (this.effectiveMode() === ListMode.WATERFALL) {
        PullRefreshWaterFlowScaffold({
          scroller: this.scroller,
          minColumnWidth: ThemeConstants.GALLERY_WATERFALL_MIN_W,
          pinchModeKey: ListMode.WATERFALL,
          itemCount: this.vm.itemCount,
          nearEndThreshold: 4,
          gap: ThemeConstants.GALLERY_GRID_GAP,
          horizontalPadding: ThemeConstants.GALLERY_GRID_GAP,
          topPadding: this.topPadding,
          bottomPadding: ThemeConstants.FLOAT_BAR_HEIGHT + ThemeConstants.SPACE_LG,
          controller: this.refreshController,
          onRefresh: async () => {
            await this.vm.refresh((prependedCount: number) => {
              this.restoreAfterPrepend(prependedCount)
            })
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
                GalleryWaterfallCard({ gallery: g })
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
      } else if (this.effectiveMode() === ListMode.COVER_WALL) {
        PullRefreshWaterFlowScaffold({
          scroller: this.scroller,
          minColumnWidth: ThemeConstants.GALLERY_COVER_WALL_MIN_W,
          pinchModeKey: ListMode.COVER_WALL,
          itemCount: this.vm.itemCount,
          nearEndThreshold: 4,
          gap: ThemeConstants.GALLERY_GRID_GAP,
          horizontalPadding: ThemeConstants.GALLERY_GRID_GAP,
          topPadding: this.topPadding,
          bottomPadding: ThemeConstants.FLOAT_BAR_HEIGHT + ThemeConstants.SPACE_LG,
          controller: this.refreshController,
          onRefresh: async () => {
            await this.vm.refresh((prependedCount: number) => {
              this.restoreAfterPrepend(prependedCount)
            })
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
                GalleryCoverWallCard({ gallery: g })
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
          topPadding: this.topPadding,
          listSpace: this.effectiveMode() === ListMode.SIMPLE_LIST ? 0 : ThemeConstants.SPACE_SM,
          bottomPadding: ThemeConstants.FLOAT_BAR_HEIGHT + ThemeConstants.SPACE_LG,
          controller: this.refreshController,
          onRefresh: async () => {
            await this.vm.refresh((prependedCount: number) => {
              this.restoreAfterPrepend(prependedCount)
            })
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
        }) {
          LazyForEach(
            this.vm.dataSource,
            (g: EhGallery, index: number) => {
              ListItem() {
                if (this.effectiveMode() === ListMode.SIMPLE_LIST) {
                  GallerySimpleCard({ gallery: g })
                } else {
                  GalleryCard({ gallery: g, listContentWidth: this.listContentWidth })
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
              // Include the page-level isLoading so a reload (source/period switch that keeps old rows and
              // forces hasMore=false up front) shows "加载中", not a stranded "没有更多了" terminal flash.
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
