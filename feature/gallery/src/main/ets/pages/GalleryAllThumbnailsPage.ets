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
 * opens the reader at that page. Page jump and first-page return live in the title bar; bidirectional
 * previous-page pull is a follow-up.
 */
@ComponentV2
export struct GalleryAllThumbnailsPage {
  @Local vm: AllThumbnailsViewModel = new AllThumbnailsViewModel();
  @Local params: AllThumbnailsParams = new AllThumbnailsParams();
  @Local jumpSheetShown: boolean = false;
  @Local jumpPageText: string = '';
  @Local jumpError: string = '';
  private stack: NavPathStack = connectNavStack().stack;
  private scroller: Scroller = new Scroller();
  private refreshController: PullRefreshController = new PullRefreshController();

  private openReader(img: EhGalleryImage): void {
    const pageZeroBased: number = img.page > 0 ? img.page - 1 : 0
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
        this.vm.loadedPreviewPageNumbers(),
        img.sUrl,
      ),
    )
  }

  private previewTitleBar(): Record<string, Object> {
    const title: Record<string, Object> = { 'mainTitle': AppStrings.get('gallery_preview') }
    const content: Record<string, Object> = { 'title': title, 'menu': this.jumpMenu() }
    return immersiveTitleBarOpts(content)
  }

  private jumpMenu(): Record<string, Object> {
    const firstInner: Record<string, Object> = {
      'label': $r('app.string.gallery_preview_first_page'),
      'icon': $r('sys.symbol.arrow_up_circle'),
      'isEnabled': true,
      'action': () => {
        this.backToFirstPage()
      },
    }
    const jumpInner: Record<string, Object> = {
      'label': $r('app.string.gallery_preview_jump'),
      'icon': $r('sys.symbol.arrow_right'),
      'isEnabled': true,
      'action': () => {
        this.jumpPageText = `${this.defaultJumpPage()}`
        this.jumpError = ''
        this.jumpSheetShown = true
      },
    }
    const items: Record<string, Object>[] = [
      { 'content': firstInner },
      { 'content': jumpInner },
    ]
    return { 'value': items, 'maxCount': 2 }
  }

  private async backToFirstPage(): Promise<void> {
    await this.vm.loadImagePage(1)
    const targetIndex: number = this.vm.visibleIndexForImagePage(1)
    if (targetIndex < 0) {
      return
    }
    setTimeout(() => {
      this.scroller.scrollToIndex(targetIndex)
    }, 50)
  }

  private async loadPreviousPreviewPage(): Promise<void> {
    const firstImagePage: number = await this.vm.loadPreviousPreviewPage()
    if (firstImagePage <= 0) {
      return
    }
    const targetIndex: number = this.vm.visibleIndexForImagePage(firstImagePage)
    if (targetIndex < 0) {
      return
    }
    setTimeout(() => {
      this.scroller.scrollToIndex(targetIndex)
    }, 50)
  }

  private scrollToImagePage(pageOneBased: number): void {
    const targetIndex: number = this.vm.visibleIndexForImagePage(pageOneBased)
    if (targetIndex < 0) {
      return
    }
    setTimeout(() => {
      this.scroller.scrollToIndex(targetIndex)
    }, 50)
  }

  private positionInitialImagePage(): void {
    const page: number = this.params.initialImagePage
    if (page <= 1) {
      return
    }
    if (this.vm.visibleIndexForImagePage(page) >= 0) {
      this.scrollToImagePage(page)
      return
    }
    this.vm.loadImagePage(page).then((loaded: boolean) => {
      if (loaded) {
        this.scrollToImagePage(page)
      }
    })
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
    const loaded: boolean = await this.vm.loadImagePage(page)
    if (!loaded) {
      this.jumpError = AppStrings.get('common_load_failed')
      return
    }
    this.jumpSheetShown = false
    const targetIndex: number = this.vm.visibleIndexForImagePage(page)
    setTimeout(() => {
      if (targetIndex >= 0) {
        this.scroller.scrollToIndex(targetIndex)
      }
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
          .fontColor(ThemeConstants.TEXT_ON_BRAND)
          .backgroundColor(ThemeConstants.BRAND_PRIMARY)
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
          // Responsive: ArkUI derives columns from the pane width + min comfortable thumb width. Tiles
          // consume their actual cell width locally; this page does not hand-calculate columns or cells.
          minColumnWidth: ThemeConstants.PREVIEW_THUMB_MIN_W,
          itemCount: this.vm.itemCount,
          bottomPadding: ThemeConstants.SPACE_XL,
          controller: this.refreshController,
          onRefresh: async () => {
            await this.loadPreviousPreviewPage()
          },
          onBottomRefresh: async () => {
            await this.vm.loadNext()
          },
          canStartBottomRefresh: () => this.vm.hasMore(),
          onReachEnd: () => {
            this.vm.loadNext()
          },
          showFooter: true,
          footerIsLoading: this.vm.loading,
          footerHasMore: this.vm.hasMore(),
          footerIsError: this.vm.error.length > 0 && this.vm.hasMore(),
          onFooterRetry: () => {
            this.vm.loadNext()
          },
        }) {
          LazyForEach(
            this.vm.dataSource,
            (img: EhGalleryImage) => {
              GridItem() {
                PreviewThumbTile({
                  image: img,
                  onTap: () => {
                    this.openReader(img)
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
        this.positionInitialImagePage()
      }
    })
  }
}
