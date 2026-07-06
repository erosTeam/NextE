import { HdsNavDestination } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import { KeyboardAvoidMode } from '@kit.ArkUI'
import {
  EhConstants,
  AppStrings,
  CookieJarSettings,
  CookieJarEntry,
  ConciseListRow,
  GroupedListSection,
  closeLoginFlowToAccount,
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
 * ipb_pass_hash) are present, then replace the jar through CookieJarSettings.replaceFromHeader so
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
  @Local parsedCookies: CookieJarEntry[] = [];
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
              this.refreshParsedCookies()
            })
          this.CookiePreviewSection()
          Button($r('app.string.cookie_import_confirm'))
            .width('100%')
            .fontColor(ThemeConstants.TEXT_ON_BRAND)
            .backgroundColor(ThemeConstants.BRAND_PRIMARY)
            .enabled(!this.submitting && this.canConfirmCookieImport())
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

  private refreshParsedCookies(): void {
    this.parsedCookies = CookieJarSettings.parseCookieEntries(this.cookieText)
  }

  private parsedCookieValue(name: string): string {
    for (let i: number = 0; i < this.parsedCookies.length; i++) {
      if (this.parsedCookies[i].name === name) {
        return this.parsedCookies[i].value
      }
    }
    return ''
  }

  private canConfirmCookieImport(): boolean {
    return (
      this.parsedCookieValue(EhConstants.COOKIE_MEMBER_ID).length > 0 &&
      this.parsedCookieValue(EhConstants.COOKIE_PASS_HASH).length > 0
    )
  }

  private previewStatus(): ResourceStr {
    if (this.cookieText.trim().length <= 0) {
      return $r('app.string.cookie_import_preview_empty')
    }
    if (this.canConfirmCookieImport()) {
      return AppStrings.get('cookie_import_preview_count').replace('%d', `${this.parsedCookies.length}`)
    }
    return $r('app.string.cookie_import_preview_missing')
  }

  @Builder
  private rowDivider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('sys.color.ohos_id_color_list_separator'))
      .margin({ left: ThemeConstants.SPACE_MD })
  }

  @Builder
  private CookiePreviewRow(entry: CookieJarEntry) {
    Column({ space: ThemeConstants.SPACE_XS }) {
      Text(entry.name)
        .fontSize(ThemeConstants.FONT_SIZE_LIST_ITEM)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(entry.value)
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontColor($r('sys.color.font_secondary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(ThemeConstants.SPACE_MD)
  }

  @Builder
  private CookiePreviewSection() {
    GroupedListSection() {
      ConciseListRow({
        title: $r('app.string.cookie_import_preview_title'),
        subtitle: this.previewStatus(),
        leadingIcon: $r('sys.symbol.list_bullet'),
        showChevron: false,
      })
      if (this.parsedCookies.length > 0) {
        this.rowDivider()
        ForEach(
          this.parsedCookies,
          (entry: CookieJarEntry, index: number) => {
            this.CookiePreviewRow(entry)
            if (index < this.parsedCookies.length - 1) {
              this.rowDivider()
            }
          },
          (entry: CookieJarEntry) => entry.name,
        )
      }
    }
  }

  private async submit(): Promise<void> {
    if (this.submitting) {
      return
    }
    this.refreshParsedCookies()
    // Validate identity WITHOUT mutating the live jar, so an invalid paste never half-applies.
    const memberId: string = this.parsedCookieValue(EhConstants.COOKIE_MEMBER_ID)
    const passHash: string = this.parsedCookieValue(EhConstants.COOKIE_PASS_HASH)
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
    const header: string = CookieJarSettings.formatEntries(this.parsedCookies)
    // Replace the jar with exactly this pasted account (clear first), preserving its complete cookie set
    // (donor/permission cookies kept, not dropped). Clearing first means importing a second account never
    // inherits the previous account's igneous/sk.
    CookieJarSettings.replaceFromHeader(header)
    DiagnosticLogger.info('auth', 'cookie_import_applied', `cookies=${this.parsedCookies.length}`)
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext
    // save() persists the jar AND refreshes AuthState (isLogin / hasIgneous / memberId) for the UI.
    await CookieJarSettings.save(ctx)
    this.getUIContext()
      .getPromptAction()
      .showToast({ message: $r('app.string.login_success') })
    closeLoginFlowToAccount(this.stack)
  }
}
