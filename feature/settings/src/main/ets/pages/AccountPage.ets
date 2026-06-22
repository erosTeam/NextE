import { HdsNavDestination } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import {
  AppStrings,
  AuthState,
  ConciseListRow,
  CookieJarSettings,
  GroupedListSection,
  SecondaryListScaffold,
  ThemeConstants,
  connectAuth,
  connectNavStack,
  immersiveTitleBar,
  AccountListState,
  connectAccountList,
} from 'shared'

/**
 * The account hub, reached from the settings account block. Owns everything account-related so the main
 * settings list stays clean. Signed in, it is the multi-account switcher: each saved account is a card,
 * the active one carries a checkmark, tapping another switches to it, swiping left deletes it (which logs
 * out only if it was the last). The login rows double as "add another account". Logged out, just the login
 * routes. Real avatars/nicknames are unavailable (forum-only, CF-blocked), so the avatar is a placeholder
 * and accounts are shown by member id.
 */
@ComponentV2
export struct AccountPage {
  @Local auth: AuthState = connectAuth();
  @Local accountList: AccountListState = connectAccountList();
  @Local refreshing: boolean = false;
  private stack: NavPathStack = connectNavStack().stack;
  private scroller: Scroller = new Scroller();

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: message })
  }

  // Force-refresh igneous (eros_fe's "Refresh Igneous") for the active account — useful if EX access lapsed.
  private refreshIgneous(): void {
    if (this.refreshing) {
      return
    }
    this.refreshing = true
    this.toast($r('app.string.site_ex_checking'))
    CookieJarSettings.refreshIgneous(this.ctx())
      .then((ok: boolean) => {
        this.toast(ok ? $r('app.string.site_ex_unlocked') : $r('app.string.site_ex_no_access'))
      })
      .finally(() => {
        this.refreshing = false
      })
  }

  private switchAccount(memberId: string): void {
    if (memberId === this.accountList.activeMemberId) {
      return
    }
    CookieJarSettings.switchTo(this.ctx(), memberId)
  }

  private removeAccount(memberId: string): void {
    CookieJarSettings.removeAccount(this.ctx(), memberId)
  }

  @Builder
  private rowDivider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('sys.color.ohos_id_color_list_separator'))
      .margin({ left: ThemeConstants.SPACE_MD })
  }

  @Builder
  private Avatar(size: number) {
    Stack() {
      SymbolGlyph($r('sys.symbol.person_fill'))
        .fontSize(size / 2)
        .fontColor([Color.White])
    }
    .width(size)
    .height(size)
    .borderRadius(size / 2)
    .backgroundColor(ThemeConstants.BRAND_PRIMARY)
  }

  // One saved account as a card row; the active account carries a checkmark (single-select).
  @Builder
  private AccountRow(memberId: string) {
    Row({ space: ThemeConstants.SPACE_MD }) {
      this.Avatar(44)
      Text(`ID ${memberId}`)
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor($r('sys.color.font_primary'))
        .layoutWeight(1)
      if (memberId === this.accountList.activeMemberId) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(ThemeConstants.FONT_SIZE_TITLE)
          .fontColor([ThemeConstants.BRAND_PRIMARY])
      }
    }
    .width('100%')
    .padding(ThemeConstants.SPACE_MD)
    .borderRadius(ThemeConstants.RADIUS_CARD)
    .backgroundColor($r('app.color.card_background'))
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private DeleteAction(memberId: string) {
    Text($r('app.string.account_remove'))
      .fontColor(Color.White)
      .fontSize(ThemeConstants.FONT_SIZE_BODY)
      .height('100%')
      .padding({ left: ThemeConstants.SPACE_LG, right: ThemeConstants.SPACE_LG })
      .backgroundColor(Color.Red)
      .onClick(() => {
        this.removeAccount(memberId)
      })
  }

  // Login routes — also the "add another account" entry when already signed in.
  @Builder
  private LoginOptions() {
    GroupedListSection() {
      ConciseListRow({
        title: $r('app.string.settings_login'),
        leadingIcon: $r('sys.symbol.person_badge_plus'),
        action: () => {
          this.stack.pushPathByName('EhLogin', null)
        },
      })
      this.rowDivider()
      ConciseListRow({
        title: $r('app.string.settings_login_password'),
        leadingIcon: $r('sys.symbol.lock'),
        action: () => {
          this.stack.pushPathByName('EhPasswordLogin', null)
        },
      })
      this.rowDivider()
      ConciseListRow({
        title: $r('app.string.settings_login_cookie'),
        leadingIcon: $r('sys.symbol.arrow_down_to_line_circle_fill'),
        action: () => {
          this.stack.pushPathByName('EhCookieImport', null)
        },
      })
    }
  }

  build() {
    HdsNavDestination() {
      SecondaryListScaffold({
        scroller: this.scroller,
        bottomPadding: ThemeConstants.SPACE_XL,
      }) {
        if (this.auth.isLogin) {
          ForEach(
            this.accountList.accounts,
            (memberId: string) => {
              ListItem() {
                this.AccountRow(memberId)
              }
              .swipeAction({
                end: () => {
                  this.DeleteAction(memberId)
                },
              })
              .onClick(() => {
                this.switchAccount(memberId)
              })
            },
            (memberId: string) => memberId,
          )
          ListItem() {
            this.LoginOptions()
          }
          ListItem() {
            GroupedListSection() {
              ConciseListRow({
                title: $r('app.string.settings_mytags'),
                leadingIcon: $r('sys.symbol.bookmark'),
                action: () => {
                  this.stack.pushPathByName('MyTags', null)
                },
              })
              this.rowDivider()
              ConciseListRow({
                title: $r('app.string.settings_refresh_igneous'),
                leadingIcon: $r('sys.symbol.arrow_clockwise'),
                showChevron: false,
                action: () => {
                  this.refreshIgneous()
                },
              })
            }
          }
        } else {
          ListItem() {
            this.LoginOptions()
          }
        }
      }
    }
    .titleBar(immersiveTitleBar(AppStrings.get('settings_account')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
