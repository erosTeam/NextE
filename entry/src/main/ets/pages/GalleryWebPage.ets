import { webview } from '@kit.ArkWeb'
import { HdsNavDestination } from '@kit.UIDesignKit'
import {
  EhWebView,
  EhConstants,
  EhCookieStore,
  GalleryWebParams,
  DiagnosticLogger,
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
    this.loadWithCookies(this.params.url)
  }

  private async loadWithCookies(url: string): Promise<void> {
    try {
      await this.injectAppCookies(url)
    } catch (error) {
      const e = error as Error
      DiagnosticLogger.warn('webview', 'gallery_webview_cookie_inject_failed', e.message)
    }
    this.safeLoadUrl(url)
  }

  private async injectAppCookies(url: string): Promise<void> {
    const cookie: string = EhCookieStore.getInstance().header()
    if (cookie.length === 0) {
      return
    }
    const baseUrl: string = url.startsWith(EhConstants.EX_BASE_URL)
      ? EhConstants.EX_BASE_URL
      : EhConstants.EH_BASE_URL
    await webview.WebCookieManager.configCookie(baseUrl, `${cookie}; Path=/`, false, true)
    try {
      webview.WebCookieManager.saveCookieSync()
    } catch (_error) {
      await webview.WebCookieManager.saveCookieAsync()
    }
  }

  private safeLoadUrl(url: string): void {
    try {
      this.controller.loadUrl(url)
    } catch (error) {
      const e = error as Error
      DiagnosticLogger.warn('webview', 'gallery_webview_load_url_failed', e.message)
      this.loading = false
    }
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
