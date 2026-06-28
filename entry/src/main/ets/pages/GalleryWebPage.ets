import { webview } from '@kit.ArkWeb'
import { HdsNavDestination } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import {
  EhWebView,
  EhConstants,
  EhCookieStore,
  GalleryWebParams,
  DiagnosticLogger,
  CookieJarSettings,
  UserProfileService,
  ThemeConstants,
  SecondaryListScaffold,
  connectNavStack,
  immersiveTitleBarOpts,
} from 'shared'

/** Generic in-app EH WebView escape hatch for pages whose native parity is still incomplete. */
@ComponentV2
export struct GalleryWebPage {
  @Local params: GalleryWebParams = new GalleryWebParams();
  @Local loading: boolean = true;
  @Local controllerReady: boolean = false;
  // Live <title> from the loaded page (onTitleReceive); falls back to the passed title/url until it arrives.
  @Local pageTitle: string = '';
  // Toolbar back/forward enablement, refreshed after each navigation (WebviewController.accessBackward/Forward).
  @Local canBack: boolean = false;
  @Local canForward: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();
  private stack: NavPathStack = connectNavStack().stack;
  private profileCaptured: boolean = false;
  // The scaffold's List owns the scroll; the Web's nestedScroll PARENT_FIRST bubbles into it so the page
  // scrolls UNDER the immersive title bar (V2Next V2exWebViewScaffold + nestedScroll → immersive nav).
  private scroller: Scroller = new Scroller();
  private loadedUrl: string = '';

  private titleText(): string {
    if (this.pageTitle.length > 0) {
      return this.pageTitle
    }
    return this.params.title.length > 0 ? this.params.title : this.params.url
  }

  private updateNavState(): void {
    if (!this.controllerReady) {
      return
    }
    try {
      this.canBack = this.controller.accessBackward()
      this.canForward = this.controller.accessForward()
    } catch (_error) {
      this.canBack = false
      this.canForward = false
    }
  }

  // Back / forward / refresh in the title-bar menu (same Record shape as Index.ets's tab menus). EH pages
  // have deep internal links (comments, multi-page viewer, pager), so browser-style history nav is useful.
  private webMenu(): Record<string, Object> {
    const back: Record<string, Object> = {
      'label': $r('app.string.web_nav_back'),
      'icon': $r('sys.symbol.chevron_left'),
      'isEnabled': this.canBack,
      'action': () => {
        if (this.controllerReady && this.controller.accessBackward()) {
          this.controller.backward()
        }
      },
    }
    const forward: Record<string, Object> = {
      'label': $r('app.string.web_nav_forward'),
      'icon': $r('sys.symbol.chevron_right'),
      'isEnabled': this.canForward,
      'action': () => {
        if (this.controllerReady && this.controller.accessForward()) {
          this.controller.forward()
        }
      },
    }
    const refresh: Record<string, Object> = {
      'label': $r('app.string.web_nav_refresh'),
      'icon': $r('sys.symbol.arrow_clockwise'),
      'isEnabled': true,
      'action': () => {
        if (this.controllerReady) {
          this.controller.refresh()
        }
      },
    }
    const items: Record<string, Object>[] = [
      { 'content': back },
      { 'content': forward },
      { 'content': refresh },
    ]
    return { 'value': items, 'maxCount': 3 }
  }

  private titleBarOpts(): Record<string, Object> {
    const title: Record<string, Object> = { 'mainTitle': this.titleText() }
    const content: Record<string, Object> = { 'title': title, 'menu': this.webMenu() }
    return immersiveTitleBarOpts(content)
  }

  private loadIfReady(): void {
    if (
      !this.controllerReady ||
      this.params.url.length === 0 ||
      this.loadedUrl === this.params.url
    ) {
      return
    }
    this.loadedUrl = this.params.url
    this.controller.setCustomUserAgent(this.isForumsUrl(this.params.url)
      ? this.forumsUserAgent()
      : EhConstants.USER_AGENT)
    this.loadWithCookies(this.params.url)
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private isForumsUrl(url: string): boolean {
    return url.startsWith(EhConstants.FORUMS_BASE_URL)
  }

  private forumsUserAgent(): string {
    try {
      const native: string = this.controller.getUserAgent()
      return native.replace(') AppleWebKit', '; Android 10) AppleWebKit')
    } catch (_error) {
      return EhConstants.USER_AGENT
    }
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

  // EH auth lives across several cookies (ipb_member_id + ipb_pass_hash, plus igneous on ex). WebCookieManager
  // sets ONE cookie per call, so the whole "a=1; b=2; …" header has to be split and injected per cookie —
  // passing it as a single value silently kept only the first, leaving the WebView logged out. (V2Next's
  // CookieJarSettings.restoreToWebCookieManager loops per cookie the same way.)
  private async injectAppCookies(url: string): Promise<void> {
    const header: string = EhCookieStore.getInstance().header()
    if (header.length === 0) {
      return
    }
    let baseUrl: string = EhConstants.EH_BASE_URL
    if (url.startsWith(EhConstants.EX_BASE_URL)) {
      baseUrl = EhConstants.EX_BASE_URL
    } else if (this.isForumsUrl(url)) {
      baseUrl = EhConstants.FORUMS_BASE_URL
    }
    const parts: string[] = header.split(';')
    for (const part of parts) {
      const pair: string = part.trim()
      if (pair.length === 0 || pair.indexOf('=') <= 0) {
        continue
      }
      try {
        webview.WebCookieManager.configCookieSync(baseUrl, `${pair}; Path=/`, false, true)
      } catch (error) {
        const e = error as Error
        DiagnosticLogger.warn('webview', 'gallery_webview_cookie_config_failed', e.message)
      }
    }
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

  private syncLoadedCookies(): void {
    if (!this.isForumsUrl(this.loadedUrl)) {
      return
    }
    CookieJarSettings.mergeFromWebCookieManager(this.ctx())
    this.captureForumProfileHtml()
    setTimeout((): void => {
      this.captureForumProfileHtml()
    }, 1000)
  }

  private async captureForumProfileHtml(): Promise<void> {
    if (this.loadedUrl.indexOf('showuser=') < 0) {
      return
    }
    try {
      const payload: string = await this.controller.runJavaScript(UserProfileService.profileDomCaptureScript())
      if (UserProfileService.applyProfileDomPayload(payload)) {
        UserProfileService.materializeAvatar(this.ctx())
        await UserProfileService.saveActive(this.ctx())
        if (this.params.closeOnProfileCaptured && !this.profileCaptured) {
          this.profileCaptured = true
          this.stack.pop()
        }
      }
    } catch (error) {
      DiagnosticLogger.warn('auth', 'user_profile_dom_capture_failed', (error as Error).message)
    }
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Center }) {
        // The scaffold's first row insets past the status bar + title bar; the Web (full-bleed ListItem,
        // height 100%) scrolls UNDER the immersive title bar as nestedScroll feeds the List (V2Next pattern).
        SecondaryListScaffold({
          scroller: this.scroller,
          horizontalPadding: 0,
          bottomPadding: 0,
          listSpace: 0,
        }) {
          ListItem() {
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
                this.updateNavState()
                this.syncLoadedCookies()
              },
              onErrorReceive: () => {
                this.loading = false
              },
              onTitleReceive: (event?: OnTitleReceiveEvent) => {
                if (event !== undefined && event.title.length > 0) {
                  this.pageTitle = event.title
                }
              },
            })
          }
          .height('100%')
          .clip(false)
        }

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
    .titleBar(this.titleBarOpts())
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
