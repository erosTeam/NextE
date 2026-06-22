import { webview } from '@kit.ArkWeb'
import { HdsNavDestination } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import { promptAction } from '@kit.ArkUI'
import {
  EhWebView,
  EhConstants,
  CookieJarSettings,
  connectNavStack,
  connectLayoutSafeArea,
  LayoutSafeAreaState,
  ThemeConstants,
  DiagnosticLogger,
  immersiveTitleBar,
} from 'shared'

/**
 * In-app EH login (V2Next web-login pattern). Hosts the EH forums login form in a native Web
 * component — the user signs in with their own credentials (we never see/handle the password).
 * After every page load we read the WebView's cookies via WebCookieManager; once both identity
 * cookies (ipb_member_id + ipb_pass_hash) are present we persist the bundle (CookieJarSettings),
 * refresh AuthState, and pop back. Cookie values are sensitive — only counts/booleans are logged.
 */
@ComponentV2
export struct EhLoginWebPage {
  private controller: webview.WebviewController = new webview.WebviewController();
  private stack: NavPathStack = connectNavStack().stack;
  private layout: LayoutSafeAreaState = connectLayoutSafeArea();
  @Local loading: boolean = true;
  private captured: boolean = false;

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Center }) {
        Column() {
          EhWebView({
            controller: this.controller,
            onControllerAttached: () => {
              // Present the SAME desktop-Chrome UA the app's HTTP client uses (proven to pass
              // e-hentai's edge). ArkWeb's default WebView UA is what trips Cloudflare's managed
              // challenge — a real browser UA lets the login page load like it does in Chrome.
              // Must be set before loadUrl so the very first request carries it.
              this.controller.setCustomUserAgent(EhConstants.USER_AGENT)
              this.controller.loadUrl(EhConstants.FORUMS_LOGIN_URL)
            },
            onPageBegin: () => {
              this.loading = true
            },
            onPageEnd: () => {
              this.loading = false
              this.tryCapture()
            },
            onErrorReceive: () => {
              this.loading = false
            },
          })
        }
        .width('100%')
        .height('100%')
        // Web content sits below the HDS title bar (which scrolls over content otherwise).
        .padding({ top: this.layout.topAvoidHeight + ThemeConstants.TITLE_BAR_HEIGHT })

        if (this.loading) {
          LoadingProgress()
            .width(ThemeConstants.LOADING_SIZE)
            .height(ThemeConstants.LOADING_SIZE)
            .color(ThemeConstants.BRAND_PRIMARY)
        }
      }
      .width('100%')
      .height('100%')
    }
    .titleBar(immersiveTitleBar($r('app.string.nav_login')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }

  private async tryCapture(): Promise<void> {
    if (this.captured) {
      return
    }
    try {
      webview.WebCookieManager.saveCookieSync()
    } catch (_e) {
      try {
        await webview.WebCookieManager.saveCookieAsync()
      } catch (_e2) {
        // best-effort flush; fetch below still reads whatever is committed
      }
    }
    let header: string = ''
    try {
      const ehCookie: string = await webview.WebCookieManager.fetchCookie(EhConstants.EH_BASE_URL)
      const forumCookie: string = await webview.WebCookieManager.fetchCookie(
        'https://forums.e-hentai.org',
      )
      header = `${ehCookie}; ${forumCookie}`
    } catch (e) {
      DiagnosticLogger.warn('auth', 'web_login_fetch_cookie_failed', (e as Error).message)
      return
    }
    if (!CookieJarSettings.applyFromHeader(header)) {
      // Not logged in yet — user is still on the form. Wait for the next page load.
      return
    }
    this.captured = true
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext
    await CookieJarSettings.save(ctx)
    promptAction.showToast({ message: $r('app.string.login_success') })
    this.stack.pop()
  }
}
