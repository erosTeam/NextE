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
  WebLoginStyleState,
  AppStrings,
  DiagnosticLogger,
  UserProfileService,
  connectWebLoginStyle,
  immersiveTitleBarOpts,
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
  @Local webLoginStyle: WebLoginStyleState = connectWebLoginStyle();
  @Local runtimeBeautifyEnabled: boolean = true;
  private captured: boolean = false;
  private profileCaptureStarted: boolean = false;
  private finished: boolean = false;

  aboutToAppear(): void {
    this.runtimeBeautifyEnabled = this.webLoginStyle.beautifyEnabled
  }

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
              // Start from a clean EH identity without deleting Cloudflare's challenge cookies. Clearing
              // the whole WebView jar forces a fresh Turnstile challenge and can strand ArkWeb in CF's
              // verification loop before the forum login form is even reachable.
              this.expireWebLoginIdentityCookies()
              this.controller.loadUrl(EhConstants.FORUMS_LOGIN_FORM_URL)
            },
            onPageBegin: () => {
              this.loading = true
            },
            onPageEnd: () => {
              this.loading = false
              if (this.profileCaptureStarted) {
                this.finishLoginWithProfile()
                return
              }
              if (this.runtimeBeautifyEnabled) {
                this.restyleLoginForm()
              }
              this.tryCapture()
            },
            onErrorReceive: () => {
              this.loading = false
              if (this.profileCaptureStarted) {
                this.finishLogin()
              }
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
    .titleBar(this.loginTitleBar())
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }

  private loginTitleBar(): Record<string, Object> {
    const item: Record<string, Object> = {
      'label': AppStrings.get(
        this.runtimeBeautifyEnabled ? 'web_login_use_original' : 'web_login_use_beautified',
      ),
      'icon': $r('sys.symbol.paintbrush'),
      'isEnabled': true,
      'action': (): void => {
        this.toggleRuntimeLoginStyle()
      },
    }
    const itemWrap: Record<string, Object> = { 'content': item }
    const menu: Record<string, Object> = { 'value': [itemWrap], 'maxCount': 1 }
    const title: Record<string, Object> = { 'mainTitle': AppStrings.get('nav_login') }
    const content: Record<string, Object> = { 'title': title, 'menu': menu }
    return immersiveTitleBarOpts(content)
  }

  private toggleRuntimeLoginStyle(): void {
    this.runtimeBeautifyEnabled = !this.runtimeBeautifyEnabled
    if (this.runtimeBeautifyEnabled) {
      this.restyleLoginForm()
      return
    }
    try {
      this.controller.loadUrl(EhConstants.FORUMS_LOGIN_FORM_URL)
    } catch (e) {
      DiagnosticLogger.warn('auth', 'web_login_reload_raw_failed', (e as Error).message)
    }
  }

  // The EH forums login is a fixed-width desktop IPB table buried in forum chrome that ArkWeb shrinks
  // to fit — tiny inputs, lots of noise. Reshape it into a clean, app-styled card: keep only the real
  // <form> (so submission + hidden auth fields stay intact), drop the forum header/footer/notice, and
  // restyle the inputs/button with the app's accent. Guarded on the password input so it ONLY runs on
  // the login form page, never the Cloudflare challenge page (which has no such input).
  private restyleLoginForm(): void {
    const accent: string = ThemeColorSettings.currentColor() as string
    // Localized labels (JSON-encoded so they inject as safe JS string literals regardless of content).
    const sUser: string = JSON.stringify(AppStrings.get('password_login_username'))
    const sPass: string = JSON.stringify(AppStrings.get('password_login_password'))
    const sSubmit: string = JSON.stringify(AppStrings.get('password_login_submit'))
    const sHint: string = JSON.stringify(AppStrings.get('web_login_hint'))
    const sCaptcha: string = JSON.stringify(AppStrings.get('web_login_captcha'))
    const js: string = `(function(){
      var pw=document.querySelector('input[type=password]'); if(!pw) return;
      var form=pw.closest('form'); if(!form) return;
      if(document.getElementById('nexte-login-style')) return;
      var user=form.querySelector('input[type=text]');
      var submit=form.querySelector('input[type=submit],button[type=submit]');
      var capKey='captcha|verify|verification|security|challenge|code';
      var capSel='.g-recaptcha,.cf-turnstile,[data-sitekey],iframe[src*=recaptcha],iframe[src*=captcha],iframe[src*="challenges.cloudflare.com"],iframe[src*=turnstile],img[src*=captcha],img[src*=verify],img[src*=code]';
      var capResponseSel='textarea[name=g-recaptcha-response],input[name=cf-turnstile-response],textarea[name=cf-turnstile-response],input[name*=captcha],textarea[name*=captcha],input[id*=captcha],textarea[id*=captcha]';
      function safeQuery(n, sel){ try { return n && n.querySelector ? n.querySelector(sel) : null; } catch(_e) { return null; } }
      function safeQueryAll(n, sel){ try { return n && n.querySelectorAll ? Array.prototype.slice.call(n.querySelectorAll(sel)) : []; } catch(_e) { return []; } }
      function safeMatches(n, sel){ try { return !!(n && n.matches && n.matches(sel)); } catch(_e) { return false; } }
      function nodeMeta(n){
        if(!n) return '';
        return String((n.getAttribute && (n.getAttribute('name') || n.getAttribute('id') || n.getAttribute('class') || n.getAttribute('src') || n.getAttribute('alt') || n.getAttribute('placeholder'))) || '').toLowerCase();
      }
      function looksCaptcha(n){ return new RegExp(capKey,'i').test(nodeMeta(n)); }
      function visibleNode(n){
        if(!n || !n.getBoundingClientRect) return false;
        var st=window.getComputedStyle ? window.getComputedStyle(n) : null;
        if(st && (st.display==='none' || st.visibility==='hidden' || st.opacity==='0')) return false;
        var r=n.getBoundingClientRect();
        return r.width>=20 && r.height>=20;
      }
      function visibleCaptcha(n){
        if(!visibleNode(n)) return false;
        var frame=(String(n.tagName || '').toLowerCase()==='iframe') ? n : safeQuery(n,'iframe');
        if(frame && !visibleNode(frame)) return false;
        return true;
      }
      function collapseCaptcha(){
        cw.className='nx-cap nx-cap-empty';
        cw.style.display='none';
      }
      function captchaNode(n){
        if(!n) return null;
        if(safeMatches(n,capSel)) return n;
        return safeQuery(n,capSel);
      }
      function holdsCaptcha(n){ return !!(captchaNode(n) || safeQuery(n,capResponseSel)); }
      function isTextLikeInput(n){
        var tag=String(n && n.tagName || '').toLowerCase();
        var type=String((n && n.getAttribute && n.getAttribute('type')) || 'text').toLowerCase();
        return tag==='textarea' || tag==='select' || (tag==='input' && /^(text|tel|number|search|url|email)?$/.test(type));
      }
      function isSubmitControl(n){
        if(!n) return false;
        if(n===submit) return true;
        var type=String((n.getAttribute && n.getAttribute('type')) || '').toLowerCase();
        return /^(submit|button|reset|image)$/.test(type);
      }
      function captchaInputs(){
        var out=[];
        safeQueryAll(form,'input,textarea,select').forEach(function(n){
          if(n===user || n===pw || isSubmitControl(n)) return;
          var type=String((n.getAttribute && n.getAttribute('type')) || '').toLowerCase();
          if(type==='hidden') return;
          if(looksCaptcha(n) || isTextLikeInput(n)) out.push(n);
        });
        return out;
      }
      function captchaMedia(){
        var out=[];
        safeQueryAll(form,'img,iframe,canvas').forEach(function(n){
          if(safeMatches(n,capSel) || looksCaptcha(n)) out.push(n);
        });
        safeQueryAll(document,capSel).forEach(function(n){
          if(form.contains(n) && out.indexOf(n)<0) out.push(n);
        });
        return out;
      }
      function cleanText(v){ return (v||'').replace(/\\s+/g,' ').trim(); }
      function visibleText(n){ return cleanText(n && n.textContent ? n.textContent : ''); }
      function addNoticeText(out, text){
        var t=cleanText(text); if(!t || t.length<4) return;
        if(t.indexOf(${sHint})>=0) return;
        if(out.indexOf(t)>=0) return;
        out.push(t);
      }
      function loginNotice(){
        var out=[];
        Array.prototype.forEach.call(document.querySelectorAll('.message,.error,.warning,.ipsMessage,.row1,.row2,td,p,div'), function(n){
          if(out.length>=3) return;
          if(n.querySelector && n.querySelector('input,button,iframe,script,style')) return;
          var t=visibleText(n);
          if(/(incorrect|invalid|failed|failure|must enter|please enter|required|captcha|verify|verification|security|验证码|验证|错误|失败|请输入|必须)/i.test(t)){
            addNoticeText(out,t);
          }
        });
        return out.join('\\n').substring(0,420);
      }
      var noticeText=loginNotice();
      var mv=document.querySelector('meta[name=viewport]');
      if(!mv){mv=document.createElement('meta');mv.name='viewport';document.getElementsByTagName('head')[0].appendChild(mv);}
      mv.setAttribute('content','width=device-width, initial-scale=1');
      document.body.insertBefore(form, document.body.firstChild);
      Array.prototype.forEach.call(document.body.children, function(c){ if(c!==form){ c.style.display='none'; } });
      // Build a clean card and move the REAL inputs into it (they stay inside the form so submission
      // and hidden auth fields still work). Everything else (titles, notice, options) is hidden.
      var box=document.createElement('div'); box.id='nx-box';
      form.insertBefore(box, form.firstChild);
      var hint=document.createElement('div');hint.className='nx-hint';hint.textContent=${sHint};box.appendChild(hint);
      if(noticeText){
        var notice=document.createElement('div');notice.className='nx-notice';notice.textContent=noticeText;box.appendChild(notice);
      }
      function field(inp){var w=document.createElement('div');w.className='nx-field';w.appendChild(inp);box.appendChild(w);return w;}
      if(user){user.setAttribute('placeholder',${sUser});field(user);}
      pw.setAttribute('placeholder',${sPass});
      var EYE_ON='<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M1 12s4-7 11-7 11 7 11 7-4 7-11 7-11-7-11-7z"/><circle cx="12" cy="12" r="3"/></svg>';
      var EYE_OFF='<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17.94 17.94A10 10 0 0 1 12 20C5 20 1 12 1 12a18.5 18.5 0 0 1 5.06-5.94M9.9 4.24A9 9 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19"/><line x1="3" y1="3" x2="21" y2="21"/></svg>';
      var pwWrap=document.createElement('div');pwWrap.className='nx-field nx-pw';pwWrap.appendChild(pw);
      var eye=document.createElement('span');eye.className='nx-eye';eye.innerHTML=EYE_OFF;
      eye.onclick=function(){var h=pw.getAttribute('type')==='password';pw.setAttribute('type',h?'text':'password');eye.innerHTML=h?EYE_ON:EYE_OFF;};
      pwWrap.appendChild(eye);box.appendChild(pwWrap);
      var cw=document.createElement('div');cw.className='nx-cap nx-cap-empty';box.appendChild(cw);
      function moveCaptchaPart(n){
        if(!n || n===cw || n===box || n===user || n===pw || isSubmitControl(n)) return false;
        if(cw.contains(n)) return true;
        if(n.parentNode){ cw.appendChild(n); }
        n.removeAttribute && n.removeAttribute('style');
        n.classList && isTextLikeInput(n) && n.classList.add('nx-captcha-input');
        if(isTextLikeInput(n) && !n.getAttribute('placeholder')) n.setAttribute('placeholder',${sCaptcha});
        n.style.display='';
        return true;
      }
      function updateCaptcha(){
        var moved=false;
        var cap=captchaNode(document);
        if(cap && cap!==cw && cap!==box){
          var holder=null;
          try { holder=cap.closest ? cap.closest('.g-recaptcha,.cf-turnstile,[data-sitekey]') : null; } catch(_e) { holder=null; }
          var node=(holder && holder!==box && holder!==cw && !safeQuery(holder,'input[type=text],input[type=password]')) ? holder : cap;
          moved=moveCaptchaPart(node) || moved;
        }
        captchaMedia().forEach(function(n){ moved=moveCaptchaPart(n) || moved; });
        captchaInputs().forEach(function(n){ moved=moveCaptchaPart(n) || moved; });
        if(!moved){
          collapseCaptcha();
          return;
        }
        cw.style.display='flex';
        cw.className='nx-cap';
      }
      updateCaptcha();
      setTimeout(updateCaptcha, 300);
      setTimeout(updateCaptcha, 1200);
      setTimeout(updateCaptcha, 2500);
      if(window.nxLoginCaptchaObserver){window.nxLoginCaptchaObserver.disconnect();}
      window.nxLoginCaptchaObserver=new MutationObserver(function(){ updateCaptcha(); });
      window.nxLoginCaptchaObserver.observe(document.body,{childList:true,subtree:true});
      if(submit){
        submit.removeAttribute('style');
        submit.className='nx-submit';
        if(submit.tagName==='INPUT'){submit.value=${sSubmit};}else{submit.textContent=${sSubmit};}
        box.appendChild(submit);
      }
      // Hide the remaining forum chrome, but NEVER a node that still holds a captcha/iframe.
      Array.prototype.forEach.call(form.children, function(c){
        if(c===box) return;
        if(holdsCaptcha(c)) return;
        c.style.display='none';
      });
      var s=document.createElement('style'); s.id='nexte-login-style';
      s.textContent=[
        "html,body{background:#F1F3F5!important;margin:0!important;padding:0!important;font-family:-apple-system,'HarmonyOS Sans',sans-serif!important;-webkit-text-size-adjust:100%!important;}",
        "form{display:block!important;height:auto!important;min-height:0!important;margin:0!important;padding:0!important;}",
        "#nx-box{margin:0 auto!important;padding:16px!important;display:block!important;height:auto!important;min-height:0!important;}",
        "#nx-box .nx-hint{font-size:14px!important;color:#8A8F99!important;padding:2px 6px 18px!important;line-height:1.5!important;}",
        "#nx-box .nx-notice{font-size:14px!important;color:#B42318!important;background:#FFF1F0!important;border-radius:14px!important;padding:10px 12px!important;margin:0 0 16px!important;line-height:1.45!important;white-space:pre-wrap!important;}",
        "#nx-box .nx-field{margin:0 0 16px!important;}",
        "#nx-box input[type=text],#nx-box input[type=password]{font-size:16px!important;width:100%!important;height:48px!important;box-sizing:border-box!important;padding:0 18px!important;border:none!important;border-radius:19px!important;background:#fff!important;color:#1A1A1A!important;outline:none!important;-webkit-appearance:none!important;}",
        "#nx-box input::placeholder{color:#9AA0A8!important;}",
        "#nx-box .nx-pw{position:relative!important;}",
        "#nx-box .nx-pw input{padding-right:52px!important;}",
        "#nx-box .nx-eye{position:absolute!important;right:14px!important;top:0!important;height:48px!important;display:flex!important;align-items:center!important;color:#9AA0A8!important;cursor:pointer!important;}",
        "#nx-box .nx-cap{display:flex!important;flex-direction:column!important;align-items:stretch!important;gap:10px!important;margin:0 0 16px!important;min-height:0!important;overflow:visible!important;}",
        "#nx-box .nx-cap:empty,#nx-box .nx-cap.nx-cap-empty{display:none!important;margin:0!important;}",
        "#nx-box .nx-cap iframe,#nx-box .nx-cap img,#nx-box .nx-cap canvas{max-width:100%!important;align-self:center!important;}",
        "#nx-box .nx-cap input,#nx-box .nx-cap textarea,#nx-box .nx-captcha-input{font-size:16px!important;width:100%!important;height:48px!important;box-sizing:border-box!important;padding:0 18px!important;border:none!important;border-radius:19px!important;background:#fff!important;color:#1A1A1A!important;outline:none!important;-webkit-appearance:none!important;}",
        "#nx-box input[type=submit],#nx-box button[type=submit],#nx-box .nx-submit{position:static!important;display:block!important;left:auto!important;right:auto!important;top:auto!important;bottom:auto!important;transform:none!important;float:none!important;font-size:16px!important;font-weight:500!important;width:100%!important;height:48px!important;min-height:48px!important;padding:0!important;border-radius:999px!important;background:${accent}!important;color:#fff!important;border:none!important;margin:4px 0 0!important;-webkit-appearance:none!important;}"
      ].join('');
      document.getElementsByTagName('head')[0].appendChild(s);
    })()`
    try {
      this.controller.runJavaScript(js)
    } catch (e) {
      DiagnosticLogger.warn('auth', 'restyle_login_failed', (e as Error).message)
    }
  }

  private expireWebLoginIdentityCookies(): void {
    const authNames: string[] = [
      EhConstants.COOKIE_MEMBER_ID,
      EhConstants.COOKIE_PASS_HASH,
      EhConstants.COOKIE_IGNEOUS,
      EhConstants.COOKIE_SK,
      EhConstants.COOKIE_STAR,
    ]
    const targets: string[][] = [
      [EhConstants.EH_BASE_URL, '; Domain=.e-hentai.org'],
      [EhConstants.FORUMS_BASE_URL, '; Domain=.e-hentai.org'],
      [EhConstants.FORUMS_BASE_URL, ''],
      [EhConstants.EX_BASE_URL, '; Domain=.exhentai.org'],
      [EhConstants.EX_BASE_URL, ''],
    ]
    for (const name of authNames) {
      for (const target of targets) {
        try {
          webview.WebCookieManager.configCookieSync(
            target[0],
            `${name}=; Path=/${target[1]}; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT`,
            false,
            true,
          )
        } catch (e) {
          DiagnosticLogger.warn('auth', 'web_login_expire_cookie_failed', (e as Error).message)
        }
      }
    }
    try {
      webview.WebCookieManager.saveCookieSync()
    } catch (_e) {
      webview.WebCookieManager.saveCookieAsync()
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
    const ehCookie: string = await this.fetchWebCookie(EhConstants.EH_BASE_URL, 'eh')
    const exCookie: string = await this.fetchWebCookie(EhConstants.EX_BASE_URL, 'ex')
    const forumCookie: string = await this.fetchWebCookie(EhConstants.FORUMS_BASE_URL, 'forums')
    const header: string = `${ehCookie}; ${exCookie}; ${forumCookie}`
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
    this.refreshIgneousAfterLogin(ctx)
    this.profileCaptureStarted = true
    this.loading = true
    try {
      this.controller.loadUrl(UserProfileService.activeProfileUrl())
    } catch (e) {
      DiagnosticLogger.warn('auth', 'web_login_profile_load_failed', (e as Error).message)
      this.finishLogin()
    }
  }

  private async fetchWebCookie(url: string, hostLabel: string): Promise<string> {
    try {
      return await webview.WebCookieManager.fetchCookie(url)
    } catch (e) {
      DiagnosticLogger.warn(
        'auth',
        'web_login_fetch_cookie_failed',
        `host=${hostLabel} ${(e as Error).message}`,
      )
      return ''
    }
  }

  private refreshIgneousAfterLogin(ctx: common.UIAbilityContext): void {
    CookieJarSettings.refreshIgneous(ctx).then((unlocked: boolean) => {
      DiagnosticLogger.info('auth', 'web_login_igneous_refresh_done', `unlocked=${unlocked}`)
    })
  }

  private async finishLoginWithProfile(): Promise<void> {
    try {
      const payload: string = await this.controller.runJavaScript(UserProfileService.profileDomCaptureScript())
      if (UserProfileService.applyProfileDomPayload(payload)) {
        const ctx: common.UIAbilityContext =
          this.getUIContext().getHostContext() as common.UIAbilityContext
        UserProfileService.materializeAvatar(ctx)
        await UserProfileService.saveActive(ctx)
      }
    } catch (e) {
      DiagnosticLogger.warn('auth', 'web_login_profile_capture_failed', (e as Error).message)
    }
    this.finishLogin()
  }

  private finishLogin(): void {
    if (this.finished) {
      return
    }
    this.finished = true
    promptAction.showToast({ message: $r('app.string.login_success') })
    this.stack.pop()
  }
}
