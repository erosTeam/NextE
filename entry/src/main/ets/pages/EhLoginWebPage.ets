import { webview } from '@kit.ArkWeb'
import { HdsNavDestination } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import { promptAction } from '@kit.ArkUI'
import {
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
  closeLoginFlowToAccount,
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
  private restyleInFlight: boolean = false;

  aboutToAppear(): void {
    this.runtimeBeautifyEnabled = this.webLoginStyle.beautifyEnabled
    CookieJarSettings.expireWebIdentityCookies()
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Center }) {
        Column() {
          Web({ src: EhConstants.FORUMS_LOGIN_FORM_URL, controller: this.controller })
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
            .onPageBegin(() => {
              this.loading = true
            })
            .onPageEnd(() => {
              this.loading = false
              if (this.profileCaptureStarted) {
                this.finishLoginWithProfile()
                return
              }
              if (this.runtimeBeautifyEnabled) {
                this.scheduleRestyleLoginForm()
              }
              this.tryCapture()
            })
            .onLoadFinished(() => {
              if (this.runtimeBeautifyEnabled && !this.profileCaptureStarted) {
                this.scheduleRestyleLoginForm()
              }
            })
            .onProgressChange((event: OnProgressChangeEvent) => {
              if (
                event.newProgress >= 70 &&
                this.runtimeBeautifyEnabled &&
                !this.profileCaptureStarted
              ) {
                this.scheduleRestyleLoginForm()
              }
            })
            .onErrorReceive(() => {
              this.loading = false
              if (this.profileCaptureStarted) {
                this.finishLogin()
              }
            })
            .onControllerAttached(() => {
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
              this.scheduleRestyleLoginForm()
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
      'icon': this.runtimeBeautifyEnabled ? $r('sys.symbol.eye_slash') : $r('sys.symbol.eye'),
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
      this.scheduleRestyleLoginForm()
      return
    }
    try {
      this.controller.loadUrl(EhConstants.FORUMS_LOGIN_FORM_URL)
    } catch (e) {
      DiagnosticLogger.warn('auth', 'web_login_reload_raw_failed', (e as Error).message)
    }
  }

  private scheduleRestyleLoginForm(): void {
    if (!this.runtimeBeautifyEnabled || this.profileCaptureStarted || this.finished) {
      return
    }
    this.restyleLoginForm()
    const delays: number[] = [500, 1500, 3000, 6000, 10000]
    for (const delay of delays) {
      setTimeout((): void => {
        if (this.runtimeBeautifyEnabled && !this.profileCaptureStarted && !this.finished) {
          this.restyleLoginForm()
        }
      }, delay)
    }
  }

  // The EH forums login is a fixed-width desktop IPB table buried in forum chrome that ArkWeb shrinks
  // to fit — tiny inputs, lots of noise. Keep the real forum DOM in place so Turnstile/captcha and
  // hidden auth fields keep working, then apply only mobile-friendly CSS to the visible login form.
  private restyleLoginForm(): void {
    if (this.restyleInFlight) {
      return
    }
    this.restyleInFlight = true
    const accent: string = ThemeColorSettings.currentColor() as string
    // Localized labels (JSON-encoded so they inject as safe JS string literals regardless of content).
    const sUser: string = JSON.stringify(AppStrings.get('password_login_username'))
    const sPass: string = JSON.stringify(AppStrings.get('password_login_password'))
    const sSubmit: string = JSON.stringify(AppStrings.get('password_login_submit'))
    const js: string = `(function nxRestyle(){
      try {
        var pw=document.querySelector('input[type=password]');
        if(!pw){
          var href=String((location && location.href) || '').substring(0,80);
          return 'waiting-password href=' + href;
        }
        var form=pw.closest ? pw.closest('form') : null;
        if(!form) return 'no-form';
        document.body.classList.add('nxe-login-page');
        form.classList.add('nxe-login-form');
        var user=form.querySelector('input[type=text]');
        var submit=form.querySelector('input[type=submit],button[type=submit]');
        function addClass(el, name){ if(el && el.classList) el.classList.add(name); }
        function closestBlock(el){ return el && el.closest ? (el.closest('tr') || el.closest('td') || el.parentElement) : null; }
        function markField(el, name){
          var block=closestBlock(el);
          addClass(block,'nxe-login-keep');
          addClass(block,name);
          if(block && block.parentElement) addClass(block.parentElement,'nxe-login-keep');
        }
        var pathNode=form;
        while(pathNode && pathNode !== document.body){
          addClass(pathNode,'nxe-login-shell');
          var parent=pathNode.parentElement;
          if(parent){
            addClass(parent,'nxe-login-shell-parent');
            var children=parent.children || [];
            for(var i=0;i<children.length;i++){
              if(children[i] !== pathNode && !(children[i].contains && children[i].contains(form))){
                addClass(children[i],'nxe-login-chrome');
              }
            }
          }
          pathNode=parent;
        }
        var mv=document.querySelector('meta[name=viewport]');
        if(!mv){mv=document.createElement('meta');mv.name='viewport';document.getElementsByTagName('head')[0].appendChild(mv);}
        mv.setAttribute('content','width=device-width, initial-scale=1');
        if(user) user.setAttribute('placeholder',${sUser});
        pw.setAttribute('placeholder',${sPass});
        if(submit){
          submit.removeAttribute('style');
          submit.className='nx-submit';
          if(submit.tagName==='INPUT'){submit.value=${sSubmit};}else{submit.textContent=${sSubmit};}
        }
        markField(user,'nxe-login-user-row');
        markField(pw,'nxe-login-pass-row');
        markField(submit,'nxe-login-submit-row');
        var passBlock=closestBlock(pw);
        if(passBlock && !document.getElementById('nxe-login-password-eye')){
          var eye=document.createElement('button');
          eye.id='nxe-login-password-eye';
          eye.type='button';
          eye.className='nxe-login-password-eye';
          eye.setAttribute('aria-label','Toggle password visibility');
          var eyeOn='<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12Z"/><circle cx="12" cy="12" r="3"/></svg>';
          var eyeOff='<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M17.94 17.94A10.94 10.94 0 0 1 12 20C6 20 2 12 2 12a20.15 20.15 0 0 1 5.06-5.94"/><path d="M9.9 4.24A10.76 10.76 0 0 1 12 4c6 0 10 8 10 8a18.4 18.4 0 0 1-2.16 3.19"/><path d="M14.12 14.12A3 3 0 0 1 9.88 9.88"/><path d="M3 3l18 18"/></svg>';
          eye.innerHTML=eyeOff;
          eye.onclick=function(){
            var show=pw.getAttribute('type')==='password';
            pw.setAttribute('type',show?'text':'password');
            eye.className=show?'nxe-login-password-eye nxe-login-password-eye-on':'nxe-login-password-eye';
            eye.innerHTML=show?eyeOn:eyeOff;
          };
          passBlock.appendChild(eye);
        }
        var optionInputs=form.querySelectorAll('input[type=checkbox],input[name*="remember"],input[name*="invisible"]');
        for(var o=0;o<optionInputs.length;o++){
          var optionBlock=closestBlock(optionInputs[o]);
          addClass(optionBlock,'nxe-login-noise');
          if(optionBlock && optionBlock.parentElement) addClass(optionBlock.parentElement,'nxe-login-noise');
        }
        var challengeNodes=form.querySelectorAll('iframe,canvas,img,.cf-turnstile,[data-sitekey],[name="cf-turnstile-response"]');
        for(var c=0;c<challengeNodes.length;c++){
          var challengeBlock=closestBlock(challengeNodes[c]);
          addClass(challengeBlock,'nxe-login-keep');
          addClass(challengeBlock,'nxe-login-captcha-row');
          if(challengeBlock && challengeBlock.parentElement) addClass(challengeBlock.parentElement,'nxe-login-keep');
        }
        var textNodes=form.querySelectorAll('tr,td,div,p,b,strong,span');
        for(var t=0;t<textNodes.length;t++){
          var node=textNodes[t];
          if(node.querySelector && node.querySelector('input,button,iframe,canvas,img,.cf-turnstile,[data-sitekey]')) continue;
          var text=(node.textContent || '').replace(/\\s+/g,' ').trim();
          if(text.indexOf('Log In') >= 0 || text === 'Options' || text === 'Please enter your details below to log in' || text === 'Enter your user name' || text === 'Enter your password' || text.indexOf('IF YOU DO NOT SEE THE CAPTCHA') >= 0 || text.indexOf('Remember me?') >= 0 || text.indexOf('Log in as invisible') >= 0 || text.indexOf('You must already have registered') >= 0 || text.indexOf("I've forgotten my password") >= 0 || text === 'Attention!'){
            addClass(node,'nxe-login-noise');
          }
        }
        var oldStyle=document.getElementById('nexte-login-style');
        if(oldStyle && oldStyle.parentElement) oldStyle.parentElement.removeChild(oldStyle);
        var s=document.createElement('style'); s.id='nexte-login-style';
        s.textContent=[
          "html,body{background:#F1F3F5!important;margin:0!important;padding:0!important;font-family:-apple-system,'HarmonyOS Sans',sans-serif!important;-webkit-text-size-adjust:100%!important;}",
          "body.nxe-login-page .nxe-login-chrome{display:none!important;}",
          "body.nxe-login-page form.nxe-login-form .maintitle,body.nxe-login-page form.nxe-login-form .pformstrip,body.nxe-login-page form.nxe-login-form .formsubtitle,body.nxe-login-page form.nxe-login-form legend,body.nxe-login-page form.nxe-login-form h1,body.nxe-login-page form.nxe-login-form h2,body.nxe-login-page form.nxe-login-form h3{display:none!important;visibility:hidden!important;height:0!important;min-height:0!important;margin:0!important;padding:0!important;overflow:hidden!important;}",
          "body.nxe-login-page .nxe-login-shell,body.nxe-login-page .nxe-login-shell-parent{display:block!important;width:100%!important;max-width:none!important;box-sizing:border-box!important;margin:0!important;padding:0!important;border:0!important;background:#F1F3F5!important;}",
          "body.nxe-login-page form.nxe-login-form{display:block!important;width:100%!important;max-width:none!important;box-sizing:border-box!important;margin:0!important;padding:18px 16px 24px!important;background:#F1F3F5!important;border:0!important;}",
          "body.nxe-login-page form.nxe-login-form table,body.nxe-login-page form.nxe-login-form tbody,body.nxe-login-page form.nxe-login-form tr,body.nxe-login-page form.nxe-login-form td{display:block!important;width:100%!important;max-width:none!important;box-sizing:border-box!important;border:0!important;background:transparent!important;margin:0!important;padding:0!important;text-align:left!important;}",
          "body.nxe-login-page form.nxe-login-form fieldset,body.nxe-login-page form.nxe-login-form .borderwrap,body.nxe-login-page form.nxe-login-form .tableborder{display:block!important;width:100%!important;max-width:none!important;box-sizing:border-box!important;border:0!important;background:transparent!important;margin:0!important;padding:0!important;}",
          "body.nxe-login-page form.nxe-login-form .nxe-login-user-row,body.nxe-login-page form.nxe-login-form .nxe-login-pass-row,body.nxe-login-page form.nxe-login-form .nxe-login-captcha-row,body.nxe-login-page form.nxe-login-form .nxe-login-submit-row{display:block!important;width:100%!important;box-sizing:border-box!important;margin:0!important;padding:0!important;}",
          "body.nxe-login-page form.nxe-login-form .nxe-login-pass-row{position:relative!important;}",
          "body.nxe-login-page form.nxe-login-form input[type=text],body.nxe-login-page form.nxe-login-form input[type=password],body.nxe-login-page form.nxe-login-form input[type=text][name*=Pass],body.nxe-login-page form.nxe-login-form .nxe-login-pass-row input{font-size:16px!important;width:100%!important;height:48px!important;box-sizing:border-box!important;padding:0 18px!important;border:none!important;border-radius:19px!important;background:#fff!important;color:#1A1A1A!important;outline:none!important;-webkit-appearance:none!important;margin:0 0 12px!important;}",
          "body.nxe-login-page form.nxe-login-form .nxe-login-pass-row input{padding-right:54px!important;}",
          "body.nxe-login-page form.nxe-login-form input::placeholder{color:#9AA0A8!important;}",
          "body.nxe-login-page form.nxe-login-form input[type=checkbox]{display:none!important;}",
          "body.nxe-login-page form.nxe-login-form .nxe-login-password-eye{position:absolute!important;right:14px!important;top:0!important;width:40px!important;height:48px!important;margin:0!important;padding:0!important;border:0!important;background:transparent!important;color:#9AA0A8!important;display:flex!important;align-items:center!important;justify-content:center!important;z-index:2!important;-webkit-appearance:none!important;}",
          "body.nxe-login-page form.nxe-login-form .nxe-login-password-eye svg{width:24px!important;height:24px!important;fill:none!important;stroke:currentColor!important;stroke-width:2!important;stroke-linecap:round!important;stroke-linejoin:round!important;}",
          "body.nxe-login-page form.nxe-login-form .nxe-login-password-eye-on{color:#1A1A1A!important;}",
          "body.nxe-login-page form.nxe-login-form .nxe-login-captcha-row{min-height:76px!important;margin:2px 0 10px!important;overflow:visible!important;}",
          "body.nxe-login-page form.nxe-login-form iframe,body.nxe-login-page form.nxe-login-form img,body.nxe-login-page form.nxe-login-form canvas{max-width:100%!important;visibility:visible!important;opacity:1!important;}",
          "body.nxe-login-page form.nxe-login-form input[type=submit],body.nxe-login-page form.nxe-login-form button[type=submit],body.nxe-login-page form.nxe-login-form .nx-submit{position:static!important;display:block!important;float:none!important;font-size:16px!important;font-weight:500!important;width:100%!important;height:48px!important;min-height:48px!important;padding:0!important;border-radius:999px!important;background:${accent}!important;color:#fff!important;border:none!important;margin:8px 0 0!important;-webkit-appearance:none!important;}",
          "body.nxe-login-page form.nxe-login-form br{display:none!important;}",
          "body.nxe-login-page .nxe-login-noise,body.nxe-login-page .nxe-login-form .nxe-login-noise{display:none!important;visibility:hidden!important;height:0!important;min-height:0!important;margin:0!important;padding:0!important;overflow:hidden!important;}"
        ].join('');
        document.getElementsByTagName('head')[0].appendChild(s);
        return 'styled';
      } catch(e) {
        return 'error:' + (e && e.message ? e.message : String(e));
      }
    })()`
    try {
      setTimeout((): void => {
        this.restyleInFlight = false
      }, 1500)
      this.controller.runJavaScript(js).then((result: string) => {
        this.restyleInFlight = false
        if (result.indexOf('error:') === 0) {
          DiagnosticLogger.warn('auth', 'restyle_login_failed', result)
        }
      }).catch((error: Error) => {
        this.restyleInFlight = false
        DiagnosticLogger.warn('auth', 'restyle_login_failed', error.message)
      })
    } catch (e) {
      this.restyleInFlight = false
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
    closeLoginFlowToAccount(this.stack)
  }
}
