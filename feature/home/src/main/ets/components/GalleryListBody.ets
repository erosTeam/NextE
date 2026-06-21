import {
  ThemeConstants,
  EhGallery,
  GalleryCard,
  GalleryGridCard,
  GalleryWaterfallCard,
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
  @Event onDidScroll?: (offset: number, state: ScrollState) => void;
  @Local listMode: ListModeState = connectListMode();
  @Local favoriteMutation: GalleryFavoriteMutationState = connectGalleryFavoriteMutation();
  @Local ratingMutation: GalleryRatingMutationState = connectGalleryRatingMutation();
  @Local listContentWidth: number = 0;
  private stack: NavPathStack = connectNavStack().stack;
  private refreshController: PullRefreshController = new PullRefreshController();

  @Monitor('favoriteMutation.version')
  onFavoriteMutation(): void {
    this.vm.applyFavoriteMutation(
      this.favoriteMutation.gid,
      this.favoriteMutation.favcat,
      this.favoriteMutation.favTitle,
    )
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
      } else if (this.listMode.mode === ListMode.GRID) {
        PullRefreshGridScaffold({
          scroller: this.scroller,
          minColumnWidth: ThemeConstants.GALLERY_GRID_MIN_W,
          gap: ThemeConstants.GALLERY_GRID_GAP,
          horizontalPadding: ThemeConstants.GALLERY_GRID_GAP,
          topPadding: this.topPadding,
          bottomPadding: ThemeConstants.FLOAT_BAR_HEIGHT + ThemeConstants.SPACE_LG,
          itemCount: this.vm.itemCount,
          nearEndThreshold: 4,
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
          onNearEnd: () => {
            this.vm.loadMore()
          },
          onDidScroll: (offset: number, state: ScrollState) => {
            if (this.onDidScroll) {
              this.onDidScroll(offset, state)
            }
          },
        }) {
          LazyForEach(
            this.vm.dataSource,
            (g: EhGallery) => {
              GridItem() {
                GalleryGridCard({ gallery: g })
              }
              .onClick(() => {
                this.openDetail(g)
              })
            },
            (g: EhGallery) => g.gid,
          )
        }
      } else if (this.listMode.mode === ListMode.WATERFALL) {
        PullRefreshWaterFlowScaffold({
          scroller: this.scroller,
          minColumnWidth: ThemeConstants.GALLERY_WATERFALL_MIN_W,
          itemCount: this.vm.itemCount,
          gap: ThemeConstants.GALLERY_GRID_GAP,
          horizontalPadding: ThemeConstants.GALLERY_GRID_GAP,
          topPadding: this.topPadding,
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
          onDidScroll: (offset: number, state: ScrollState) => {
            if (this.onDidScroll) {
              this.onDidScroll(offset, state)
            }
          },
        }) {
          LazyForEach(
            this.vm.dataSource,
            (g: EhGallery) => {
              FlowItem() {
                GalleryWaterfallCard({ gallery: g })
              }
              .width('100%')
              .onClick(() => {
                this.openDetail(g)
              })
            },
            (g: EhGallery) => g.gid,
          )
        }
      } else {
        PullRefreshListScaffold({
          scroller: this.scroller,
          topPadding: this.topPadding,
          listSpace: this.listMode.mode === ListMode.SIMPLE_LIST ? 0 : ThemeConstants.SPACE_SM,
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
            (g: EhGallery) => {
              ListItem() {
                if (this.listMode.mode === ListMode.SIMPLE_LIST) {
                  GallerySimpleCard({ gallery: g })
                } else {
                  GalleryCard({ gallery: g, listContentWidth: this.listContentWidth })
                }
              }
              .onClick(() => {
                this.openDetail(g)
              })
            },
            (g: EhGallery) => g.gid,
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
