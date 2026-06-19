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
  private controller: webview.WebviewController = new webview.WebviewController();
  private layout: LayoutSafeAreaState = connectLayoutSafeArea();

  private titleText(): string {
    return this.params.title.length > 0 ? this.params.title : this.params.url
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Center }) {
        Column() {
          EhWebView({
            controller: this.controller,
            onControllerAttached: () => {
              this.controller.setCustomUserAgent(EhConstants.USER_AGENT)
              this.controller.loadUrl(this.params.url)
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
  }
}
