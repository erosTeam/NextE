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
              // Cloudflare's managed challenge (forums.e-hentai.org login) never clears under ArkWeb's
              // native UA because its OS token "(Phone; OpenHarmony X)" is unknown to Cloudflare's
              // device database — the challenge re-issues forever. The Huawei system browser passes
              // precisely because it injects a "; Android 10" token so it looks like a known Android
              // device; we mirror that. Derive from the NATIVE UA (getUserAgent) so the Chrome/ArkWeb
              // versions and the rest of the mobile fingerprint (navigator.platform/WebGL/touch) stay
              // self-consistent — a spoofed *desktop* UA instead contradicts that fingerprint and also
              // fails CF (that was the original bug). Must be set before loadUrl.
              try {
                const native: string = this.controller.getUserAgent()
                this.controller.setCustomUserAgent(
                  native.replace(') AppleWebKit', '; Android 10) AppleWebKit'),
                )
              } catch (e) {
                DiagnosticLogger.warn('auth', 'web_login_set_ua_failed', (e as Error).message)
              }
              // Turnstile runs in a cross-origin iframe whose cookies need third-party acceptance.
              try {
                webview.WebCookieManager.putAcceptCookieEnabled(true)
                webview.WebCookieManager.putAcceptThirdPartyCookieEnabled(true)
              } catch (e) {
                DiagnosticLogger.warn('auth', 'web_login_accept_cookie_failed', (e as Error).message)
              }
              // Start from a CLEAN WebView session so a *new* account can sign in (the store otherwise
              // still holds the active account's forum session). Re-solving CF afterwards is fine.
              try {
                webview.WebCookieManager.clearAllCookiesSync()
              } catch (e) {
                DiagnosticLogger.warn('auth', 'web_login_clear_cookie_failed', (e as Error).message)
              }
              this.controller.loadUrl(EhConstants.FORUMS_LOGIN_FORM_URL)
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
    // Peek for the identity cookies WITHOUT mutating the jar, so a still-loading page never half-applies.
    const member: string = CookieJarSettings.parseCookieValue(header, EhConstants.COOKIE_MEMBER_ID)
    const pass: string = CookieJarSettings.parseCookieValue(header, EhConstants.COOKIE_PASS_HASH)
    if (member.length === 0 || pass.length === 0) {
      // Not logged in yet — user is still on the form. Wait for the next page load.
      return
    }
    this.captured = true
    // Replace (clear + apply) so a newly-added account doesn't inherit the previous account's igneous/sk.
    CookieJarSettings.replaceFromHeader(header)
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext
    await CookieJarSettings.save(ctx)
    promptAction.showToast({ message: $r('app.string.login_success') })
    this.stack.pop()
  }
}
