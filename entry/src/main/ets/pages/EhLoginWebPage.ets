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
  ThemeColorSettings,
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
              this.restyleLoginForm()
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

  // The EH forums login is a fixed-width desktop IPB table buried in forum chrome that ArkWeb shrinks
  // to fit — tiny inputs, lots of noise. Reshape it into a clean, app-styled card: keep only the real
  // <form> (so submission + hidden auth fields stay intact), drop the forum header/footer/notice, and
  // restyle the inputs/button with the app's accent. Guarded on the password input so it ONLY runs on
  // the login form page, never the Cloudflare challenge page (which has no such input).
  private restyleLoginForm(): void {
    const accent: string = ThemeColorSettings.currentColor() as string
    const js: string = `(function(){
      var pw=document.querySelector('input[type=password]'); if(!pw) return;
      var form=pw.closest('form'); if(!form) return;
      if(document.getElementById('nexte-login-style')) return;
      var user=form.querySelector('input[type=text]');
      var submit=form.querySelector('input[type=submit],button[type=submit]');
      var capSel='.g-recaptcha,[data-sitekey],iframe[src*=recaptcha],iframe[src*=captcha],[class*=captcha],[class*=recaptcha],[id*=captcha]';
      var cap=form.querySelector(capSel);
      var mv=document.querySelector('meta[name=viewport]');
      if(!mv){mv=document.createElement('meta');mv.name='viewport';document.getElementsByTagName('head')[0].appendChild(mv);}
      mv.setAttribute('content','width=device-width, initial-scale=1');
      document.body.insertBefore(form, document.body.firstChild);
      Array.prototype.forEach.call(document.body.children, function(c){ if(c!==form){ c.style.display='none'; } });
      // Build a clean card and move the REAL inputs into it (they stay inside the form so submission
      // and hidden auth fields still work). Everything else (titles, notice, options) is hidden.
      var box=document.createElement('div'); box.id='nx-box';
      form.insertBefore(box, form.firstChild);
      var hint=document.createElement('div');hint.className='nx-hint';hint.textContent='使用 E-Hentai 论坛账号登录';box.appendChild(hint);
      function field(inp){var w=document.createElement('div');w.className='nx-field';w.appendChild(inp);box.appendChild(w);return w;}
      if(user){user.setAttribute('placeholder','用户名');field(user);}
      pw.setAttribute('placeholder','密码');
      var EYE_ON='<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M1 12s4-7 11-7 11 7 11 7-4 7-11 7-11-7-11-7z"/><circle cx="12" cy="12" r="3"/></svg>';
      var EYE_OFF='<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17.94 17.94A10 10 0 0 1 12 20C5 20 1 12 1 12a18.5 18.5 0 0 1 5.06-5.94M9.9 4.24A9 9 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19"/><line x1="3" y1="3" x2="21" y2="21"/></svg>';
      var pwWrap=document.createElement('div');pwWrap.className='nx-field nx-pw';pwWrap.appendChild(pw);
      var eye=document.createElement('span');eye.className='nx-eye';eye.innerHTML=EYE_OFF;
      eye.onclick=function(){var h=pw.getAttribute('type')==='password';pw.setAttribute('type',h?'text':'password');eye.innerHTML=h?EYE_ON:EYE_OFF;};
      pwWrap.appendChild(eye);box.appendChild(pwWrap);
      if(cap){var cw=document.createElement('div');cw.className='nx-cap';cw.appendChild(cap);box.appendChild(cw);}
      if(submit){ if(submit.tagName==='INPUT'){submit.value='登录';}else{submit.textContent='登录';} box.appendChild(submit); }
      // Hide the remaining forum chrome, but NEVER a node that still holds a captcha/iframe.
      Array.prototype.forEach.call(form.children, function(c){
        if(c===box) return;
        if(c.querySelector && c.querySelector('iframe,[class*=captcha],[class*=recaptcha],[data-sitekey],textarea[name=g-recaptcha-response]')) return;
        c.style.display='none';
      });
      var s=document.createElement('style'); s.id='nexte-login-style';
      s.textContent=[
        "html,body{background:#F1F3F5!important;margin:0!important;padding:0!important;font-family:-apple-system,'HarmonyOS Sans',sans-serif!important;-webkit-text-size-adjust:100%!important;}",
        "#nx-box{margin:0 auto!important;padding:16px!important;display:block!important;}",
        "#nx-box .nx-hint{font-size:14px!important;color:#8A8F99!important;padding:2px 6px 18px!important;line-height:1.5!important;}",
        "#nx-box .nx-field{margin:0 0 16px!important;}",
        "#nx-box input[type=text],#nx-box input[type=password]{font-size:16px!important;width:100%!important;height:48px!important;box-sizing:border-box!important;padding:0 18px!important;border:none!important;border-radius:19px!important;background:#fff!important;color:#1A1A1A!important;outline:none!important;-webkit-appearance:none!important;}",
        "#nx-box input::placeholder{color:#9AA0A8!important;}",
        "#nx-box .nx-pw{position:relative!important;}",
        "#nx-box .nx-pw input{padding-right:52px!important;}",
        "#nx-box .nx-eye{position:absolute!important;right:14px!important;top:0!important;height:48px!important;display:flex!important;align-items:center!important;color:#9AA0A8!important;cursor:pointer!important;}",
        "#nx-box .nx-cap{display:flex!important;justify-content:center!important;margin:0 0 16px!important;}",
        "#nx-box input[type=submit],#nx-box button[type=submit]{font-size:16px!important;font-weight:500!important;width:100%!important;height:48px!important;padding:0!important;border-radius:999px!important;background:${accent}!important;color:#fff!important;border:none!important;margin-top:4px!important;-webkit-appearance:none!important;}"
      ].join('');
      document.getElementsByTagName('head')[0].appendChild(s);
    })()`
    try {
      this.controller.runJavaScript(js)
    } catch (e) {
      DiagnosticLogger.warn('auth', 'restyle_login_failed', (e as Error).message)
    }
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
