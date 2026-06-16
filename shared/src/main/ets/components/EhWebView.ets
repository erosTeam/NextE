import { webview } from '@kit.ArkWeb'

/**
 * Thin native Web wrapper (HarmonyOS @kit.ArkWeb), mirroring V2Next's V2exWebView. Hosts the
 * EH forums login page so the user signs in with EH's own form; the host page captures the
 * resulting cookies via WebCookieManager. JS + DOM storage are on (EH's login needs them);
 * darkMode is Off so EH's own page styling isn't double-inverted.
 */
@ComponentV2
export struct EhWebView {
  @Param controller: webview.WebviewController = new webview.WebviewController()
  @Event onControllerAttached?: () => void
  @Event onPageBegin?: (event?: OnPageBeginEvent) => void
  @Event onPageEnd?: (event?: OnPageEndEvent) => void
  @Event onErrorReceive?: (event: OnErrorReceiveEvent) => void

  build() {
    Web({ src: '', controller: this.controller })
      .darkMode(WebDarkMode.Off)
      .backgroundColor(Color.White)
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .onlineImageAccess(true)
      .width('100%')
      .height('100%')
      .onControllerAttached(() => {
        if (this.onControllerAttached) {
          this.onControllerAttached()
        }
      })
      .onPageBegin((event: OnPageBeginEvent) => {
        if (this.onPageBegin) {
          this.onPageBegin(event)
        }
      })
      .onPageEnd((event: OnPageEndEvent) => {
        if (this.onPageEnd) {
          this.onPageEnd(event)
        }
      })
      .onErrorReceive((event: OnErrorReceiveEvent) => {
        if (this.onErrorReceive) {
          this.onErrorReceive(event)
        }
      })
  }
}
