import { HdsNavDestination } from '@kit.UIDesignKit'
import { CustomContentDialog } from '@kit.ArkUI'
import {
  ThemeConstants,
  EhGalleryImage,
  PreviewThumbTile,
  ReaderParams,
  AllThumbnailsParams,
  connectNavStack,
  connectReaderOverlayNavigation,
  PullRefreshGridScaffold,
  PullRefreshController,
  AppStrings,
  ListMode,
  immersiveTitleBarOpts,
} from 'shared'
import { AllThumbnailsViewModel } from '../viewmodel/AllThumbnailsViewModel'

/**
 * Reusable full-thumbnail browsing surface. Its host owns the ViewModel, Scroller, refresh controller,
 * route shell, title actions, and sheets; this component only renders the existing paged grid and
 * forwards thumbnail activation. Keeping those owners outside lets another page mount the same surface
 * without duplicating navigation chrome or losing paging state when the surface is recomposed.
 */
@ComponentV2
export struct GalleryAllThumbnailsContent {
  @Require @Param vm: AllThumbnailsViewModel;
  @Param scroller: Scroller = new Scroller();
  @Param controller: PullRefreshController = new PullRefreshController();
  // The inline detail workspace grants the native status-bar action to one pane at a time.
  // Standalone all-thumbnails pages keep the default true value.
  @Param backToTop: boolean = true;
  @Event onOpen: (image: EhGalleryImage) => void = (_image: EhGalleryImage) => {};
  @Event onUserScroll?: () => void;
  @Local thumbnailReloadToken: number = 0;

  private loadNextIfTailAppeared(index: number): void {
    if (index < this.vm.itemCount - 1) {
      return
    }
    if (!this.vm.loading && this.vm.error.length === 0 && this.vm.hasMore()) {
      this.vm.loadNext()
    }
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

  private async refreshThumbnailLoads(): Promise<void> {
    this.thumbnailReloadToken += 1
    await this.loadPreviousPreviewPage()
  }

  build() {
    PullRefreshGridScaffold({
      scroller: this.scroller,
      backToTop: this.backToTop,
      // Responsive: ArkUI derives columns from the pane width + min comfortable thumb width. Tiles
      // consume their actual cell width locally; this surface does not hand-calculate columns or cells.
      minColumnWidth: ThemeConstants.PREVIEW_THUMB_MIN_W,
      pinchModeKey: ListMode.THUMBNAIL_GRID,
      itemCount: this.vm.itemCount,
      bottomPadding: ThemeConstants.SPACE_XL,
      controller: this.controller,
      onRefresh: async () => {
        await this.refreshThumbnailLoads()
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
      onUserScroll: () => {
        if (this.onUserScroll) {
          this.onUserScroll()
        }
      },
    }) {
      LazyForEach(
        this.vm.dataSource,
        (img: EhGalleryImage, index: number) => {
          GridItem() {
            PreviewThumbTile({
              image: img,
              reloadToken: this.thumbnailReloadToken,
              onTap: () => {
                this.onOpen(img)
              },
            })
          }
          .onAppear(() => {
            this.loadNextIfTailAppeared(index)
          })
        },
        (img: EhGalleryImage) => `${img.page}`,
      )
    }
  }
}

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
  @Local jumpPageText: string = '';
  @Local jumpError: string = '';
  private jumpSubmitting: boolean = false;
  private stack: NavPathStack = connectNavStack().stack;
  private scroller: Scroller = new Scroller();
  private refreshController: PullRefreshController = new PullRefreshController();
  private jumpDialogController: CustomDialogController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: $r('app.string.gallery_preview_jump'),
      contentBuilder: () => {
        this.JumpDialogContent()
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
          value: $r('app.string.gallery_preview_jump'),
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: () => {
            this.confirmJump()
          },
        },
      ],
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    customStyle: false,
  });

  private openReader(img: EhGalleryImage): void {
    const pageZeroBased: number = img.page > 0 ? img.page - 1 : 0
    const params: ReaderParams = new ReaderParams(
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
    )
    params.sourceLanguage = this.params.sourceLanguage
    connectReaderOverlayNavigation().open(params)
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
        this.openJumpDialog()
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

  private openJumpDialog(): void {
    this.jumpPageText = `${this.defaultJumpPage()}`
    this.jumpError = ''
    this.jumpDialogController.open()
  }

  private closeJumpDialog(): void {
    try {
      this.jumpDialogController.close()
    } catch (_error) {
      // Dialog may already be dismissed by tapping outside.
    }
  }

  private normalizeJumpInput(value: string): string {
    return (value || '').replace(/[^0-9]/g, '')
  }

  private jumpHelpText(): string {
    const maxPage: number = this.maxImagePage()
    if (maxPage <= 0) {
      return AppStrings.get('gallery_preview_jump_help')
    }
    return `${AppStrings.get('gallery_preview_jump_help')} 1 - ${maxPage}`
  }

  private confirmJump(): void {
    if (this.jumpSubmitting) {
      return
    }
    const page: number = Number.parseInt(this.jumpPageText, 10)
    const maxPage: number = this.maxImagePage()
    if (Number.isNaN(page) || page <= 0 || (maxPage > 0 && page > maxPage)) {
      this.jumpError = AppStrings.get('gallery_preview_jump_invalid')
      return
    }
    this.jumpSubmitting = true
    this.vm.loadImagePage(page)
      .then((loaded: boolean) => {
        this.jumpSubmitting = false
        if (!loaded) {
          this.jumpError = AppStrings.get('common_load_failed')
          return
        }
        this.closeJumpDialog()
        const targetIndex: number = this.vm.visibleIndexForImagePage(page)
        setTimeout(() => {
          if (targetIndex >= 0) {
            this.scroller.scrollToIndex(targetIndex)
          }
        }, 50)
      })
      .catch((_error: Error) => {
        this.jumpSubmitting = false
        this.jumpError = AppStrings.get('common_load_failed')
      })
  }

  @Builder
  JumpDialogContent() {
    Column({ space: ThemeConstants.SPACE_SM }) {
      Text(this.jumpHelpText())
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      TextInput({ text: this.jumpPageText, placeholder: $r('app.string.gallery_preview_jump_placeholder') })
        .type(InputType.Number)
        .inputFilter('^[0-9]*$')
        .defaultFocus(true)
        .width('100%')
        .onChange((v: string) => {
          this.jumpPageText = this.normalizeJumpInput(v)
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

  build() {
    HdsNavDestination() {
      Stack() {
        GalleryAllThumbnailsContent({
          vm: this.vm,
          scroller: this.scroller,
          controller: this.refreshController,
          onOpen: (img: EhGalleryImage) => {
            this.openReader(img)
          },
        })
      }
      .width('100%')
      .height('100%')
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
