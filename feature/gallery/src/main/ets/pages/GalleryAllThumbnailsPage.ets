import { HdsNavDestination } from '@kit.UIDesignKit'
import {
  ThemeConstants,
  EhGalleryImage,
  PreviewThumbTile,
  ReaderParams,
  AllThumbnailsParams,
  connectNavStack,
  PullRefreshGridScaffold,
  PullRefreshController,
  AppStrings,
  immersiveTitleBar,
} from 'shared'
import { AllThumbnailsViewModel } from '../viewmodel/AllThumbnailsViewModel'

/**
 * The separate all-thumbnails page (eros_fe galleryAllThumbnails). The detail page shows only the
 * first preview page as a peek and links here; this page owns the full paged thumbnail grid so a
 * thousand-page gallery never inflates the detail. Native PullRefreshGridScaffold; tapping a thumb
 * opens the reader at that page. (Forward paging now; bidirectional + jump-dialog are follow-ups.)
 */
@ComponentV2
export struct GalleryAllThumbnailsPage {
  @Local vm: AllThumbnailsViewModel = new AllThumbnailsViewModel();
  @Local params: AllThumbnailsParams = new AllThumbnailsParams();
  // Responsive cell width (vp) emitted by the scaffold; drives the sprite thumb so it fills its column.
  @Local thumbW: number = 0;
  private stack: NavPathStack = connectNavStack().stack;
  private scroller: Scroller = new Scroller();
  private refreshController: PullRefreshController = new PullRefreshController();

  private openReader(pageZeroBased: number): void {
    this.stack.pushPathByName(
      'Reader',
      new ReaderParams(
        this.params.gid,
        this.params.token,
        pageZeroBased,
        this.params.fileCount,
        this.params.title,
      ),
    )
  }

  build() {
    HdsNavDestination() {
      PullRefreshGridScaffold({
        scroller: this.scroller,
        // Responsive: column count derived from the pane width + a min comfortable thumb width (a phone
        // lands ~3, wider screens scale up), not a hardcoded count. The cell width feeds the thumbs.
        minColumnWidth: ThemeConstants.PREVIEW_THUMB_MIN_W,
        onCellSize: (_cols: number, cellWidth: number) => {
          this.thumbW = cellWidth
        },
        bottomPadding: ThemeConstants.SPACE_XL,
        controller: this.refreshController,
        onBottomRefresh: async () => {
          await this.vm.loadNext()
        },
        canStartBottomRefresh: () => this.vm.hasMore(),
        onReachEnd: () => {
          this.vm.loadNext()
        },
      }) {
        LazyForEach(
          this.vm.dataSource,
          (img: EhGalleryImage) => {
            GridItem() {
              PreviewThumbTile({
                image: img,
                tileWidth: this.thumbW > 0 ? this.thumbW : ThemeConstants.PREVIEW_THUMB_MIN_W,
                onTap: () => {
                  this.openReader(img.page - 1)
                },
              })
            }
          },
          (img: EhGalleryImage) => `${img.page}`,
        )
      }
    }
    .titleBar(immersiveTitleBar(AppStrings.get('gallery_preview')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .onReady((context: NavDestinationContext) => {
      const p = context.pathInfo.param as AllThumbnailsParams
      if (p !== undefined && p.gid.length > 0) {
        this.params = p
        this.vm.seed(p)
      }
    })
  }
}
