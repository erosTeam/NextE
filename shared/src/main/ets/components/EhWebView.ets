import { webview } from '@kit.ArkWeb'

/**
 * Generic native Web wrapper (HarmonyOS @kit.ArkWeb), ported from V2Next's V2exWebView. Used by both the
 * EH-forums login page (host captures the resulting cookies via WebCookieManager) and the generic in-app
 * gallery WebView. JS + DOM storage are on (EH's login needs them); darkMode is Off so EH's own page styling
 * isn't double-inverted; overScroll is off to kill the bounce/glow; nestedScroll defers to a scrollable
 * parent first when there is one (harmless in a plain Column). Title/load callbacks let the host show the
 * live page title and react to load completion. Kept parent-agnostic (no ListItem wrap) so it drops into a
 * Column or a List alike.
 */
@ComponentV2
export struct EhWebView {
  @Param controller: webview.WebviewController = new webview.WebviewController();
  @Event onControllerAttached?: () => void;
  @Event onPageBegin?: (event?: OnPageBeginEvent) => void;
  @Event onPageEnd?: (event?: OnPageEndEvent) => void;
  @Event onLoadFinished?: (event?: OnLoadFinishedEvent) => void;
  @Event onErrorReceive?: (event: OnErrorReceiveEvent) => void;
  @Event onTitleReceive?: (event?: OnTitleReceiveEvent) => void;

  build() {
    Web({ src: '', controller: this.controller })
      .nestedScroll({
        scrollUp: NestedScrollMode.PARENT_FIRST,
        scrollDown: NestedScrollMode.PARENT_FIRST,
      })
      .overScrollMode(OverScrollMode.NEVER)
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
      .onLoadFinished((event: OnLoadFinishedEvent) => {
        if (this.onLoadFinished) {
          this.onLoadFinished(event)
        }
      })
      .onErrorReceive((event: OnErrorReceiveEvent) => {
        if (this.onErrorReceive) {
          this.onErrorReceive(event)
        }
      })
      .onTitleReceive((event: OnTitleReceiveEvent) => {
        if (this.onTitleReceive) {
          this.onTitleReceive(event)
        }
      })
  }
}
