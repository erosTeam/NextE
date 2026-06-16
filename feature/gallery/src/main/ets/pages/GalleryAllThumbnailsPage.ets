import { HdsNavDestination } from '@kit.UIDesignKit'
import {
  ThemeConstants,
  EhGalleryImage,
  EhSpriteThumbnail,
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
        columns: 4,
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
              Column({ space: 2 }) {
                EhSpriteThumbnail({
                  url: img.thumbUrl,
                  thumbWidth: img.thumbWidth,
                  thumbHeight: img.thumbHeight,
                  offsetX: img.thumbOffsetX,
                  spriteWidth: img.spriteWidth,
                  spriteHeight: img.spriteHeight,
                  displayWidth: 82,
                })
                Text(`${img.page}`)
                  .fontSize(ThemeConstants.FONT_SIZE_TINY)
                  .fontColor($r('sys.color.font_tertiary'))
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
              .onClick(() => {
                this.openReader(img.page - 1)
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
