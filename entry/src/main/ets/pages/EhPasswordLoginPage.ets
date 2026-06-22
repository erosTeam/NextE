import { HdsNavDestination } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import {
  CookieJarSettings,
  connectNavStack,
  connectLayoutSafeArea,
  LayoutSafeAreaState,
  ThemeConstants,
  immersiveTitleBar,
} from 'shared'

/**
 * In-app forums password login: username + password POSTed to the forums login (CookieJarSettings.
 * passwordLogin). forums.e-hentai.org is often Cloudflare-gated, so this can fail with a block — the hint
 * points users to the WebView login when it does. Credentials live only in this component's in-memory
 * @Local and are never logged or persisted.
 */
@ComponentV2
export struct EhPasswordLoginPage {
  private stack: NavPathStack = connectNavStack().stack;
  private layout: LayoutSafeAreaState = connectLayoutSafeArea();
  @Local username: string = '';
  @Local password: string = '';
  @Local submitting: boolean = false;

  build() {
    HdsNavDestination() {
      Scroll() {
        Column({ space: ThemeConstants.SPACE_LG }) {
          Text($r('app.string.password_login_hint'))
            .fontSize(ThemeConstants.FONT_SIZE_BODY)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
          TextInput({ text: this.username, placeholder: $r('app.string.password_login_username') })
            .width('100%')
            .height(48)
            .fontSize(ThemeConstants.FONT_SIZE_BODY)
            .backgroundColor($r('sys.color.ohos_id_color_card_bg'))
            .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
            .enabled(!this.submitting)
            .onChange((value: string) => {
              this.username = value
            })
          TextInput({ text: this.password, placeholder: $r('app.string.password_login_password') })
            .type(InputType.Password)
            .width('100%')
            .height(48)
            .fontSize(ThemeConstants.FONT_SIZE_BODY)
            .backgroundColor($r('sys.color.ohos_id_color_card_bg'))
            .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
            .enabled(!this.submitting)
            .onChange((value: string) => {
              this.password = value
            })
          Button($r('app.string.password_login_submit'))
            .width('100%')
            .enabled(
              !this.submitting && this.username.trim().length > 0 && this.password.length > 0,
            )
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
      .padding({ top: this.layout.topAvoidHeight + ThemeConstants.TITLE_BAR_HEIGHT })
    }
    .titleBar(immersiveTitleBar($r('app.string.password_login_title')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }

  private async submit(): Promise<void> {
    if (this.submitting) {
      return
    }
    this.submitting = true
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext
    const ok: boolean = await CookieJarSettings.passwordLogin(
      ctx,
      this.username.trim(),
      this.password,
    )
    this.submitting = false
    if (ok) {
      this.getUIContext()
        .getPromptAction()
        .showToast({ message: $r('app.string.login_success') })
      this.stack.pop()
    } else {
      this.getUIContext()
        .getPromptAction()
        .showToast({ message: $r('app.string.password_login_failed') })
    }
  }
}
