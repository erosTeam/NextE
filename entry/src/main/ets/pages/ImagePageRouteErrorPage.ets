import { HdsNavDestination } from '@kit.UIDesignKit'
import {
  ThemeConstants,
  PageErrorState,
  ImagePageRouteErrorParams,
  ImagePageRouteService,
  ImagePageRouteTarget,
  ReaderParams,
  DiagnosticLogger,
  connectReaderOverlayNavigation,
  immersiveTitleBar,
} from 'shared'

/**
 * Visible failure surface for stale/invalid EH /s/ deep links. A failed image-page route used to log
 * and leave the user on the previous tab, which made a real tap look ignored.
 */
@ComponentV2
export struct ImagePageRouteErrorPage {
  @Local params: ImagePageRouteErrorParams = new ImagePageRouteErrorParams();
  @Local loading: boolean = false;

  private retry(): void {
    if (this.params.url.length === 0 || this.loading) {
      return
    }
    this.loading = true
    ImagePageRouteService.resolve(this.params.url)
      .then((target: ImagePageRouteTarget) => {
        this.loading = false
        connectReaderOverlayNavigation().open(
          new ReaderParams(target.gid, target.token, target.index, target.fileCount, '', [target.seedImage], 0, 0),
        )
      })
      .catch((err: Error) => {
        this.loading = false
        DiagnosticLogger.warn('nav', 'image_page_deep_link_retry_failed', err.message)
      })
  }

  build() {
    HdsNavDestination() {
      Column() {
        if (this.loading) {
          LoadingProgress()
            .width(ThemeConstants.LOADING_SIZE)
            .height(ThemeConstants.LOADING_SIZE)
            .color(ThemeConstants.BRAND_PRIMARY)
        } else {
          PageErrorState({
            message: $r('app.string.image_page_open_failed'),
            retryAction: () => {
              this.retry()
            },
          })
        }
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .padding(ThemeConstants.SPACE_XL)
    }
    .titleBar(immersiveTitleBar($r('app.string.image_page_open_failed_title')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .onReady((context: NavDestinationContext) => {
      const p = context.pathInfo.param as ImagePageRouteErrorParams
      if (p !== undefined && p.url.length > 0) {
        this.params = p
      }
    })
  }
}
