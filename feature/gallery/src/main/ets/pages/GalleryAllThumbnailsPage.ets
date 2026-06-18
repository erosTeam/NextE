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
  immersiveTitleBarOpts,
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
  @Local jumpSheetShown: boolean = false;
  @Local jumpPageText: string = '';
  @Local jumpError: string = '';
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
        this.vm.loadedImages(),
        this.vm.loadedPreviewPages(),
        this.vm.seedPerPage(),
      ),
    )
  }

  private previewTitleBar(): Record<string, Object> {
    const title: Record<string, Object> = { 'mainTitle': AppStrings.get('gallery_preview') }
    const content: Record<string, Object> = { 'title': title, 'menu': this.jumpMenu() }
    return immersiveTitleBarOpts(content)
  }

  private jumpMenu(): Record<string, Object> {
    const inner: Record<string, Object> = {
      'label': $r('app.string.gallery_preview_jump'),
      'icon': $r('sys.symbol.arrow_right'),
      'isEnabled': true,
      'action': () => {
        this.jumpPageText = `${this.defaultJumpPage()}`
        this.jumpError = ''
        this.jumpSheetShown = true
      },
    }
    const items: Record<string, Object>[] = [{ 'content': inner }]
    return { 'value': items, 'maxCount': 1 }
  }

  private maxImagePage(): number {
    return this.params.fileCount > 0 ? this.params.fileCount : this.vm.itemCount
  }

  private defaultJumpPage(): number {
    const maxPage: number = this.maxImagePage()
    if (maxPage <= 0) {
      return 1
    }
    return Math.min(maxPage, this.vm.itemCount + 1)
  }

  private async confirmJump(): Promise<void> {
    const page: number = Number.parseInt(this.jumpPageText, 10)
    const maxPage: number = this.maxImagePage()
    if (Number.isNaN(page) || page <= 0 || (maxPage > 0 && page > maxPage)) {
      this.jumpError = AppStrings.get('gallery_preview_jump_invalid')
      return
    }
    const loaded: boolean = await this.vm.loadThroughImagePage(page)
    if (!loaded) {
      this.jumpError = AppStrings.get('common_load_failed')
      return
    }
    this.jumpSheetShown = false
    const targetIndex: number = page - 1
    setTimeout(() => {
      this.scroller.scrollToIndex(targetIndex)
    }, 50)
  }

  @Builder
  JumpSheet() {
    Column({ space: ThemeConstants.SPACE_MD }) {
      Text($r('app.string.gallery_preview_jump_help'))
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor($r('sys.color.font_secondary'))
      TextInput({ text: this.jumpPageText, placeholder: $r('app.string.gallery_preview_jump_placeholder') })
        .type(InputType.Number)
        .height(44)
        .backgroundColor($r('app.color.card_background'))
        .onChange((v: string) => {
          this.jumpPageText = v
          this.jumpError = ''
        })
      if (this.jumpError.length > 0) {
        Text(this.jumpError)
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor(Color.Red)
      }
      Row({ space: ThemeConstants.SPACE_MD }) {
        Button($r('app.string.common_cancel'))
          .type(ButtonType.Capsule)
          .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
          .onClick(() => {
            this.jumpSheetShown = false
          })
        Button($r('app.string.gallery_preview_jump'))
          .type(ButtonType.Capsule)
          .layoutWeight(1)
          .onClick(() => {
            this.confirmJump()
          })
      }.width('100%')
    }
    .width('100%')
    .padding(ThemeConstants.SPACE_LG)
  }

  build() {
    HdsNavDestination() {
      Stack() {
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
      .width('100%')
      .height('100%')
      .bindSheet($$this.jumpSheetShown, this.JumpSheet(), {
        detents: [SheetSize.MEDIUM],
        title: { title: $r('app.string.gallery_preview_jump') },
        showClose: true,
      })
    }
    .titleBar(this.previewTitleBar())
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
