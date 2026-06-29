import { HdsNavDestination } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import { KeyboardAvoidMode } from '@kit.ArkUI'
import {
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
 * Manual Cookie login/import — the safe fallback to the in-app WebView login (EhLoginWebPage),
 * for users who already hold an EH session (donor account, another device) and want to paste the
 * cookie header rather than re-typing their password into a Web form. The user pastes a
 * "name=value; …" Cookie string; we validate the two identity cookies (ipb_member_id +
 * ipb_pass_hash) are present, then hand the WHOLE string to CookieJarSettings.applyFromHeader so
 * unknown donor/permission cookies are preserved (never whitelist-dropped), persist via
 * CookieJarSettings.save (which refreshes AuthState), and pop. The pasted text is sensitive: it
 * lives only in this component's in-memory @Local and the cookie jar — never logged, never
 * persisted elsewhere. Logs carry only redacted facts (cookie counts / presence booleans).
 */
@ComponentV2
export struct EhCookieImportPage {
  private stack: NavPathStack = connectNavStack().stack;
  private layout: LayoutSafeAreaState = connectLayoutSafeArea();
  @Local cookieText: string = '';
  @Local submitting: boolean = false;

  aboutToAppear(): void {
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE)
  }

  aboutToDisappear(): void {
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.OFFSET)
  }

  build() {
    HdsNavDestination() {
      Scroll() {
        Column({ space: ThemeConstants.SPACE_LG }) {
          Text($r('app.string.cookie_import_hint'))
            .fontSize(ThemeConstants.FONT_SIZE_BODY)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
          TextArea({
            text: this.cookieText,
            placeholder: $r('app.string.cookie_import_placeholder'),
          })
            .width('100%')
            .height(160)
            .fontSize(ThemeConstants.FONT_SIZE_BODY)
            .backgroundColor($r('sys.color.ohos_id_color_card_bg'))
            .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
            .enabled(!this.submitting)
            .onChange((value: string) => {
              this.cookieText = value
            })
          Button($r('app.string.cookie_import_submit'))
            .width('100%')
            .fontColor(ThemeConstants.TEXT_ON_BRAND)
            .backgroundColor(ThemeConstants.BRAND_PRIMARY)
            .enabled(!this.submitting && this.cookieText.trim().length > 0)
            .onClick(() => {
              this.submit()
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(ThemeConstants.SPACE_LG)
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      // Content sits below the immersive HDS title bar (which scrolls over content otherwise).
      .padding({ top: this.layout.topAvoidHeight + ThemeConstants.TITLE_BAR_HEIGHT })
    }
    .titleBar(immersiveTitleBar($r('app.string.cookie_import_title')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }

  // How many real cookies the pasted header carries (name=value, non-empty value, excluding nw).
  // Used only for a REDACTED diagnostic — never logs the names or values themselves.
  private cookieCount(header: string): number {
    let count: number = 0
    const pairs: string[] = header.split(';')
    for (const pair of pairs) {
      const trimmed: string = pair.trim()
      const eq: number = trimmed.indexOf('=')
      if (eq <= 0) {
        continue
      }
      const name: string = trimmed.substring(0, eq).trim()
      const value: string = trimmed.substring(eq + 1).trim()
      if (name.length > 0 && name !== EhConstants.COOKIE_NW && value.length > 0) {
        count++
      }
    }
    return count
  }

  private async submit(): Promise<void> {
    if (this.submitting) {
      return
    }
    const header: string = this.cookieText.trim()
    // Validate identity WITHOUT mutating the live jar, so an invalid paste never half-applies.
    const memberId: string = CookieJarSettings.parseCookieValue(
      header,
      EhConstants.COOKIE_MEMBER_ID,
    )
    const passHash: string = CookieJarSettings.parseCookieValue(
      header,
      EhConstants.COOKIE_PASS_HASH,
    )
    if (memberId.length === 0 || passHash.length === 0) {
      // Redacted: presence booleans only, never the pasted values.
      DiagnosticLogger.warn(
        'auth',
        'cookie_import_invalid',
        `member=${memberId.length > 0} hash=${passHash.length > 0}`,
      )
      this.getUIContext()
        .getPromptAction()
        .showToast({ message: $r('app.string.cookie_import_invalid') })
      return
    }
    this.submitting = true
    // Replace the jar with exactly this pasted account (clear first), preserving its complete cookie set
    // (donor/permission cookies kept, not dropped). Clearing first means importing a second account never
    // inherits the previous account's igneous/sk.
    CookieJarSettings.replaceFromHeader(header)
    DiagnosticLogger.info('auth', 'cookie_import_applied', `cookies=${this.cookieCount(header)}`)
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext
    // save() persists the jar AND refreshes AuthState (isLogin / hasIgneous / memberId) for the UI.
    await CookieJarSettings.save(ctx)
    this.getUIContext()
      .getPromptAction()
      .showToast({ message: $r('app.string.login_success') })
    this.stack.pop()
  }
}
