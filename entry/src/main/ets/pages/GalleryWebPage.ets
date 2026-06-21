import { webview } from '@kit.ArkWeb'
import { HdsNavDestination } from '@kit.UIDesignKit'
import {
  EhWebView,
  EhConstants,
  GalleryWebParams,
  ThemeConstants,
  connectLayoutSafeArea,
  LayoutSafeAreaState,
  immersiveTitleBar,
} from 'shared'

/** Generic in-app EH WebView escape hatch for pages whose native parity is still incomplete. */
@ComponentV2
export struct GalleryWebPage {
  @Local params: GalleryWebParams = new GalleryWebParams();
  @Local loading: boolean = true;
  @Local controllerReady: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();
  private layout: LayoutSafeAreaState = connectLayoutSafeArea();
  private loadedUrl: string = '';

  private titleText(): string {
    return this.params.title.length > 0 ? this.params.title : this.params.url
  }

  private loadIfReady(): void {
    if (!this.controllerReady || this.params.url.length === 0 || this.loadedUrl === this.params.url) {
      return
    }
    this.loadedUrl = this.params.url
    this.controller.setCustomUserAgent(EhConstants.USER_AGENT)
    this.controller.loadUrl(this.params.url)
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Center }) {
        Column() {
          EhWebView({
            controller: this.controller,
            onControllerAttached: () => {
              this.controllerReady = true
              this.loadIfReady()
            },
            onPageBegin: () => {
              this.loading = true
            },
            onPageEnd: () => {
              this.loading = false
            },
            onErrorReceive: () => {
              this.loading = false
            },
          })
        }
        .width('100%')
        .height('100%')
        .padding({ top: this.layout.topAvoidHeight + ThemeConstants.TITLE_BAR_HEIGHT })

        if (this.loading) {
          LoadingProgress()
            .width(ThemeConstants.LOADING_SIZE)
            .height(ThemeConstants.LOADING_SIZE)
        }
      }
      .width('100%')
      .height('100%')
    }
    .titleBar(immersiveTitleBar(this.titleText()))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .onReady((context: NavDestinationContext) => {
      const p = context.pathInfo.param as GalleryWebParams
      if (p !== undefined) {
        this.params = p
        this.loadIfReady()
      }
    })
  }
}
